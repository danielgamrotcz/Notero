-- Web sharing: allow individual notes to be shared as read-only web pages
ALTER TABLE notes ADD COLUMN is_shared BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE notes ADD COLUMN share_id UUID DEFAULT NULL UNIQUE;
CREATE INDEX idx_notes_share_id ON notes(share_id) WHERE is_shared = true;

-- Anon read policy (RLS) — allows unauthenticated access to shared notes
CREATE POLICY "Anon can read shared notes" ON notes
  FOR SELECT USING (is_shared = true AND share_id IS NOT NULL)
  TO anon;
