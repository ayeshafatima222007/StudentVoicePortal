"""
Automated tests for US-06: Swagger UI at /api/docs served from openapi.json.

Run from the project root:
    python -m pytest tests/test_us06.py -v

No database is needed: the MySQL pool is mocked before main.py is imported.
"""
import json
from pathlib import Path
from unittest.mock import patch

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