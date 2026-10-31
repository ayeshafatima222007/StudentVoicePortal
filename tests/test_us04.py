"""
Automated tests for US-04: health endpoint and standard JSON error handler.

Run from the project root (next to main.py):
    pip install pytest
    python -m pytest test/test_us04.py -v

No database is needed: the MySQL pool is mocked before main.py is imported.
"""
import logging
from unittest.mock import patch

import pytest
from fastapi import HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.testclient import TestClient
from pydantic import BaseModel

# main.py creates the MySQL pool at import time, so mock it first.
with patch("mysql.connector.pooling.MySQLConnectionPool"):
    import main

from errors import AppError


# ---------------------------------------------------------------------------
# Temporary routes. They exist only inside the test process.
# ---------------------------------------------------------------------------
class Payload(BaseModel):
    name: str


@main.app.post("/__test/validate")
def _validate(payload: Payload):
    return {"success": True}


@main.app.get("/__test/unauthorized")
def _unauthorized():
    raise HTTPException(status_code=401, detail="Authentication required")


@main.app.get("/__test/http/{code}")
def _http_status(code: int):
    raise HTTPException(status_code=code, detail=f"status {code}")


@main.app.get("/__test/app-error")
def _app_error():
    raise AppError(409, "TEST_CONFLICT", "Synthetic conflict", {"id": "invalid"})


@main.app.get("/__test/crash")
def _crash():
    raise RuntimeError("SECRET_DO_NOT_LEAK")


@main.app.get("/__test/duplicate-errors")
def _duplicate_errors():
    # Two errors with the same location, as a custom validator could produce.
    raise RequestValidationError([
        {"loc": ("body", "name"), "msg": "First error", "type": "value_error"},
        {"loc": ("body", "name"), "msg": "Second error", "type": "value_error"},
    ])


@pytest.fixture(scope="module")
def client():
    # raise_server_exceptions=False lets us see the real 500 response.
    return TestClient(main.app, raise_server_exceptions=False)


def assert_error_shape(response, status, code=None):
    """Every error must look like {"error": {"code", "message", "fields"}}."""
    assert response.status_code == status
    body = response.json()
    assert set(body) == {"error"}
    error = body["error"]
    assert set(error) == {"code", "message", "fields"}
    assert isinstance(error["code"], str) and error["code"]
    assert isinstance(error["message"], str) and error["message"]
    assert isinstance(error["fields"], dict)
    if code:
        assert error["code"] == code
    return error


# ---------------------------------------------------------------------------
# Health endpoint
# ---------------------------------------------------------------------------
def test_health_returns_200_ok(client):
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


# ---------------------------------------------------------------------------
# Standard error shape
# ---------------------------------------------------------------------------
def test_unknown_route_returns_404(client):
    r = client.get("/api/v1/does-not-exist")
    assert_error_shape(r, 404, "NOT_FOUND")


def test_wrong_method_returns_405(client):
    r = client.post("/api/v1/health")
    assert_error_shape(r, 405, "METHOD_NOT_ALLOWED")


def test_http_exception_returns_401(client):
    r = client.get("/__test/unauthorized")
    error = assert_error_shape(r, 401, "UNAUTHORIZED")
    assert error["message"] == "Authentication required"


@pytest.mark.parametrize("status, code", [
    (400, "BAD_REQUEST"),
    (403, "FORBIDDEN"),
    (409, "CONFLICT"),
    (418, "HTTP_ERROR"),  # status without its own code falls back to HTTP_ERROR
])
def test_http_status_maps_to_error_code(client, status, code):
    r = client.get(f"/__test/http/{status}")
    assert_error_shape(r, status, code)


def test_missing_static_file_uses_standard_error_shape(client):
    # Mounted frontend folders (css, js, admin, student) must use it too.
    r = client.get("/css/does-not-exist.css")
    assert_error_shape(r, 404, "NOT_FOUND")


def test_app_error_keeps_status_code_message_and_fields(client):
    r = client.get("/__test/app-error")
    error = assert_error_shape(r, 409, "TEST_CONFLICT")
    assert error["message"] == "Synthetic conflict"
    assert error["fields"] == {"id": "invalid"}


def test_validation_error_returns_422_with_field_name(client):
    r = client.post("/__test/validate", json={})
    error = assert_error_shape(r, 422, "VALIDATION_ERROR")
    assert "name" in error["fields"]


# ---------------------------------------------------------------------------
# Malformed JSON
# ---------------------------------------------------------------------------
def test_malformed_json_is_reported_under_request(client):
    r = client.post(
        "/__test/validate",
        content='{"name":',
        headers={"Content-Type": "application/json"},
    )
    error = assert_error_shape(r, 422, "VALIDATION_ERROR")
    # The parser position (e.g. "8") must not leak as a field name.
    assert list(error["fields"]) == ["request"]


# ---------------------------------------------------------------------------
# Several errors on the same field
# ---------------------------------------------------------------------------
def test_multiple_errors_for_same_field_are_all_kept(client):
    r = client.get("/__test/duplicate-errors")
    error = assert_error_shape(r, 422, "VALIDATION_ERROR")
    messages = error["fields"]["name"]
    assert isinstance(messages, list)
    assert messages == ["First error", "Second error"]


# ---------------------------------------------------------------------------
# Unexpected errors
# ---------------------------------------------------------------------------
def test_unexpected_error_returns_generic_500_without_leaking(client):
    r = client.get("/__test/crash")
    error = assert_error_shape(r, 500, "INTERNAL_ERROR")
    assert "SECRET_DO_NOT_LEAK" not in r.text
    assert error["fields"] == {}


def test_unexpected_error_is_logged_on_the_server(client, caplog):
    with caplog.at_level(logging.ERROR):
        client.get("/__test/crash")
    assert "SECRET_DO_NOT_LEAK" in caplog.text