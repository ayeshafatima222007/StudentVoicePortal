"""
Automated tests for US-06: Swagger UI at /api/docs served from openapi.json.

Install the development dependencies once:
    python -m pip install -r requirements-dev.txt

Run from the project root:
    python -m pytest tests/test_us06.py -v

No database is needed: the MySQL pool is mocked before main.py is imported.
"""
import json
import logging
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

with patch("mysql.connector.pooling.MySQLConnectionPool"):
    import main

client = TestClient(main.app)
HTTP_METHODS = {"get", "post", "put", "patch", "delete"}


def test_swagger_ui_page_is_served():
    response = client.get("/api/docs")
    assert response.status_code == 200
    assert "swagger-ui" in response.text.lower()
    assert "/api/openapi.json" in response.text  # the page loads our spec


def test_openapi_json_is_the_us05_contract():
    spec = client.get("/api/openapi.json").json()
    file_spec = json.loads((Path(main.__file__).parent / "openapi.json").read_text(encoding="utf-8"))
    assert spec == file_spec
    assert spec["openapi"] == "3.0.3"


def test_contract_has_17_operations():
    spec = client.get("/api/openapi.json").json()
    operations = [m for path in spec["paths"].values() for m in path if m in HTTP_METHODS]
    assert len(operations) == 17


def test_authorize_schemes_are_available():
    schemes = client.get("/api/openapi.json").json()["components"]["securitySchemes"]
    assert schemes["bearerAuth"]["scheme"] == "bearer"
    assert schemes["trackingReference"]["name"] == "X-Tracking-Reference"


def test_old_default_docs_urls_are_gone():
    for url in ("/docs", "/redoc", "/openapi.json"):
        response = client.get(url)
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "NOT_FOUND"


def test_oauth2_redirect_route_is_not_left_at_old_path():
    assert client.get("/docs/oauth2-redirect").status_code == 404


# ---------------------------------------------------------------------------
# Fallback: the server must keep working if openapi.json is missing or broken.
# ---------------------------------------------------------------------------
@pytest.fixture
def contract_file(tmp_path, monkeypatch):
    """Point main.py at a temporary openapi.json, then restore the real one."""
    path = tmp_path / "openapi.json"
    monkeypatch.setattr(main, "OPENAPI_FILE", path)
    main.app.openapi_schema = None
    yield path
    main.app.openapi_schema = None  # the next request reloads the real file


def assert_fallback_schema():
    response = client.get("/api/openapi.json")
    assert response.status_code == 200
    spec = response.json()
    assert spec["openapi"] == main.app.openapi_version
    assert "/api/v1/health" in spec["paths"]  # FastAPI's own schema, not the contract


def test_missing_contract_file_falls_back_and_logs(contract_file, caplog):
    with caplog.at_level(logging.WARNING):
        assert_fallback_schema()
    assert "Could not load" in caplog.text


def test_malformed_contract_file_falls_back(contract_file):
    contract_file.write_text("{", encoding="utf-8")
    assert_fallback_schema()


@pytest.mark.parametrize("content", [
    "{}",
    "[]",
    '{"openapi": "3.0.3"}',
    '{"openapi": "2.0", "info": {"title": "Bad", "version": "1"}, "paths": {"/x": {}}}',
    '{"openapi": "3.", "info": {"title": "Bad", "version": "1"}, "paths": {"/x": {}}}',
    '{"openapi": "3.not-a-version", "info": {"title": "Bad", "version": "1"}, "paths": {"/x": {}}}',
    '{"openapi": "3.0.3", "info": [], "paths": {"/x": {}}}',
    '{"openapi": "3.0.3", "info": {"title": "", "version": "1"}, "paths": {"/x": {}}}',
    '{"openapi": "3.0.3", "info": {"title": "Bad", "version": "1"}, "paths": "invalid"}',
    '{"openapi": "3.0.3", "info": {"title": "Bad", "version": "1"}, "paths": {"no-slash": {}}}',
    '{"openapi": "3.0.3", "info": {"title": "Bad", "version": "1"}, "paths": {"/x": []}}',
])
def test_invalid_contract_falls_back(contract_file, content):
    contract_file.write_text(content, encoding="utf-8")
    assert_fallback_schema()


def test_invalid_utf8_contract_falls_back(contract_file):
    contract_file.write_bytes(b"\xff")
    assert_fallback_schema()


def test_real_contract_is_served_again_after_fallback_tests():
    # Guards against a fallback schema leaking out of the tests above.
    assert len(client.get("/api/openapi.json").json()["paths"]) == 17
