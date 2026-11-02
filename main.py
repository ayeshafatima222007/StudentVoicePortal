import json
import logging
import os
import re
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
import mysql.connector.pooling

from errors import register_error_handlers
from health import router as health_router

BASE_DIR = Path(__file__).parent
OPENAPI_FILE = BASE_DIR / "openapi.json"  # generated from openapi.yaml (US-05)
logger = logging.getLogger(__name__)

# 1. .env file load karo
load_dotenv()

# 2. MySQL connection pool banao
pool = mysql.connector.pooling.MySQLConnectionPool(
    pool_name="svp_pool",
    pool_size=5,
    host=os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT", 3306)),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    database=os.getenv("DB_NAME"),
)

# US-06: Swagger UI at /api/docs, using our own API contract file
app = FastAPI(
    title="Student Voice Portal API",
    docs_url="/api/docs",              # Swagger UI page
    redoc_url=None,                    # we only need Swagger UI
    openapi_url="/api/openapi.json",   # the spec that Swagger UI reads
    swagger_ui_oauth2_redirect_url=None,  # we do not use OAuth2 login, so no extra /docs/... route
)


def validate_openapi_contract(spec):
    """Raise ValueError unless spec looks like a usable OpenAPI 3 document.
    Basic structure only; validate_openapi.py does the full validation."""
    if not isinstance(spec, dict):
        raise ValueError("document root must be an object")
    version = spec.get("openapi")
    if not isinstance(version, str) or not re.fullmatch(r"3\.\d+\.\d+", version):
        raise ValueError("'openapi' must be a valid 3.x.y version string")
    info = spec.get("info")
    if not isinstance(info, dict):
        raise ValueError("'info' must be an object")
    for field in ("title", "version"):
        value = info.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"'info.{field}' must be a non-empty string")
    paths = spec.get("paths")
    if not isinstance(paths, dict) or not paths:
        raise ValueError("'paths' must be a non-empty object")
    for path, item in paths.items():
        if not path.startswith("/") or not isinstance(item, dict):
            raise ValueError(f"invalid path entry: {path!r}")
    if not isinstance(spec.get("components", {}), dict):
        raise ValueError("'components' must be an object")


def read_openapi_contract():
    """Read and check openapi.json. Return None (and log why) if it is unusable."""
    try:
        spec = json.loads(OPENAPI_FILE.read_text(encoding="utf-8"))
        validate_openapi_contract(spec)
    except (OSError, ValueError) as exc:  # missing, unreadable, bad encoding, bad JSON or bad structure
        logger.warning("Could not load %s (%s); using generated schema", OPENAPI_FILE.name, exc)
        return None
    return spec


def load_openapi_contract():
    """Return openapi.json (the US-05 contract) instead of the schema
    FastAPI would build from the code, so /api/docs always shows the agreed design."""
    if app.openapi_schema is None:
        # The server must still start, so fall back to FastAPI's own schema.
        app.openapi_schema = read_openapi_contract() or get_openapi(
            title=app.title, version="1.0.0", openapi_version=app.openapi_version, routes=app.routes
        )
    return app.openapi_schema


app.openapi = load_openapi_contract

register_error_handlers(app)
app.include_router(health_router)

# 3. Database test ka raasta
@app.get("/api/db-test")
def db_test():
    conn = pool.get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        cursor.close()
        return {"db": "ok", "result": result[0]}
    finally:
        conn.close()


# 4. Home page aur documentation page
@app.get("/", include_in_schema=False)
@app.get("/index.html", include_in_schema=False)
def home():
    return FileResponse(BASE_DIR / "index.html")


@app.get("/documentation.html", include_in_schema=False)
def documentation():
    return FileResponse(BASE_DIR / "documentation.html")


# 5. Sirf website ke folders serve karo (sab se aakhir mein)
for folder in ["css", "js", "assets", "admin", "student"]:
    app.mount(
        f"/{folder}",
        StaticFiles(directory=BASE_DIR / folder, html=True),
        name=folder,
    )