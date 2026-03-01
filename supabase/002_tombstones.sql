-- Tombstone tables for tracking deletions across devices

CREATE TABLE note_deletions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    path TEXT NOT NULL,
    deleted_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE folder_deletions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    path TEXT NOT NULL,
    deleted_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_note_del_user_time ON note_deletions(user_id, deleted_at);
CREATE INDEX idx_folder_del_user_time ON folder_deletions(user_id, deleted_at);

-- RLS
ALTER TABLE note_deletions ENABLE ROW LEVEL SECURITY;
ALTER TABLE folder_deletions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_note_dels" ON note_deletions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "own_folder_dels" ON folder_deletions FOR ALL USING (auth.uid() = user_id);

-- Trigger: on DELETE from notes -> insert tombstone
CREATE OR REPLACE FUNCTION on_note_deleted() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO note_deletions (user_id, path) VALUES (OLD.user_id, OLD.path);
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notes_tombstone AFTER DELETE ON notes
    FOR EACH ROW EXECUTE FUNCTION on_note_deleted();

-- Trigger: on DELETE from folders -> insert tombstone
CREATE OR REPLACE FUNCTION on_folder_deleted() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO folder_deletions (user_id, path) VALUES (OLD.user_id, OLD.path);
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER folders_tombstone AFTER DELETE ON folders
    FOR EACH ROW EXECUTE FUNCTION on_folder_deleted();
