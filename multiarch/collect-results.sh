#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR=${1:-$(pwd -P)/multiarch/results}

python3 - "$RESULTS_DIR" <<'PY'
import glob
import json
import os
import sys

root = sys.argv[1]
rows = []
for path in sorted(glob.glob(os.path.join(root, "*"))):
    if not os.path.isdir(path):
        continue
    row = {"run": os.path.basename(path), "ok": "missing", "backend": "", "partition": "", "node": "", "device_name": "", "job_id": ""}
    result = os.path.join(path, "result.json")
    if os.path.exists(result):
        try:
            with open(result, "r", encoding="utf-8") as f:
                row.update(json.load(f))
        except Exception as exc:
            row["ok"] = f"bad-json:{exc}"
    rows.append(row)

cols = ["run", "ok", "backend", "partition", "node", "device_name", "job_id"]
widths = {}
for c in cols:
    values = [len(c)]
    values.extend(len(str(r.get(c, ""))) for r in rows)
    widths[c] = max(values)
print("  ".join(c.ljust(widths[c]) for c in cols))
print("  ".join("-" * widths[c] for c in cols))
for row in rows:
    print("  ".join(str(row.get(c, "")).ljust(widths[c]) for c in cols))
if not rows:
    print(f"No result directories under {root}")
PY
