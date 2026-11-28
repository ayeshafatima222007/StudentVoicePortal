import os
from threading import Lock

import mysql.connector.pooling
from dotenv import load_dotenv
load_dotenv()
_pool = None
_pool_lock = Lock()


def get_pool():
    """Create the pool only when a database-backed endpoint is called."""
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                required = ("DB_HOST", "DB_USER", "DB_NAME")
                missing = [key for key in required if not os.getenv(key)]
                if missing:
                    raise RuntimeError("Missing database configuration: " + ", ".join(missing))
                _pool = mysql.connector.pooling.MySQLConnectionPool(
                    pool_name="svp_pool",
                    pool_size=5,
                    host=os.getenv("DB_HOST"),
                    port=int(os.getenv("DB_PORT", "3306")),
                    user=os.getenv("DB_USER"),
                    password=os.getenv("DB_PASSWORD", ""),
                    database=os.getenv("DB_NAME"),
                    autocommit=False,
                )
    return _pool


def get_connection():
    return get_pool().get_connection()
