-- Per-app APNs topic (consumer vs provider bundle id) for `mobile_devices`.
ALTER TABLE mobile_devices
  ADD COLUMN IF NOT EXISTS bundle_id VARCHAR(255);

CREATE INDEX IF NOT EXISTS idx_mobile_devices_bundle_id ON mobile_devices(bundle_id)
  WHERE bundle_id IS NOT NULL;
