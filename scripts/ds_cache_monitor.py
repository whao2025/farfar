#!/usr/bin/env python3
"""DeepSeek prefix-cache hit-rate monitor for opencode sessions (freepdf).

Read-only viewer over the opencode SQLite store (opencode.db). It focuses on
official DeepSeek API sessions (session.model JSON providerID == 'deepseek'),
which is the only endpoint where prompt_cache_* is hard-validatable and real
cost accrues. Zen free sessions (providerID == 'opencode') are excluded by
default. NEVER writes to the database.

Usage:
  python ds_cache_monitor.py --recent 5
  python ds_cache_monitor.py --session <id> --tail 20
  python ds_cache_monitor.py --watch 10
  python ds_cache_monitor.py --checkpoint
  python ds_cache_monitor.py --provider all --recent 5 --json

Hit rate = cache.read / (cache.read + input), token-weighted, double-zero rows
excluded. Per project guide: cache.write is always 0 for this setup.
"""

import argparse
import json
import os
import sqlite3
import sys
import time
from datetime import datetime

# Official endpoint only (paid DeepSeek API). Zen free uses providerID 'opencode'.
OFFICIAL = "deepseek"

DB_PATH = os.environ.get(
    "OPENCODE_DB",
    os.path.expanduser(r"~\.local\share\opencode\opencode.db"),
)


def connect_ro(path: str) -> sqlite3.Connection:
    """Open DB strictly read-only with busy retries. Never creates writes."""
    uri = "file:" + path.replace("\\", "/") + "?mode=ro"
    last: Exception | None = None
    for _ in range(5):
        try:
            conn = sqlite3.connect(uri, uri=True, timeout=30.0)
            conn.execute("PRAGMA busy_timeout=30000")
            conn.execute("PRAGMA query_only=ON")
            return conn
        except sqlite3.Error as exc:
            last = exc
            time.sleep(1.0)
    raise RuntimeError(f"cannot open db read-only: {path}: {last}")


def load_sessions(conn: sqlite3.Connection, provider: str | None, limit: int) -> list[dict]:
    """Fetch lean session rows, filter by provider in Python (avoid json_extract
    in WHERE: non-JSON rows or index issues)."""
    rows = conn.execute(
        "SELECT id, slug, title, agent, model, cost, tokens_input, tokens_output,"
        " tokens_reasoning, tokens_cache_read, tokens_cache_write,"
        " time_created, time_updated"
        " FROM session"
        f" ORDER BY time_updated DESC LIMIT {int(limit)}"
    ).fetchall()
    out = []
    for r in rows:
        modelJSON = None
        try:
            import json
            modelJSON = json.loads(r[4]) if r[4] else {}
        except Exception:
            modelJSON = {}
        pid = modelJSON.get("providerID")
        if provider in ("all", None) or pid == provider:
            out.append({
                "id": r[0],
                "provider": pid,
                "model": modelJSON.get("id"),
                "title": r[2],
                "agent": r[3],
                "cost": r[5] or 0.0,
                "inp": r[6] or 0,
                "out": r[7] or 0,
                "reasoning": r[8] or 0,
                "c_read": r[9] or 0,
                "c_write": r[10] or 0,
                "created": r[11],
                "updated": r[12],
            })
    return out


def hit_rate(c_read: int, inp: int) -> float | None:
    """token-weighted hit rate; None when denominator is zero."""
    if c_read + inp <= 0:
        return None
    return c_read / (c_read + inp)


def fmt_rate(r: float | None) -> str:
    if r is None:
        return "  -  "
    return f"{r * 100:6.1f}%"


def fmt_dt(ms: int) -> str:
    if not ms:
        return "-"
    return datetime.fromtimestamp(ms / 1000).strftime("%m-%d %H:%M")


def print_session_table(sessions: list[dict], json_out: bool) -> None:
    if json_out:
        import json
        print(json.dumps(sessions, ensure_ascii=False, indent=2))
        return
    print(f"{'SESSION':<22} {'PROV':<9}{'RATE':>8}  {'cost':>8}  {'inp':>9}  {'read':>9}  updated")
    for s in sessions:
        r = hit_rate(s["c_read"], s["inp"])
        print(f"{s['id'][:20]:<22} {str(s['provider'])[:13]:<14}{fmt_rate(r):>8}  "
              f"{s['cost']:>8.4f} {s['inp']:>9} {s['c_read']:>9}  {fmt_dt(s['updated'])}  {s['title'][:24]}")


def load_rounds(conn: sqlite3.Connection, sid: str) -> list[dict]:
    """Per-assistant-message usage for one session (oldest first)."""
    rows = conn.execute(
        "SELECT data, time_created FROM message"
        " WHERE session_id=? AND json_extract(data,'$.role')='assistant'"
        " ORDER BY time_created ASC",
        (sid,),
    ).fetchall()
    rounds = []
    for raw, t in rows:
        try:
            import json
            d = json.loads(raw)
            tk = d.get("tokens") or {}
            r = {
                "t": t,
                "inp": tk.get("input") or 0,
                "out": tk.get("output") or 0,
                "reasoning": tk.get("reasoning") or 0,
                "c_read": (tk.get("cache") or {}).get("read") or 0,
                "c_write": (tk.get("cache") or {}).get("write") or 0,
                "cost": d.get("cost") or 0.0,
            }
            r["hr"] = hit_rate(r["c_read"], r["inp"])
            rounds.append(r)
        except Exception:
            continue
    return rounds


def cmd_tail(conn, sessions: list[dict], sid: str, n: int, json_out: bool, since_h: float | None) -> None:
    if sid not in {s["id"] for s in sessions}:
        sys.exit(f"session {sid} not found or not in provider filter")
    rounds = load_rounds(conn, sid)
    if since_h:
        cutoff = time.time() * 1000 - since_h * 3600_000
        rounds = [r for r in rounds if r["t"] >= cutoff]
    rounds = rounds[-n:]
    if json_out:
        import json
        print(json.dumps(rounds, ensure_ascii=False, indent=2))
        return
    print(f"session {sid} — last {len(rounds)} assistant rounds")
    print(f"{'time':>12} {'inp':>8} {'read':>8} {'out':>6} {'rz':>6} {'cost':>8} {'HR':>7}")
    for r in rounds:
        print(f"{fmt_dt(r['t']):>12} {r['inp']:>8} {r['c_read']:>8} {r['out']:>6} "
              f"{r['reasoning']:>6} {r['cost']:>8.4f} {fmt_rate(r['hr']):>7}")
    tot_read = sum(r["c_read"] for r in rounds)
    tot_inp = sum(r["inp"] for r in rounds)
    print("agg:", fmt_rate(hit_rate(tot_read, tot_inp)), f"(read={tot_read}, input={tot_inp})")


def cmd_recent(sessions, n, json_out):
    print_session_table(sessions, json_out)


def cmd_watch(seconds, json_out):
    """Poll the most recently-updated session every `seconds` s, incremental."""
    last_total = 0
    while True:
        conn = connect_ro(DB_PATH)
        sessions = load_sessions(conn, "all", 50)
        active = max(sessions, key=lambda s: s["updated"]) if sessions else None
        if not active:
            print("no sessions")
            break
        tot_c = active["c_read"]
        tot_i = active["inp"]
        hr = hit_rate(tot_c, tot_i)
        total = tot_c + tot_i
        if total != last_total:
            stamp = datetime.now().strftime("%H:%M:%S")
            line = f"[{stamp}] {active['id'][:20]} prov={active['provider']} " \
                   f"HR={fmt_rate(hr)} input={tot_i} read={tot_c} cost={active['cost']:.4f}"
            print(line)
            last_total = total
        time.sleep(seconds)


def cmd_checkpoint(sessions, conn, json_out):
    """Compare recent window vs previous window hit-rates to attribute a drop."""
    latest = max(sessions, key=lambda s: s["updated"]) if sessions else None
    if not latest:
        print("no sessions")
        return
    rounds = load_rounds(conn, latest["id"])
    if len(rounds) < 8:
        print("not enough rounds for checkpoint, use --tail instead")
        return
    half = len(rounds) // 2
    first, second = rounds[:half], rounds[half:]
    fR = sum(r["c_read"] for r in first); fI = sum(r["inp"] for r in first)
    sR = sum(r["c_read"] for r in second); sI = sum(r["inp"] for r in second)
    fh, sh = hit_rate(fR, fI), hit_rate(sR, sI)
    print(f"session {latest['id'][:20]}")
    print(f"  first {len(first)} rounds: HR={fmt_rate(fh)} (read={fR}, in={fI})")
    print(f"  last  {len(second)} rounds: HR={fmt_rate(sh)} (read={sR}, in={sI})")
    print("  drop =", fmt_rate((fh or 0) - (sh or 0)))


def main():
    import json
    p = argparse.ArgumentParser(description="DeepSeek cache monitor (read-only)")
    p.add_argument("--recent", type=int, default=5, help="list N most recent sessions")
    p.add_argument("--session", type=str, help="session id")
    p.add_argument("--tail", type=int, default=20, help="last N rounds (with --session)")
    p.add_argument("--watch", type=float, help="poll interval seconds for active session")
    p.add_argument("--checkpoint", action="store_true", help="half-vs-half hit-rate diff")
    p.add_argument("--provider", default="deepseek", choices=["deepseek", "opencode", "all"],
                   help="provider filter (default: official deepseek only)")
    p.add_argument("--since", type=float, help="only rounds since N hours")
    p.add_argument("--json", action="store_true", help="emit JSON")
    a = p.parse_args()

    if not os.path.exists(DB_PATH):
        print(f"db not found: {DB_PATH} (set OPENCODE_DB if relocated)", file=sys.stderr)
        sys.exit(1)

    conn = connect_ro(DB_PATH)
    limit = max(a.recent, 200)
    sessions = load_sessions(conn, a.provider, limit)

    if a.watch is not None:
        cmd_watch(a.watch, a.json)
        return
    if a.session:
        cmd_tail(conn, sessions, a.session, a.tail, a.json, a.since)
        return
    if a.checkpoint:
        cmd_checkpoint(sessions, conn, a.json)
        return
    cmd_recent(sessions, a.recent, a.json)


if __name__ == "__main__":
    main()