/**
 * GET/PUT /v1/meta/accounts/:accountKey
 * POST /v1/meta/accounts/:accountKey/purchase
 * GET  /v1/meta/accounts/:accountKey/mailbox
 * POST /v1/meta/accounts/:accountKey/mailbox/claim
 * POST /v1/meta/accounts/:accountKey/mailbox/claim-all
 * GET /v1/shop/catalog
 */

"use strict";

const db = require("./db");
const { purchase } = require("./purchase");
const { validateDeckOwned } = require("./validate_deck");
const shopCatalog = require("./shop_catalog");
const { updateProfile, sanitizeDisplayName, resolveProfileIconId } = require("./profile");
const mailbox = require("./mailbox");

/**
 * @param {import("http").ServerResponse} res
 * @param {number} status
 * @param {object} body
 */
function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
    "Access-Control-Allow-Origin": "*",
  });
  res.end(payload);
}

/**
 * @param {object} payload
 * @returns {{ card_back: string, field: string }}
 */
function deckAccessoriesFromPayload(payload) {
  const raw =
    payload && typeof payload.accessories === "object" ? payload.accessories : {};
  const deckRaw = raw && typeof raw === "object" ? raw : {};
  const cardBack = String(deckRaw.card_back || payload.card_back || "").trim();
  const field = String(deckRaw.field || payload.field || "").trim();
  /** @type {{ card_back: string, field: string }} */
  const out = { card_back: "", field: "" };
  if (cardBack) out.card_back = cardBack.slice(0, 128);
  if (field) out.field = field.slice(0, 128);
  return out;
}

/**
 * @param {object} payload
 * @returns {{ card_id: number, rarity: number } | Record<string, never>}
 */
function deckMainCardFromPayload(payload) {
  const raw =
    payload && typeof payload.main_card === "object" && payload.main_card
      ? payload.main_card
      : null;
  if (!raw) return {};
  const cardId = Number(raw.card_id) || 0;
  if (cardId <= 0) return {};
  const rarity = Math.max(0, Math.min(3, Number(raw.rarity) || 0));
  return { card_id: cardId, rarity };
}

/**
 * @param {import("http").IncomingMessage} req
 * @returns {Promise<object>}
 */
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8").trim();
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

/**
 * @param {import("pg").PoolClient | null} client
 * @param {string} accountKey
 */
async function bumpMetaRevision(client, accountKey) {
  const q = client || db;
  await q.query(
    `UPDATE accounts SET meta_revision = COALESCE(meta_revision, 0) + 1 WHERE account_key = $1`,
    [accountKey]
  );
}

async function loadSnapshot(accountKey) {
  const acc = await db.query(
    `SELECT account_key, auth_kind, display_name, profile_icon_id, created_at, client_migrated_at, meta_revision
     FROM accounts WHERE account_key = $1`,
    [accountKey]
  );
  if (acc.rowCount === 0) {
    return null;
  }
  const row = acc.rows[0];
  const wallet = await db.query(`SELECT gold FROM wallets WHERE account_key = $1`, [accountKey]);
  const ownedRows = await db.query(
    `SELECT card_id, rarity, count FROM owned_cards WHERE account_key = $1`,
    [accountKey]
  );
  const accessoryRows = await db.query(
    `SELECT accessory_type, accessory_id FROM owned_accessories WHERE account_key = $1`,
    [accountKey]
  );
  const deckRows = await db.query(
    `SELECT deck_id, name, format, payload FROM decks WHERE account_key = $1`,
    [accountKey]
  );

  /** @type {Record<string, Record<string, number>>} */
  const owned = {};
  for (const o of ownedRows.rows) {
    const id = String(o.card_id);
    if (!owned[id]) owned[id] = {};
    owned[id][String(o.rarity)] = Number(o.count);
  }

  /** @type {Record<string, string[]>} */
  const ownedAccessories = { icon: [], card_back: [], field: [] };
  for (const a of accessoryRows.rows) {
    const t = String(a.accessory_type || "");
    const id = String(a.accessory_id || "").trim();
    if (!id || !Object.prototype.hasOwnProperty.call(ownedAccessories, t)) continue;
    if (!ownedAccessories[t].includes(id)) ownedAccessories[t].push(id);
  }

  const decks = deckRows.rows.map((d) => {
    const payload = d.payload && typeof d.payload === "object" ? d.payload : {};
    const accessories = deckAccessoriesFromPayload(payload);
    const mainCard = deckMainCardFromPayload(payload);
    return {
      id: String(d.deck_id),
      name: String(d.name || payload.name || "Deck"),
      format: String(d.format || payload.format || "mono"),
      base_color: String(payload.base_color || "black"),
      card_ids: Array.isArray(payload.card_ids) ? payload.card_ids : [],
      card_rarities: Array.isArray(payload.card_rarities) ? payload.card_rarities : [],
      accessories,
      main_card: mainCard,
    };
  });

  return {
    account: {
      accountKey: String(row.account_key),
      authKind: String(row.auth_kind || "guest"),
      displayName: String(row.display_name || row.account_key),
      profileIconId: String(row.profile_icon_id || ""),
      clientMigratedAt: row.client_migrated_at
        ? new Date(row.client_migrated_at).toISOString()
        : null,
    },
    gold: wallet.rowCount ? Number(wallet.rows[0].gold) : 0,
    owned,
    ownedAccessories,
    decks,
    metaRevision: Number(row.meta_revision) || 0,
    mailboxPendingCount: await mailbox.countPending(accountKey),
  };
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {object} body
 */
async function upsertSnapshot(client, accountKey, body) {
  const account = body.account && typeof body.account === "object" ? body.account : {};
  const authKind = String(account.authKind || body.authKind || "guest").slice(0, 64);
  const nameSan = sanitizeDisplayName(
    account.displayName || body.displayName || accountKey,
    accountKey
  );
  const displayName = nameSan.ok ? nameSan.name : String(accountKey).slice(0, 50);
  const rawProfileIcon = String(
    account.profileIconId || body.profileIconId || ""
  ).trim().slice(0, 128);
  const decks = Array.isArray(body.decks) ? body.decks : [];

  const tomb = await client.query(
    `SELECT 1 FROM deleted_accounts WHERE account_key = $1`,
    [accountKey]
  );
  if (tomb.rowCount > 0) {
    const err = new Error("account_deleted");
    err.code = "account_deleted";
    throw err;
  }

  const existing = await client.query(
    `SELECT meta_revision FROM accounts WHERE account_key = $1 FOR UPDATE`,
    [accountKey]
  );
  const isCreate = existing.rowCount === 0;
  if (!isCreate) {
    const current = Number(existing.rows[0].meta_revision) || 0;
    const hasBase = body.baseRevision !== undefined && body.baseRevision !== null;
    const base = hasBase ? Number(body.baseRevision) : NaN;
    if (!hasBase || !Number.isFinite(base) || base !== current) {
      const err = new Error("revision_conflict");
      err.code = "revision_conflict";
      throw err;
    }
  }

  await client.query(
    `INSERT INTO accounts (account_key, auth_kind, display_name, profile_icon_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (account_key) DO UPDATE SET
       auth_kind = EXCLUDED.auth_kind,
       display_name = EXCLUDED.display_name`,
    [accountKey, authKind, displayName, ""]
  );

  if (isCreate) {
    // Economy/owned are server-only after create. Initial gold is always 0.
    await client.query(
      `INSERT INTO wallets (account_key, gold) VALUES ($1, 0)
       ON CONFLICT (account_key) DO NOTHING`,
      [accountKey]
    );

    const ownedAccessories =
      body.ownedAccessories && typeof body.ownedAccessories === "object"
        ? body.ownedAccessories
        : { icon: ["icon_default"], card_back: ["card_back_default"], field: ["default_field"] };
    const accessoryTypes = ["icon", "card_back", "field"];
    for (const accessoryType of accessoryTypes) {
      const idsRaw = ownedAccessories[accessoryType];
      if (!Array.isArray(idsRaw)) continue;
      for (const idRaw of idsRaw) {
        const accessoryId = String(idRaw || "").trim().slice(0, 128);
        if (!accessoryId) continue;
        await client.query(
          `INSERT INTO owned_accessories (account_key, accessory_type, accessory_id)
           VALUES ($1, $2, $3)
           ON CONFLICT DO NOTHING`,
          [accountKey, accessoryType, accessoryId]
        );
      }
    }
    await mailbox.enqueueWelcomeGold(client, accountKey);
  }

  // Icon ownership is known after owned_accessories (create) or existing rows (update).
  const profileIconId = await resolveProfileIconId(client, accountKey, rawProfileIcon);
  await client.query(
    `UPDATE accounts SET profile_icon_id = $2 WHERE account_key = $1`,
    [accountKey, profileIconId]
  );

  await client.query(`DELETE FROM decks WHERE account_key = $1`, [accountKey]);
  for (const deck of decks) {
    if (!deck || typeof deck !== "object") continue;
    const deckId = String(deck.id || "").trim();
    if (!deckId || deckId.startsWith("builtin_")) continue;
    const name = String(deck.name || "Deck").slice(0, 120);
    const format = String(deck.format || "mono").slice(0, 32);
    const payload = {
      id: deckId,
      name,
      format,
      base_color: String(deck.base_color || "black"),
      card_ids: Array.isArray(deck.card_ids) ? deck.card_ids : [],
      card_rarities: Array.isArray(deck.card_rarities) ? deck.card_rarities : [],
      accessories: deckAccessoriesFromPayload(deck),
      main_card: deckMainCardFromPayload(deck),
    };
    await client.query(
      `INSERT INTO decks (account_key, deck_id, name, format, payload)
       VALUES ($1, $2, $3, $4, $5::jsonb)`,
      [accountKey, deckId, name, format, JSON.stringify(payload)]
    );
  }

  await bumpMetaRevision(client, accountKey);
}

/**
 * Try handle meta route. Returns true if handled.
 * @param {import("http").IncomingMessage} req
 * @param {import("http").ServerResponse} res
 * @param {URL} url
 * @param {string} method
 */
async function tryHandle(req, res, url, method) {
  if (url.pathname === "/v1/shop/catalog") {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    if (method !== "GET") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      const catalog = await shopCatalog.loadPublicCatalog();
      json(res, 200, catalog);
      return true;
    } catch (e) {
      db.log("shop catalog error", e.message || e);
      json(res, 500, { error: "internal", message: String(e.message || e) });
      return true;
    }
  }

  const mailboxListMatch = url.pathname.match(/^\/v1\/meta\/accounts\/([^/]+)\/mailbox$/);
  if (mailboxListMatch) {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    const accountKey = decodeURIComponent(mailboxListMatch[1]).trim();
    if (!accountKey) {
      json(res, 400, { error: "account_key_required" });
      return true;
    }
    if (method !== "GET") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      db.log("GET", "mailbox", accountKey);
      json(res, 200, await mailbox.listPending(accountKey));
      return true;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      db.log("mailbox list error", e.message || e);
      if (code === "not_found") {
        json(res, 404, { error: String(e.message || "account_not_found") });
        return true;
      }
      json(res, Number(e.status) || 500, { error: String(e.message || e) });
      return true;
    }
  }

  const mailboxClaimAllMatch = url.pathname.match(
    /^\/v1\/meta\/accounts\/([^/]+)\/mailbox\/claim-all$/
  );
  if (mailboxClaimAllMatch) {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    const accountKey = decodeURIComponent(mailboxClaimAllMatch[1]).trim();
    if (!accountKey) {
      json(res, 400, { error: "account_key_required" });
      return true;
    }
    if (method !== "POST") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      db.log("POST", "mailbox/claim-all", accountKey);
      json(res, 200, await mailbox.claimAll(accountKey));
      return true;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      db.log("mailbox claim-all error", e.message || e);
      if (code === "not_found") {
        json(res, 404, { error: String(e.message || "account_not_found") });
        return true;
      }
      json(res, Number(e.status) || 500, { error: String(e.message || e) });
      return true;
    }
  }

  const mailboxClaimMatch = url.pathname.match(
    /^\/v1\/meta\/accounts\/([^/]+)\/mailbox\/claim$/
  );
  if (mailboxClaimMatch) {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    const accountKey = decodeURIComponent(mailboxClaimMatch[1]).trim();
    if (!accountKey) {
      json(res, 400, { error: "account_key_required" });
      return true;
    }
    if (method !== "POST") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      let body = {};
      try {
        body = await readBody(req);
      } catch (_) {
        json(res, 400, { error: "bad_json" });
        return true;
      }
      const itemId = body.id || body.itemId || body.item_id;
      db.log("POST", "mailbox/claim", accountKey, itemId);
      json(res, 200, await mailbox.claimOne(accountKey, itemId));
      return true;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      db.log("mailbox claim error", e.message || e);
      if (code === "not_found") {
        json(res, 404, { error: String(e.message || "mailbox_item_not_found") });
        return true;
      }
      if (code === "conflict") {
        json(res, 409, { error: String(e.message || "already_claimed") });
        return true;
      }
      if (code === "bad_request") {
        json(res, 400, { error: String(e.message || "bad_request") });
        return true;
      }
      json(res, Number(e.status) || 500, { error: String(e.message || e) });
      return true;
    }
  }

  const validateMatch = url.pathname.match(/^\/v1\/meta\/accounts\/([^/]+)\/validate-deck$/);
  if (validateMatch) {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    const accountKey = decodeURIComponent(validateMatch[1]).trim();
    if (!accountKey) {
      json(res, 400, { error: "account_key_required" });
      return true;
    }
    if (method !== "POST") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      let body = {};
      try {
        body = await readBody(req);
      } catch (_) {
        json(res, 400, { error: "bad_json" });
        return true;
      }
      const result = await validateDeckOwned(
        accountKey,
        body.card_ids || body.cardIds || [],
        body.card_rarities || body.cardRarities || []
      );
      if (!result.ok) {
        json(res, 409, result);
        return true;
      }
      json(res, 200, result);
      return true;
    } catch (e) {
      db.log("validate-deck error", e.message || e);
      json(res, 500, { error: "internal", message: String(e.message || e) });
      return true;
    }
  }

  const profileMatch = url.pathname.match(/^\/v1\/meta\/accounts\/([^/]+)\/profile$/);
  if (profileMatch) {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    const accountKey = decodeURIComponent(profileMatch[1]).trim();
    if (!accountKey) {
      json(res, 400, { error: "account_key_required" });
      return true;
    }
    if (method !== "POST") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      let body = {};
      try {
        body = await readBody(req);
      } catch (_) {
        json(res, 400, { error: "bad_json" });
        return true;
      }
      db.log("POST", "profile", accountKey);
      await db.withTransaction(async (client) => {
        await updateProfile(client, accountKey, body);
      });
      const snap = await loadSnapshot(accountKey);
      json(res, 200, snap);
      return true;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      db.log("profile error", e.message || e);
      if (code === "not_found") {
        json(res, 404, { error: String(e.message || "account_not_found") });
        return true;
      }
      if (code === "revision_conflict") {
        const snap = await loadSnapshot(accountKey);
        json(res, 409, { error: "revision_conflict", snapshot: snap });
        return true;
      }
      if (code === "account_deleted") {
        json(res, 410, { error: "account_deleted" });
        return true;
      }
      if (code === "conflict") {
        json(res, 409, { error: String(e.message || "conflict") });
        return true;
      }
      if (code === "bad_request") {
        json(res, 400, { error: String(e.message || "bad_request") });
        return true;
      }
      json(res, 500, { error: "internal", message: String(e.message || e) });
      return true;
    }
  }

  const purchaseMatch = url.pathname.match(/^\/v1\/meta\/accounts\/([^/]+)\/purchase$/);
  if (purchaseMatch) {
    if (!db.isConfigured()) {
      json(res, 503, { error: "meta_db_not_configured" });
      return true;
    }
    const accountKey = decodeURIComponent(purchaseMatch[1]).trim();
    if (!accountKey) {
      json(res, 400, { error: "account_key_required" });
      return true;
    }
    if (method !== "POST") {
      json(res, 405, { error: "method_not_allowed" });
      return true;
    }
    try {
      let body = {};
      try {
        body = await readBody(req);
      } catch (_) {
        json(res, 400, { error: "bad_json" });
        return true;
      }
      db.log("POST", "purchase", accountKey);
      const result = await db.withTransaction(async (client) => {
        return purchase(client, accountKey, body);
      });
      json(res, 200, result);
      return true;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      db.log("purchase error", e.message || e);
      if (code === "not_found") {
        json(res, 404, { error: String(e.message || "account_not_found") });
        return true;
      }
      if (code === "conflict") {
        json(res, 409, { error: String(e.message || "conflict") });
        return true;
      }
      if (code === "bad_request") {
        json(res, 400, { error: String(e.message || "bad_request") });
        return true;
      }
      json(res, 500, { error: "internal", message: String(e.message || e) });
      return true;
    }
  }

  const match = url.pathname.match(/^\/v1\/meta\/accounts\/([^/]+)$/);
  if (!match) {
    return false;
  }

  if (!db.isConfigured()) {
    json(res, 503, { error: "meta_db_not_configured" });
    return true;
  }

  const accountKey = decodeURIComponent(match[1]).trim();
  if (!accountKey) {
    json(res, 400, { error: "account_key_required" });
    return true;
  }

  try {
    if (method === "GET") {
      const snap = await loadSnapshot(accountKey);
      if (!snap) {
        const tomb = await db.query(
          `SELECT 1 FROM deleted_accounts WHERE account_key = $1`,
          [accountKey]
        );
        if (tomb.rowCount > 0) {
          json(res, 410, { error: "account_deleted" });
          return true;
        }
        json(res, 404, { error: "account_not_found" });
        return true;
      }
      json(res, 200, snap);
      return true;
    }

    if (method === "PUT" || method === "POST") {
      let body = {};
      try {
        body = await readBody(req);
      } catch (_) {
        json(res, 400, { error: "bad_json" });
        return true;
      }
      db.log(method, "upsert", accountKey);
      try {
        await db.withTransaction(async (client) => {
          await upsertSnapshot(client, accountKey, body);
        });
      } catch (e) {
        if (e && e.code === "revision_conflict") {
          const snap = await loadSnapshot(accountKey);
          json(res, 409, { error: "revision_conflict", snapshot: snap });
          return true;
        }
        if (e && e.code === "account_deleted") {
          json(res, 410, { error: "account_deleted" });
          return true;
        }
        throw e;
      }
      const snap = await loadSnapshot(accountKey);
      json(res, 200, snap);
      return true;
    }

    json(res, 405, { error: "method_not_allowed" });
    return true;
  } catch (e) {
    db.log("route error", e.message || e);
    json(res, 500, { error: "internal", message: String(e.message || e) });
    return true;
  }
}

module.exports = {
  tryHandle,
  loadSnapshot,
  bumpMetaRevision,
};
