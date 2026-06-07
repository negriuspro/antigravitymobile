from __future__ import annotations

import json
import os
import glob
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


CLAUDE_HOME = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))


PRICING = {
    "opus": {
        "in": 15.0,
        "out": 75.0,
        "cache_read": 1.50,
        "cache_w_5m": 18.75,
        "cache_w_1h": 30.0,
    },
    "sonnet": {
        "in": 3.0,
        "out": 15.0,
        "cache_read": 0.30,
        "cache_w_5m": 3.75,
        "cache_w_1h": 6.0,
    },
    "haiku": {
        "in": 1.0,
        "out": 5.0,
        "cache_read": 0.10,
        "cache_w_5m": 1.25,
        "cache_w_1h": 2.0,
    },
}


def _model_family(model_id: Optional[str]) -> str:
    if not model_id:
        return "opus"
    m = model_id.lower()
    if "opus" in m:
        return "opus"
    if "sonnet" in m:
        return "sonnet"
    if "haiku" in m:
        return "haiku"
    return "opus"


def _estimate_cost(usage: dict, model: Optional[str]) -> float:
    p = PRICING[_model_family(model)]
    cache = usage.get("cache_creation") or {}
    c5m = cache.get("ephemeral_5m_input_tokens", 0)
    c1h = cache.get("ephemeral_1h_input_tokens", 0)
    return (
        usage.get("input_tokens", 0) * p["in"] / 1_000_000
        + usage.get("output_tokens", 0) * p["out"] / 1_000_000
        + usage.get("cache_read_input_tokens", 0) * p["cache_read"] / 1_000_000
        + c5m * p["cache_w_5m"] / 1_000_000
        + c1h * p["cache_w_1h"] / 1_000_000
    )


@dataclass
class Snapshot:
    session: dict = field(default_factory=dict)
    today: dict = field(default_factory=dict)
    sparkline: list[int] = field(default_factory=list)
    has_data: bool = False


def _parse_jsonl(path: str) -> list[dict]:
    records = []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if d.get("type") != "assistant":
                    continue
                msg = d.get("message") or {}
                usage = msg.get("usage")
                if not usage:
                    continue
                ts_str = d.get("timestamp") or ""
                try:
                    ts = datetime.fromisoformat(
                        ts_str.replace("Z", "+00:00")
                    ).timestamp()
                except ValueError:
                    ts = 0.0
                records.append(
                    {
                        "ts": ts,
                        "session": d.get("sessionId"),
                        "model": msg.get("model"),
                        "usage": usage,
                    }
                )
    except (FileNotFoundError, OSError):
        pass
    return records


def collect() -> Snapshot:
    projects_dir = CLAUDE_HOME / "projects"
    history_file = CLAUDE_HOME / "history.jsonl"

    if not projects_dir.is_dir() and not history_file.is_file():
        return Snapshot()

    now = datetime.now(timezone.utc)
    now_epoch = now.timestamp()
    today_start = datetime(
        now.year, now.month, now.day, tzinfo=timezone.utc
    ).timestamp()

    paths = glob.glob(str(projects_dir / "**" / "*.jsonl"), recursive=True)
    if not paths and not history_file.is_file():
        return Snapshot()

    histories: dict[str, list[dict]] = {p: _parse_jsonl(p) for p in paths}

    latest_path = None
    latest_mtime = 0
    for p in paths:
        try:
            mt = os.stat(p).st_mtime
        except FileNotFoundError:
            continue
        if mt > latest_mtime:
            latest_mtime = mt
            latest_path = p

    sess = {
        "id": None,
        "model": None,
        "tier": None,
        "input": 0,
        "output": 0,
        "cache_read": 0,
        "cache_write": 0,
        "total": 0,
        "cost": 0.0,
        "last_mtime": latest_mtime,
    }
    today = {
        "input": 0,
        "output": 0,
        "cache_read": 0,
        "cache_write": 0,
        "total": 0,
        "cost": 0.0,
        "messages": 0,
    }
    sparkline = [0] * 30
    spark_window = 30 * 60

    for path, records in histories.items():
        for r in records:
            u = r["usage"]
            inp = u.get("input_tokens", 0)
            outp = u.get("output_tokens", 0)
            cr = u.get("cache_read_input_tokens", 0)
            cw = u.get("cache_creation_input_tokens", 0)
            total = inp + outp + cr + cw
            cost = _estimate_cost(u, r["model"])

            if path == latest_path:
                sess["input"] += inp
                sess["output"] += outp
                sess["cache_read"] += cr
                sess["cache_write"] += cw
                sess["total"] += total
                sess["cost"] += cost
                if r["model"]:
                    sess["model"] = r["model"]
                if u.get("service_tier"):
                    sess["tier"] = u["service_tier"]
                if r["session"]:
                    sess["id"] = r["session"]

            if r["ts"] >= today_start:
                today["input"] += inp
                today["output"] += outp
                today["cache_read"] += cr
                today["cache_write"] += cw
                today["total"] += total
                today["cost"] += cost
                today["messages"] += 1

            delta = now_epoch - r["ts"]
            if 0 <= delta < spark_window:
                idx = 29 - int(delta // 60)
                if 0 <= idx < 30:
                    sparkline[idx] += total

    sess["cost"] = round(sess["cost"], 6)
    today["cost"] = round(today["cost"], 6)

    return Snapshot(session=sess, today=today, sparkline=sparkline, has_data=True)
