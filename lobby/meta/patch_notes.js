/**
 * Patch notes — public list/detail + ops create/delete.
 */

"use strict";

const db = require("./db");

function rowToNote(row, { includeBody = true } = {}) {
  if (!row) {
    return null;
  }
  const note = {
    id: Number(row.id),
    title: String(row.title || ""),
    publishedAt: row.published_at ? new Date(row.published_at).toISOString() : null,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
    updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : null,
  };
  if (includeBody) {
    note.body = String(row.body || "");
  }
  return note;
}

/** Published notes only (published_at <= now). Newest first. */
async function listPublished(limit = 50) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const lim = Math.min(100, Math.max(1, Math.floor(Number(limit) || 50)));
  const result = await db.query(
    `SELECT id, title, published_at, created_at, updated_at
     FROM patch_notes
     WHERE published_at <= NOW()
     ORDER BY published_at DESC, id DESC
     LIMIT $1`,
    [lim]
  );
  return result.rows.map((r) => rowToNote(r, { includeBody: false }));
}

async function getPublished(id) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const noteId = Math.floor(Number(id));
  if (!Number.isFinite(noteId) || noteId <= 0) {
    throw Object.assign(new Error("invalid_id"), { status: 400 });
  }
  const result = await db.query(
    `SELECT id, title, body, published_at, created_at, updated_at
     FROM patch_notes
     WHERE id = $1 AND published_at <= NOW()`,
    [noteId]
  );
  if (!result.rowCount) {
    return null;
  }
  return rowToNote(result.rows[0], { includeBody: true });
}

/** Ops: all notes including scheduled. */
async function listAll(limit = 100) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const lim = Math.min(200, Math.max(1, Math.floor(Number(limit) || 100)));
  const result = await db.query(
    `SELECT id, title, body, published_at, created_at, updated_at
     FROM patch_notes
     ORDER BY published_at DESC, id DESC
     LIMIT $1`,
    [lim]
  );
  return result.rows.map((r) => rowToNote(r, { includeBody: true }));
}

/**
 * @param {{ title: string, body?: string, publishAt?: string|null, publishNow?: boolean }} input
 */
async function createNote(input) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const title = String(input.title || "").trim().slice(0, 200);
  const body = String(input.body || "").slice(0, 50000);
  if (!title) {
    throw Object.assign(new Error("title_required"), { status: 400 });
  }

  let publishedAt;
  if (input.publishAt != null && String(input.publishAt).trim() !== "") {
    publishedAt = new Date(String(input.publishAt));
    if (Number.isNaN(publishedAt.getTime())) {
      throw Object.assign(new Error("invalid_publish_at"), { status: 400 });
    }
  } else {
    publishedAt = new Date();
  }

  const result = await db.query(
    `INSERT INTO patch_notes (title, body, published_at)
     VALUES ($1, $2, $3)
     RETURNING id, title, body, published_at, created_at, updated_at`,
    [title, body, publishedAt.toISOString()]
  );
  return { ok: true, note: rowToNote(result.rows[0], { includeBody: true }) };
}

async function deleteNote(id) {
  if (!db.isConfigured()) {
    throw Object.assign(new Error("meta_db_not_configured"), { status: 503 });
  }
  const noteId = Math.floor(Number(id));
  if (!Number.isFinite(noteId) || noteId <= 0) {
    throw Object.assign(new Error("invalid_id"), { status: 400 });
  }
  const result = await db.query(
    `DELETE FROM patch_notes WHERE id = $1
     RETURNING id`,
    [noteId]
  );
  if (!result.rowCount) {
    throw Object.assign(new Error("not_found"), { status: 404 });
  }
  return { ok: true, deletedId: noteId };
}

/**
 * Public patch-note routes (no auth).
 * @returns {Promise<boolean>}
 */
async function tryHandlePublic(req, res, url, method) {
  const listMatch = url.pathname === "/v1/patch-notes";
  const oneMatch = url.pathname.match(/^\/v1\/patch-notes\/(\d+)$/);
  if (!listMatch && !oneMatch) {
    return false;
  }

  function json(status, body) {
    const payload = JSON.stringify(body);
    res.writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Length": Buffer.byteLength(payload),
      "Access-Control-Allow-Origin": "*",
    });
    res.end(payload);
  }

  try {
    if (!db.isConfigured()) {
      json(503, { error: "meta_db_not_configured" });
      return true;
    }
    if (method !== "GET") {
      json(405, { error: "method_not_allowed" });
      return true;
    }
    if (listMatch) {
      const notes = await listPublished(url.searchParams.get("limit") || 50);
      json(200, { ok: true, notes });
      return true;
    }
    const note = await getPublished(oneMatch[1]);
    if (!note) {
      json(404, { error: "not_found" });
      return true;
    }
    json(200, { ok: true, note });
    return true;
  } catch (e) {
    db.log("patch-notes public error", e.message || e);
    json(500, { error: "internal", message: String(e.message || e) });
    return true;
  }
}

module.exports = {
  listPublished,
  getPublished,
  listAll,
  createNote,
  deleteNote,
  tryHandlePublic,
};
