CREATE TABLE rides (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('Request', 'Offer')),
  direction TEXT NOT NULL CHECK (direction IN ('campus', 'home')),
  community TEXT NOT NULL,
  days TEXT NOT NULL,
  time TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
