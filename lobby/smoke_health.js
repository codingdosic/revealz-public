/**
 * Start lobby with warm pool off, GET /v1/health, then stop.
 * Does not spawn Dedicated. Does not hit a remote VM.
 */
"use strict";

const http = require("http");
const { spawn } = require("child_process");

const HOST = "127.0.0.1";
const PORT = Number(process.env.SMOKE_PORT || 18080);
const DEADLINE_MS = Number(process.env.SMOKE_DEADLINE_MS || 15000);

function getHealth() {
  return new Promise((resolve, reject) => {
    const req = http.get(`http://${HOST}:${PORT}/v1/health`, (res) => {
      let buf = "";
      res.on("data", (c) => {
        buf += c;
      });
      res.on("end", () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(buf) });
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on("error", reject);
    req.setTimeout(2000, () => {
      req.destroy(new Error("health timeout"));
    });
  });
}

async function waitHealth() {
  const t0 = Date.now();
  let lastErr = new Error("smoke timeout");
  while (Date.now() - t0 < DEADLINE_MS) {
    try {
      const got = await getHealth();
      if (got.status === 200 && got.body && got.body.ok === true) {
        return got.body;
      }
      lastErr = new Error(`health status=${got.status} ok=${got.body && got.body.ok}`);
    } catch (e) {
      lastErr = e;
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw lastErr;
}

function assertHealth(body) {
  if (!body.version || !String(body.version.lobby || "")) {
    throw new Error("missing version.lobby");
  }
  if (!body.worker || typeof body.worker.present !== "boolean") {
    throw new Error("missing worker.present");
  }
  if (body.worker.present) {
    if (!/^[a-f0-9]{64}$/.test(String(body.worker.sha256 || ""))) {
      throw new Error("worker.sha256 is not 64-char hex");
    }
  }
}

function main() {
  const child = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      WARM_POOL_SIZE: "0",
      LOBBY_BIND: HOST,
      LOBBY_HTTP_PORT: String(PORT),
      LOBBY_PUBLIC_HOST: "127.0.0.1",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (d) => process.stdout.write(d));
  child.stderr.on("data", (d) => process.stderr.write(d));

  let exiting = false;
  const stop = (code) => {
    if (exiting) return;
    exiting = true;
    const killer = setTimeout(() => process.exit(code), 2000);
    child.once("exit", () => {
      clearTimeout(killer);
      process.exit(code);
    });
    child.kill("SIGTERM");
  };

  child.on("exit", (code, sig) => {
    if (!exiting) {
      console.error("lobby exited before smoke finished", code, sig);
      process.exit(1);
    }
  });

  waitHealth()
    .then((body) => {
      assertHealth(body);
      console.log(
        "smoke ok",
        JSON.stringify({ ok: body.ok, version: body.version, worker: body.worker })
      );
      stop(0);
    })
    .catch((e) => {
      console.error("smoke failed:", e.message || e);
      stop(1);
    });
}

main();
