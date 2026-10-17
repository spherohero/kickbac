CREATE TABLE sessions (
 id TEXT PRIMARY KEY,
 device_id TEXT NOT NULL REFERENCES devices(id),
 user_id TEXT NOT NULL,
 status TEXT NOT NULL CHECK (status IN ('ARMED','SAMPLING','COMPLETE','CANCELLED','EXPIRED')),
 created_at TEXT NOT NULL,
 expires_at TEXT NOT NULL,
 completed_at TEXT,
 CHECK ((status = 'COMPLETE') = (completed_at IS NOT NULL))
);
CREATE UNIQUE INDEX one_active_session ON sessions(device_id) WHERE status IN ('ARMED','SAMPLING');
CREATE INDEX sessions_owner ON sessions(user_id);
CREATE TABLE measurements (
 id TEXT PRIMARY KEY,
 session_id TEXT NOT NULL UNIQUE REFERENCES sessions(id),
 device_id TEXT NOT NULL REFERENCES devices(id),
 user_id TEXT NOT NULL,
 payload TEXT NOT NULL CHECK (json_valid(payload)),
 received_at TEXT NOT NULL
);
CREATE INDEX measurements_history ON measurements(user_id, received_at DESC, id DESC);
PRAGMA user_version = 2;
