CREATE TABLE party_check_ins (
    check_in_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL UNIQUE REFERENCES sessions(id),
    party_id TEXT NOT NULL REFERENCES parties(party_id),
    game_instance_id TEXT REFERENCES party_games(game_instance_id),
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL REFERENCES devices(id)
);
CREATE INDEX party_check_ins_owner_history ON party_check_ins(user_id,check_in_id);
PRAGMA user_version=6;
