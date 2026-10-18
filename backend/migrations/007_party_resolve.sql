-- Additive retry ledger; existing records and definitions are untouched.
CREATE TABLE party_resolve_requests (
 request_id TEXT PRIMARY KEY NOT NULL,
 user_id TEXT NOT NULL,
 device_id TEXT NOT NULL REFERENCES devices(id),
 name TEXT NOT NULL,
 party_id TEXT NOT NULL REFERENCES parties(party_id),
 action TEXT NOT NULL CHECK(action IN ('created','joined'))
);
-- Guards inspect only future active writes: installing them never rewrites legacy duplicates.
CREATE TRIGGER party_member_one_open_insert BEFORE INSERT ON party_members
WHEN NEW.left_at IS NULL AND EXISTS(SELECT 1 FROM parties WHERE party_id=NEW.party_id AND state='OPEN')
BEGIN
 SELECT CASE WHEN EXISTS(
  SELECT 1 FROM parties p WHERE p.state='OPEN' AND p.party_id<>NEW.party_id
   AND (p.host_user_id=NEW.user_id OR EXISTS(SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=NEW.user_id AND m.left_at IS NULL))
 ) THEN RAISE(ABORT,'active_party_conflict') END;
END;
CREATE TRIGGER party_member_one_open_update BEFORE UPDATE ON party_members
WHEN NEW.left_at IS NULL AND EXISTS(SELECT 1 FROM parties WHERE party_id=NEW.party_id AND state='OPEN')
BEGIN
 SELECT CASE WHEN EXISTS(
  SELECT 1 FROM parties p WHERE p.state='OPEN' AND p.party_id<>NEW.party_id
   AND (p.host_user_id=NEW.user_id OR EXISTS(SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=NEW.user_id AND m.left_at IS NULL))
 ) THEN RAISE(ABORT,'active_party_conflict') END;
END;
CREATE TRIGGER party_host_one_open_insert BEFORE INSERT ON parties WHEN NEW.state='OPEN'
BEGIN
 SELECT CASE WHEN EXISTS(
  SELECT 1 FROM parties p WHERE p.state='OPEN' AND p.party_id<>NEW.party_id
   AND (p.host_user_id=NEW.host_user_id OR EXISTS(SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=NEW.host_user_id AND m.left_at IS NULL)
    OR EXISTS(SELECT 1 FROM party_members own WHERE own.party_id=NEW.party_id AND own.left_at IS NULL
     AND (p.host_user_id=own.user_id OR EXISTS(SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=own.user_id AND m.left_at IS NULL))))
 ) THEN RAISE(ABORT,'active_party_conflict') END;
END;
CREATE TRIGGER party_host_one_open_update BEFORE UPDATE OF state,host_user_id,party_id ON parties WHEN NEW.state='OPEN'
BEGIN
 SELECT CASE WHEN EXISTS(
  SELECT 1 FROM parties p WHERE p.state='OPEN' AND p.party_id<>OLD.party_id
   AND (p.host_user_id=NEW.host_user_id OR EXISTS(SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=NEW.host_user_id AND m.left_at IS NULL)
    OR EXISTS(SELECT 1 FROM party_members own WHERE own.party_id=OLD.party_id AND own.left_at IS NULL
     AND (p.host_user_id=own.user_id OR EXISTS(SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=own.user_id AND m.left_at IS NULL))))
 ) THEN RAISE(ABORT,'active_party_conflict') END;
END;
PRAGMA user_version = 7;
