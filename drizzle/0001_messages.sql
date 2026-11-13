CREATE TABLE ride_messages (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  thread_id TEXT NOT NULL,
  ride_id TEXT NOT NULL,
  poster_id TEXT NOT NULL,
  visitor_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  sent_at INTEGER NOT NULL
);
--> statement-breakpoint
CREATE INDEX ride_messages_thread ON ride_messages (thread_id, sequence);
--> statement-breakpoint
CREATE INDEX ride_messages_poster ON ride_messages (poster_id, sequence);
--> statement-breakpoint
CREATE INDEX ride_messages_visitor ON ride_messages (visitor_id, sequence);
