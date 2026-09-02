/**
 * G3.1 — deck ⊆ owned multiset check (card_id + rarity).
 */

"use strict";

const db = require("./db");

/**
 * @param {string} accountKey
 * @param {unknown[]} cardIds
 * @param {unknown[]} cardRarities
 * @returns {Promise<{ ok: boolean, error?: string, detail?: string }>}
 */
async function validateDeckOwned(accountKey, cardIds, cardRarities) {
  if (!accountKey) {
    return { ok: false, error: "account_key_required" };
  }
  const ids = Array.isArray(cardIds) ? cardIds : [];
  const rarities = Array.isArray(cardRarities) ? cardRarities : [];
  if (ids.length === 0) {
    return { ok: false, error: "empty_deck" };
  }

  const acc = await db.query(`SELECT 1 FROM accounts WHERE account_key = $1`, [accountKey]);
  if (acc.rowCount === 0) {
    return { ok: false, error: "account_not_found" };
  }

  /** @type {Map<string, number>} */
  const need = new Map();
  for (let i = 0; i < ids.length; i++) {
    const cardId = Math.floor(Number(ids[i]));
    if (!Number.isFinite(cardId) || cardId <= 0) {
      return { ok: false, error: "invalid_card_id", detail: String(ids[i]) };
    }
    let rarity = 0;
    if (i < rarities.length) {
      rarity = Math.floor(Number(rarities[i]));
    }
    if (!Number.isFinite(rarity) || rarity < 0 || rarity > 3) {
      rarity = 0;
    }
    const key = `${cardId}:${rarity}`;
    need.set(key, (need.get(key) || 0) + 1);
  }

  const ownedRows = await db.query(
    `SELECT card_id, rarity, count FROM owned_cards WHERE account_key = $1`,
    [accountKey]
  );
  /** @type {Map<string, number>} */
  const have = new Map();
  for (const row of ownedRows.rows) {
    have.set(`${row.card_id}:${row.rarity}`, Number(row.count));
  }

  for (const [key, n] of need.entries()) {
    const h = have.get(key) || 0;
    if (h < n) {
      return { ok: false, error: "not_owned", detail: key };
    }
  }
  return { ok: true };
}

module.exports = {
  validateDeckOwned,
};
