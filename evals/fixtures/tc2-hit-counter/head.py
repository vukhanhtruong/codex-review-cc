"""Persistent hit counter."""
import os


def increment_counter(path):
    """Increment the integer stored in `path` and return the new value."""
    try:
        with open(path) as f:
            n = int(f.read().strip())
    except FileNotFoundError:
        n = 0
    n += 1
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(str(n))
    os.replace(tmp, path)
    return n
