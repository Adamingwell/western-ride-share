ALTER TABLE notification_recipients ADD COLUMN email_enabled INTEGER NOT NULL DEFAULT 1 CHECK (email_enabled IN (0, 1));
