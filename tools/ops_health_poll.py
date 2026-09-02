#!/usr/bin/env python3
"""Poll lobby GET /v1/health into lobby/ops-data/health.jsonl. Does not start Node."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO / "lobby" / "ops-data" / "health.jsonl"
DEFAULT_URL = "http://127.0.0.1:8080/v1/health"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def host_stats():
    try:
        import psutil  # type: ignore
    except Exception:
        return None
    try:
        vm = psutil.virtual_memory()
        return {
            "cpuPct": round(float(psutil.cpu_percent(interval=0.1)), 1),
            "memUsedMb": int(vm.used / (1024 * 1024)),
            "memTotalMb": int(vm.total / (1024 * 1024)),
        }
    except Exception:
        return None


def poll_once(url: str, timeout: float) -> dict:
    record = {"ts": utc_now(), "ok": False}
    host = host_stats()
    if host:
        record["host"] = host
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = resp.getcode()
            body = json.loads(resp.read().decode("utf-8"))
        if not isinstance(body, dict):
            record["error"] = "health_not_object"
            return record
        record["ok"] = bool(body.get("ok", False)) and 200 <= status < 300
        for key in (
            "rooms",
            "freePorts",
            "queueSize",
            "warmReady",
            "warmSpawning",
            "warmTarget",
            "metaDb",
            "version",
            "worker",
            "maintenance",
            "maintenanceMessage",
        ):
            if key in body:
                record[key] = body[key]
        if not record["ok"]:
            record["error"] = "health_ok_false"
        return record
    except urllib.error.HTTPError as e:
        record["error"] = f"http_{e.code}"
        return record
    except Exception as e:
        record["error"] = str(e)[:200]
        return record


def append_jsonl(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
    with path.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Append lobby health snapshots to jsonl.")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--interval", type=int, default=60, help="Seconds between polls (0=once)")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    out = Path(args.out)
    interval = 0 if args.once else max(0, args.interval)

    def tick() -> None:
        rec = poll_once(args.url, args.timeout)
        append_jsonl(out, rec)
        status = "ok" if rec.get("ok") else rec.get("error", "fail")
        print(f"{rec['ts']} {status} -> {out}", flush=True)

    if interval <= 0:
        tick()
        return 0
    print(f"polling {args.url} every {interval}s -> {out}", flush=True)
    while True:
        tick()
        time.sleep(interval)


if __name__ == "__main__":
    sys.exit(main())
