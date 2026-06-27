-- Consumer-proposed date/time changes require provider approval before updating requestedAt.
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS "pendingRequestedAt" TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "pendingScheduleRequestedAt" TIMESTAMPTZ;

COMMENT ON COLUMN bookings."pendingRequestedAt" IS 'Proposed appointment time awaiting barber approval';
COMMENT ON COLUMN bookings."pendingScheduleRequestedAt" IS 'When the consumer submitted the pending time change';
