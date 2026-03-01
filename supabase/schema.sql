-- Notero Supabase Schema
-- Run this in Supabase SQL Editor (Settings → SQL Editor → New Query → Run)

-- ============================================================================
-- Tables
-- ============================================================================

CREATE TABLE folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  parent_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  path TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, path)
);

CREATE TABLE notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  folder_id UUID REFERENCES folders(id) ON DELETE SET NULL,
  title TEXT NOT NULL DEFAULT 'Untitled',
  content TEXT NOT NULL DEFAULT '',
  path TEXT NOT NULL,
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  search_vector TSVECTOR GENERATED ALWAYS AS (
    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(content, '')), 'B')
  ) STORED,
  UNIQUE(user_id, path)
);

CREATE TABLE note_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id UUID REFERENCES notes(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  version INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE favourites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  note_id UUID REFERENCES notes(id) ON DELETE CASCADE NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  UNIQUE(user_id, note_id)
);

CREATE TABLE settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  key TEXT NOT NULL,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, key)
);

-- ============================================================================
-- Indexes
-- ============================================================================

CREATE INDEX idx_notes_search ON notes USING GIN(search_vector);
CREATE INDEX idx_notes_folder ON notes(folder_id);
CREATE INDEX idx_notes_updated ON notes(user_id, updated_at DESC);
CREATE INDEX idx_notes_path ON notes(user_id, path);
CREATE INDEX idx_folders_path ON folders(user_id, path);
CREATE INDEX idx_folders_parent ON folders(parent_id);
CREATE INDEX idx_history_note ON note_history(note_id, created_at DESC);
CREATE INDEX idx_favourites_user ON favourites(user_id, sort_order);

-- ============================================================================
-- Row Level Security
-- ============================================================================

ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE note_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE favourites ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own notes" ON notes
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users see own folders" ON folders
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users see own history" ON note_history
  FOR ALL USING (note_id IN (SELECT id FROM notes WHERE user_id = auth.uid()));

CREATE POLICY "Users see own favourites" ON favourites
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users see own settings" ON settings
  FOR ALL USING (auth.uid() = user_id);

-- ============================================================================
-- Updated_at trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notes_updated_at
  BEFORE UPDATE ON notes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER folders_updated_at
  BEFORE UPDATE ON folders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER settings_updated_at
  BEFORE UPDATE ON settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- Realtime (for cross-client sync)
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE notes;
ALTER PUBLICATION supabase_realtime ADD TABLE folders;
ALTER PUBLICATION supabase_realtime ADD TABLE favourites;
