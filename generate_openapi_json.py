"""Regenerate openapi.json from the canonical openapi.yaml.

Run from this directory after editing openapi.yaml:
    python generate_openapi_json.py
"""
from __future__ import annotations

import json
from pathlib import Path
import sys

try:
    import yaml  # type: ignore
except ImportError:
    print("PyYAML is required. Install it with: python -m pip install pyyaml")
    raise SystemExit(1)

root = Path(__file__).resolve().parent
yaml_path = root / "openapi.yaml"
json_path = root / "openapi.json"

try:
    spec = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
except FileNotFoundError:
    print("openapi.yaml is missing.")
    raise SystemExit(1)
except yaml.YAMLError as exc:
    print(f"openapi.yaml is invalid YAML: {exc}")
    raise SystemExit(1)

json_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Generated openapi.json from openapi.yaml.")
