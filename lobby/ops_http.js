/**
 * Token-gated ops HTTP — monitor, db page, grant/account/backup/maintenance.
 * OPS_TOKEN unset → /ops and /v1/ops/* are 404.
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const metaOps = require("./meta/ops");
const patchNotes = require("./meta/patch_notes");

const HEALTH_LOG = path.join(__dirname, "ops-data", "health.jsonl");
const RECENT_LINES = 120;

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
    "Access-Control-Allow-Origin": "*",
  });
  res.end(payload);
}

function html(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function opsTokenConfigured() {
  return String(process.env.OPS_TOKEN || "").trim().length > 0;
}

function readPresentedToken(req, url) {
  const q = String(url.searchParams.get("token") || url.searchParams.get("ops_token") || "").trim();
  const header = String(req.headers["x-ops-token"] || "").trim();
  const auth = String(req.headers.authorization || "");
  let bearer = "";
  if (auth.toLowerCase().startsWith("bearer ")) {
    bearer = auth.slice(7).trim();
  }
  return q || header || bearer;
}

function tokenMatches(presented) {
  const want = String(process.env.OPS_TOKEN || "").trim();
  const got = String(presented || "").trim();
  if (!want || !got) {
    return false;
  }
  const a = crypto.createHash("sha256").update(want).digest();
  const b = crypto.createHash("sha256").update(got).digest();
  return crypto.timingSafeEqual(a, b);
}

function isOpsPath(pathname) {
  return pathname === "/ops" || pathname.startsWith("/ops/") || pathname.startsWith("/v1/ops");
}

function readRecentLog(maxLines) {
  if (!fs.existsSync(HEALTH_LOG)) {
    return [];
  }
  let stat;
  try {
    stat = fs.statSync(HEALTH_LOG);
  } catch (_) {
    return [];
  }
  const size = stat.size;
  if (size <= 0) {
    return [];
  }
  const readStart = Math.max(0, size - 256 * 1024);
  const buf = Buffer.alloc(size - readStart);
  const fd = fs.openSync(HEALTH_LOG, "r");
  try {
    fs.readSync(fd, buf, 0, buf.length, readStart);
  } finally {
    fs.closeSync(fd);
  }
  const lines = buf.toString("utf8").split(/\r?\n/);
  const parsed = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    try {
      parsed.push(JSON.parse(trimmed));
    } catch (_) {
      // skip corrupt line
    }
  }
  return parsed.slice(-maxLines);
}

function lastCollectedLabel(recent) {
  if (!recent.length) {
    return "폴러 기록 없음 — VM에서 tools/ops_health_poll.py 를 켜세요";
  }
  const last = recent[recent.length - 1];
  const ts = Date.parse(String(last.ts || last.time || ""));
  if (Number.isNaN(ts)) {
    return "마지막 수집 시각을 읽지 못함";
  }
  const mins = Math.max(0, Math.round((Date.now() - ts) / 60000));
  if (mins <= 0) {
    return "마지막 수집: 방금";
  }
  return `마지막 수집: ${mins}분 전`;
}

function monitorPayload(healthPayload) {
  const recent = readRecentLog(RECENT_LINES);
  return {
    now: healthPayload(),
    recent,
    collected: lastCollectedLabel(recent),
    logPath: "lobby/ops-data/health.jsonl",
  };
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderMonitorPage(data) {
  const now = data.now || {};
  const rows = (data.recent || [])
    .slice()
    .reverse()
    .map((row) => {
      const ok = row.ok === true;
      const host = row.host && typeof row.host === "object" ? row.host : {};
      const cpu = host.cpuPct != null ? host.cpuPct : "";
      const mem = host.memUsedMb != null ? `${host.memUsedMb}/${host.memTotalMb}` : "";
      return `<tr class="${ok ? "ok" : "bad"}">
        <td>${escapeHtml(row.ts || "")}</td>
        <td>${ok ? "ok" : escapeHtml(row.error || "fail")}</td>
        <td>${escapeHtml(row.rooms)}</td>
        <td>${escapeHtml(row.queueSize)}</td>
        <td>${escapeHtml(row.warmReady)}</td>
        <td>${escapeHtml(row.freePorts)}</td>
        <td>${escapeHtml(cpu)}</td>
        <td>${escapeHtml(mem)}</td>
      </tr>`;
    })
    .join("");
  const maint = now.maintenance === true ? "ON" : "off";
  const ver = now.version && typeof now.version === "object"
    ? `protocol ${escapeHtml(now.version.protocol)} · lobby ${escapeHtml(now.version.lobby)}`
    : "—";
  const w = now.worker && typeof now.worker === "object" ? now.worker : {};
  const workerLabel = w.present
    ? `${escapeHtml(String(w.sha256 || "").slice(0, 12))}…`
    : "missing";
  return `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>revealz ops</title>
  <style>
    body { font-family: Segoe UI, sans-serif; background: #111; color: #eee; margin: 1.5rem; }
    h1 { font-size: 1.2rem; margin: 0 0 .5rem; }
    .meta { color: #aaa; margin-bottom: 1rem; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: .6rem; margin: 1rem 0; }
    .card { background: #1c1c1c; border: 1px solid #333; padding: .7rem .8rem; border-radius: 6px; }
    .card b { display: block; font-size: 1.3rem; }
    .card span { color: #888; font-size: .8rem; }
    table { width: 100%; border-collapse: collapse; font-size: .85rem; }
    th, td { text-align: left; padding: .35rem .4rem; border-bottom: 1px solid #333; }
    tr.bad td { color: #f88; }
    .warn { color: #fc6; }
    .charts { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: .8rem; margin: 1.2rem 0; }
    .chart { background: #1c1c1c; border: 1px solid #333; border-radius: 6px; padding: .6rem .8rem; }
    .chart h3 { margin: 0 0 .4rem; font-size: .9rem; font-weight: 600; }
    .chart h3 small { color: #8cf; font-weight: 400; }
    .chart svg { width: 100%; height: 88px; display: block; }
    .chart .rng { color: #777; font-size: .75rem; margin-top: .25rem; }
  </style>
</head>
<body>
  <h1>revealz lobby monitor</h1>
  <p><a href="/ops?token=" id="nav-mon">모니터</a> · <a href="/ops/db?token=" id="nav-db">계정/DB</a></p>
  <div class="meta">${escapeHtml(data.collected)} · 전투 상세 없음 (로비 수치만) · 그래프는 jsonl 추이</div>
  <div class="grid">
    <div class="card"><span>rooms</span><b>${escapeHtml(now.rooms)}</b></div>
    <div class="card"><span>queue</span><b>${escapeHtml(now.queueSize)}</b></div>
    <div class="card"><span>warm ready</span><b>${escapeHtml(now.warmReady)}</b></div>
    <div class="card"><span>warm spawn</span><b>${escapeHtml(now.warmSpawning)}</b></div>
    <div class="card"><span>free ports</span><b>${escapeHtml(now.freePorts)}</b></div>
    <div class="card"><span>metaDb</span><b>${now.metaDb ? "on" : "off"}</b></div>
    <div class="card"><span>maintenance</span><b>${maint}</b></div>
    <div class="card"><span>version</span><b style="font-size:1rem">${ver}</b></div>
    <div class="card"><span>worker sha256</span><b style="font-size:1rem">${workerLabel}</b></div>
  </div>
  <p class="${now.ok ? "" : "warn"}">live health ok=${now.ok === true}</p>
  <div class="charts" id="charts"></div>
  <table>
    <thead><tr>
      <th>ts</th><th>ok</th><th>rooms</th><th>queue</th><th>warm</th><th>ports</th><th>cpu%</th><th>mem MB</th>
    </tr></thead>
    <tbody>${rows || "<tr><td colspan='8'>기록 없음</td></tr>"}</tbody>
  </table>
  <script type="application/json" id="recent-json">${JSON.stringify(data.recent || []).replace(/</g, "\\u003c")}</script>
  <script>
    const q = new URLSearchParams(location.search).get("token") || "";
    const nm = document.getElementById("nav-mon");
    const nd = document.getElementById("nav-db");
    if (nm) nm.href = "/ops?token=" + encodeURIComponent(q);
    if (nd) nd.href = "/ops/db?token=" + encodeURIComponent(q);
    function num(v) {
      const n = Number(v);
      return Number.isFinite(n) ? n : null;
    }
    function spark(title, values) {
      const box = document.createElement("div");
      box.className = "chart";
      const usable = values.filter((v) => v != null);
      if (!usable.length) {
        box.innerHTML = "<h3>" + title + "</h3><div class='rng'>데이터 없음</div>";
        return box;
      }
      const w = 320, h = 80, pad = 10;
      const min = Math.min.apply(null, usable);
      const max = Math.max.apply(null, usable);
      const span = max - min || 1;
      const last = usable[usable.length - 1];
      const pts = [];
      for (let i = 0; i < values.length; i++) {
        if (values[i] == null) continue;
        const x = pad + (i / Math.max(values.length - 1, 1)) * (w - 2 * pad);
        const y = h - pad - ((values[i] - min) / span) * (h - 2 * pad);
        pts.push(x.toFixed(1) + "," + y.toFixed(1));
      }
      box.innerHTML = "<h3>" + title + " <small>" + last + "</small></h3>" +
        "<svg viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='none'>" +
        "<polyline fill='none' stroke='#6cf' stroke-width='2' points='" + pts.join(" ") + "' />" +
        "</svg><div class='rng'>" + min + " – " + max + " · " + usable.length + " pts</div>";
      return box;
    }
    const recent = JSON.parse(document.getElementById("recent-json").textContent || "[]");
    const rooms = recent.map((r) => num(r.rooms));
    const queue = recent.map((r) => num(r.queueSize));
    const warm = recent.map((r) => num(r.warmReady));
    const ports = recent.map((r) => num(r.freePorts));
    const cpu = recent.map((r) => r.host && num(r.host.cpuPct));
    const mem = recent.map((r) => r.host && num(r.host.memUsedMb));
    const root = document.getElementById("charts");
    root.appendChild(spark("rooms", rooms));
    root.appendChild(spark("queue", queue));
    root.appendChild(spark("warm ready", warm));
    root.appendChild(spark("free ports", ports));
    if (cpu.some((v) => v != null)) root.appendChild(spark("cpu %", cpu));
    if (mem.some((v) => v != null)) root.appendChild(spark("mem MB", mem));
    async function tick() {
      const u = "/v1/ops/monitor" + (q ? ("?token=" + encodeURIComponent(q)) : "");
      try {
        const r = await fetch(u, { headers: q ? { "X-Ops-Token": q } : {} });
        if (r.ok) location.reload();
      } catch (e) {}
    }
    setInterval(tick, 30000);
  </script>
</body>
</html>`;
}

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

function sendOpsError(res, e) {
  const status = Number(e && e.status) || 500;
  json(res, status, { ok: false, error: String((e && e.message) || e) });
}

const DB_PAGE_PATH = path.join(__dirname, "ops_db.html");

function renderDbPage() {
  return fs.readFileSync(DB_PAGE_PATH, "utf8");
}

async function handleApi(req, res, url, method, deps) {
  const p = url.pathname;
  try {
    if (method === "GET" && p === "/v1/ops/accounts") {
      const listed = await metaOps.listAccounts({
        q: url.searchParams.get("q") || "",
        sort: url.searchParams.get("sort") || "created",
        order: url.searchParams.get("order") || "desc",
        page: url.searchParams.get("page") || 1,
        limit: url.searchParams.get("limit") || 20,
      });
      json(res, 200, listed);
      return;
    }
    if (method === "GET" && p === "/v1/ops/account") {
      const key = String(url.searchParams.get("key") || "").trim();
      const displayName = String(url.searchParams.get("displayName") || "").trim();
      if (key) {
        const snap = await metaOps.loadSnapshot(key);
        if (!snap) { json(res, 404, { error: "account_not_found" }); return; }
        json(res, 200, { ok: true, snapshot: snap });
        return;
      }
      if (displayName) {
        const results = await metaOps.searchByDisplayName(displayName);
        json(res, 200, { ok: true, results });
        return;
      }
      json(res, 400, { error: "key_or_displayName_required" });
      return;
    }
    if (method === "GET" && p === "/v1/ops/backups") {
      json(res, 200, { ok: true, backups: metaOps.listBackups() });
      return;
    }
    if (method === "GET" && p === "/v1/ops/patch-notes") {
      const notes = await patchNotes.listAll(url.searchParams.get("limit") || 100);
      json(res, 200, { ok: true, notes });
      return;
    }
    if (method !== "POST") {
      json(res, 404, { error: "not_found" });
      return;
    }
    const body = await readBody(req).catch(() => null);
    if (body === null) {
      json(res, 400, { error: "bad_json" });
      return;
    }
    if (p === "/v1/ops/patch-notes") {
      const publishAt =
        body.publishNow === false && body.publishAt
          ? body.publishAt
          : null;
      json(res, 200, await patchNotes.createNote({
        title: body.title,
        body: body.body,
        publishAt,
      }));
      return;
    }
    if (p === "/v1/ops/patch-notes/delete") {
      json(res, 200, await patchNotes.deleteNote(body.id));
      return;
    }
    if (p === "/v1/ops/grant") {
      const key = String(body.accountKey || body.account_key || "").trim();
      const mode = String(body.mode || "one");
      const count = body.count != null ? body.count : 1;
      if (mode === "all") {
        json(res, 200, await metaOps.grantAll(key, count));
        return;
      }
      json(res, 200, await metaOps.grantOne(key, body.cardId || body.card_id, body.rarity, count));
      return;
    }
    if (p === "/v1/ops/account") {
      const key = String(body.accountKey || body.account_key || "").trim();
      json(res, 200, await metaOps.patchAccount(key, body.gold, body.displayName || body.display_name));
      return;
    }
    if (p === "/v1/ops/account/delete") {
      const key = String(body.accountKey || body.account_key || "").trim();
      json(res, 200, await metaOps.deleteAccount(key));
      return;
    }
    if (p === "/v1/ops/maintenance") {
      json(res, 200, { ok: true, ...metaOps.writeMaintenance(body.enabled === true, body.message || "") });
      return;
    }
    if (p === "/v1/ops/precheck") {
      json(res, 200, metaOps.writePrecheck(deps.healthPayload()));
      return;
    }
    if (p === "/v1/ops/backup") {
      json(res, 200, metaOps.runBackup(body.label || body.name));
      return;
    }
    if (p === "/v1/ops/restore") {
      const name = String(body.name || "").trim();
      if (!name) { json(res, 400, { error: "backup_name_required" }); return; }
      json(res, 200, await metaOps.runRestore(name));
      return;
    }
    json(res, 404, { error: "not_found" });
  } catch (e) {
    sendOpsError(res, e);
  }
}

/**
 * @param {import("http").IncomingMessage} req
 * @param {import("http").ServerResponse} res
 * @param {URL} url
 * @param {string} method
 * @param {{ healthPayload: () => object }} deps
 * @returns {Promise<boolean>}
 */
async function tryHandle(req, res, url, method, deps) {
  if (!isOpsPath(url.pathname)) {
    return false;
  }
  if (method !== "GET" && method !== "POST") {
    json(res, 404, { error: "not_found" });
    return true;
  }
  if (!opsTokenConfigured() || !tokenMatches(readPresentedToken(req, url))) {
    json(res, 404, { error: "not_found" });
    return true;
  }
  if (method === "GET" && (url.pathname === "/ops" || url.pathname === "/ops/monitor")) {
    html(res, 200, renderMonitorPage(monitorPayload(deps.healthPayload)));
    return true;
  }
  if (method === "GET" && url.pathname === "/ops/db") {
    html(res, 200, renderDbPage());
    return true;
  }
  if (method === "GET" && url.pathname === "/v1/ops/monitor") {
    json(res, 200, monitorPayload(deps.healthPayload));
    return true;
  }
  await handleApi(req, res, url, method, deps);
  return true;
}

module.exports = {
  tryHandle,
  opsTokenConfigured,
  HEALTH_LOG,
};
