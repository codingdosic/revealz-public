/**
 * MetaSrv pack purchase — server-side roll + wallet/owned transaction.
 */

"use strict";

const db = require("./db");

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {object} body
 */
async function purchasePack(client, accountKey, body) {
  const productId = String(body.product_id || body.productId || "").trim();
  const packCount = Math.max(1, Math.floor(Number(body.pack_count || body.packCount) || 1));
  const unitPrice = Math.max(0, Math.floor(Number(body.price_gold || body.priceGold) || 0));
  const packSize = Math.max(1, Math.floor(Number(body.pack_size || body.packSize) || 1));
  const totalPrice = unitPrice * packCount;
  const weights = [
    Math.max(0, Math.floor(Number(body.weight_n ?? body.weightN) || 0)),
    Math.max(0, Math.floor(Number(body.weight_r ?? body.weightR) || 0)),
    Math.max(0, Math.floor(Number(body.weight_sr ?? body.weightSr) || 0)),
    Math.max(0, Math.floor(Number(body.weight_ur ?? body.weightUr) || 0)),
  ];
  const poolRaw = Array.isArray(body.pool) ? body.pool : [];
  const pool = poolRaw
    .map((id) => Math.floor(Number(id)))
    .filter((id) => Number.isFinite(id) && id > 0);

  if (!productId) {
    const err = new Error("product_id_required");
    err.code = "bad_request";
    throw err;
  }
  if (pool.length === 0) {
    const err = new Error("empty_pool");
    err.code = "bad_request";
    throw err;
  }

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

  const grantedIds = [];
  const grantedRarities = [];
  const totalCards = packSize * packCount;
  for (let i = 0; i < totalCards; i++) {
    grantedRarities.push(rollRarity(weights));
    grantedIds.push(pool[Math.floor(Math.random() * pool.length)]);
  }

  const goldAfter = goldNow - totalPrice;
  await client.query(`UPDATE wallets SET gold = $2 WHERE account_key = $1`, [
    accountKey,
    goldAfter,
  ]);

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

  await client.query(
    `UPDATE accounts SET meta_revision = COALESCE(meta_revision, 0) + 1 WHERE account_key = $1`,
    [accountKey]
  );
  const revRes = await client.query(
    `SELECT meta_revision FROM accounts WHERE account_key = $1`,
    [accountKey]
  );

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

  return {
    ok: true,
    product_id: productId,
    spent: totalPrice,
    pack_count: packCount,
    gold: goldAfter,
    granted_card_ids: grantedIds,
    granted_rarities: grantedRarities,
    owned,
    metaRevision: revRes.rowCount ? Number(revRes.rows[0].meta_revision) || 0 : 0,
  };
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
  purchasePack,
};
