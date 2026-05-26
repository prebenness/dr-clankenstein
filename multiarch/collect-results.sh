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
    row = {
        "run": os.path.basename(path),
        "ok": "missing",
        "backend": "",
        "partition": "",
        "node": "",
        "device_name": "",
        "job_id": "",
        "error": "",
        "variant": "",
        "apptainer_exit": "",
    }
    result = os.path.join(path, "result.json")
    if os.path.exists(result):
        try:
            with open(result, "r", encoding="utf-8") as f:
                row.update(json.load(f))
        except Exception as exc:
            row["ok"] = f"bad-json:{exc}"
    variant = os.path.join(path, "successful-variant.txt")
    if os.path.exists(variant):
        with open(variant, "r", encoding="utf-8") as f:
            row["variant"] = f.read().strip()
    exit_code = os.path.join(path, "exit-code.txt")
    if os.path.exists(exit_code):
        with open(exit_code, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("apptainer_exit="):
                    row["apptainer_exit"] = line.split("=", 1)[1].strip()
    rows.append(row)

cols = ["run", "ok", "backend", "partition", "node", "device_name", "job_id", "variant", "apptainer_exit", "error"]
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
