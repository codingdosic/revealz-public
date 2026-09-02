#!/usr/bin/env python3
"""Ops CLI — talks to lobby /v1/ops/* and /v1/health. Does not start Node."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_URL = os.environ.get("OPS_LOBBY_URL", "http://127.0.0.1:8080").rstrip("/")


def request(method: str, path: str, token: str, body: dict | None = None) -> dict:
    url = DEFAULT_URL + path
    sep = "&" if "?" in path else "?"
    if token:
        url = url + sep + "token=" + urllib.parse.quote(token)
    data = None
    headers = {"X-Ops-Token": token, "Content-Type": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"error": raw[:400], "status": e.code}
        print(json.dumps(parsed, ensure_ascii=False, indent=2))
        raise SystemExit(1)


def main() -> int:
    p = argparse.ArgumentParser(description="revealz ops CLI")
    p.add_argument("--token", default=os.environ.get("OPS_TOKEN", ""))
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("health")
    acc = sub.add_parser("account")
    acc.add_argument("key")
    g = sub.add_parser("grant")
    g.add_argument("key")
    g.add_argument("--card", type=int, required=True)
    g.add_argument("--rarity", type=int, default=0)
    g.add_argument("--count", type=int, default=1)
    ga = sub.add_parser("grant-all")
    ga.add_argument("key")
    ga.add_argument("--count", type=int, default=1)
    gold = sub.add_parser("gold")
    gold.add_argument("key")
    gold.add_argument("amount", type=int)
    name = sub.add_parser("name")
    name.add_argument("key")
    name.add_argument("display_name")
    delete_acc = sub.add_parser("delete-account")
    delete_acc.add_argument("key")
    m = sub.add_parser("maintenance")
    m.add_argument("state", choices=["on", "off"])
    m.add_argument("--message", default="")
    sub.add_parser("precheck")
    backup = sub.add_parser("backup")
    backup.add_argument("--label", required=True, help="backup label text (used in dump filename)")
    sub.add_parser("backups")
    restore = sub.add_parser("restore")
    restore.add_argument("name", help="backup file name to restore")

    args = p.parse_args()
    token = args.token
    if args.cmd != "health" and not token:
        print("OPS_TOKEN or --token required", file=sys.stderr)
        return 2

    if args.cmd == "health":
        out = request("GET", "/v1/health", token)
    elif args.cmd == "account":
        out = request("GET", "/v1/ops/account?key=" + urllib.parse.quote(args.key), token)
    elif args.cmd == "grant":
        out = request(
            "POST",
            "/v1/ops/grant",
            token,
            {
                "mode": "one",
                "accountKey": args.key,
                "cardId": args.card,
                "rarity": args.rarity,
                "count": args.count,
            },
        )
    elif args.cmd == "grant-all":
        out = request(
            "POST",
            "/v1/ops/grant",
            token,
            {"mode": "all", "accountKey": args.key, "count": args.count},
        )
    elif args.cmd == "gold":
        out = request("POST", "/v1/ops/account", token, {"accountKey": args.key, "gold": args.amount})
    elif args.cmd == "name":
        out = request(
            "POST",
            "/v1/ops/account",
            token,
            {"accountKey": args.key, "displayName": args.display_name},
        )
    elif args.cmd == "delete-account":
        out = request(
            "POST",
            "/v1/ops/account/delete",
            token,
            {"accountKey": args.key},
        )
    elif args.cmd == "maintenance":
        out = request(
            "POST",
            "/v1/ops/maintenance",
            token,
            {"enabled": args.state == "on", "message": args.message},
        )
    elif args.cmd == "precheck":
        out = request("POST", "/v1/ops/precheck", token, {})
    elif args.cmd == "backup":
        out = request("POST", "/v1/ops/backup", token, {"label": args.label})
    elif args.cmd == "backups":
        out = request("GET", "/v1/ops/backups", token)
    elif args.cmd == "restore":
        out = request("POST", "/v1/ops/restore", token, {"name": args.name})
    else:
        return 2
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
