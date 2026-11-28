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
from datetime import datetime
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
EXPECTED_OPERATIONS = 21
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


def operation_request_schema(document: dict[str, Any], operation: dict[str, Any]) -> Any:
    request = operation.get("requestBody")
    if not request:
        return {}
    body = dereference(document, request)
    schema = body.get("content", {}).get("application/json", {}).get("schema", {})
    return dereference(document, schema)


def response_has_error_code(document: dict[str, Any], response: Any, code: str) -> bool:
    response = dereference(document, response)
    content = response.get("content", {}).get("application/json", {})
    candidates = []
    if "example" in content:
        candidates.append(content["example"])
    candidates.extend(
        item.get("value")
        for item in content.get("examples", {}).values()
        if isinstance(item, dict) and "value" in item
    )
    return any(
        isinstance(example, dict)
        and isinstance(example.get("error"), dict)
        and example["error"].get("code") == code
        for example in candidates
    )


def example_schema_problems(
    document: dict[str, Any], schema: Any, value: Any, location: str
) -> list[str]:
    problems: list[str] = []
    if not isinstance(schema, dict):
        return [f"{location}: example has no object schema."]
    if "$ref" in schema:
        return example_schema_problems(document, resolve_ref(document, schema["$ref"]), value, location)
    if "allOf" in schema:
        for index, child in enumerate(schema["allOf"]):
            problems.extend(example_schema_problems(document, child, value, f"{location}.allOf[{index}]"))
    for composition, required_matches in (("oneOf", 1), ("anyOf", 1)):
        alternatives = schema.get(composition, [])
        if alternatives:
            matches = sum(
                not example_schema_problems(document, child, value, location)
                for child in alternatives
            )
            if (composition == "oneOf" and matches != required_matches) or (
                composition == "anyOf" and matches < required_matches
            ):
                problems.append(f"{location}: example does not satisfy {composition} schema.")
    if value is None and schema.get("nullable") is True:
        return problems

    expected_type = schema.get("type")
    type_matches = {
        "object": lambda item: isinstance(item, dict),
        "array": lambda item: isinstance(item, list),
        "string": lambda item: isinstance(item, str),
        "integer": lambda item: isinstance(item, int) and not isinstance(item, bool),
        "number": lambda item: isinstance(item, (int, float)) and not isinstance(item, bool),
        "boolean": lambda item: isinstance(item, bool),
    }
    if expected_type in type_matches and not type_matches[expected_type](value):
        return problems + [f"{location}: example value does not match type {expected_type}."]
    if "enum" in schema and value not in schema["enum"]:
        problems.append(f"{location}: example value is outside the schema enum.")
    if expected_type == "string" and isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            problems.append(f"{location}: example is shorter than minLength.")
        if len(value) > schema.get("maxLength", len(value)):
            problems.append(f"{location}: example is longer than maxLength.")
        pattern = schema.get("pattern")
        if pattern and re.search(pattern, value) is None:
            problems.append(f"{location}: example does not match its pattern.")
        if schema.get("format") == "email" and re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value) is None:
            problems.append(f"{location}: example is not a valid email address.")
        if schema.get("format") == "date-time":
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                problems.append(f"{location}: example is not an ISO 8601 date-time.")
            else:
                if parsed.tzinfo is None:
                    problems.append(f"{location}: date-time example must include a timezone.")
    if expected_type in {"integer", "number"} and isinstance(value, (int, float)):
        if value < schema.get("minimum", value):
            problems.append(f"{location}: example is below minimum.")
        if value > schema.get("maximum", value):
            problems.append(f"{location}: example exceeds maximum.")
    if expected_type == "object" and isinstance(value, dict):
        properties = schema.get("properties", {})
        missing = set(schema.get("required", [])) - set(value)
        if missing:
            problems.append(f"{location}: example omits required properties {sorted(missing)}.")
        if schema.get("additionalProperties") is False:
            extra = set(value) - set(properties)
            if extra:
                problems.append(f"{location}: example includes undeclared properties {sorted(extra)}.")
        elif isinstance(schema.get("additionalProperties"), dict):
            additional_schema = schema["additionalProperties"]
            for key, item in value.items():
                if key not in properties:
                    problems.extend(
                        example_schema_problems(
                            document, additional_schema, item, f"{location}.{key}"
                        )
                    )
        for key, item in value.items():
            if key in properties:
                problems.extend(example_schema_problems(document, properties[key], item, f"{location}.{key}"))
    if expected_type == "array" and isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            problems.extend(example_schema_problems(document, schema["items"], item, f"{location}[{index}]"))
    return problems


def check_media_examples(
    document: dict[str, Any], media: Any, location: str
) -> list[str]:
    if not isinstance(media, dict) or "schema" not in media:
        return []
    examples: list[tuple[str, Any]] = []
    if "example" in media:
        examples.append(("example", media["example"]))
    for name, item in media.get("examples", {}).items():
        if isinstance(item, dict) and "value" in item:
            examples.append((name, item["value"]))
    problems: list[str] = []
    for name, value in examples:
        problems.extend(example_schema_problems(document, media["schema"], value, f"{location}.{name}"))
    return problems


def documents_student_login_lockout(description: str) -> bool:
    text = re.sub(r"\s+", " ", description.casefold())
    failed_attempts_pattern = (
        r"\b(?:5|five)\b.{0,50}\b(?:failed|unsuccessful)\b.{0,50}\battempts?\b"
    )
    lockout_duration = r"(?:15\s*(?:-| )?\s*(?:minutes?|mins?)|900\s*seconds?)"
    lockout_term = r"(?:lock(?:ed|out)?s?|block(?:ed|ing)?)"
    timed_lockout_pattern = (
        rf"\b{lockout_term}\b.{{0,60}}\b{lockout_duration}\b"
        rf"|\b{lockout_duration}\b.{{0,60}}\b{lockout_term}\b"
    )
    return any(
        re.search(failed_attempts_pattern, sentence) is not None
        and re.search(timed_lockout_pattern, sentence) is not None
        for sentence in re.split(r"[.!?;]\s*", text)
    )


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
                if security != [{"bearerAuth": []}]:
                    problems.append(f"{label}: admin operation must require only bearerAuth.")
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
        "/health", "/auth/login", "/auth/student/login",
        "/auth/student/change-password", "/student/me", "/student/complaints/otp",
        "/lookups", "/complaints/anonymous", "/complaints/identified",
        "/track/{ref}", "/admin/complaints",
        "/admin/complaints/{complaintId}",
        "/admin/complaints/{complaintId}/status",
        "/admin/complaints/{complaintId}/assignment", "/admin/staff",
        "/admin/complaints/{complaintId}/notes",
        "/admin/complaints/{complaintId}/meetings",
        "/meetings/{meetingId}/confirm", "/meetings/{meetingId}/reschedule",
        "/admin/meetings", "/admin/analytics",
    }
    if set(paths) != expected_paths:
        problems.append("The documented path set does not match the agreed 21-operation contract.")

    # Auth contract checks.
    bearer = security_schemes.get("bearerAuth", {})
    if not (bearer.get("type") == "http" and bearer.get("scheme") == "bearer" and bearer.get("bearerFormat") == "JWT"):
        problems.append("bearerAuth must be HTTP Bearer with bearerFormat JWT.")
    if "role claim set to admin" not in bearer.get("description", "").lower():
        problems.append("bearerAuth must be documented as the administrator JWT with role=admin.")
    student_bearer = security_schemes.get("studentBearerAuth", {})
    if not (
        student_bearer.get("type") == "http"
        and student_bearer.get("scheme") == "bearer"
        and student_bearer.get("bearerFormat") == "JWT"
    ):
        problems.append("studentBearerAuth must be HTTP Bearer with bearerFormat JWT.")
    student_bearer_description = student_bearer.get("description", "").lower()
    if not all(
        phrase in student_bearer_description
        for phrase in ("post /auth/student/login", "8 hours", "role claim set to student")
    ):
        problems.append("studentBearerAuth must document its issuer, 8-hour expiry, and student role claim.")
    tracking = security_schemes.get("trackingReference", {})
    if not (tracking.get("type") == "apiKey" and tracking.get("in") == "header" and tracking.get("name") == "X-Tracking-Reference"):
        problems.append("trackingReference must use the X-Tracking-Reference header.")
    for path in ("/meetings/{meetingId}/confirm", "/meetings/{meetingId}/reschedule"):
        operation = paths.get(path, {}).get("post", {})
        if operation.get("security") != [{"trackingReference": []}]:
            problems.append(f"POST {path}: must use only trackingReference security.")

    student_protected = (
        ("/auth/student/change-password", "post"),
        ("/student/me", "get"),
        ("/student/complaints/otp", "post"),
        ("/complaints/identified", "post"),
    )
    for path, method in student_protected:
        operation = paths.get(path, {}).get(method, {})
        if operation.get("security") != [{"studentBearerAuth": []}]:
            problems.append(f"{method.upper()} {path}: must require only studentBearerAuth.")
    for path, method in (
        ("/health", "get"), ("/auth/login", "post"), ("/auth/student/login", "post"),
        ("/lookups", "get"), ("/complaints/anonymous", "post"), ("/track/{ref}", "get"),
    ):
        operation = paths.get(path, {}).get(method, {})
        if operation.get("security") != []:
            problems.append(f"{method.upper()} {path}: must remain public.")
    if spec.get("security"):
        problems.append("The document must not impose global security on public operations.")

    # Contract-level business rules.
    for path, method in (
        ("/auth/login", "post"), ("/track/{ref}", "get"),
        ("/auth/student/login", "post"), ("/student/complaints/otp", "post"),
        ("/meetings/{meetingId}/confirm", "post"),
        ("/meetings/{meetingId}/reschedule", "post"),
    ):
        if "429" not in paths.get(path, {}).get(method, {}).get("responses", {}):
            problems.append(f"{method.upper()} {path}: expected documented 429 response.")
    if "/admin/complaints/{complaintId}/staff" in paths:
        problems.append("Stale /staff assignment route exists; use /assignment.")

    def get_operation(path: str, method: str) -> dict[str, Any]:
        return paths.get(path, {}).get(method, {})

    def get_response_schema(path: str, method: str, code: str) -> dict[str, Any]:
        response = dereference(spec, get_operation(path, method).get("responses", {}).get(code, {}))
        schema = response.get("content", {}).get("application/json", {}).get("schema", {})
        return dereference(spec, schema)

    student_login = get_operation("/auth/student/login", "post")
    for code in ("401", "403", "429"):
        if code not in student_login.get("responses", {}):
            problems.append(f"POST /auth/student/login: expected documented {code} response.")
    if not documents_student_login_lockout(student_login.get("description", "")):
        problems.append(
            "POST /auth/student/login: describe a five-failed-attempt threshold and a 15-minute account lockout."
        )
    if not response_has_error_code(spec, student_login.get("responses", {}).get("401", {}), "UNAUTHORIZED"):
        problems.append("POST /auth/student/login: 401 must use the UNAUTHORIZED error code.")
    if "inactive" not in student_login.get("responses", {}).get("403", {}).get("description", "").lower():
        problems.append("POST /auth/student/login: 403 must document an inactive student account.")

    login_request = operation_request_schema(spec, student_login)
    if set(login_request.get("properties", {})) != {"email", "password"} or set(login_request.get("required", [])) != {"email", "password"}:
        problems.append("StudentLoginRequest must contain only required email and password fields.")
    login_response = get_response_schema("/auth/student/login", "post", "200")
    login_response_properties = login_response.get("properties", {})
    if (
        set(login_response_properties)
        != {"access_token", "token_type", "expires_in", "must_change_password"}
        or set(login_response.get("required", []))
        != {"access_token", "token_type", "expires_in", "must_change_password"}
        or login_response_properties.get("token_type", {}).get("enum") != ["bearer"]
        or login_response_properties.get("expires_in", {}).get("enum") != [28800]
        or login_response_properties.get("must_change_password", {}).get("type") != "boolean"
    ):
        problems.append("StudentLoginResponse must match the required bearer-token response contract.")
    login_401 = student_login.get("responses", {}).get("401", {})
    if "same 401 response" not in student_login.get("description", "").lower():
        problems.append("Student login must document the same response for wrong email and password.")
    if not response_has_error_code(spec, login_401, "UNAUTHORIZED"):
        problems.append("Student login must use the shared unauthorized error envelope.")

    password_change = get_operation("/auth/student/change-password", "post")
    password_schema = operation_request_schema(spec, password_change)
    password_properties = password_schema.get("properties", {})
    password_required = set(password_schema.get("required", []))
    new_password = password_properties.get("new_password", {})
    if (
        set(password_properties) != {"current_password", "new_password"}
        or password_schema.get("additionalProperties") is not False
    ):
        problems.append(
            "StudentChangePasswordRequest must contain exactly current_password and new_password."
        )
    if password_required != {"current_password", "new_password"}:
        problems.append(
            "StudentChangePasswordRequest must require both current_password and new_password."
        )
    if new_password.get("minLength") != 8 or new_password.get("maxLength") != 64:
        problems.append(
            "StudentChangePasswordRequest.new_password must have an 8-64 character limit."
        )
    password_response = get_response_schema("/auth/student/change-password", "post", "200")
    if (
        set(password_response.get("properties", {})) != {"must_change_password"}
        or password_response.get("properties", {}).get("must_change_password", {}).get("enum") != [False]
    ):
        problems.append("StudentChangePasswordResponse must be {must_change_password: false}.")

    otp_request = get_operation("/student/complaints/otp", "post")
    for code in ("202", "409", "429"):
        if code not in otp_request.get("responses", {}):
            problems.append(f"POST /student/complaints/otp: expected documented {code} response.")
    if not response_has_error_code(spec, otp_request.get("responses", {}).get("409", {}), "OPEN_COMPLAINT_LIMIT"):
        problems.append("POST /student/complaints/otp: 409 must use OPEN_COMPLAINT_LIMIT.")
    if "60 seconds" not in otp_request.get("description", ""):
        problems.append("POST /student/complaints/otp: document its 60-second resend cooldown.")

    identified = get_operation("/complaints/identified", "post")
    identified_schema = operation_request_schema(spec, identified)
    if set(identified_schema.get("properties", {})) != {"category_id", "description", "otp"}:
        problems.append("IdentifiedComplaintRequest must contain only category_id, description, and otp.")
    if set(identified_schema.get("required", [])) != {"category_id", "description", "otp"}:
        problems.append("IdentifiedComplaintRequest must require category_id, description, and otp.")
    description_schema = identified_schema.get("properties", {}).get("description", {})
    otp_schema = identified_schema.get("properties", {}).get("otp", {})
    if description_schema.get("minLength") != 20 or description_schema.get("maxLength") != 1000:
        problems.append("IdentifiedComplaintRequest.description must be 20-1000 characters.")
    if (
        otp_schema.get("type") != "string"
        or otp_schema.get("pattern") != "^[0-9]{6}$"
        or otp_schema.get("minLength") != 6
        or otp_schema.get("maxLength") != 6
    ):
        problems.append(
            "IdentifiedComplaintRequest.otp must be a six-character string matching ^[0-9]{6}$."
        )
    if "422" not in identified.get("responses", {}):
        problems.append("POST /complaints/identified: incorrect or expired OTP must document 422.")
    if "incorrect or expired" not in identified.get("responses", {}).get("422", {}).get("description", "").lower():
        problems.append("POST /complaints/identified: 422 must describe incorrect or expired OTP.")
    if not response_has_error_code(spec, identified.get("responses", {}).get("409", {}), "OPEN_COMPLAINT_LIMIT"):
        problems.append("POST /complaints/identified: 409 must use OPEN_COMPLAINT_LIMIT.")
    if identified.get("x-user-story") != "US-44":
        problems.append("POST /complaints/identified must be traced to US-44.")

    profile_schema = get_response_schema("/student/me", "get", "200")
    profile_properties = profile_schema.get("properties", {})
    expected_profile_fields = {
        "email", "registration_no", "batch", "section", "class_timing", "open_complaints"
    }
    if set(profile_properties) != expected_profile_fields:
        problems.append(
            "StudentProfileResponse must contain exactly email, registration_no, batch, "
            "section, class_timing, and open_complaints."
        )
    if set(profile_schema.get("required", [])) != expected_profile_fields:
        problems.append("StudentProfileResponse must require all six documented profile fields.")
    if (
        profile_properties.get("email", {}).get("type") != "string"
        or profile_properties.get("email", {}).get("format") != "email"
    ):
        problems.append("StudentProfileResponse.email must be a string with email format.")
    if (
        profile_properties.get("registration_no", {}).get("type") != "string"
        or profile_properties.get("registration_no", {}).get("pattern")
        != "^[0-9]{4}-[A-Z]{2,4}-[0-9]{3}$"
    ):
        problems.append(
            "StudentProfileResponse.registration_no must match the documented registration-number pattern."
        )
    expected_profile_refs = {
        "batch": "#/components/schemas/LookupBatch",
        "section": "#/components/schemas/LookupSection",
        "class_timing": "#/components/schemas/ClassTiming",
    }
    for field, reference in expected_profile_refs.items():
        if profile_properties.get(field, {}).get("$ref") != reference:
            problems.append(f"StudentProfileResponse.{field} must reference {reference}.")
    open_complaints = profile_properties.get("open_complaints", {})
    if (
        open_complaints.get("type") != "integer"
        or open_complaints.get("minimum") != 0
        or open_complaints.get("maximum") != 2
    ):
        problems.append(
            "StudentProfileResponse.open_complaints must be an integer from 0 through 2."
        )

    otp_response = get_response_schema("/student/complaints/otp", "post", "202")
    otp_properties = otp_response.get("properties", {})
    if (
        set(otp_properties) != {"expires_in", "resend_after"}
        or otp_properties.get("expires_in", {}).get("enum") != [300]
        or otp_properties.get("resend_after", {}).get("enum") != [60]
    ):
        problems.append("StudentComplaintOtpResponse must document 300-second expiry and 60-second resend delay.")

    anonymous = get_operation("/complaints/anonymous", "post")
    if "503" not in anonymous.get("responses", {}):
        problems.append("POST /complaints/anonymous must document 503 while paused.")
    if not response_has_error_code(spec, anonymous.get("responses", {}).get("503", {}), "ANONYMOUS_PAUSED"):
        problems.append("POST /complaints/anonymous: 503 must use ANONYMOUS_PAUSED.")
    if anonymous.get("requestBody") is None:
        problems.append("POST /complaints/anonymous and its request schema must be preserved.")

    # Check examples on the student flows and both complaint submissions against
    # their documented schemas, including string OTPs that preserve leading zeroes.
    example_paths = {
        ("/auth/student/login", "post"),
        ("/auth/student/change-password", "post"),
        ("/student/me", "get"),
        ("/student/complaints/otp", "post"),
        ("/complaints/anonymous", "post"),
        ("/complaints/identified", "post"),
    }
    for path, method in example_paths:
        operation = get_operation(path, method)
        body = operation.get("requestBody")
        if body:
            body = dereference(spec, body)
            media = body.get("content", {}).get("application/json", {})
            problems.extend(check_media_examples(spec, media, f"{method.upper()} {path} request"))
        for code, response in operation.get("responses", {}).items():
            response = dereference(spec, response)
            media = response.get("content", {}).get("application/json", {})
            problems.extend(check_media_examples(spec, media, f"{method.upper()} {path} response {code}"))

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
    print("PASS: administrator, student, public, and tracking-reference security requirements are distinct.")
    print("PASS: student login, password, profile, OTP, open-complaint, and anonymous-pause contract checks pass.")
    print("PASS: existing JSON examples in the selected student and complaint requests and responses match their schemas.")
    print("PASS: all rate-limited contract operations document 429 responses.")
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
