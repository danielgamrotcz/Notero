-- Preserve created_at on UPDATE (upsert from syncNote would overwrite it).
-- IMPORTANT: Run this AFTER the backfill has completed on all devices.

CREATE OR REPLACE FUNCTION preserve_note_created_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.created_at = OLD.created_at;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notes_preserve_created_at
  BEFORE UPDATE ON notes
  FOR EACH ROW EXECUTE FUNCTION preserve_note_created_at();
