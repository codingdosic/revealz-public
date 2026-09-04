/**
 * Ops mutations — grant, account gold/name, maintenance file, precheck, pg_dump.
 * account_key is never renamed. Arbitrary SQL is not exposed.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const db = require("./db");
const { loadSnapshot, bumpMetaRevision } = require("./routes");
const mailbox = require("./mailbox");

const OPS_DATA = path.join(__dirname, "..", "ops-data");
const MAINT_PATH = path.join(OPS_DATA, "maintenance.json");
const BACKUP_DIR = path.join(OPS_DATA, "backups");
const CARDS_ROOT = path.join(__dirname, "..", "..", "resources", "cards");
const MAX_GRANT = 99;
/** CardData.trigger_type TOKEN bit (클라 CollectionStore.TRIGGER_TOKEN과 동일). */
const TRIGGER_TOKEN = 128;

function ensureOpsDir() {
  fs.mkdirSync(OPS_DATA, { recursive: true });
}

function readMaintenance() {
  try {
    const raw = JSON.parse(fs.readFileSync(MAINT_PATH, "utf8"));
    return {
      enabled: raw.enabled === true,
      message: String(raw.message || ""),
    };
  } catch (_) {
    return { enabled: false, message: "" };
  }
}

function writeMaintenance(enabled, message) {
  ensureOpsDir();
  const body = {
    enabled: enabled === true,
    message: enabled ? String(message || "") : "",
    updatedAt: new Date().toISOString(),
  };
  fs.writeFileSync(MAINT_PATH, JSON.stringify(body, null, 2), "utf8");
  return body;
}

let catalogCardsCache = null;

function listCatalogCards() {
  if (catalogCardsCache) {
    return catalogCardsCache;
  }
  const cards = [];
  if (!fs.existsSync(CARDS_ROOT)) {
    return cards;
  }
  function walk(dir) {
    let ents;
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch (_) {
      return;
    }
    for (const ent of ents) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        walk(p);
        continue;
      }
      if (!ent.name.endsWith(".tres")) {
        continue;
      }
      const text = fs.readFileSync(p, "utf8");
      const idM = text.match(/^id = (\d+)\s*$/m);
      if (!idM) {
        continue;
      }
      const id = Number(idM[1]);
      if (!Number.isFinite(id) || id <= 0) {
        continue;
      }
      const nameM = text.match(/^card_name = "([^"]*)"/m);
      const triggerM = text.match(/^trigger_type = (\d+)\s*$/m);
      const triggerType = triggerM ? Number(triggerM[1]) : 0;
      cards.push({
        id,
        name: nameM ? String(nameM[1]) : "",
        triggerType: Number.isFinite(triggerType) ? triggerType : 0,
        isToken: Number.isFinite(triggerType) && (triggerType & TRIGGER_TOKEN) !== 0,
      });
    }
  }
  walk(CARDS_ROOT);
  cards.sort((a, b) => a.id - b.id);
  catalogCardsCache = cards;
  return catalogCardsCache;
}

/** 팩 풀·grant-all용 — TOKEN 트리거 카드 제외. */
function listCatalogCardIds() {
  return listCatalogCards()
    .filter((c) => !c.isToken)
    .map((c) => c.id);
}

function catalogNameById(cardId) {
  const found = listCatalogCards().find((c) => c.id === cardId);
  return found && found.name ? found.name : "";
}

function clampCount(n) {
  const v = Math.floor(Number(n));
  if (!Number.isFinite(v) || v < 1) {
    return 0;
  }
  return Math.min(MAX_GRANT, v);
}

function clampRarity(n, fallback) {
  if (n === undefined || n === null || n === "") {
    return fallback;
  }
  const v = Math.floor(Number(n));
  if (!Number.isFinite(v) || v < 0 || v > 3) {
    return null;
  }
  return v;
}

async function grantRows(accountKey, rows) {
  const enqueueRows = rows.map((row) => {
    const name = catalogNameById(row.cardId) || `카드 ${row.cardId}`;
    return {
      source: "ops",
      title: name,
      payload: {
        cards: [{ id: row.cardId, rarity: row.rarity, count: row.count, name }],
      },
    };
  });
  const items = await mailbox.enqueueMany(accountKey, enqueueRows);
  return { items, snapshot: await loadSnapshot(accountKey) };
}

async function grantOne(accountKey, cardId, rarity, count) {
  const id = Math.floor(Number(cardId));
  const r = clampRarity(rarity, 0);
  const n = clampCount(count);
  if (!Number.isFinite(id) || id <= 0) {
    throw Object.assign(new Error("invalid_card_id"), { status: 400 });
  }
  if (r === null) {
    throw Object.assign(new Error("invalid_rarity"), { status: 400 });
  }
  if (n < 1) {
    throw Object.assign(new Error("invalid_count"), { status: 400 });
  }
  const result = await grantRows(accountKey, [{ cardId: id, rarity: r, count: n }]);
  return {
    ok: true,
    granted: { mode: "one", cardId: id, rarity: r, count: n },
    enqueued: result.items,
    snapshot: result.snapshot,
  };
}

async function grantAll(accountKey, count) {
  const n = clampCount(count);
  if (n < 1) {
    throw Object.assign(new Error("invalid_count"), { status: 400 });
  }
  const ids = listCatalogCardIds();
  if (!ids.length) {
    throw Object.assign(new Error("catalog_empty"), { status: 500 });
  }
  const rows = [];
  for (const cardId of ids) {
    for (let rarity = 0; rarity <= 3; rarity++) {
      rows.push({ cardId, rarity, count: n });
    }
  }
  const result = await grantRows(accountKey, rows);
  return {
    ok: true,
    granted: { mode: "all", cardIds: ids.length, rarities: 4, count: n, rows: rows.length },
    enqueuedCount: result.items.length,
    snapshot: result.snapshot,
  };
}

async function grantGold(accountKey, goldRaw) {
  const gold = Math.floor(Number(goldRaw));
  if (!Number.isFinite(gold) || gold < 1) {
    throw Object.assign(new Error("invalid_gold"), { status: 400 });
  }
  const capped = Math.min(gold, 999999999);
  const item = await mailbox.enqueue(accountKey, {
    source: "ops",
    title: "골드",
    payload: { gold: capped },
  });
  return {
    ok: true,
    granted: { mode: "gold", gold: capped },
    enqueued: item,
    snapshot: await loadSnapshot(accountKey),
  };
}

async function searchByDisplayName(displayName) {
  const listed = await listAccounts({
    q: displayName,
    sort: "name",
    order: "asc",
    page: 1,
    limit: 20,
  });
  return listed.accounts.map((a) => ({
    account: {
      accountKey: a.accountKey,
      displayName: a.displayName,
    },
  }));
}

/**
 * Paginated account browse. q matches display_name or account_key (ILIKE).
 * sort: name | created. order: asc | desc. limit default 20, max 50.
 * @param {{ q?: string, sort?: string, order?: string, page?: number, limit?: number }} opts
 */
async function listAccounts(opts = {}) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const q = String(opts.q || "").trim().slice(0, 120);
  const sort = String(opts.sort || "created").toLowerCase() === "name" ? "name" : "created";
  const order = String(opts.order || "desc").toLowerCase() === "asc" ? "ASC" : "DESC";
  const limitRaw = Math.floor(Number(opts.limit) || 20);
  const limit = Math.min(50, Math.max(1, Number.isFinite(limitRaw) ? limitRaw : 20));
  const pageRaw = Math.floor(Number(opts.page) || 1);
  const page = Math.max(1, Number.isFinite(pageRaw) ? pageRaw : 1);
  const offset = (page - 1) * limit;

  const where = q
    ? `WHERE display_name ILIKE $1 OR account_key ILIKE $1`
    : "";
  const params = q ? [`%${q}%`] : [];
  const orderSql =
    sort === "name"
      ? `ORDER BY LOWER(display_name) ${order}, account_key ${order}`
      : `ORDER BY created_at ${order}, account_key ${order}`;

  const countRes = await db.query(
    `SELECT COUNT(*)::int AS n FROM accounts ${where}`,
    params
  );
  const total = countRes.rowCount ? Number(countRes.rows[0].n) || 0 : 0;

  const listParams = q ? [`%${q}%`, limit, offset] : [limit, offset];
  const listRes = await db.query(
    `SELECT account_key, display_name, created_at, auth_kind
     FROM accounts
     ${where}
     ${orderSql}
     LIMIT $${q ? 2 : 1} OFFSET $${q ? 3 : 2}`,
    listParams
  );

  const accounts = listRes.rows.map((r) => ({
    accountKey: r.account_key,
    displayName: r.display_name || r.account_key,
    authKind: r.auth_kind || "guest",
    createdAt: r.created_at ? new Date(r.created_at).toISOString() : null,
  }));

  return {
    ok: true,
    accounts,
    total,
    page,
    limit,
    sort,
    order: order.toLowerCase(),
    q,
  };
}

async function patchAccount(accountKey, goldRaw, displayNameRaw) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const snap = await loadSnapshot(accountKey);
  if (!snap) {
    throw Object.assign(new Error("account_not_found"), { status: 404 });
  }
  const updates = {};
  if (displayNameRaw !== undefined && displayNameRaw !== null) {
    updates.displayName = String(displayNameRaw).slice(0, 64);
  }
  if (goldRaw !== undefined && goldRaw !== null && goldRaw !== "") {
    const gold = Math.floor(Number(goldRaw));
    if (!Number.isFinite(gold) || gold < 0) {
      throw Object.assign(new Error("invalid_gold"), { status: 400 });
    }
    updates.gold = Math.min(gold, 999999999);
  }
  if (!Object.keys(updates).length) {
    throw Object.assign(new Error("nothing_to_update"), { status: 400 });
  }
  await db.withTransaction(async (client) => {
    if (updates.displayName !== undefined) {
      await client.query(`UPDATE accounts SET display_name = $2 WHERE account_key = $1`, [
        accountKey,
        updates.displayName,
      ]);
    }
    if (updates.gold !== undefined) {
      await client.query(
        `INSERT INTO wallets (account_key, gold) VALUES ($1, $2)
         ON CONFLICT (account_key) DO UPDATE SET gold = EXCLUDED.gold`,
        [accountKey, updates.gold]
      );
    }
    await bumpMetaRevision(client, accountKey);
  });
  return { ok: true, updated: updates, snapshot: await loadSnapshot(accountKey) };
}

/**
 * Hard-delete account row (CASCADE wallets/owned/decks) and tombstone the key
 * so the same guest id cannot remigrate via PUT.
 */
async function deleteAccount(accountKey) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const key = String(accountKey || "").trim();
  if (!key) {
    throw Object.assign(new Error("account_key_required"), { status: 400 });
  }
  const existing = await db.query(`SELECT 1 FROM accounts WHERE account_key = $1`, [key]);
  if (!existing.rowCount) {
    throw Object.assign(new Error("account_not_found"), { status: 404 });
  }
  await db.withTransaction(async (client) => {
    await client.query(
      `INSERT INTO deleted_accounts (account_key, deleted_at)
       VALUES ($1, NOW())
       ON CONFLICT (account_key) DO UPDATE SET deleted_at = NOW()`,
      [key]
    );
    await client.query(`DELETE FROM accounts WHERE account_key = $1`, [key]);
  });
  return { ok: true, deletedAccountKey: key };
}

function writePrecheck(health) {
  ensureOpsDir();
  const ts = new Date();
  const stamp = ts.toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const file = path.join(OPS_DATA, `precheck-${stamp}.json`);
  const body = { ts: ts.toISOString(), health };
  fs.writeFileSync(file, JSON.stringify(body, null, 2), "utf8");
  return { ok: true, file: path.basename(file), health };
}

function parseMetaUrl() {
  const raw = String(process.env.META_DATABASE_URL || "").trim();
  if (!raw) {
    return null;
  }
  const u = new URL(raw);
  const database = decodeURIComponent(u.pathname.replace(/^\//, ""));
  return {
    host: u.hostname || "127.0.0.1",
    port: u.port || "5432",
    user: decodeURIComponent(u.username || ""),
    password: decodeURIComponent(u.password || ""),
    database,
  };
}

function listBackups() {
  if (!fs.existsSync(BACKUP_DIR)) {
    return [];
  }
  return fs
    .readdirSync(BACKUP_DIR)
    .filter((n) => n.endsWith(".dump") || n.endsWith(".sql"))
    .map((name) => {
      const st = fs.statSync(path.join(BACKUP_DIR, name));
      return { name, bytes: st.size, mtime: st.mtime.toISOString() };
    })
    .sort((a, b) => (a.mtime < b.mtime ? 1 : -1));
}

function slugifyLabel(label) {
  return String(label || "")
    .trim()
    .replace(/[\\/:*?"<>|]/g, "")
    .replace(/\s+/g, "_")
    .slice(0, 80);
}

function runBackup(label) {
  const cfg = parseMetaUrl();
  if (!cfg) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const slug = slugifyLabel(label);
  if (!slug) {
    throw Object.assign(new Error("backup_label_required"), { status: 400 });
  }
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "").replace("T", "_");
  const name = `${stamp}_${slug}.dump`;
  const out = path.join(BACKUP_DIR, name);
  const bin = String(process.env.PG_DUMP || "pg_dump").trim() || "pg_dump";
  const args = ["-Fc", "-h", cfg.host, "-p", String(cfg.port), "-U", cfg.user, "-d", cfg.database, "-f", out];
  const result = spawnSync(bin, args, {
    env: { ...process.env, PGPASSWORD: cfg.password },
    encoding: "utf8",
    timeout: 120000,
    windowsHide: true,
  });
  if (result.error) {
    throw Object.assign(new Error(`pg_dump_missing:${result.error.message}`), { status: 500 });
  }
  if (result.status !== 0) {
    const err = String(result.stderr || result.stdout || "pg_dump_failed").slice(0, 400);
    throw Object.assign(new Error(err), { status: 500 });
  }
  let bytes = 0;
  try {
    bytes = fs.statSync(out).size;
  } catch (_) {}
  if (bytes <= 0) {
    throw Object.assign(new Error("backup_empty"), { status: 500 });
  }
  return { ok: true, name, bytes, backups: listBackups() };
}

function runRestore(name) {
  const cfg = parseMetaUrl();
  if (!cfg) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const safeName = path.basename(String(name || ""));
  if (!safeName || (!safeName.endsWith(".dump") && !safeName.endsWith(".sql"))) {
    throw Object.assign(new Error("invalid_backup_name"), { status: 400 });
  }
  const filePath = path.join(BACKUP_DIR, safeName);
  if (!fs.existsSync(filePath)) {
    throw Object.assign(new Error("backup_not_found"), { status: 404 });
  }
  const bin = String(process.env.PG_RESTORE || "pg_restore").trim() || "pg_restore";
  const args = ["-Fc", "-h", cfg.host, "-p", String(cfg.port), "-U", cfg.user, "-d", cfg.database, "--clean", "--if-exists", filePath];
  const result = spawnSync(bin, args, {
    env: { ...process.env, PGPASSWORD: cfg.password },
    encoding: "utf8",
    timeout: 300000,
    windowsHide: true,
  });
  if (result.error) {
    throw Object.assign(new Error(`pg_restore_missing:${result.error.message}`), { status: 500 });
  }
  if (result.status !== 0) {
    const err = String(result.stderr || result.stdout || "pg_restore_failed").slice(0, 400);
    throw Object.assign(new Error(err), { status: 500 });
  }
  return { ok: true, restored: safeName };
}

module.exports = {
  readMaintenance,
  writeMaintenance,
  loadSnapshot,
  searchByDisplayName,
  listAccounts,
  grantOne,
  grantAll,
  grantGold,
  patchAccount,
  deleteAccount,
  writePrecheck,
  runBackup,
  runRestore,
  listBackups,
  listCatalogCardIds,
};
