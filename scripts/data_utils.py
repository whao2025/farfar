#!/usr/bin/env python3
"""Shared data-loading helpers for freepdf training scripts. Pure stdlib."""

import json
from pathlib import Path


def load_records(path) -> list:
    """Load records from single JSON document or JSONL.

    Formats accepted:
      * bare array ``[...]``
      * wrapper ``{..., records:[...]}``
      * JSONL (one JSON object per non-empty line)

    Strategy: try to parse the whole file as one JSON document first (covers
    bare array and wrapper dict); if that fails (e.g. JSONL), parse line-by-line.
    """
    if not isinstance(path, Path):
        path = Path(path)
    raw = path.read_text(encoding='utf-8')

    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and 'records' in data:
            return data['records']
        raise ValueError('Unsupported JSON document: not an array and missing "records" key')
    except json.JSONDecodeError:
        pass

    records = []
    for line in raw.splitlines():
        line = line.strip()
        if line:
            payload = json.loads(line)
            if isinstance(payload, dict) and 'records' in payload:
                records.extend(payload['records'])
            else:
                records.append(payload)
    return records