import json
import logging
import os
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
)


def load_openapi_contract():
    """Return openapi.json (the US-05 contract) instead of the schema
    FastAPI would build from the code, so /api/docs always shows the agreed design."""
    if app.openapi_schema is None:
        try:
            app.openapi_schema = json.loads(OPENAPI_FILE.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError) as exc:
            # The server must still start; fall back to FastAPI's own schema.
            logger.warning("Could not load %s (%s); using generated schema", OPENAPI_FILE.name, exc)
            app.openapi_schema = get_openapi(title=app.title, version="1.0.0", routes=app.routes)
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