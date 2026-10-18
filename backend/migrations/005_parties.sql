-- Additive party context: existing profiles/measurements/game ledger stay intact.
CREATE TABLE parties (
 party_id TEXT PRIMARY KEY NOT NULL,
 host_user_id TEXT NOT NULL,
 name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
 join_code TEXT NOT NULL UNIQUE,
 created_at TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('OPEN','CLOSED')),
 closed_at TEXT,
 CHECK((state='CLOSED') = (closed_at IS NOT NULL))
);
CREATE TABLE party_members (
 party_id TEXT NOT NULL REFERENCES parties(party_id),
 user_id TEXT NOT NULL,
 joined_at TEXT NOT NULL,
 left_at TEXT,
 PRIMARY KEY(party_id,user_id)
);
CREATE INDEX party_members_owner ON party_members(user_id,party_id);
CREATE TABLE device_party_hosts (
 device_id TEXT NOT NULL REFERENCES devices(id),
 user_id TEXT NOT NULL,
 PRIMARY KEY(device_id,user_id)
);
CREATE TABLE party_devices (
 party_id TEXT PRIMARY KEY NOT NULL REFERENCES parties(party_id),
 device_id TEXT NOT NULL UNIQUE REFERENCES devices(id)
);
CREATE TABLE party_games (
 game_instance_id TEXT PRIMARY KEY NOT NULL,
 party_id TEXT NOT NULL REFERENCES parties(party_id),
 game_id TEXT NOT NULL,
 device_id TEXT REFERENCES devices(id),
 created_at TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('OPEN','CLOSED')),
 closed_at TEXT,
 CHECK((state='CLOSED') = (closed_at IS NOT NULL))
);
CREATE UNIQUE INDEX one_open_party_game ON party_games(party_id) WHERE state='OPEN';
CREATE INDEX party_games_order ON party_games(party_id,created_at DESC,game_instance_id DESC);
CREATE TABLE party_result_context (
 result_id TEXT PRIMARY KEY NOT NULL REFERENCES game_results(result_id),
 game_instance_id TEXT NOT NULL REFERENCES party_games(game_instance_id),
 user_id TEXT NOT NULL,
 measurement_id TEXT UNIQUE REFERENCES measurements(id),
 placement INTEGER CHECK(placement BETWEEN 1 AND 10000),
 UNIQUE(game_instance_id,user_id)
);
CREATE TABLE party_join_attempts (
 user_id TEXT PRIMARY KEY NOT NULL,
 window_started TEXT NOT NULL,
 attempts INTEGER NOT NULL CHECK(attempts BETWEEN 1 AND 10)
);
PRAGMA user_version = 5;
