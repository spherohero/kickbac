CREATE TABLE app_readings (
    reading_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    value REAL NOT NULL CHECK(typeof(value) = 'real' AND value >= 0 AND value <= 1),
    recorded_at TEXT NOT NULL,
    duration_ms INTEGER NOT NULL CHECK(typeof(duration_ms) = 'integer' AND duration_ms BETWEEN 1 AND 60000),
    source TEXT NOT NULL CHECK(source = 'app_generated'),
    received_at TEXT NOT NULL
);
CREATE INDEX app_readings_owner_order ON app_readings(user_id, recorded_at DESC, reading_id DESC);
CREATE TABLE app_reading_save_windows (
    user_id TEXT PRIMARY KEY,
    window_started REAL NOT NULL,
    accepted INTEGER NOT NULL CHECK(typeof(accepted) = 'integer' AND accepted BETWEEN 1 AND 60)
);
PRAGMA user_version = 8;
