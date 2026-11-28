# Student Voice Portal
Frontend prototype for complaints, feedback and suggestions.
Built with HTML, CSS, Bootstrap 5 and JavaScript.


## US-07: Administrator login (bcrypt + JWT)

1. Install dependencies: `python -m pip install -r requirements.txt`.
2. Copy `.env.example` to `.env` and configure the MySQL connection.
3. Set `JWT_SECRET_KEY` to a private random value of at least 32 characters. Do not commit `.env`.
4. Run `schema.sql` in MySQL/XAMPP to create the `admin_user` table.
5. Create the first admin account with `python create_admin.py`. The script prompts for a password and stores only its bcrypt hash.
6. Start the API with `uvicorn main:app --reload`.
7. Open `http://127.0.0.1:8000/api/docs` and test `POST /api/v1/auth/login` using the admin email and password.

Successful login returns a Bearer JWT with an 8-hour lifetime. Invalid credentials return 401; inactive accounts return 403. Login attempts are limited to five per 15-minute window per client IP in this single-process implementation. Use a shared limiter (such as Redis) before deploying multiple workers or servers.

The admin login page now calls the real API. The token is stored in browser storage for the current prototype's admin-page guard. Any future `/admin/*` API endpoint must independently use the `get_current_admin` dependency; hiding a page in JavaScript is not API security.
