#!/usr/bin/env python3
"""
Daily backup of Notero notes from Supabase to a ZIP file.

Downloads all notes and folders, recreates the directory structure
as .md files, and saves a timestamped ZIP archive.

Usage:
    python backup.py                    # Run backup with defaults
    python backup.py --dry-run          # Preview without creating ZIP
"""

import argparse
import os
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta
from pathlib import Path

BACKUP_DIR = os.path.expanduser(
    "~/Library/CloudStorage/GoogleDrive-daniel@gamrot.cz/Můj disk/Notero_backup"
)
RETENTION_DAYS = 30
PAGE_SIZE = 1000


def fetch_all_notes(client, user_id: str) -> list[dict]:
    """Fetch all notes with pagination (Supabase limits to 1000 per request)."""
    all_notes = []
    offset = 0
    while True:
        result = (
            client.table("notes")
            .select("title,content,path,created_at,updated_at")
            .eq("user_id", user_id)
            .order("path")
            .range(offset, offset + PAGE_SIZE - 1)
            .execute()
        )
        all_notes.extend(result.data)
        if len(result.data) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return all_notes


def fetch_all_folders(client, user_id: str) -> list[dict]:
    """Fetch all folders."""
    result = (
        client.table("folders")
        .select("path")
        .eq("user_id", user_id)
        .order("path")
        .execute()
    )
    return result.data


def create_backup_zip(notes: list[dict], folders: list[dict], backup_path: Path):
    """Create ZIP archive with .md files preserving folder structure."""
    date_str = datetime.now().strftime("%Y-%m-%d")
    zip_name = f"notero-backup-{date_str}.zip"
    zip_path = backup_path / zip_name

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / f"notero-backup-{date_str}"
        root.mkdir()

        # Create folder structure
        for folder in folders:
            (root / folder["path"]).mkdir(parents=True, exist_ok=True)

        # Write notes as .md files
        for note in notes:
            note_path = root / f"{note['path']}.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(note["content"] or "", encoding="utf-8")

        # Create ZIP
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for file in root.rglob("*"):
                if file.is_file():
                    zf.write(file, file.relative_to(tmp))

    return zip_path


def rotate_backups(backup_path: Path, retention_days: int):
    """Delete backups older than retention_days."""
    cutoff = datetime.now() - timedelta(days=retention_days)
    deleted = 0
    for f in backup_path.glob("notero-backup-*.zip"):
        # Parse date from filename: notero-backup-YYYY-MM-DD.zip
        try:
            date_str = f.stem.replace("notero-backup-", "")
            file_date = datetime.strptime(date_str, "%Y-%m-%d")
            if file_date < cutoff:
                f.unlink()
                deleted += 1
                print(f"  Deleted old backup: {f.name}")
        except ValueError:
            continue
    return deleted


def dry_run(client, user_id: str):
    """Preview what would be backed up."""
    print("=== DRY RUN ===\n")

    folders = fetch_all_folders(client, user_id)
    notes = fetch_all_notes(client, user_id)

    print(f"Folders: {len(folders)}")
    for f in folders:
        print(f"  {f['path']}/")

    print(f"\nNotes: {len(notes)}")
    total_size = 0
    for n in notes:
        size = len((n["content"] or "").encode("utf-8"))
        total_size += size
        print(f"  {n['path']}.md ({size:,} bytes)")

    print(f"\nTotal content: {total_size:,} bytes ({total_size / 1024:.1f} KB)")
    print(f"Backup dir: {BACKUP_DIR}")
    print(f"Retention: {RETENTION_DAYS} days")


def backup(client, user_id: str):
    """Run the backup."""
    backup_path = Path(BACKUP_DIR)
    backup_path.mkdir(parents=True, exist_ok=True)

    print("Fetching data from Supabase...")
    folders = fetch_all_folders(client, user_id)
    notes = fetch_all_notes(client, user_id)
    print(f"  {len(folders)} folders, {len(notes)} notes")

    if not notes:
        print("No notes found — skipping backup.")
        return

    print("Creating ZIP archive...")
    zip_path = create_backup_zip(notes, folders, backup_path)
    zip_size = zip_path.stat().st_size
    print(f"  Created: {zip_path.name} ({zip_size:,} bytes)")

    print("Rotating old backups...")
    deleted = rotate_backups(backup_path, RETENTION_DAYS)
    if deleted == 0:
        print("  No old backups to delete.")

    print(f"\nBackup complete: {zip_path}")


def main():
    parser = argparse.ArgumentParser(description="Backup Notero notes from Supabase")
    parser.add_argument("--dry-run", action="store_true", help="Preview without backup")
    args = parser.parse_args()

    # Load .env from script directory
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    user_id = os.environ.get("SUPABASE_USER_ID")

    if not url or not key:
        print("ERROR: Missing SUPABASE_URL or SUPABASE_SERVICE_KEY")
        print("  Set them in supabase/.env or as environment variables")
        sys.exit(1)

    try:
        from supabase import create_client
    except ImportError:
        print("ERROR: supabase package not installed. Run: pip install supabase")
        sys.exit(1)

    client = create_client(url, key)

    # Auto-detect user_id if not set (single-user setup)
    if not user_id:
        result = client.table("notes").select("user_id").limit(1).execute()
        if not result.data:
            print("ERROR: No notes found and SUPABASE_USER_ID not set")
            sys.exit(1)
        user_id = result.data[0]["user_id"]
        print(f"Auto-detected user_id: {user_id}")

    if args.dry_run:
        dry_run(client, user_id)
    else:
        backup(client, user_id)


if __name__ == "__main__":
    main()
