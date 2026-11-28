"""Create an administrator account with a bcrypt-hashed password.

Run: python create_admin.py
The password is requested interactively and is never stored in source code.
"""
import getpass
import re

import bcrypt

from database import get_connection


def main():
    name = input("Administrator full name: ").strip()
    email = input("Administrator email: ").strip().lower()
    if len(name) < 2 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise SystemExit("Please enter a valid name and email address.")
    password = getpass.getpass("Password (minimum 8 characters): ")
    confirm = getpass.getpass("Confirm password: ")
    if len(password) < 8 or password != confirm:
        raise SystemExit("Passwords must match and contain at least 8 characters.")

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("utf-8")
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO admin_user (full_name, email, password_hash) VALUES (%s, %s, %s)",
            (name, email, password_hash),
        )
        conn.commit()
        print("Administrator account created successfully.")
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()
