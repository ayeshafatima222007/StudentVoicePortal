"""US-07 tests for bcrypt-backed admin login and JWT lifetime.

Run after installing requirements-dev.txt:
    python -m pytest tests/test_us07.py -v
"""
from datetime import datetime, timezone
from unittest.mock import patch

import bcrypt
import jwt
from fastapi.testclient import TestClient

# main imports the DB connector, so the pool constructor is mocked for API tests.
with patch("mysql.connector.pooling.MySQLConnectionPool"):
    import main
import auth

client = TestClient(main.app)


class FakeCursor:
    def __init__(self, admin):
        self.admin = admin
        self.statements = []
    def execute(self, sql, params=None):
        self.statements.append((sql, params))
    def fetchone(self):
        return self.admin
    def close(self):
        pass


class FakeConnection:
    def __init__(self, admin):
        self.cursor_obj = FakeCursor(admin)
        self.committed = False
        self.rolled_back = False
    def cursor(self, dictionary=False):
        return self.cursor_obj
    def commit(self):
        self.committed = True
    def rollback(self):
        self.rolled_back = True
    def close(self):
        pass


def test_successful_login_returns_eight_hour_jwt_and_updates_last_login(monkeypatch):
    password_hash = bcrypt.hashpw(b"StrongPassword123", bcrypt.gensalt()).decode()
    admin = {"admin_id": 7, "email": "admin@example.com", "password_hash": password_hash, "is_active": 1}
    connection = FakeConnection(admin)
    monkeypatch.setattr(auth, "get_connection", lambda: connection)
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-that-is-at-least-32-characters-long")
    monkeypatch.setattr(auth, "_check_rate_limit", lambda request: None)

    response = client.post("/api/v1/auth/login", json={
        "email": "ADMIN@example.com", "password": "StrongPassword123"
    })
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 28800
    claims = jwt.decode(body["access_token"], "test-secret-that-is-at-least-32-characters-long", algorithms=["HS256"])
    assert claims["sub"] == "7"
    assert int(claims["exp"] - claims["iat"]) == 28800
    assert connection.committed
    assert any("last_login_at" in sql for sql, _ in connection.cursor_obj.statements)


def test_wrong_password_returns_401(monkeypatch):
    password_hash = bcrypt.hashpw(b"CorrectPassword123", bcrypt.gensalt()).decode()
    connection = FakeConnection({
        "admin_id": 7, "email": "admin@example.com", "password_hash": password_hash, "is_active": 1
    })
    monkeypatch.setattr(auth, "get_connection", lambda: connection)
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-that-is-at-least-32-characters-long")
    monkeypatch.setattr(auth, "_check_rate_limit", lambda request: None)
    response = client.post("/api/v1/auth/login", json={
        "email": "admin@example.com", "password": "WrongPassword"
    })
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"
    assert not connection.committed


def test_unknown_email_returns_401(monkeypatch):
    connection = FakeConnection(None)
    monkeypatch.setattr(auth, "get_connection", lambda: connection)
    monkeypatch.setattr(auth, "_check_rate_limit", lambda request: None)
    response = client.post("/api/v1/auth/login", json={
        "email": "nobody@example.com", "password": "WrongPassword"
    })
    assert response.status_code == 401


def test_inactive_admin_returns_403(monkeypatch):
    password_hash = bcrypt.hashpw(b"CorrectPassword123", bcrypt.gensalt()).decode()
    connection = FakeConnection({
        "admin_id": 7, "email": "admin@example.com", "password_hash": password_hash, "is_active": 0
    })
    monkeypatch.setattr(auth, "get_connection", lambda: connection)
    monkeypatch.setattr(auth, "_check_rate_limit", lambda request: None)
    response = client.post("/api/v1/auth/login", json={
        "email": "admin@example.com", "password": "CorrectPassword123"
    })
    assert response.status_code == 403
