CREATE TABLE profiles (
 user_id TEXT PRIMARY KEY NOT NULL,
 display_name TEXT NOT NULL,
 profile_picture BLOB,
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL
);
PRAGMA user_version = 3;
