CREATE TABLE devices (
 id TEXT PRIMARY KEY,
 credential_hash TEXT NOT NULL UNIQUE,
 last_seen_at TEXT
);
PRAGMA user_version = 1;
