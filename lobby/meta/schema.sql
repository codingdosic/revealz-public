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

-- Server-authority shop catalog (ops/db editable). Client .tres = display only.
-- pool_mode: explicit = use pool_json card ids; all_non_token = full non-token catalog at purchase time.
CREATE TABLE IF NOT EXISTS shop_products (
  product_id TEXT PRIMARY KEY,
  product_type TEXT NOT NULL CHECK (product_type IN ('pack', 'accessory')),
  display_name TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  price_gold INTEGER NOT NULL DEFAULT 0 CHECK (price_gold >= 0),
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  pack_size INTEGER NOT NULL DEFAULT 5 CHECK (pack_size >= 1),
  weight_n INTEGER NOT NULL DEFAULT 70 CHECK (weight_n >= 0),
  weight_r INTEGER NOT NULL DEFAULT 20 CHECK (weight_r >= 0),
  weight_sr INTEGER NOT NULL DEFAULT 8 CHECK (weight_sr >= 0),
  weight_ur INTEGER NOT NULL DEFAULT 2 CHECK (weight_ur >= 0),
  pool_mode TEXT NOT NULL DEFAULT 'explicit'
    CHECK (pool_mode IN ('explicit', 'all_non_token')),
  pool_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  accessory_type TEXT NOT NULL DEFAULT ''
    CHECK (accessory_type = '' OR accessory_type IN ('icon', 'card_back', 'field')),
  accessory_id TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shop_products_enabled
  ON shop_products (enabled, product_type, sort_order);

-- Key/value runtime config (catalog revision, feature flags, etc.).
CREATE TABLE IF NOT EXISTS app_config (
  config_key TEXT PRIMARY KEY,
  config_value JSONB NOT NULL DEFAULT 'null'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ops grants land here; inventory/wallet change only on claim TX.
CREATE TABLE IF NOT EXISTS mailbox_items (
  id BIGSERIAL PRIMARY KEY,
  account_key TEXT NOT NULL REFERENCES accounts(account_key) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'ops',
  title TEXT NOT NULL DEFAULT '',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'claimed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  claimed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_mailbox_account_status
  ON mailbox_items (account_key, status, created_at DESC);

-- Welcome gold: at most one mailbox row per account.
CREATE UNIQUE INDEX IF NOT EXISTS idx_mailbox_welcome_once
  ON mailbox_items (account_key)
  WHERE source = 'welcome';
