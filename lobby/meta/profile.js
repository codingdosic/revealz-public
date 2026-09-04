/**
 * Profile field validation — displayName + profileIcon ownership (server authority).
 */

"use strict";

const DISPLAY_NAME_MAX = 50;
const DISPLAY_NAME_RE = /^[A-Za-z0-9가-힣_\-]+$/;

/**
 * @param {unknown} raw
 * @returns {{ ok: true, name: string } | { ok: false, error: string }}
 */
function sanitizeDisplayName(raw, fallbackKey) {
  const name = String(raw || "").trim();
  if (!name) {
    const fb = String(fallbackKey || "").trim().slice(0, DISPLAY_NAME_MAX);
    return fb ? { ok: true, name: fb } : { ok: false, error: "display_name_required" };
  }
  if (name.length > DISPLAY_NAME_MAX) {
    return { ok: false, error: "display_name_too_long" };
  }
  if (!DISPLAY_NAME_RE.test(name)) {
    return { ok: false, error: "display_name_invalid" };
  }
  return { ok: true, name };
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {string} iconId
 */
async function resolveProfileIconId(client, accountKey, iconId) {
  let id = String(iconId || "").trim().slice(0, 128);
  if (!id) {
    return "";
  }
  const owned = await client.query(
    `SELECT 1 FROM owned_accessories
     WHERE account_key = $1 AND accessory_type = 'icon' AND accessory_id = $2`,
    [accountKey, id]
  );
  if (owned.rowCount > 0) {
    return id;
  }
  // Not owned — keep previous DB value if any, else empty (client default).
  const prev = await client.query(
    `SELECT profile_icon_id FROM accounts WHERE account_key = $1`,
    [accountKey]
  );
  if (prev.rowCount > 0) {
    return String(prev.rows[0].profile_icon_id || "");
  }
  return "";
}

/**
 * @param {import("pg").PoolClient} client
 * @param {string} accountKey
 * @param {object} body
 */
async function updateProfile(client, accountKey, body) {
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
    `SELECT meta_revision, display_name, profile_icon_id FROM accounts WHERE account_key = $1 FOR UPDATE`,
    [accountKey]
  );
  if (existing.rowCount === 0) {
    const err = new Error("account_not_found");
    err.code = "not_found";
    throw err;
  }

  const current = Number(existing.rows[0].meta_revision) || 0;
  const hasBase = body.baseRevision !== undefined && body.baseRevision !== null;
  const base = hasBase ? Number(body.baseRevision) : NaN;
  if (!hasBase || !Number.isFinite(base) || base !== current) {
    const err = new Error("revision_conflict");
    err.code = "revision_conflict";
    throw err;
  }

  let displayName = String(existing.rows[0].display_name || accountKey);
  if (body.displayName !== undefined || body.display_name !== undefined) {
    const sanitized = sanitizeDisplayName(
      body.displayName !== undefined ? body.displayName : body.display_name,
      accountKey
    );
    if (!sanitized.ok) {
      const err = new Error(sanitized.error);
      err.code = "bad_request";
      throw err;
    }
    displayName = sanitized.name;
  }

  let profileIconId = String(existing.rows[0].profile_icon_id || "");
  if (body.profileIconId !== undefined || body.profile_icon_id !== undefined) {
    const raw =
      body.profileIconId !== undefined ? body.profileIconId : body.profile_icon_id;
    const wanted = String(raw || "").trim().slice(0, 128);
    if (wanted) {
      const owned = await client.query(
        `SELECT 1 FROM owned_accessories
         WHERE account_key = $1 AND accessory_type = 'icon' AND accessory_id = $2`,
        [accountKey, wanted]
      );
      if (owned.rowCount === 0) {
        const err = new Error("icon_not_owned");
        err.code = "conflict";
        throw err;
      }
      profileIconId = wanted;
    } else {
      profileIconId = "";
    }
  }

  await client.query(
    `UPDATE accounts
     SET display_name = $2,
         profile_icon_id = $3,
         meta_revision = COALESCE(meta_revision, 0) + 1
     WHERE account_key = $1`,
    [accountKey, displayName, profileIconId]
  );
}

module.exports = {
  sanitizeDisplayName,
  resolveProfileIconId,
  updateProfile,
  DISPLAY_NAME_MAX,
};
