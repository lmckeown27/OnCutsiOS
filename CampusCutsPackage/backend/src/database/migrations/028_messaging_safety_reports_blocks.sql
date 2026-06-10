-- UGC / messaging safety: reports for moderator review + per-user blocks (App Store Guideline 1.2).

CREATE TABLE IF NOT EXISTS message_content_reports (
    id SERIAL PRIMARY KEY,
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    conversation_id INTEGER REFERENCES conversations(id) ON DELETE CASCADE,
    message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_message_content_reports_reporter ON message_content_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_message_content_reports_conversation ON message_content_reports(conversation_id);
CREATE INDEX IF NOT EXISTS idx_message_content_reports_created ON message_content_reports(created_at DESC);

CREATE TABLE IF NOT EXISTS user_message_blocks (
    id SERIAL PRIMARY KEY,
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_message_blocks_blocker ON user_message_blocks(blocker_id);
