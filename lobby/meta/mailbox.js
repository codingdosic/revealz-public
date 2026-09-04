/**
 * Mailbox — ops enqueue pending rewards; claim applies inventory/wallet in Meta TX.
 * Payload is gold XOR cards (one kind per row). Claim is idempotent via status.
 */

"use strict";

const db = require("./db");

const WELCOME_GOLD = 1000000;
const WELCOME_SOURCE = "welcome";
const WELCOME_TITLE = "시작 골드";

function routesApi() {
  return require("./routes");
}

function httpErr(message, status, code) {
  const e = new Error(message);
  e.status = status;
  e.code = code || message;
  return e;
}

function toIso(v) {
  if (!v) return "";
  const d = v instanceof Date ? v : new Date(v);
  if (Number.isNaN(d.getTime())) return String(v);
  return d.toISOString();
}

function rowToItem(row) {
  const payload = row.payload && typeof row.payload === "object" ? row.payload : {};
  return {
    id: String(row.id),
    account_key: String(row.account_key),
    source: String(row.source || "ops"),
    title: String(row.title || ""),
    payload,
    status: String(row.status || "pending"),
    created_at: toIso(row.created_at),
    claimed_at: row.claimed_at ? toIso(row.claimed_at) : "",
  };
}

function normalizePayload(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  const gold = Math.floor(Number(src.gold) || 0);
  const cardsIn = Array.isArray(src.cards) ? src.cards : [];
  const cards = [];
  for (const c of cardsIn) {
    if (!c || typeof c !== "object") continue;
    const id = Math.floor(Number(c.id || c.cardId || c.card_id) || 0);
    const rarity = Math.floor(Number(c.rarity));
    const count = Math.floor(Number(c.count) || 1);
    if (id <= 0 || !Number.isFinite(rarity) || rarity < 0 || rarity > 3 || count < 1) {
      throw httpErr("invalid_card_payload", 400, "bad_request");
    }
    const name = String(c.name || "").trim();
    const entry = { id, rarity, count };
    if (name) entry.name = name;
    cards.push(entry);
  }
  const hasGold = gold > 0;
  const hasCards = cards.length > 0;
  if (hasGold === hasCards) {
    throw httpErr("payload_gold_xor_cards", 400, "bad_request");
  }
  if (hasGold) {
    return { gold };
  }
  return { cards };
}

async function countPending(accountKey, client) {
  const q = client || db;
  const res = await q.query(
    `SELECT COUNT(*)::int AS n FROM mailbox_items
     WHERE account_key = $1 AND status = 'pending'`,
    [accountKey]
  );
  return res.rowCount ? Number(res.rows[0].n) || 0 : 0;
}

async function applyPayload(client, accountKey, payload) {
  const gold = Math.floor(Number(payload.gold) || 0);
  if (gold > 0) {
    await client.query(
      `INSERT INTO wallets (account_key, gold) VALUES ($1, $2)
       ON CONFLICT (account_key) DO UPDATE SET gold = wallets.gold + EXCLUDED.gold`,
      [accountKey, gold]
    );
  }
  const cards = Array.isArray(payload.cards) ? payload.cards : [];
  for (const c of cards) {
    const cardId = Math.floor(Number(c.id || c.cardId) || 0);
    const rarity = Math.floor(Number(c.rarity));
    const count = Math.max(1, Math.floor(Number(c.count) || 1));
    if (cardId <= 0 || rarity < 0 || rarity > 3) continue;
    await client.query(
      `INSERT INTO owned_cards (account_key, card_id, rarity, count)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (account_key, card_id, rarity)
       DO UPDATE SET count = owned_cards.count + EXCLUDED.count`,
      [accountKey, cardId, rarity, count]
    );
  }
}

async function enqueue(accountKey, opts) {
  if (!db.isConfigured()) {
    throw httpErr("meta_db_not_configured", 503);
  }
  const key = String(accountKey || "").trim();
  if (!key) {
    throw httpErr("account_key_required", 400, "bad_request");
  }
  const snap = await routesApi().loadSnapshot(key);
  if (!snap) {
    throw httpErr("account_not_found", 404, "not_found");
  }
  const payload = normalizePayload(opts && opts.payload);
  const title = String((opts && opts.title) || "").trim().slice(0, 120);
  const source = String((opts && opts.source) || "ops").slice(0, 32) || "ops";
  const inserted = await db.query(
    `INSERT INTO mailbox_items (account_key, source, title, payload, status)
     VALUES ($1, $2, $3, $4::jsonb, 'pending')
     RETURNING id, account_key, source, title, payload, status, created_at, claimed_at`,
    [key, source, title || "선물", JSON.stringify(payload)]
  );
  return rowToItem(inserted.rows[0]);
}

async function enqueueInTx(client, accountKey, opts) {
  const key = String(accountKey || "").trim();
  if (!key) {
    throw httpErr("account_key_required", 400, "bad_request");
  }
  const payload = normalizePayload(opts && opts.payload);
  const title = String((opts && opts.title) || "").trim().slice(0, 120) || "선물";
  const source = String((opts && opts.source) || "ops").slice(0, 32) || "ops";
  const inserted = await client.query(
    `INSERT INTO mailbox_items (account_key, source, title, payload, status)
     VALUES ($1, $2, $3, $4::jsonb, 'pending')
     RETURNING id, account_key, source, title, payload, status, created_at, claimed_at`,
    [key, source, title, JSON.stringify(payload)]
  );
  return inserted.rowCount ? rowToItem(inserted.rows[0]) : null;
}

async function enqueueWelcomeGold(client, accountKey) {
  const key = String(accountKey || "").trim();
  if (!key) {
    return null;
  }
  const inserted = await client.query(
    `INSERT INTO mailbox_items (account_key, source, title, payload, status)
     VALUES ($1, $2, $3, $4::jsonb, 'pending')
     ON CONFLICT (account_key) WHERE source = 'welcome' DO NOTHING
     RETURNING id, account_key, source, title, payload, status, created_at, claimed_at`,
    [key, WELCOME_SOURCE, WELCOME_TITLE, JSON.stringify({ gold: WELCOME_GOLD })]
  );
  return inserted.rowCount ? rowToItem(inserted.rows[0]) : null;
}

async function enqueueMany(accountKey, rows) {
  if (!db.isConfigured()) {
    throw httpErr("meta_db_not_configured", 503);
  }
  const key = String(accountKey || "").trim();
  if (!key) {
    throw httpErr("account_key_required", 400, "bad_request");
  }
  const snap = await routesApi().loadSnapshot(key);
  if (!snap) {
    throw httpErr("account_not_found", 404, "not_found");
  }
  if (!Array.isArray(rows) || !rows.length) {
    throw httpErr("nothing_to_enqueue", 400, "bad_request");
  }
  const items = [];
  await db.withTransaction(async (client) => {
    for (const row of rows) {
      const payload = normalizePayload(row.payload);
      const title = String(row.title || "").trim().slice(0, 120) || "선물";
      const source = String(row.source || "ops").slice(0, 32) || "ops";
      const inserted = await client.query(
        `INSERT INTO mailbox_items (account_key, source, title, payload, status)
         VALUES ($1, $2, $3, $4::jsonb, 'pending')
         RETURNING id, account_key, source, title, payload, status, created_at, claimed_at`,
        [key, source, title, JSON.stringify(payload)]
      );
      items.push(rowToItem(inserted.rows[0]));
    }
  });
  return items;
}

async function listPending(accountKey) {
  if (!db.isConfigured()) {
    throw httpErr("meta_db_not_configured", 503);
  }
  const key = String(accountKey || "").trim();
  if (!key) {
    throw httpErr("account_key_required", 400, "bad_request");
  }
  const snap = await routesApi().loadSnapshot(key);
  if (!snap) {
    throw httpErr("account_not_found", 404, "not_found");
  }
  const res = await db.query(
    `SELECT id, account_key, source, title, payload, status, created_at, claimed_at
     FROM mailbox_items
     WHERE account_key = $1 AND status = 'pending'
     ORDER BY created_at DESC, id DESC`,
    [key]
  );
  const items = res.rows.map(rowToItem);
  return { ok: true, items, pendingCount: items.length };
}

async function claimOne(accountKey, itemId) {
  if (!db.isConfigured()) {
    throw httpErr("meta_db_not_configured", 503);
  }
  const key = String(accountKey || "").trim();
  const id = String(itemId || "").trim();
  if (!key) {
    throw httpErr("account_key_required", 400, "bad_request");
  }
  if (!id || !/^\d+$/.test(id)) {
    throw httpErr("invalid_mailbox_id", 400, "bad_request");
  }
  const claimed = await db.withTransaction(async (client) => {
    const locked = await client.query(
      `SELECT id, account_key, source, title, payload, status, created_at, claimed_at
       FROM mailbox_items
       WHERE id = $1 AND account_key = $2
       FOR UPDATE`,
      [id, key]
    );
    if (!locked.rowCount) {
      throw httpErr("mailbox_item_not_found", 404, "not_found");
    }
    const row = locked.rows[0];
    if (String(row.status) !== "pending") {
      throw httpErr("already_claimed", 409, "conflict");
    }
    await applyPayload(client, key, row.payload && typeof row.payload === "object" ? row.payload : {});
    const updated = await client.query(
      `UPDATE mailbox_items
       SET status = 'claimed', claimed_at = NOW()
       WHERE id = $1 AND account_key = $2 AND status = 'pending'
       RETURNING id, account_key, source, title, payload, status, created_at, claimed_at`,
      [id, key]
    );
    if (!updated.rowCount) {
      throw httpErr("already_claimed", 409, "conflict");
    }
    await routesApi().bumpMetaRevision(client, key);
    return rowToItem(updated.rows[0]);
  });
  const snapshot = await routesApi().loadSnapshot(key);
  return { ok: true, claimed, snapshot };
}

async function claimAll(accountKey) {
  if (!db.isConfigured()) {
    throw httpErr("meta_db_not_configured", 503);
  }
  const key = String(accountKey || "").trim();
  if (!key) {
    throw httpErr("account_key_required", 400, "bad_request");
  }
  const claimedCount = await db.withTransaction(async (client) => {
    const acc = await client.query(
      `SELECT 1 FROM accounts WHERE account_key = $1 FOR UPDATE`,
      [key]
    );
    if (!acc.rowCount) {
      throw httpErr("account_not_found", 404, "not_found");
    }
    const pending = await client.query(
      `SELECT id, payload
       FROM mailbox_items
       WHERE account_key = $1 AND status = 'pending'
       ORDER BY created_at ASC, id ASC
       FOR UPDATE`,
      [key]
    );
    for (const row of pending.rows) {
      await applyPayload(client, key, row.payload && typeof row.payload === "object" ? row.payload : {});
    }
    if (pending.rowCount) {
      await client.query(
        `UPDATE mailbox_items
         SET status = 'claimed', claimed_at = NOW()
         WHERE account_key = $1 AND status = 'pending'`,
        [key]
      );
      await routesApi().bumpMetaRevision(client, key);
    }
    return pending.rowCount;
  });
  const snapshot = await routesApi().loadSnapshot(key);
  return { ok: true, claimedCount, snapshot };
}

module.exports = {
  WELCOME_GOLD,
  enqueue,
  enqueueInTx,
  enqueueWelcomeGold,
  enqueueMany,
  listPending,
  claimOne,
  claimAll,
  countPending,
  rowToItem,
};
