/**
 * Shop catalog — Postgres shop_products / app_config (server-authority SoT).
 * Step 0: read helpers. Purchase lookup + GET /v1/shop/catalog land in step 2.
 */

"use strict";

const db = require("./db");

/**
 * @param {import("pg").QueryResultRow} row
 */
function rowToProduct(row) {
  const poolRaw = row.pool_json;
  let pool = [];
  if (Array.isArray(poolRaw)) {
    pool = poolRaw.map((id) => Math.floor(Number(id))).filter((id) => Number.isFinite(id) && id > 0);
  }
  return {
    productId: String(row.product_id),
    productType: String(row.product_type),
    displayName: String(row.display_name || ""),
    description: String(row.description || ""),
    priceGold: Number(row.price_gold) || 0,
    enabled: row.enabled === true,
    packSize: Math.max(1, Number(row.pack_size) || 1),
    weightN: Math.max(0, Number(row.weight_n) || 0),
    weightR: Math.max(0, Number(row.weight_r) || 0),
    weightSr: Math.max(0, Number(row.weight_sr) || 0),
    weightUr: Math.max(0, Number(row.weight_ur) || 0),
    poolMode: String(row.pool_mode || "explicit"),
    pool,
    accessoryType: String(row.accessory_type || ""),
    accessoryId: String(row.accessory_id || ""),
    sortOrder: Number(row.sort_order) || 0,
  };
}

/**
 * @param {string} productId
 * @param {{ enabledOnly?: boolean }} [opts]
 */
async function getProduct(productId, opts = {}) {
  const id = String(productId || "").trim();
  if (!id) {
    return null;
  }
  const enabledOnly = opts.enabledOnly !== false;
  const res = await db.query(
    `SELECT * FROM shop_products WHERE product_id = $1${enabledOnly ? " AND enabled = TRUE" : ""}`,
    [id]
  );
  if (res.rowCount === 0) {
    return null;
  }
  return rowToProduct(res.rows[0]);
}

/**
 * @param {{ enabledOnly?: boolean, productType?: string }} [opts]
 */
async function listProducts(opts = {}) {
  const enabledOnly = opts.enabledOnly !== false;
  const type = String(opts.productType || "").trim();
  const params = [];
  const where = [];
  if (enabledOnly) {
    where.push("enabled = TRUE");
  }
  if (type) {
    params.push(type);
    where.push(`product_type = $${params.length}`);
  }
  const sql = `SELECT * FROM shop_products${
    where.length ? ` WHERE ${where.join(" AND ")}` : ""
  } ORDER BY sort_order ASC, product_id ASC`;
  const res = await db.query(sql, params);
  return res.rows.map(rowToProduct);
}

async function getCatalogRevision() {
  const res = await db.query(
    `SELECT config_value FROM app_config WHERE config_key = 'shop_catalog_revision'`
  );
  if (res.rowCount === 0) {
    return 0;
  }
  const v = res.rows[0].config_value;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Public catalog payload for GET /v1/shop/catalog (step 2).
 */
async function loadPublicCatalog() {
  const [products, revision] = await Promise.all([listProducts({ enabledOnly: true }), getCatalogRevision()]);
  return {
    revision,
    products: products.map((p) => ({
      productId: p.productId,
      productType: p.productType,
      displayName: p.displayName,
      description: p.description,
      priceGold: p.priceGold,
      packSize: p.packSize,
      weightN: p.weightN,
      weightR: p.weightR,
      weightSr: p.weightSr,
      weightUr: p.weightUr,
      poolMode: p.poolMode,
      pool: p.poolMode === "explicit" ? p.pool : [],
      accessoryType: p.accessoryType,
      accessoryId: p.accessoryId,
      sortOrder: p.sortOrder,
    })),
  };
}

module.exports = {
  getProduct,
  listProducts,
  getCatalogRevision,
  loadPublicCatalog,
  rowToProduct,
};
