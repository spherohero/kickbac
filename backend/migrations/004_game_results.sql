CREATE TABLE game_results (
 result_id TEXT PRIMARY KEY NOT NULL,
 user_id TEXT NOT NULL,
 game_id TEXT NOT NULL,
 score INTEGER NOT NULL CHECK(score BETWEEN 0 AND 1000000),
 outcome TEXT NOT NULL CHECK(outcome IN ('win','loss','draw','completed')),
 data TEXT NOT NULL,
 awarded_points INTEGER NOT NULL CHECK(awarded_points = 10),
 scoring_policy TEXT NOT NULL CHECK(scoring_policy = 'completion_v1'),
 source TEXT NOT NULL CHECK(source = 'client_reported'),
 created_at TEXT NOT NULL
);
CREATE INDEX game_results_owner_order ON game_results(user_id,created_at DESC,result_id DESC);
CREATE INDEX game_results_owner_game_order ON game_results(user_id,game_id,created_at DESC,result_id DESC);
PRAGMA user_version = 4;
