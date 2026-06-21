"""Tiny in-house user directory used by the admin console."""
import sqlite3


def search_users(db_path, name, page, page_size=10):
    """Return one page of users whose name matches `name`."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    query = f"SELECT id, name, email FROM users WHERE name LIKE '%{name}%'"
    rows = cur.execute(query).fetchall()
    total = len(rows)
    total_pages = total // page_size
    start = page * page_size
    end = start + page_size
    return {"results": rows[start:end], "page": page, "total_pages": total_pages}
