-- revealz MetaSrv schema (IF NOT EXISTS — safe on every lobby boot)

CREATE TABLE IF NOT EXISTS accounts (
  account_key TEXT PRIMARY KEY,
  auth_kind TEXT NOT NULL DEFAULT 'guest',
  display_name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  client_migrated_at TIMESTAMPTZ,
  meta_revision BIGINT NOT NULL DEFAULT 0
);

-- Existing DBs created before meta_revision.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS meta_revision BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS wallets (
  account_key TEXT PRIMARY KEY REFERENCES accounts(account_key) ON DELETE CASCADE,
  gold INTEGER NOT NULL DEFAULT 0 CHECK (gold >= 0)
);

CREATE TABLE IF NOT EXISTS owned_cards (
  account_key TEXT NOT NULL REFERENCES accounts(account_key) ON DELETE CASCADE,
  card_id INTEGER NOT NULL,
  rarity INTEGER NOT NULL CHECK (rarity >= 0 AND rarity <= 3),
  count INTEGER NOT NULL CHECK (count > 0),
  PRIMARY KEY (account_key, card_id, rarity)
);

CREATE TABLE IF NOT EXISTS decks (
  account_key TEXT NOT NULL REFERENCES accounts(account_key) ON DELETE CASCADE,
  deck_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'Deck',
  format TEXT NOT NULL DEFAULT 'mono',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (account_key, deck_id)
);

CREATE INDEX IF NOT EXISTS idx_owned_cards_account ON owned_cards(account_key);
CREATE INDEX IF NOT EXISTS idx_decks_account ON decks(account_key);

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS profile_icon_id TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS owned_accessories (
  account_key TEXT NOT NULL REFERENCES accounts(account_key) ON DELETE CASCADE,
  accessory_type TEXT NOT NULL CHECK (accessory_type IN ('icon', 'card_back', 'field')),
  accessory_id TEXT NOT NULL,
  PRIMARY KEY (account_key, accessory_type, accessory_id)
);

CREATE INDEX IF NOT EXISTS idx_owned_accessories_account ON owned_accessories(account_key);

CREATE TABLE IF NOT EXISTS patch_notes (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  published_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_patch_notes_published ON patch_notes (published_at DESC, id DESC);

-- Hard-deleted keys: block remigrate/PUT so test cleanup sticks.
CREATE TABLE IF NOT EXISTS deleted_accounts (
  account_key TEXT PRIMARY KEY,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
