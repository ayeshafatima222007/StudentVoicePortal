import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
import mysql.connector.pooling

BASE_DIR = Path(__file__).parent

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

app = FastAPI()


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