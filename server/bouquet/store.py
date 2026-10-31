"""SQLite storage for items, topics, corrections and feeds.

Every change to an item bumps a global sequence number so devices can ask
for "everything changed since N".
"""

import json
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path

from bouquet.urls import canonical_url, tweet_id

STARTER_TOPICS = [
    "AI",
    "Engineering",
    "Career",
    "Cooking & baking",
    "Body & health",
    "Art & craft",
    "Games & streaming",
    "Science",
    "Philosophy",
    "Culture",
    "Money",
    "News",
]

INTERNAL_FIELDS = ("source_html", "shared_text", "field_times", "tag_attempts", "last_error")
JSON_FIELDS = ("topics", "field_times")
BOOL_FIELDS = ("favorite", "deleted")

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    canonical_url TEXT NOT NULL UNIQUE,
    kind TEXT NOT NULL,
    location TEXT NOT NULL,
    status TEXT NOT NULL,
    title TEXT,
    author TEXT,
    site TEXT,
    published_at TEXT,
    saved_at TEXT NOT NULL,
    excerpt TEXT NOT NULL DEFAULT '',
    content_html TEXT NOT NULL DEFAULT '',
    word_count INTEGER NOT NULL DEFAULT 0,
    minutes INTEGER NOT NULL DEFAULT 0,
    topics TEXT NOT NULL DEFAULT '[]',
    topics_source TEXT NOT NULL DEFAULT 'claude',
    favorite INTEGER NOT NULL DEFAULT 0,
    progress REAL NOT NULL DEFAULT 0,
    feed_id TEXT,
    deleted INTEGER NOT NULL DEFAULT 0,
    deleted_at TEXT,
    seq INTEGER NOT NULL,
    source_html TEXT,
    shared_text TEXT,
    field_times TEXT NOT NULL DEFAULT '{}',
    tag_attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
);
CREATE INDEX IF NOT EXISTS items_seq ON items(seq);
CREATE INDEX IF NOT EXISTS items_status ON items(status, saved_at);
CREATE TABLE IF NOT EXISTS topics (name TEXT PRIMARY KEY, position INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS corrections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL,
    title TEXT,
    site TEXT,
    before TEXT NOT NULL,
    after TEXT NOT NULL,
    at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS feeds (
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL UNIQUE,
    title TEXT,
    site TEXT,
    etag TEXT,
    last_modified TEXT,
    last_checked TEXT,
    last_error TEXT
);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
"""


class Store:
    def __init__(self, path: str | Path):
        self._lock = threading.RLock()
        self._db = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.executescript(SCHEMA)
        self._db.execute("INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', 0)")
        if self._db.execute("SELECT COUNT(*) FROM topics").fetchone()[0] == 0:
            self._db.executemany(
                "INSERT INTO topics (name, position) VALUES (?, ?)",
                [(name, i) for i, name in enumerate(STARTER_TOPICS)],
            )

    @staticmethod
    def now() -> str:
        return datetime.now(UTC).isoformat(timespec="milliseconds")

    @staticmethod
    def public(item: dict) -> dict:
        return {key: value for key, value in item.items() if key not in INTERNAL_FIELDS and key != "deleted_at"}

    @contextmanager
    def _transaction(self):
        """All-or-nothing for multi-statement changes; nested uses join the outer transaction."""
        with self._lock:
            if self._db.in_transaction:
                yield
                return
            self._db.execute("BEGIN IMMEDIATE")
            try:
                yield
            except BaseException:
                self._db.execute("ROLLBACK")
                raise
            self._db.execute("COMMIT")

    def _next_seq(self) -> int:
        self._db.execute("UPDATE meta SET value = value + 1 WHERE key = 'seq'")
        return self._db.execute("SELECT value FROM meta WHERE key = 'seq'").fetchone()[0]

    @staticmethod
    def _row_to_item(row: sqlite3.Row | None) -> dict | None:
        if row is None:
            return None
        item = dict(row)
        for field in JSON_FIELDS:
            item[field] = json.loads(item[field])
        for field in BOOL_FIELDS:
            item[field] = bool(item[field])
        return item

    def create_item(
        self,
        url: str,
        *,
        location: str = "inbox",
        kind: str | None = None,
        saved_at: str | None = None,
        feed_id: str | None = None,
        title: str | None = None,
        shared_text: str | None = None,
        source_html: str | None = None,
    ) -> dict:
        item_id = str(uuid.uuid4())
        with self._transaction():
            self._db.execute(
                """INSERT INTO items (id, url, canonical_url, kind, location, status, title, saved_at,
                                      feed_id, shared_text, source_html, seq)
                   VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?)""",
                (
                    item_id,
                    url,
                    canonical_url(url),
                    kind or ("tweet" if tweet_id(url) else "article"),
                    location,
                    title,
                    saved_at or self.now(),
                    feed_id,
                    shared_text,
                    source_html,
                    self._next_seq(),
                ),
            )
            return self.get_item(item_id)

    def get_item(self, item_id: str) -> dict | None:
        with self._lock:
            return self._row_to_item(self._db.execute("SELECT * FROM items WHERE id = ?", (item_id,)).fetchone())

    def find_by_canonical(self, url: str) -> dict | None:
        with self._lock:
            row = self._db.execute(
                "SELECT * FROM items WHERE canonical_url = ? AND deleted = 0", (canonical_url(url),)
            ).fetchone()
            return self._row_to_item(row)

    def update_item(self, item_id: str, **fields) -> dict:
        for field in JSON_FIELDS:
            if field in fields:
                fields[field] = json.dumps(fields[field])
        for field in BOOL_FIELDS:
            if field in fields:
                fields[field] = int(fields[field])
        with self._transaction():
            fields["seq"] = self._next_seq()
            assignments = ", ".join(f"{name} = ?" for name in fields)
            self._db.execute(f"UPDATE items SET {assignments} WHERE id = ?", (*fields.values(), item_id))
            return self.get_item(item_id)

    def next_pending(self) -> dict | None:
        with self._lock:
            row = self._db.execute(
                "SELECT * FROM items WHERE status = 'pending' AND deleted = 0 ORDER BY saved_at LIMIT 1"
            ).fetchone()
            return self._row_to_item(row)

    def untagged(self, max_attempts: int) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                """SELECT * FROM items
                   WHERE status IN ('ready', 'web_only') AND topics = '[]' AND tag_attempts < ? AND deleted = 0
                   ORDER BY saved_at""",
                (max_attempts,),
            ).fetchall()
            return [self._row_to_item(row) for row in rows]

    def changes_since(self, seq: int) -> tuple[int, list[dict]]:
        with self._lock:
            current = self._db.execute("SELECT value FROM meta WHERE key = 'seq'").fetchone()[0]
            rows = self._db.execute("SELECT * FROM items WHERE seq > ? ORDER BY seq", (seq,)).fetchall()
            items = [self.public(self._row_to_item(row)) for row in rows]
            if seq == 0:
                items = [item for item in items if not item["deleted"]]
            return current, items

    def apply_patch(self, item_id: str, changes: dict, at: str) -> dict:
        """Apply each changed field whose time is newer than that field's last accepted change."""
        with self._transaction():
            item = self.get_item(item_id)
            field_times = dict(item["field_times"])
            accepted = {}
            for field, value in changes.items():
                if field in field_times and field_times[field] >= at:
                    continue
                accepted[field] = value
                field_times[field] = at
            if not accepted:
                return item
            if "topics" in accepted:
                accepted["topics_source"] = "you"
                self._db.execute(
                    "INSERT INTO corrections (item_id, title, site, before, after, at) VALUES (?, ?, ?, ?, ?, ?)",
                    (item_id, item["title"], item["site"], json.dumps(item["topics"]), json.dumps(accepted["topics"]), at),
                )
            return self.update_item(item_id, field_times=field_times, **accepted)

    def set_topics(self, names: list[str]) -> None:
        """Replace the topic list. Claude's tags that used a removed topic, and inbox items when a topic
        was added, are queued for re-tagging; tags he set himself just lose the removed names."""
        with self._transaction():
            added = set(names) - set(self.topics())
            self._db.execute("DELETE FROM topics")
            self._db.executemany("INSERT INTO topics (name, position) VALUES (?, ?)", [(n, i) for i, n in enumerate(names)])
            kept = set(names) | {"Other"}
            rows = self._db.execute("SELECT * FROM items WHERE deleted = 0 AND topics != '[]'").fetchall()
            for item in map(self._row_to_item, rows):
                stale = any(topic not in kept for topic in item["topics"])
                if item["topics_source"] == "you":
                    if stale:
                        self.update_item(item["id"], topics=[t for t in item["topics"] if t in kept] or ["Other"])
                elif stale or (added and item["location"] == "inbox"):
                    self.update_item(item["id"], topics=[], tag_attempts=0)

    def delete_item(self, item_id: str) -> None:
        """Soft delete, so devices hear about it; the link is freed so it can be saved again."""
        with self._transaction():
            item = self.get_item(item_id)
            self.update_item(
                item_id,
                deleted=True,
                deleted_at=self.now(),
                canonical_url=f"{item['canonical_url']}#deleted:{item_id}",
                content_html="",
                source_html=None,
            )

    def purge_deleted(self, before: str) -> int:
        """Forgets old deletions. Devices that last synced before them get a full snapshot instead."""
        with self._transaction():
            newest = self._db.execute(
                "SELECT MAX(seq) FROM items WHERE deleted = 1 AND deleted_at < ?", (before,)
            ).fetchone()[0]
            if newest is None:
                return 0
            self._db.execute(
                "INSERT INTO meta (key, value) VALUES ('purged_seq', ?) "
                "ON CONFLICT(key) DO UPDATE SET value = MAX(value, excluded.value)",
                (newest,),
            )
            return self._db.execute("DELETE FROM items WHERE deleted = 1 AND deleted_at < ?", (before,)).rowcount

    def needs_reset(self, seq: int) -> bool:
        """A device that missed purged deletions, or is ahead of a restored database, must start over."""
        if seq == 0:
            return False
        with self._lock:
            current = self._db.execute("SELECT value FROM meta WHERE key = 'seq'").fetchone()[0]
            purged = self._db.execute("SELECT value FROM meta WHERE key = 'purged_seq'").fetchone()
            return seq > current or (purged is not None and seq < purged[0])

    def swap_url(self, item_id: str, url: str) -> dict:
        """Point an item at a different page (a tweet becoming the article it shared). If that page
        is already saved, keep the saved one, back in the inbox, and drop this item."""
        with self._transaction():
            existing = self.find_by_canonical(url)
            if existing and existing["id"] != item_id:
                if existing["location"] != "inbox":
                    self.apply_patch(existing["id"], {"location": "inbox"}, self.now())
                self.delete_item(item_id)
                return self.get_item(item_id)
            return self.update_item(item_id, url=url, canonical_url=canonical_url(url), kind="article")

    def save_link(self, url: str, *, title: str | None = None, text: str | None = None) -> tuple[dict, bool]:
        """The item for this link, created if new; an archived or feed copy moves back to the inbox."""
        with self._transaction():
            if existing := self.find_by_canonical(url):
                if existing["location"] != "inbox":
                    existing = self.apply_patch(existing["id"], {"location": "inbox"}, self.now())
                return existing, False
            return self.create_item(url, title=title, shared_text=text), True

    def stale_feed_items(self, saved_before: str) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT * FROM items WHERE location = 'feed' AND favorite = 0 AND deleted = 0 AND saved_at < ?",
                (saved_before,),
            ).fetchall()
            return [self._row_to_item(row) for row in rows]

    def add_feed(self, url: str, title: str, site: str) -> dict:
        feed_id = str(uuid.uuid4())
        with self._lock:
            self._db.execute("INSERT INTO feeds (id, url, title, site) VALUES (?, ?, ?, ?)", (feed_id, url, title, site))
            return self.get_feed(feed_id)

    def get_feed(self, feed_id: str) -> dict | None:
        with self._lock:
            row = self._db.execute("SELECT * FROM feeds WHERE id = ?", (feed_id,)).fetchone()
            return dict(row) if row else None

    def find_feed(self, url: str) -> dict | None:
        with self._lock:
            row = self._db.execute("SELECT * FROM feeds WHERE url = ?", (url,)).fetchone()
            return dict(row) if row else None

    def update_feed(self, feed_id: str, **fields) -> dict:
        with self._lock:
            assignments = ", ".join(f"{name} = ?" for name in fields)
            self._db.execute(f"UPDATE feeds SET {assignments} WHERE id = ?", (*fields.values(), feed_id))
            return self.get_feed(feed_id)

    def delete_feed(self, feed_id: str) -> None:
        """Drops the feed and its posts he never kept or starred."""
        with self._transaction():
            rows = self._db.execute(
                "SELECT id FROM items WHERE feed_id = ? AND location = 'feed' AND favorite = 0 AND deleted = 0",
                (feed_id,),
            ).fetchall()
            for row in rows:
                self.delete_item(row["id"])
            self._db.execute("DELETE FROM feeds WHERE id = ?", (feed_id,))

    def list_feeds(self) -> list[dict]:
        with self._lock:
            return [dict(row) for row in self._db.execute("SELECT * FROM feeds ORDER BY title")]

    def corrections(self, limit: int = 20) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT title, site, before, after FROM corrections ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
            return [
                {"title": row["title"], "site": row["site"], "before": json.loads(row["before"]), "after": json.loads(row["after"])}
                for row in rows
            ]

    def topics(self) -> list[str]:
        with self._lock:
            return [row["name"] for row in self._db.execute("SELECT name FROM topics ORDER BY position")]
