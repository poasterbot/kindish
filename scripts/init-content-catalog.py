#!/usr/bin/env python3
"""Bootstrap the empty varlocal content catalog as Lab126 init.lua would."""
import re
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1])
db_path = root / "var/local/cc.db"
if db_path.exists() and db_path.stat().st_size > 0:
    raise SystemExit(0)

sqls = (root / "usr/share/cc/cc.sqls").read_text()
directive = re.compile(r"(?m)^--## (Create|Update): ([^:\n]+):(\d+)(?::(\d+))?[^\n]*\n")
matches = list(directive.finditer(sqls))
blocks = []
for index, match in enumerate(matches):
    end = matches[index + 1].start() if index + 1 < len(matches) else len(sqls)
    blocks.append((match.group(1), match.group(2), int(match.group(3)),
                   int(match.group(4)) if match.group(4) else None,
                   sqls[match.end():end].strip()))

db_path.unlink(missing_ok=True)
connection = sqlite3.connect(db_path)
connection.create_collation("icu", lambda left, right: (left > right) - (left < right))
for name in (
    "build_credit_collation", "build_credit_json", "build_metadate_unicode_word",
    "build_title_collation", "build_title_json", "get_language_from_titles",
    "json_string",
):
    connection.create_function(name, -1, lambda *args: args[0] if args else "")
for name in ("is_journaling_enabled", "should_rebuild_credit_collation",
             "should_rebuild_title_collation"):
    connection.create_function(name, -1, lambda *args: 0)

connection.executescript("""
CREATE TABLE Versions (x_table PRIMARY KEY NOT NULL UNIQUE, x_version);
CREATE TABLE DBOK (x_ok PRIMARY KEY NOT NULL UNIQUE CHECK (x_ok = 1));
""")
versions = {}
for kind, name, start, finish, statement in blocks:
    if kind == "Create" and name not in versions:
        if statement:
            connection.executescript(statement)
        versions[name] = start
        connection.execute("INSERT INTO Versions VALUES (?, ?)", (name, start))
    elif kind == "Update" and versions.get(name) == start:
        if statement:
            connection.executescript(statement)
        versions[name] = finish
        connection.execute("UPDATE Versions SET x_version=? WHERE x_table=?", (finish, name))

connection.execute("INSERT INTO DBOK VALUES (1)")
connection.commit()
connection.close()
