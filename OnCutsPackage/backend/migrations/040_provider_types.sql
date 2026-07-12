-- Provider type catalog + column on barbers (Home Tags: Barber / Beauty).
-- Idempotent for production DBs that already have these objects.

CREATE TABLE IF NOT EXISTS provider_types (
  provider_type TEXT PRIMARY KEY,
  label TEXT NOT NULL
);

INSERT INTO provider_types (provider_type, label) VALUES
  ('barber', 'Barber'),
  ('beauty', 'Beauty')
ON CONFLICT (provider_type) DO UPDATE SET label = EXCLUDED.label;

ALTER TABLE barbers
  ADD COLUMN IF NOT EXISTS provider_type TEXT NOT NULL DEFAULT 'barber';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'barbers_provider_type_fkey'
  ) THEN
    ALTER TABLE barbers
      ADD CONSTRAINT barbers_provider_type_fkey
      FOREIGN KEY (provider_type) REFERENCES provider_types (provider_type);
  END IF;
EXCEPTION
  WHEN others THEN
    -- Column may already reference provider_types under another constraint name.
    NULL;
END $$;
