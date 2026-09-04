/**
 * MetaSrv purchase — server catalog lookup (price/pool/weights). Client body: product_id + pack_count.
 */

"use strict";

const { rowToProduct } = require("./shop_catalog");

/**
 * @param {import("pg").PoolClient} client
 * @param {string} productId
 */
async function loadEnabledProduct(client, productId) {
  const id = String(productId || "").trim();
  if (!id) {
    return null;
  }
  const res = await client.query(
    `SELECT * FROM shop_products WHERE product_id = $1 AND enabled = TRUE`,
    [id]
  );
  if (res.rowCount === 0) {
    return null;
  }
  return rowToProduct(res.rows[0]);
}

/**
 * @param {object} product from rowToProduct
 * @returns {number[]}
 */
function resolvePool(product) {
  // Lazy require — ops ↔ routes ↔ purchase 순환 참조 방지.
  const { listCatalogCardIds } = require("./ops");
  const nonToken = new Set(listCatalogCardIds());
  if (product.poolMode === "all_non_token") {
    return Array.from(nonToken);
  }
  const raw = Array.isArray(product.pool) ? product.pool : [];
  return raw
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id) && id > 0 && nonToken.has(id));
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {object} body
 */
async function purchase(client, accountKey, body) {
  const productId = String(body.product_id || body.productId || "").trim();
  const packCount = Math.max(1, Math.floor(Number(body.pack_count || body.packCount) || 1));

  if (!productId) {
    const err = new Error("product_id_required");
    err.code = "bad_request";
    throw err;
  }

  const product = await loadEnabledProduct(client, productId);
  if (!product) {
    const err = new Error("product_not_found");
    err.code = "not_found";
    throw err;
  }

  if (product.productType === "accessory") {
    return purchaseAccessory(client, accountKey, product);
  }
  if (product.productType === "pack") {
    return purchasePack(client, accountKey, product, packCount);
  }

  const err = new Error("unsupported_product_type");
  err.code = "bad_request";
  throw err;
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {object} product
 * @param {number} packCount
 */
async function purchasePack(client, accountKey, product, packCount) {
  const unitPrice = Math.max(0, product.priceGold);
  const packSize = Math.max(1, product.packSize);
  const totalPrice = unitPrice * packCount;
  const weights = [product.weightN, product.weightR, product.weightSr, product.weightUr];
  const pool = resolvePool(product);

  if (pool.length === 0) {
    const err = new Error("empty_pool");
    err.code = "bad_request";
    throw err;
  }

  const goldAfter = await spendGold(client, accountKey, totalPrice);

  const grantedIds = [];
  const grantedRarities = [];
  const totalCards = packSize * packCount;
  for (let i = 0; i < totalCards; i++) {
    grantedRarities.push(rollRarity(weights));
    grantedIds.push(pool[Math.floor(Math.random() * pool.length)]);
  }

  for (let i = 0; i < grantedIds.length; i++) {
    const cardId = grantedIds[i];
    const rarity = grantedRarities[i];
    await client.query(
      `INSERT INTO owned_cards (account_key, card_id, rarity, count)
       VALUES ($1, $2, $3, 1)
       ON CONFLICT (account_key, card_id, rarity)
       DO UPDATE SET count = owned_cards.count + 1`,
      [accountKey, cardId, rarity]
    );
  }

  const metaRevision = await bumpRevision(client, accountKey);
  const owned = await loadOwnedCards(client, accountKey);

  return {
    ok: true,
    product_id: product.productId,
    product_type: "pack",
    spent: totalPrice,
    pack_count: packCount,
    gold: goldAfter,
    granted_card_ids: grantedIds,
    granted_rarities: grantedRarities,
    owned,
    metaRevision,
  };
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {object} product
 */
async function purchaseAccessory(client, accountKey, product) {
  const accType = String(product.accessoryType || "").trim();
  const accId = String(product.accessoryId || "").trim();
  if (!accType || !accId) {
    const err = new Error("invalid_accessory_product");
    err.code = "bad_request";
    throw err;
  }

  const existing = await client.query(
    `SELECT 1 FROM owned_accessories
     WHERE account_key = $1 AND accessory_type = $2 AND accessory_id = $3`,
    [accountKey, accType, accId]
  );
  if (existing.rowCount > 0) {
    const err = new Error("already_owned");
    err.code = "conflict";
    throw err;
  }

  const unitPrice = Math.max(0, product.priceGold);
  const goldAfter = await spendGold(client, accountKey, unitPrice);

  await client.query(
    `INSERT INTO owned_accessories (account_key, accessory_type, accessory_id)
     VALUES ($1, $2, $3)
     ON CONFLICT DO NOTHING`,
    [accountKey, accType, accId]
  );

  const metaRevision = await bumpRevision(client, accountKey);
  const ownedAccessories = await loadOwnedAccessories(client, accountKey);

  return {
    ok: true,
    product_id: product.productId,
    product_type: "accessory",
    spent: unitPrice,
    pack_count: 1,
    gold: goldAfter,
    granted_accessory_type: accType,
    granted_accessory_id: accId,
    ownedAccessories,
    metaRevision,
  };
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {number} totalPrice
 */
async function spendGold(client, accountKey, totalPrice) {
  const wallet = await client.query(
    `SELECT gold FROM wallets WHERE account_key = $1 FOR UPDATE`,
    [accountKey]
  );
  if (wallet.rowCount === 0) {
    const err = new Error("account_not_found");
    err.code = "not_found";
    throw err;
  }
  const goldNow = Number(wallet.rows[0].gold);
  if (goldNow < totalPrice) {
    const err = new Error("insufficient_gold");
    err.code = "conflict";
    throw err;
  }
  const goldAfter = goldNow - totalPrice;
  await client.query(`UPDATE wallets SET gold = $2 WHERE account_key = $1`, [
    accountKey,
    goldAfter,
  ]);
  return goldAfter;
}

async function bumpRevision(client, accountKey) {
  await client.query(
    `UPDATE accounts SET meta_revision = COALESCE(meta_revision, 0) + 1 WHERE account_key = $1`,
    [accountKey]
  );
  const revRes = await client.query(
    `SELECT meta_revision FROM accounts WHERE account_key = $1`,
    [accountKey]
  );
  return revRes.rowCount ? Number(revRes.rows[0].meta_revision) || 0 : 0;
}

async function loadOwnedCards(client, accountKey) {
  const ownedRows = await client.query(
    `SELECT card_id, rarity, count FROM owned_cards WHERE account_key = $1`,
    [accountKey]
  );
  /** @type {Record<string, Record<string, number>>} */
  const owned = {};
  for (const o of ownedRows.rows) {
    const id = String(o.card_id);
    if (!owned[id]) owned[id] = {};
    owned[id][String(o.rarity)] = Number(o.count);
  }
  return owned;
}

async function loadOwnedAccessories(client, accountKey) {
  const rows = await client.query(
    `SELECT accessory_type, accessory_id FROM owned_accessories WHERE account_key = $1`,
    [accountKey]
  );
  /** @type {Record<string, string[]>} */
  const out = { icon: [], card_back: [], field: [] };
  for (const a of rows.rows) {
    const t = String(a.accessory_type || "");
    const id = String(a.accessory_id || "").trim();
    if (!out[t] || !id) continue;
    out[t].push(id);
  }
  return out;
}

/**
 * @param {number[]} weights length 4
 */
function rollRarity(weights) {
  let total = 0;
  for (const w of weights) total += w;
  if (total <= 0) return 0;
  let roll = Math.floor(Math.random() * total);
  for (let tier = 0; tier < weights.length; tier++) {
    roll -= weights[tier];
    if (roll < 0) return tier;
  }
  return 0;
}

module.exports = {
  purchase,
  purchasePack,
  /** @deprecated use purchase — kept for tests naming */
  purchasePackLegacyName: purchase,
};
