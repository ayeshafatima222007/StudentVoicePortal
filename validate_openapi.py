"""Project-specific structural checks for the Student Voice Portal OpenAPI contract.

Run from the directory containing openapi.yaml and openapi.json:
    python validate_openapi.py

For full OpenAPI specification validation, also install openapi-spec-validator:
    python -m pip install openapi-spec-validator
    openapi-spec-validator openapi.yaml
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    print("FAIL: PyYAML is missing. Install it with: python -m pip install pyyaml")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parent
YAML_PATH = ROOT / "openapi.yaml"
JSON_PATH = ROOT / "openapi.json"
EXPECTED_OPERATIONS = 17
ALLOWED_METHODS = {"get", "post", "put", "patch", "delete", "options", "head", "trace"}


def resolve_ref(document: dict[str, Any], ref: str) -> Any:
    if not ref.startswith("#/"):
        raise ValueError(f"Only local component references are allowed: {ref}")
    node: Any = document
    for raw in ref[2:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if not isinstance(node, dict) or token not in node:
            raise KeyError(ref)
        node = node[token]
    return node


def walk_refs(node: Any, location: str = "$") -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    if isinstance(node, dict):
        if "$ref" in node:
            found.append((location, node["$ref"]))
        for key, value in node.items():
            found.extend(walk_refs(value, f"{location}.{key}"))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            found.extend(walk_refs(value, f"{location}[{index}]"))
    return found


def dereference(document: dict[str, Any], value: Any) -> Any:
    if isinstance(value, dict) and "$ref" in value:
        return resolve_ref(document, value["$ref"])
    return value


def error_response_uses_envelope(document: dict[str, Any], response: Any) -> bool:
    response = dereference(document, response)
    schema = response.get("content", {}).get("application/json", {}).get("schema", {})
    return schema.get("$ref") == "#/components/schemas/ErrorEnvelope"


def main() -> int:
    problems: list[str] = []
    if not YAML_PATH.exists():
        print("FAIL: openapi.yaml is missing.")
        return 1

    try:
        spec = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        print(f"FAIL: openapi.yaml cannot be parsed: {exc}")
        return 1

    if not isinstance(spec, dict):
        print("FAIL: OpenAPI document root must be a mapping/object.")
        return 1

    if spec.get("openapi") != "3.0.3":
        problems.append("openapi must be 3.0.3.")
    info = spec.get("info", {})
    if not info.get("title") or not info.get("version") or not info.get("description"):
        problems.append("info.title, info.version and info.description are required.")
    if not spec.get("servers"):
        problems.append("At least one server entry is required.")

    components = spec.get("components", {})
    schemas = components.get("schemas", {})
    responses = components.get("responses", {})
    security_schemes = components.get("securitySchemes", {})
    paths = spec.get("paths", {})
    operation_list: list[tuple[str, str, dict[str, Any]]] = []

    for path, path_item in paths.items():
        if not isinstance(path_item, dict):
            problems.append(f"{path}: path item must be an object.")
            continue
        path_placeholders = set(re.findall(r"\{([^{}]+)\}", path))
        path_level_params = path_item.get("parameters", [])
        for method, operation in path_item.items():
            method = method.lower()
            if method not in ALLOWED_METHODS:
                continue
            if not isinstance(operation, dict):
                problems.append(f"{method.upper()} {path}: operation must be an object.")
                continue
            operation_list.append((method, path, operation))
            label = f"{method.upper()} {path}"

            for required_key in ("operationId", "summary", "description", "responses", "x-user-story"):
                if not operation.get(required_key):
                    problems.append(f"{label}: {required_key} is required.")

            operation_ids = [p for p in (path_level_params + operation.get("parameters", [])) if isinstance(p, dict)]
            declared_path_params: set[str] = set()
            for parameter in operation_ids:
                parameter = dereference(spec, parameter)
                if parameter.get("in") == "path" and parameter.get("required") is True:
                    declared_path_params.add(parameter.get("name"))
            missing = path_placeholders - declared_path_params
            if missing:
                problems.append(f"{label}: path parameters not declared as required: {sorted(missing)}")

            security = operation.get("security", [])
            if path.startswith("/admin/"):
                if not any("bearerAuth" in requirement for requirement in security):
                    problems.append(f"{label}: admin operation must require bearerAuth.")
            elif any("bearerAuth" in requirement for requirement in security):
                problems.append(f"{label}: public/student operation must not require admin bearerAuth.")

            for requirement in security:
                for scheme_name in requirement:
                    if scheme_name not in security_schemes:
                        problems.append(f"{label}: unknown security scheme {scheme_name}.")

            request_body = operation.get("requestBody")
            if request_body:
                body = dereference(spec, request_body)
                json_content = body.get("content", {}).get("application/json", {})
                if not json_content.get("schema"):
                    problems.append(f"{label}: JSON request body must define a schema.")

            op_responses = operation.get("responses", {})
            success = [code for code in op_responses if code.isdigit() and 200 <= int(code) < 300]
            if not success:
                problems.append(f"{label}: at least one 2xx response is required.")
            if "default" not in op_responses:
                problems.append(f"{label}: default response is required.")
            for code, response in op_responses.items():
                if code == "default" or (code.isdigit() and int(code) >= 400):
                    try:
                        if not error_response_uses_envelope(spec, response):
                            problems.append(f"{label}: error response {code} must use ErrorEnvelope.")
                    except (KeyError, TypeError, ValueError) as exc:
                        problems.append(f"{label}: cannot resolve error response {code}: {exc}")

    if len(operation_list) != EXPECTED_OPERATIONS:
        problems.append(f"Expected {EXPECTED_OPERATIONS} operations; found {len(operation_list)}.")
    ids = [op.get("operationId") for _, _, op in operation_list]
    if len(set(ids)) != len(ids):
        problems.append("operationId values must be unique.")

    # Project's exact agreed route set.
    expected_paths = {
        "/health", "/auth/login", "/lookups", "/complaints/anonymous",
        "/complaints/identified", "/track/{ref}", "/admin/complaints",
        "/admin/complaints/{complaintId}",
        "/admin/complaints/{complaintId}/status",
        "/admin/complaints/{complaintId}/assignment", "/admin/staff",
        "/admin/complaints/{complaintId}/notes",
        "/admin/complaints/{complaintId}/meetings",
        "/meetings/{meetingId}/confirm", "/meetings/{meetingId}/reschedule",
        "/admin/meetings", "/admin/analytics",
    }
    if set(paths) != expected_paths:
        problems.append("The documented path set does not match the agreed 17-operation contract.")

    # Auth contract checks.
    bearer = security_schemes.get("bearerAuth", {})
    if not (bearer.get("type") == "http" and bearer.get("scheme") == "bearer" and bearer.get("bearerFormat") == "JWT"):
        problems.append("bearerAuth must be HTTP Bearer with bearerFormat JWT.")
    tracking = security_schemes.get("trackingReference", {})
    if not (tracking.get("type") == "apiKey" and tracking.get("in") == "header" and tracking.get("name") == "X-Tracking-Reference"):
        problems.append("trackingReference must use the X-Tracking-Reference header.")
    for path in ("/meetings/{meetingId}/confirm", "/meetings/{meetingId}/reschedule"):
        operation = paths.get(path, {}).get("post", {})
        if not any("trackingReference" in requirement for requirement in operation.get("security", [])):
            problems.append(f"POST {path}: must require trackingReference security.")

    # Contract-level business rules.
    for path, method in (
        ("/auth/login", "post"), ("/track/{ref}", "get"),
        ("/meetings/{meetingId}/confirm", "post"),
        ("/meetings/{meetingId}/reschedule", "post"),
    ):
        if "429" not in paths.get(path, {}).get(method, {}).get("responses", {}):
            problems.append(f"{method.upper()} {path}: expected documented 429 response.")
    if "/admin/complaints/{complaintId}/staff" in paths:
        problems.append("Stale /staff assignment route exists; use /assignment.")

    # OpenAPI 3.0 uses nullable: true, not a JSON Schema null type.
    def inspect_null_types(value: Any, location: str = "$") -> None:
        if isinstance(value, dict):
            if value.get("type") == "null":
                problems.append(f"{location}: type: null is not valid in OpenAPI 3.0; use nullable: true.")
            for key, child in value.items():
                inspect_null_types(child, f"{location}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                inspect_null_types(child, f"{location}[{index}]")
    inspect_null_types(spec)

    for location, ref in walk_refs(spec):
        try:
            resolve_ref(spec, ref)
        except (KeyError, ValueError, TypeError) as exc:
            problems.append(f"Unresolved reference at {location}: {ref} ({exc}).")

    # JSON must be a generated semantic mirror, never a different contract.
    if not JSON_PATH.exists():
        problems.append("openapi.json is missing; regenerate the JSON mirror from openapi.yaml.")
    else:
        try:
            json_spec = json.loads(JSON_PATH.read_text(encoding="utf-8"))
            if json_spec != spec:
                problems.append("openapi.json differs from openapi.yaml; regenerate it from the YAML source.")
        except (json.JSONDecodeError, OSError) as exc:
            problems.append(f"openapi.json cannot be parsed: {exc}.")

    if problems:
        print("FAIL: project-specific OpenAPI checks found problems:")
        for problem in problems:
            print(f"- {problem}")
        return 1

    print("PASS: openapi.yaml parses as YAML.")
    print("PASS: OpenAPI version is 3.0.3.")
    print(f"PASS: exactly {len(operation_list)} operations; operationIds are unique.")
    print("PASS: path parameters are declared and required.")
    print("PASS: all local $ref references resolve.")
    print("PASS: all operations include a user-story trace, success response and default response.")
    print("PASS: all error responses use the common ErrorEnvelope.")
    print("PASS: admin endpoints require JWT and student meeting actions use the tracking-reference header.")
    print("PASS: rate-limited contract operations document 429 responses.")
    print("PASS: openapi.json is semantically identical to openapi.yaml.")

    try:
        from openapi_spec_validator import validate_spec  # type: ignore
    except ImportError:
        print("NOTE: openapi-spec-validator is not installed; run the official CLI separately for full conformance validation.")
    else:
        try:
            validate_spec(spec)
        except Exception as exc:  # validator exceptions vary by package version
            print(f"FAIL: official OpenAPI validation failed: {exc}")
            return 1
        print("PASS: openapi-spec-validator accepted the document.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
