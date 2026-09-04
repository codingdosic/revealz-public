/**
 * MetaSrv Postgres pool + schema bootstrap.
 * Env: META_DATABASE_URL (required for meta routes).
 * Example: postgres://revealz_meta:PASSWORD@127.0.0.1:5432/revealz_meta
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { Pool } = require("pg");

/** @type {import("pg").Pool | null} */
let pool = null;
let schemaReady = false;

function log(...args) {
  console.log("[lobby:meta]", ...args);
}

function databaseUrl() {
  return String(process.env.META_DATABASE_URL || "").trim();
}

function isConfigured() {
  return databaseUrl().length > 0;
}

function getPool() {
  if (!isConfigured()) {
    return null;
  }
  if (!pool) {
    pool = new Pool({ connectionString: databaseUrl() });
    pool.on("error", (err) => {
      log("pool error", err.message || err);
    });
  }
  return pool;
}

async function ensureSchema() {
  const p = getPool();
  if (!p) {
    return false;
  }
  if (schemaReady) {
    return true;
  }
  const sqlPath = path.join(__dirname, "schema.sql");
  const sql = fs.readFileSync(sqlPath, "utf8");
  await p.query(sql);
  const seedPath = path.join(__dirname, "seed_shop.sql");
  if (fs.existsSync(seedPath)) {
    const seedSql = fs.readFileSync(seedPath, "utf8");
    await p.query(seedSql);
    log("shop seed applied (ON CONFLICT DO NOTHING)");
  }
  schemaReady = true;
  log("schema ready");
  return true;
}

async function query(text, params) {
  const p = getPool();
  if (!p) {
    throw new Error("meta_db_not_configured");
  }
  await ensureSchema();
  return p.query(text, params);
}

async function withTransaction(fn) {
  const p = getPool();
  if (!p) {
    throw new Error("meta_db_not_configured");
  }
  await ensureSchema();
  const client = await p.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {
      /* ignore */
    }
    throw e;
  } finally {
    client.release();
  }
}

async function endPool() {
  if (pool) {
    await pool.end();
    pool = null;
    schemaReady = false;
  }
}

module.exports = {
  databaseUrl,
  isConfigured,
  getPool,
  ensureSchema,
  query,
  withTransaction,
  endPool,
  log,
};
