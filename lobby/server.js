/**
 * revealz G4 lobby (S1 create/join · S3 matchmaking · G4e-L2 warm pool)
 * SSOT: export/g4_lobby_design.md §7 / §7.1
 *
 * POST /v1/rooms
 * POST /v1/rooms/{code}/join
 * GET  /v1/health
 * GET  /ops  /ops/monitor  /v1/ops/monitor  (OPS_TOKEN)
 * POST /v1/matchmaking/enqueue
 * POST /v1/matchmaking/cancel
 * GET  /v1/matchmaking/tickets/{ticketId}
 * GET/PUT /v1/meta/accounts/{accountKey}  (MetaSrv — requires META_DATABASE_URL)
 *
 * Port pool 7700–7799 · spawn --port + --room-code · child exit reclaim · TTL 10m
 * Warm pool: idle workers listen ahead · create/matched claim · refill · no listen rebind
 * Matchmaking: queue 2 → acquire room → wait [MP-SERVER] listening → matched
 */

"use strict";

const http = require("http");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const metaDb = require("./meta/db");
const metaRoutes = require("./meta/routes");
const metaOps = require("./meta/ops");
const patchNotes = require("./meta/patch_notes");
const opsHttp = require("./ops_http");

const ROOT = path.resolve(__dirname, "..");

const CONFIG = {
  httpHost: process.env.LOBBY_BIND || "0.0.0.0",
  httpPort: Number(process.env.LOBBY_HTTP_PORT || 8080),
  publicHost: process.env.LOBBY_PUBLIC_HOST || "127.0.0.1",
  portStart: Number(process.env.PORT_POOL_START || 7700),
  portEnd: Number(process.env.PORT_POOL_END || 7799),
  ttlMs: Number(process.env.ROOM_TTL_MS || 10 * 60 * 1000),
  matchTimeoutMs: Number(process.env.MATCH_TIMEOUT_MS || 60 * 1000),
  /** Wait for worker `[MP-SERVER] listening` before create/match response. */
  workerReadyMs: Number(process.env.WORKER_READY_MS || 120 * 1000),
  /** Idle workers kept listening ahead (0 = disabled). Reserved from port pool. */
  warmPoolSize: Math.max(0, Number(process.env.WARM_POOL_SIZE || 2)),
  maxSeats: 2,
  // Prefer exported dedicated exe; fall back to Godot editor headless.
  workerBin: process.env.WORKER_BIN || "",
  godotBin: process.env.GODOT_BIN || "",
  projectPath: process.env.PROJECT_PATH || ROOT,
};

function loadVersion() {
  try {
    const raw = JSON.parse(fs.readFileSync(path.join(__dirname, "version.json"), "utf8"));
    return {
      protocol: raw.protocol,
      lobby: String(raw.lobby || ""),
    };
  } catch (_) {
    return null;
  }
}

const VERSION = loadVersion();

function sha256FileSync(filePath) {
  const hash = crypto.createHash("sha256");
  const fd = fs.openSync(filePath, "r");
  try {
    const buf = Buffer.alloc(1024 * 1024);
    let n;
    while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) {
      hash.update(buf.subarray(0, n));
    }
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest("hex");
}

/** Git-ignored Dedicated path. Cached at boot — scp then restart lobby to refresh. */
function loadWorkerFingerprint() {
  const empty = { present: false, path: "", sha256: null, bytes: null, mtimeUtc: "" };
  const fromEnv = String(CONFIG.workerBin || "").trim();
  const abs = fromEnv ? path.resolve(fromEnv) : defaultWorkerBin();
  if (!abs) {
    return empty;
  }
  const rel = path.relative(ROOT, abs);
  const shown = (rel && !rel.startsWith("..") ? rel : abs).replace(/\\/g, "/");
  try {
    const st = fs.statSync(abs);
    if (!st.isFile()) {
      return { ...empty, path: shown };
    }
    return {
      present: true,
      path: shown,
      sha256: sha256FileSync(abs),
      bytes: st.size,
      mtimeUtc: new Date(st.mtimeMs).toISOString(),
    };
  } catch (_) {
    return { ...empty, path: shown };
  }
}

const WORKER_FP = loadWorkerFingerprint();

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // avoid 0/O/1/I confusion lightly

/** @type {number[]} */
const freePorts = [];
for (let p = CONFIG.portStart; p <= CONFIG.portEnd; p++) {
  freePorts.push(p);
}

/**
 * @typedef {{
 *   roomCode: string,
 *   port: number,
 *   host: string,
 *   state: "waiting" | "closed",
 *   createdAt: number,
 *   seatsTaken: number,
 *   warm: boolean,
 *   child: import("child_process").ChildProcess | null,
 *   ttlTimer: NodeJS.Timeout | null,
 *   ready: Promise<void>,
 *   _readyResolve: (() => void) | null,
 *   _readyReject: ((err: Error) => void) | null,
 *   _readyTimer: NodeJS.Timeout | null,
 *   _readySettled: boolean,
 *   _stdoutBuf: string,
 * }} Room
 */

const WORKER_LISTENING_MARKER = "[MP-SERVER] listening";

/** @type {Map<string, Room>} */
const rooms = new Map();

/** Ready warm rooms (listening, warm=true, seatsTaken=0). */
/** @type {Room[]} */
const warmReady = [];

/**
 * @typedef {{
 *   ticketId: string,
 *   status: "queued" | "matched" | "cancelled" | "expired" | "error",
 *   enqueuedAt: number,
 *   match: { roomCode: string, host: string, port: number } | null,
 *   error: string | null,
 *   timeoutTimer: NodeJS.Timeout | null,
 *   pairing: boolean,
 * }} Ticket
 */

/** @type {Map<string, Ticket>} */
const tickets = new Map();
/** @type {string[]} ticketIds waiting for a pair */
const matchQueue = [];

function log(...args) {
  console.log("[lobby]", ...args);
}

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
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

function allocPort() {
  if (freePorts.length === 0) return null;
  return freePorts.shift();
}

function releasePort(port) {
  if (typeof port !== "number") return;
  if (port < CONFIG.portStart || port > CONFIG.portEnd) return;
  if (!freePorts.includes(port)) {
    freePorts.push(port);
    freePorts.sort((a, b) => a - b);
  }
}

function generateRoomCode() {
  for (let attempt = 0; attempt < 64; attempt++) {
    let code = "";
    for (let i = 0; i < 4; i++) {
      code += CODE_ALPHABET[(Math.random() * CODE_ALPHABET.length) | 0];
    }
    if (!rooms.has(code)) return code;
  }
  throw new Error("failed to allocate unique roomCode");
}

function generateTicketId() {
  return crypto.randomBytes(8).toString("hex");
}

function resolveWorkerLaunch(port, roomCode) {
  const portStr = String(port);
  const userArgs = ["--port", portStr, "--room-code", roomCode];

  // Prefer Godot editor headless when GODOT_BIN is set — export exe may be stale
  // (missing --port) until re-exported after G4b.
  const godot = CONFIG.godotBin || process.env.GODOT || "";
  if (godot && fs.existsSync(godot)) {
    return {
      bin: godot,
      args: [
        "--headless",
        "--path",
        CONFIG.projectPath,
        "res://scenes/server/server_main.tscn",
        "--",
        ...userArgs,
      ],
      cwd: CONFIG.projectPath,
    };
  }

  const exported = CONFIG.workerBin || defaultWorkerBin();
  if (!exported) {
    throw new Error(
      "No worker binary. Set GODOT_BIN (dev) or WORKER_BIN to revealz_server / revealz_server.exe"
    );
  }
  return launchExportedWorker(exported, userArgs);
}

/** Linux export waits on a display unless --headless. */
function exportedWorkerArgs(userArgs) {
  if (process.platform === "win32") {
    return ["--", ...userArgs];
  }
  return ["--headless", "--", ...userArgs];
}

function defaultWorkerBin() {
  const defaultCandidates = [
    path.join(ROOT, "export", "revealz_server.exe"),
    path.join(ROOT, "export", "revealz_server_win64.exe"),
    path.join(ROOT, "export", "revealz_server"),
    path.join(ROOT, "export", "linux", "revealz_server"),
  ];
  for (const exe of defaultCandidates) {
    if (fs.existsSync(exe)) {
      return exe;
    }
  }
  return "";
}

/** Pipe spawn fully buffers Godot stdout; stdbuf -oL lets [MP-SERVER] listening reach the lobby. */
function launchExportedWorker(bin, userArgs) {
  const args = exportedWorkerArgs(userArgs);
  const cwd = path.dirname(bin);
  if (process.platform !== "win32" && fs.existsSync("/usr/bin/stdbuf")) {
    return { bin: "/usr/bin/stdbuf", args: ["-oL", "-eL", bin, ...args], cwd };
  }
  return { bin, args, cwd };
}

function clearTtl(room) {
  if (room.ttlTimer) {
    clearTimeout(room.ttlTimer);
    room.ttlTimer = null;
  }
}

function scheduleTtl(room) {
  clearTtl(room);
  room.ttlTimer = setTimeout(() => {
    if (!rooms.has(room.roomCode)) return;
    if (room.seatsTaken > 0) {
      log("TTL skipped (seatsTaken>0)", room.roomCode);
      return;
    }
    log("TTL expired — killing worker", room.roomCode, "port", room.port);
    closeRoom(room.roomCode, "ttl");
  }, CONFIG.ttlMs);
}

function clearReadyTimer(room) {
  if (room._readyTimer) {
    clearTimeout(room._readyTimer);
    room._readyTimer = null;
  }
}

/** Resolve room.ready once (listening). */
function settleReadyOk(room) {
  if (room._readySettled) return;
  room._readySettled = true;
  clearReadyTimer(room);
  if (room._readyResolve) room._readyResolve();
  room._readyResolve = null;
  room._readyReject = null;
  log("worker ready", room.roomCode, "port", room.port, room.warm ? "(warm)" : "");
}

/** Reject room.ready once (timeout / exit / spawn error). */
function settleReadyFail(room, err) {
  if (room._readySettled) return;
  room._readySettled = true;
  clearReadyTimer(room);
  if (room._readyReject) room._readyReject(err instanceof Error ? err : new Error(String(err)));
  room._readyResolve = null;
  room._readyReject = null;
}

function attachReadyGate(room) {
  room._readySettled = false;
  room._stdoutBuf = "";
  room._readyResolve = null;
  room._readyReject = null;
  room.ready = new Promise((resolve, reject) => {
    room._readyResolve = resolve;
    room._readyReject = reject;
  });
  // Prevent unhandled rejection if nobody awaits (should always await).
  room.ready.catch(() => {});
  room._readyTimer = setTimeout(() => {
    log("worker ready timeout", room.roomCode, "ms=", CONFIG.workerReadyMs);
    settleReadyFail(room, new Error("worker_not_ready"));
    if (rooms.has(room.roomCode)) {
      closeRoom(room.roomCode, "ready_timeout");
    }
  }, CONFIG.workerReadyMs);
}

function removeFromWarmReady(room) {
  const idx = warmReady.indexOf(room);
  if (idx >= 0) warmReady.splice(idx, 1);
}

/** Rooms still marked warm (ready + spawning). */
function countWarmSlots() {
  let n = 0;
  for (const room of rooms.values()) {
    if (room.warm) n += 1;
  }
  return n;
}

function warmStats() {
  const slots = countWarmSlots();
  const ready = warmReady.length;
  return {
    warmReady: ready,
    warmSpawning: Math.max(0, slots - ready),
    warmTarget: CONFIG.warmPoolSize,
  };
}

/**
 * Keep warm pool at target. Spawns missing idle workers (listen ahead).
 * No-op when WARM_POOL_SIZE=0 or ports exhausted.
 */
function ensureWarmPool() {
  if (CONFIG.warmPoolSize <= 0) return;
  const need = CONFIG.warmPoolSize - countWarmSlots();
  for (let i = 0; i < need; i++) {
    void startWarmWorker();
  }
}

/** Spawn one warm worker; push to warmReady after listening. */
async function startWarmWorker() {
  if (CONFIG.warmPoolSize <= 0) return;
  if (countWarmSlots() >= CONFIG.warmPoolSize) return;

  const created = createRoomInternal({ warm: true });
  if (!created.ok) {
    log("warm spawn failed", created.error, created.message || "");
    return;
  }
  const room = created.room;
  try {
    await room.ready;
  } catch (e) {
    log(
      "warm ready failed",
      room.roomCode,
      String(e && e.message ? e.message : e)
    );
    return;
  }
  if (!rooms.has(room.roomCode) || room.state !== "waiting" || !room.warm) {
    return;
  }
  if (!warmReady.includes(room)) {
    warmReady.push(room);
  }
  log("warm stocked", room.roomCode, "port", room.port, warmStats());
}

/**
 * Claim a ready warm room, or cold-spawn. Triggers refill after claim/spawn.
 * @returns {Promise<{ ok: true, room: Room, warmHit: boolean } | { ok: false, error: string, message?: string }>}
 */
async function acquireRoom() {
  while (warmReady.length > 0) {
    const room = warmReady.shift();
    if (!room || !rooms.has(room.roomCode) || room.state !== "waiting" || !room.warm) {
      continue;
    }
    try {
      await room.ready;
    } catch (_) {
      continue;
    }
    if (!rooms.has(room.roomCode) || room.state !== "waiting" || !room.warm) {
      continue;
    }
    room.warm = false;
    log("warm hit", room.roomCode, "port", room.port);
    ensureWarmPool();
    return { ok: true, room, warmHit: true };
  }

  const created = createRoomInternal({ warm: false });
  if (!created.ok) {
    ensureWarmPool();
    return created;
  }
  log("warm miss — cold spawn", created.room.roomCode, "port", created.room.port);
  ensureWarmPool();
  return { ok: true, room: created.room, warmHit: false };
}

function closeRoom(roomCode, reason) {
  const room = rooms.get(roomCode);
  if (!room) return;
  clearTtl(room);
  removeFromWarmReady(room);
  settleReadyFail(room, new Error(reason || "closed"));
  room.state = "closed";
  room.warm = false;
  rooms.delete(roomCode);
  if (room.child && !room.child.killed) {
    try {
      room.child.kill();
    } catch (_) {
      /* ignore */
    }
  }
  releasePort(room.port);
  log("room closed", roomCode, "reason=", reason, "port=", room.port, "freePorts=", freePorts.length);
  if (reason !== "shutdown") {
    setImmediate(() => ensureWarmPool());
  }
}

function spawnWorker(room) {
  const launch = resolveWorkerLaunch(room.port, room.roomCode);
  log("spawn", launch.bin, launch.args.join(" "));
  const child = spawn(launch.bin, launch.args, {
    cwd: launch.cwd,
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
    env: {
      ...process.env,
      GODOT_SILENCE_ROOT_WARNING: "1",
      // Dedicated → same-VM lobby Meta (G3.1 validate-deck). Override with META_LOBBY_URL if needed.
      META_LOBBY_URL:
        process.env.META_LOBBY_URL || `http://127.0.0.1:${CONFIG.httpPort}`,
    },
  });
  room.child = child;
  child.stdout.on("data", (buf) => {
    const text = buf.toString("utf8");
    process.stdout.write(`[worker ${room.roomCode}] ${text}`);
    room._stdoutBuf += text;
    if (room._stdoutBuf.includes(WORKER_LISTENING_MARKER)) {
      settleReadyOk(room);
      // Cap buffer so long-running workers do not grow forever.
      if (room._stdoutBuf.length > 4096) {
        room._stdoutBuf = room._stdoutBuf.slice(-1024);
      }
    } else if (room._stdoutBuf.length > 16384) {
      room._stdoutBuf = room._stdoutBuf.slice(-4096);
    }
  });
  child.stderr.on("data", (buf) => {
    const text = buf.toString("utf8");
    process.stderr.write(`[worker ${room.roomCode} ERR] ${text}`);
    room._stdoutBuf += text;
    if (room._stdoutBuf.includes(WORKER_LISTENING_MARKER)) {
      settleReadyOk(room);
    }
  });
  child.on("exit", (code, signal) => {
    log("worker exit", room.roomCode, "code=", code, "signal=", signal);
    if (rooms.has(room.roomCode)) {
      closeRoom(room.roomCode, "exit");
    } else {
      settleReadyFail(room, new Error("exit"));
      removeFromWarmReady(room);
    }
  });
  child.on("error", (err) => {
    log("worker spawn error", room.roomCode, err.message);
    settleReadyFail(room, err);
    if (rooms.has(room.roomCode)) {
      closeRoom(room.roomCode, "spawn_error");
    }
  });
}

function roomPublic(room) {
  return {
    roomCode: room.roomCode,
    host: room.host,
    port: room.port,
  };
}

/**
 * Allocate port, spawn worker, register room.
 * @param {{ warm?: boolean }} [opts]
 * @returns {{ ok: true, room: Room } | { ok: false, error: string, message?: string }}
 */
function createRoomInternal(opts = {}) {
  const warm = !!opts.warm;
  const port = allocPort();
  if (port == null) {
    return { ok: false, error: "no_free_ports" };
  }
  let roomCode;
  try {
    roomCode = generateRoomCode();
  } catch (e) {
    releasePort(port);
    return { ok: false, error: "code_alloc_failed" };
  }
  /** @type {Room} */
  const room = {
    roomCode,
    port,
    host: CONFIG.publicHost,
    state: "waiting",
    createdAt: Date.now(),
    seatsTaken: 0,
    warm,
    child: null,
    ttlTimer: null,
    ready: Promise.resolve(),
    _readyResolve: null,
    _readyReject: null,
    _readyTimer: null,
    _readySettled: false,
    _stdoutBuf: "",
  };
  attachReadyGate(room);
  rooms.set(roomCode, room);
  try {
    spawnWorker(room);
  } catch (e) {
    settleReadyFail(room, e instanceof Error ? e : new Error(String(e)));
    rooms.delete(roomCode);
    releasePort(port);
    return { ok: false, error: "spawn_failed", message: String(e.message || e) };
  }
  // Warm idle: no empty-room TTL until claimed by Create.
  if (!warm) {
    scheduleTtl(room);
  }
  log(warm ? "warm spawn" : "created", roomCode, "port", port, "ttlMs", warm ? "-" : CONFIG.ttlMs);
  return { ok: true, room };
}

function clearTicketTimeout(ticket) {
  if (ticket.timeoutTimer) {
    clearTimeout(ticket.timeoutTimer);
    ticket.timeoutTimer = null;
  }
}

function removeFromQueue(ticketId) {
  const idx = matchQueue.indexOf(ticketId);
  if (idx >= 0) matchQueue.splice(idx, 1);
}

function ticketPublic(ticket) {
  const body = {
    status: ticket.status,
    ticketId: ticket.ticketId,
    queueSize: matchQueue.length,
    matchTimeoutMs: CONFIG.matchTimeoutMs,
  };
  if (ticket.status === "matched" && ticket.match) {
    body.roomCode = ticket.match.roomCode;
    body.host = ticket.match.host;
    body.port = ticket.match.port;
  }
  if (ticket.status === "error" && ticket.error) {
    body.error = ticket.error;
  }
  return body;
}

function expireTicket(ticketId) {
  const ticket = tickets.get(ticketId);
  if (!ticket || ticket.status !== "queued") return;
  removeFromQueue(ticketId);
  clearTicketTimeout(ticket);
  ticket.status = "expired";
  log("matchmaking expired", ticketId, "queueSize=", matchQueue.length);
}

/**
 * Pair two queued tickets: acquire room (warm hit preferred), wait listening, matched.
 * @param {Ticket} a
 * @param {Ticket} b
 */
async function pairTickets(a, b) {
  clearTicketTimeout(a);
  clearTicketTimeout(b);
  removeFromQueue(a.ticketId);
  removeFromQueue(b.ticketId);
  a.pairing = true;
  b.pairing = true;

  const acquired = await acquireRoom();
  if (!acquired.ok) {
    a.pairing = false;
    b.pairing = false;
    a.status = "error";
    a.error = acquired.error;
    b.status = "error";
    b.error = acquired.error;
    log("matchmaking spawn failed", acquired.error, a.ticketId, b.ticketId);
    return;
  }
  const room = acquired.room;
  // Both matched players will ENet-join; reserve seats + drop empty-room TTL.
  room.seatsTaken = CONFIG.maxSeats;
  clearTtl(room);
  log(
    "matchmaking waiting_ready",
    a.ticketId,
    "+",
    b.ticketId,
    "→",
    room.roomCode,
    "port",
    room.port,
    acquired.warmHit ? "warmHit" : "cold"
  );

  try {
    await room.ready;
  } catch (e) {
    a.pairing = false;
    b.pairing = false;
    if (a.status === "queued") {
      a.status = "error";
      a.error = "worker_not_ready";
    }
    if (b.status === "queued") {
      b.status = "error";
      b.error = "worker_not_ready";
    }
    log(
      "matchmaking ready failed",
      room.roomCode,
      String(e && e.message ? e.message : e),
      a.ticketId,
      b.ticketId
    );
    if (rooms.has(room.roomCode)) {
      closeRoom(room.roomCode, "ready_failed");
    }
    return;
  }

  a.pairing = false;
  b.pairing = false;
  if (a.status !== "queued" || b.status !== "queued") {
    log("matchmaking aborted after ready (ticket left queue)", a.ticketId, b.ticketId);
    if (rooms.has(room.roomCode)) {
      closeRoom(room.roomCode, "match_aborted");
    }
    return;
  }

  const match = roomPublic(room);
  a.status = "matched";
  a.match = match;
  b.status = "matched";
  b.match = match;
  log(
    "matchmaking matched",
    a.ticketId,
    "+",
    b.ticketId,
    "→",
    room.roomCode,
    "port",
    room.port,
    acquired.warmHit ? "warmHit" : "cold",
    "queueSize=",
    matchQueue.length
  );
}

function scheduleTicketTimeout(ticket) {
  clearTicketTimeout(ticket);
  ticket.timeoutTimer = setTimeout(() => {
    expireTicket(ticket.ticketId);
  }, CONFIG.matchTimeoutMs);
}

async function handleCreate(_req, res) {
  const acquired = await acquireRoom();
  if (!acquired.ok) {
    const status = acquired.error === "no_free_ports" ? 503 : 500;
    const body = { error: acquired.error };
    if (acquired.message) body.message = acquired.message;
    json(res, status, body);
    return;
  }
  // Wait until Dedicated listens — warm hit is already resolved.
  try {
    await acquired.room.ready;
  } catch (e) {
    if (rooms.has(acquired.room.roomCode)) {
      closeRoom(acquired.room.roomCode, "ready_failed");
    }
    json(res, 503, {
      error: "worker_not_ready",
      message: String(e && e.message ? e.message : e),
    });
    return;
  }
  if (!rooms.has(acquired.room.roomCode) || acquired.room.state !== "waiting") {
    json(res, 503, { error: "worker_not_ready" });
    return;
  }
  // Empty waiting TTL starts when Create publishes the room (not while warm).
  scheduleTtl(acquired.room);
  if (acquired.warmHit) {
    log("create warmHit", acquired.room.roomCode, "port", acquired.room.port);
  }
  json(res, 201, roomPublic(acquired.room));
}

async function handleJoin(req, res, code) {
  const roomCode = String(code || "").trim().toUpperCase();
  const room = rooms.get(roomCode);
  // Warm stock is not joinable until Create/match claims it (warm=false).
  if (!room || room.state !== "waiting" || room.warm) {
    json(res, 404, { error: "room_not_found" });
    return;
  }
  if (room.seatsTaken >= CONFIG.maxSeats) {
    json(res, 409, { error: "room_full" });
    return;
  }
  room.seatsTaken += 1;
  if (room.seatsTaken > 0) {
    clearTtl(room);
  }
  log("join", roomCode, "seats", room.seatsTaken, "port", room.port);
  json(res, 200, roomPublic(room));
}

function healthPayload() {
  const warm = warmStats();
  const maint = metaOps.readMaintenance();
  return {
    ok: true,
    rooms: rooms.size,
    freePorts: freePorts.length,
    ttlMs: CONFIG.ttlMs,
    queueSize: matchQueue.length,
    matchTimeoutMs: CONFIG.matchTimeoutMs,
    warmReady: warm.warmReady,
    warmSpawning: warm.warmSpawning,
    warmTarget: warm.warmTarget,
    metaDb: metaDb.isConfigured(),
    version: VERSION,
    worker: WORKER_FP,
    maintenance: maint.enabled === true,
    maintenanceMessage: maint.enabled ? String(maint.message || "") : "",
  };
}

function handleHealth(_req, res) {
  json(res, 200, healthPayload());
}

async function handleEnqueue(req, res) {
  const ticketId = generateTicketId();
  /** @type {Ticket} */
  const ticket = {
    ticketId,
    status: "queued",
    enqueuedAt: Date.now(),
    match: null,
    error: null,
    timeoutTimer: null,
    pairing: false,
  };
  tickets.set(ticketId, ticket);
  matchQueue.push(ticketId);
  scheduleTicketTimeout(ticket);
  log("matchmaking enqueue", ticketId, "queueSize=", matchQueue.length);

  if (matchQueue.length >= 2) {
    const idA = matchQueue[0];
    const idB = matchQueue[1];
    const a = tickets.get(idA);
    const b = tickets.get(idB);
    if (a && b && a.status === "queued" && b.status === "queued" && !a.pairing && !b.pairing) {
      // Holds this request until worker listening (or failure).
      await pairTickets(a, b);
    }
  }

  const fresh = tickets.get(ticketId);
  if (!fresh) {
    json(res, 500, { error: "internal" });
    return;
  }
  const httpStatus = fresh.status === "error" ? 503 : 200;
  json(res, httpStatus, ticketPublic(fresh));
}

async function handleCancel(req, res) {
  let body = {};
  try {
    body = await readBody(req);
  } catch (_) {
    json(res, 400, { error: "bad_json" });
    return;
  }
  const ticketId = String(body.ticketId || "").trim();
  if (!ticketId) {
    json(res, 400, { error: "ticket_required" });
    return;
  }
  const ticket = tickets.get(ticketId);
  if (!ticket) {
    json(res, 404, { error: "ticket_not_found" });
    return;
  }
  if (ticket.status === "matched") {
    json(res, 409, { error: "already_matched", ticketId });
    return;
  }
  if (ticket.pairing) {
    json(res, 409, { error: "pairing_in_progress", ticketId });
    return;
  }
  if (ticket.status === "queued") {
    removeFromQueue(ticketId);
    clearTicketTimeout(ticket);
    ticket.status = "cancelled";
    log("matchmaking cancel", ticketId, "queueSize=", matchQueue.length);
  }
  json(res, 200, { ok: true, ticketId, status: ticket.status, queueSize: matchQueue.length });
}

function handleTicketStatus(_req, res, ticketIdRaw) {
  const ticketId = String(ticketIdRaw || "").trim();
  const ticket = tickets.get(ticketId);
  if (!ticket) {
    json(res, 404, { error: "ticket_not_found" });
    return;
  }
  json(res, 200, ticketPublic(ticket));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  const method = req.method || "GET";

  if (method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Ops-Token",
    });
    res.end();
    return;
  }

  try {
    if (await opsHttp.tryHandle(req, res, url, method, { healthPayload })) {
      return;
    }
    if (await patchNotes.tryHandlePublic(req, res, url, method)) {
      return;
    }
    if (await metaRoutes.tryHandle(req, res, url, method)) {
      return;
    }
    if (method === "GET" && url.pathname === "/v1/health") {
      handleHealth(req, res);
      return;
    }
    if (method === "POST" && url.pathname === "/v1/rooms") {
      await readBody(req).catch(() => ({}));
      await handleCreate(req, res);
      return;
    }
    const joinMatch = url.pathname.match(/^\/v1\/rooms\/([^/]+)\/join$/);
    if (method === "POST" && joinMatch) {
      await readBody(req).catch(() => ({}));
      await handleJoin(req, res, decodeURIComponent(joinMatch[1]));
      return;
    }
    if (method === "POST" && url.pathname === "/v1/matchmaking/enqueue") {
      await readBody(req).catch(() => ({}));
      await handleEnqueue(req, res);
      return;
    }
    if (method === "POST" && url.pathname === "/v1/matchmaking/cancel") {
      await handleCancel(req, res);
      return;
    }
    const ticketMatch = url.pathname.match(/^\/v1\/matchmaking\/tickets\/([^/]+)$/);
    if (method === "GET" && ticketMatch) {
      handleTicketStatus(req, res, decodeURIComponent(ticketMatch[1]));
      return;
    }
    json(res, 404, { error: "not_found" });
  } catch (e) {
    log("handler error", e);
    json(res, 500, { error: "internal", message: String(e.message || e) });
  }
});

server.listen(CONFIG.httpPort, CONFIG.httpHost, () => {
  log(
    `listening http://${CONFIG.httpHost}:${CONFIG.httpPort} publicHost=${CONFIG.publicHost} pool=${CONFIG.portStart}-${CONFIG.portEnd} ttlMs=${CONFIG.ttlMs} matchTimeoutMs=${CONFIG.matchTimeoutMs} workerReadyMs=${CONFIG.workerReadyMs} warmPoolSize=${CONFIG.warmPoolSize}`
  );
  log(`projectPath=${CONFIG.projectPath}`);
  if (CONFIG.workerBin) log(`WORKER_BIN=${CONFIG.workerBin}`);
  if (CONFIG.godotBin) log(`GODOT_BIN=${CONFIG.godotBin}`);
  if (WORKER_FP.present) {
    log(
      `worker sha256=${WORKER_FP.sha256} bytes=${WORKER_FP.bytes} path=${WORKER_FP.path} mtime=${WORKER_FP.mtimeUtc}`
    );
  } else {
    log(`worker missing path=${WORKER_FP.path || "(none)"} — lobby/health still up`);
  }
  if (metaDb.isConfigured()) {
    metaDb
      .ensureSchema()
      .then(() => log("MetaSrv Postgres schema OK"))
      .catch((e) => log("MetaSrv schema failed:", e.message || e));
  } else {
    log("MetaSrv disabled — set META_DATABASE_URL to enable /v1/meta/*");
  }
  if (CONFIG.publicHost === "127.0.0.1" || CONFIG.publicHost === "localhost") {
    log(
      "WARN LOBBY_PUBLIC_HOST is loopback — remote clients cannot join ENet. Set LOBBY_PUBLIC_HOST=<public IP or DNS>"
    );
  } else {
    log(`LOBBY_PUBLIC_HOST=${CONFIG.publicHost}`);
  }
  if (opsHttp.opsTokenConfigured()) {
    log("ops monitor GET /ops · GET /ops/db (OPS_TOKEN required)");
  }
  ensureWarmPool();
});

function shutdown() {
  log("shutdown — closing rooms + queue");
  for (const id of [...matchQueue]) {
    const t = tickets.get(id);
    if (t) {
      clearTicketTimeout(t);
      t.status = "cancelled";
    }
  }
  matchQueue.length = 0;
  warmReady.length = 0;
  for (const code of [...rooms.keys()]) {
    closeRoom(code, "shutdown");
  }
  metaDb.endPool().catch(() => {});
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 2000).unref();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
