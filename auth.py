"""US-07 administrator authentication: bcrypt password verification and JWT."""
import os
import re
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from functools import wraps
from threading import Lock

import bcrypt
import jwt
from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, field_validator

from database import get_connection
from errors import AppError

router = APIRouter(prefix="/api/v1", tags=["Authentication"])
bearer_scheme = HTTPBearer(auto_error=False)

TOKEN_LIFETIME_SECONDS = 8 * 60 * 60
LOGIN_WINDOW_SECONDS = 15 * 60
LOGIN_MAX_ATTEMPTS = 5

# In-process limiter suitable for a single-process student deployment.
# Use a shared Redis/database limiter if running multiple workers/servers.
_attempts = defaultdict(deque)
_attempts_lock = Lock()


class AdminLoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=150)
    password: str = Field(min_length=1)

@field_validator("email")
@classmethod
def valid_email(cls, value):
    value = value.strip().lower()

    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
        raise ValueError("Enter a valid email address")

    return value

def _check_rate_limit(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    with _attempts_lock:
        history = _attempts[client_ip]
        while history and now - history[0] >= LOGIN_WINDOW_SECONDS:
            history.popleft()
        if len(history) >= LOGIN_MAX_ATTEMPTS:
            retry_after = max(1, int(LOGIN_WINDOW_SECONDS - (now - history[0])))
            raise AppError(429, "TOO_MANY_REQUESTS", "Too many login attempts. Try again later.")
        history.append(now)


def _jwt_secret():
    secret = os.getenv("JWT_SECRET_KEY")
    if not secret or len(secret) < 32:
        raise RuntimeError("JWT_SECRET_KEY must be configured with at least 32 characters")
    return secret


@router.post("/auth/login")
def login_admin(payload: AdminLoginRequest, request: Request):
    _check_rate_limit(request)
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            """SELECT admin_id, email, password_hash, is_active
               FROM admin_user WHERE email = %s LIMIT 1""",
            (payload.email,),
        )
        admin = cursor.fetchone()

        # Use a valid dummy bcrypt hash for unknown emails to reduce timing differences.
        if admin is None:
            bcrypt.checkpw(payload.password.encode("utf-8"), _DUMMY_HASH)
            raise AppError(401, "UNAUTHORIZED", "Invalid email or password")

        stored_hash = admin["password_hash"]
        if isinstance(stored_hash, str):
            stored_hash = stored_hash.encode("utf-8")
        try:
            password_ok = bcrypt.checkpw(payload.password.encode("utf-8"), stored_hash)
        except (ValueError, TypeError):
            password_ok = False

        if not password_ok:
            raise AppError(401, "UNAUTHORIZED", "Invalid email or password")
        if not admin["is_active"]:
            raise AppError(403, "FORBIDDEN", "This administrator account is inactive")

        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(seconds=TOKEN_LIFETIME_SECONDS)
        token = jwt.encode(
            {
                "sub": str(admin["admin_id"]),
                "email": admin["email"],
                "iat": now,
                "exp": expires_at,
            },
            _jwt_secret(),
            algorithm="HS256",
        )

        cursor.execute(
            "UPDATE admin_user SET last_login_at = UTC_TIMESTAMP() WHERE admin_id = %s",
            (admin["admin_id"],),
        )
        conn.commit()
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_in": TOKEN_LIFETIME_SECONDS,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        try:
            cursor.close()
        except (UnboundLocalError, AttributeError):
            pass
        conn.close()


def get_current_admin(credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme)):
    """Validate a Bearer JWT and re-check that its administrator is still active."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AppError(401, "UNAUTHORIZED", "A valid Bearer token is required")
    try:
        claims = jwt.decode(credentials.credentials, _jwt_secret(), algorithms=["HS256"])
        admin_id = int(claims["sub"])
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
        raise AppError(401, "UNAUTHORIZED", "Invalid or expired token")

    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT admin_id, email, is_active FROM admin_user WHERE admin_id = %s",
            (admin_id,),
        )
        admin = cursor.fetchone()
        if not admin:
            raise AppError(401, "UNAUTHORIZED", "Invalid or expired token")
        if not admin["is_active"]:
            raise AppError(403, "FORBIDDEN", "This administrator account is inactive")
        return admin
    finally:
        try:
            cursor.close()
        except (UnboundLocalError, AttributeError):
            pass
        conn.close()


# bcrypt hash of a fixed, non-secret dummy value; used only for unknown email timing.
_DUMMY_HASH = bcrypt.hashpw(b"not-a-real-password", bcrypt.gensalt(rounds=12))
