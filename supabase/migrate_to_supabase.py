#!/usr/bin/env python3
"""
Migrate Notero vault from Google Drive to Supabase.

Reads .md files from the vault folder, metadata from ~/.notero/meta/,
and favourites.json, then uploads everything to Supabase.

Usage:
    python migrate_to_supabase.py --dry-run          # Preview what would be migrated
    python migrate_to_supabase.py                     # Run actual migration
    python migrate_to_supabase.py --vault /path/to   # Custom vault path
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

# Vault default - Google Drive mount
DEFAULT_VAULT = os.path.expanduser(
    "~/Library/CloudStorage/GoogleDrive-daniel@gamrot.cz/Můj disk/Notero"
)
NOTERO_META_DIR = os.path.expanduser("~/.notero/meta")
SKIP_FILES = {"favourites.json", ".DS_Store"}
SKIP_DIRS = {".git", ".obsidian", ".trash"}


def find_md_files(vault_path: str) -> list[Path]:
    """Find all .md files in the vault recursively."""
    vault = Path(vault_path)
    files = []
    for f in vault.rglob("*.md"):
        if any(part.startswith(".") or part in SKIP_DIRS for part in f.relative_to(vault).parts):
            continue
        files.append(f)
    return sorted(files)


def find_folders(vault_path: str) -> list[Path]:
    """Find all subdirectories in the vault."""
    vault = Path(vault_path)
    folders = []
    for d in vault.rglob("*"):
        if not d.is_dir():
            continue
        rel = d.relative_to(vault)
        if any(part.startswith(".") or part in SKIP_DIRS for part in rel.parts):
            continue
        folders.append(d)
    return sorted(folders)


def load_favourites(vault_path: str) -> list[str]:
    """Load favourites.json from vault root."""
    fav_path = Path(vault_path) / "favourites.json"
    if not fav_path.exists():
        print("  [WARN] favourites.json not found")
        return []
    with open(fav_path, "r") as f:
        data = json.load(f)
    if not isinstance(data, list):
        print("  [WARN] favourites.json is not an array")
        return []
    return data


def get_file_dates(path: Path) -> tuple[datetime, datetime]:
    """Get creation and modification dates from filesystem."""
    stat = path.stat()
    # macOS: st_birthtime is creation time
    created = datetime.fromtimestamp(stat.st_birthtime, tz=timezone.utc)
    modified = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    return created, modified


def extract_title(content: str, filename: str) -> str:
    """Extract title from first H1 heading, fallback to filename."""
    for line in content.split("\n"):
        line = line.strip()
        if line.startswith("# "):
            return line[2:].strip()
        if line and not line.startswith("#"):
            break
    # Fallback: filename without .md
    return filename.rsplit(".", 1)[0]


def relative_path(vault_path: str, file_path: Path) -> str:
    """Get vault-relative path (without .md extension)."""
    rel = file_path.relative_to(vault_path)
    return str(rel).rsplit(".md", 1)[0]


def relative_path_with_ext(vault_path: str, file_path: Path) -> str:
    """Get vault-relative path (with extension)."""
    return str(file_path.relative_to(vault_path))


def folder_relative_path(vault_path: str, folder_path: Path) -> str:
    """Get vault-relative path for a folder."""
    return str(folder_path.relative_to(vault_path))


def dry_run(vault_path: str):
    """Preview what would be migrated without touching Supabase."""
    print(f"=== DRY RUN ===")
    print(f"Vault: {vault_path}\n")

    # Folders
    folders = find_folders(vault_path)
    print(f"Folders ({len(folders)}):")
    for f in folders:
        rel = folder_relative_path(vault_path, f)
        parent = str(Path(rel).parent) if "/" in rel else None
        print(f"  {rel}  (parent: {parent or 'root'})")

    # Notes
    files = find_md_files(vault_path)
    print(f"\nNotes ({len(files)}):")
    total_size = 0
    for f in files:
        content = f.read_text(encoding="utf-8", errors="replace")
        title = extract_title(content, f.name)
        path = relative_path(vault_path, f)
        created, modified = get_file_dates(f)
        size = len(content.encode("utf-8"))
        total_size += size
        print(f"  {path}")
        print(f"    title: {title}")
        print(f"    size: {size:,} bytes")
        print(f"    created: {created.isoformat()}")
        print(f"    modified: {modified.isoformat()}")

    print(f"\nTotal size: {total_size:,} bytes ({total_size / 1024:.1f} KB)")

    # Favourites
    favourites = load_favourites(vault_path)
    print(f"\nFavourites ({len(favourites)}):")
    for i, fav in enumerate(favourites):
        exists = (Path(vault_path) / fav).exists()
        status = "OK" if exists else "MISSING"
        print(f"  [{i}] {fav} ({status})")

    print(f"\n=== Summary ===")
    print(f"  {len(folders)} folders")
    print(f"  {len(files)} notes")
    print(f"  {len(favourites)} favourites")
    print(f"  {total_size / 1024:.1f} KB total content")


def migrate(vault_path: str, user_id: str):
    """Run the actual migration to Supabase."""
    try:
        from supabase import create_client
    except ImportError:
        print("ERROR: supabase package not installed. Run: pip install supabase")
        sys.exit(1)

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        print("ERROR: Set SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables")
        print("  See .env.example for details")
        sys.exit(1)

    client = create_client(url, key)
    print(f"Connected to Supabase: {url}")
    print(f"User ID: {user_id}")
    print(f"Vault: {vault_path}\n")

    # --- Cleanup previous data (idempotent re-runs) ---
    print("Cleaning previous data...")
    client.table("favourites").delete().eq("user_id", user_id).execute()
    # notes CASCADE deletes note_history
    client.table("notes").delete().eq("user_id", user_id).execute()
    # Delete folders deepest-first to avoid FK violations
    existing_folders = (
        client.table("folders")
        .select("id,path")
        .eq("user_id", user_id)
        .order("path", desc=True)
        .execute()
    )
    for f in existing_folders.data:
        client.table("folders").delete().eq("id", f["id"]).execute()
    print("  Done.\n")

    # --- Phase 1: Folders ---
    folders = find_folders(vault_path)
    print(f"Migrating {len(folders)} folders...")

    folder_id_map: dict[str, str] = {}  # path -> UUID

    # Sort by depth so parents are created first
    folders.sort(key=lambda f: str(f).count("/"))

    for folder in folders:
        rel = folder_relative_path(vault_path, folder)
        parent_rel = str(Path(rel).parent) if "/" in rel else None
        parent_id = folder_id_map.get(parent_rel) if parent_rel else None

        folder_id = str(uuid4())
        folder_id_map[rel] = folder_id

        row = {
            "id": folder_id,
            "user_id": user_id,
            "parent_id": parent_id,
            "name": folder.name,
            "path": rel,
        }
        client.table("folders").upsert(row, on_conflict="user_id,path").execute()
        print(f"  + {rel}")

    # --- Phase 2: Notes ---
    files = find_md_files(vault_path)
    print(f"\nMigrating {len(files)} notes...")

    note_id_map: dict[str, str] = {}  # relative path (with .md) -> UUID

    for f in files:
        content = f.read_text(encoding="utf-8", errors="replace")
        title = extract_title(content, f.name)
        path = relative_path(vault_path, f)
        path_with_ext = relative_path_with_ext(vault_path, f)
        created, modified = get_file_dates(f)

        # Find parent folder
        parent_dir = str(Path(path_with_ext).parent)
        folder_id = folder_id_map.get(parent_dir) if parent_dir != "." else None

        note_id = str(uuid4())
        note_id_map[path_with_ext] = note_id

        row = {
            "id": note_id,
            "user_id": user_id,
            "folder_id": folder_id,
            "title": title,
            "content": content,
            "path": path,
            "version": 1,
            "created_at": created.isoformat(),
            "updated_at": modified.isoformat(),
        }
        client.table("notes").upsert(row, on_conflict="user_id,path").execute()
        print(f"  + {path} ({len(content):,} bytes)")

    # --- Phase 3: Favourites ---
    favourites = load_favourites(vault_path)
    print(f"\nMigrating {len(favourites)} favourites...")

    migrated_favs = 0
    for i, fav in enumerate(favourites):
        note_id = note_id_map.get(fav)
        if not note_id:
            print(f"  ! SKIP: {fav} (note not found)")
            continue

        row = {
            "user_id": user_id,
            "note_id": note_id,
            "sort_order": i,
        }
        client.table("favourites").upsert(
            row, on_conflict="user_id,note_id"
        ).execute()
        migrated_favs += 1
        print(f"  + [{i}] {fav}")

    # --- Verification ---
    print(f"\n=== Verification ===")
    notes_count = client.table("notes").select("id", count="exact").eq("user_id", user_id).execute()
    folders_count = client.table("folders").select("id", count="exact").eq("user_id", user_id).execute()
    favs_count = client.table("favourites").select("id", count="exact").eq("user_id", user_id).execute()

    print(f"  Folders in DB: {folders_count.count}")
    print(f"  Notes in DB:   {notes_count.count}")
    print(f"  Favourites:    {favs_count.count}")
    print(f"\n  Expected: {len(folders)} folders, {len(files)} notes, {migrated_favs} favourites")

    if notes_count.count == len(files) and folders_count.count == len(folders):
        print("\n  Migration successful!")
    else:
        print("\n  WARNING: Count mismatch — check for errors above")


def main():
    parser = argparse.ArgumentParser(description="Migrate Notero vault to Supabase")
    parser.add_argument("--dry-run", action="store_true", help="Preview without migrating")
    parser.add_argument("--vault", default=DEFAULT_VAULT, help="Path to vault folder")
    parser.add_argument("--user-id", help="Supabase user UUID (required for migration)")
    args = parser.parse_args()

    vault_path = os.path.expanduser(args.vault)
    if not os.path.isdir(vault_path):
        print(f"ERROR: Vault not found: {vault_path}")
        sys.exit(1)

    if args.dry_run:
        dry_run(vault_path)
    else:
        if not args.user_id:
            print("ERROR: --user-id is required for migration")
            print("  Get it from Supabase: Authentication → Users → click user → copy UUID")
            sys.exit(1)
        migrate(vault_path, args.user_id)


if __name__ == "__main__":
    main()
