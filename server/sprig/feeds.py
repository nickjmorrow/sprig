"""RSS and Atom subscriptions: new posts land in the Feed tab."""

import calendar
import logging
import threading
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import feedparser
import httpx

from sprig.extract import site_of
from sprig.pipeline import FETCH_HEADERS, html_text
from sprig.store import Store
from sprig.timing import word_count

log = logging.getLogger(__name__)

POLL_INTERVAL = 30 * 60
ENTRIES_PER_CHECK = 20
MAX_ENTRY_AGE = timedelta(days=14)
FULL_CONTENT_WORDS = 150  # feeds that carry the whole post save a page fetch
FEED_ITEM_LIFETIME = timedelta(days=30)
PURGE_AFTER = timedelta(days=7)


@dataclass
class FeedEntry:
    url: str
    title: str
    published_at: str | None
    content_html: str | None


class NotAFeed(Exception):
    pass


def entry_time(entry) -> datetime | None:
    parsed = entry.get("published_parsed") or entry.get("updated_parsed")
    return datetime.fromtimestamp(calendar.timegm(parsed), UTC) if parsed else None


def parse_feed(content: bytes, url: str) -> tuple[str, str, list[FeedEntry]]:
    parsed = feedparser.parse(content)
    if not parsed.get("version") and not parsed.entries:
        raise NotAFeed(f"{url} isn't an RSS or Atom feed")
    entries = []
    for entry in parsed.entries:
        if not entry.get("link"):
            continue
        content_html = None
        if entry.get("content"):
            candidate = entry.content[0].value
            if word_count(html_text(candidate)) > FULL_CONTENT_WORDS:
                content_html = candidate
        published = entry_time(entry)
        entries.append(
            FeedEntry(
                url=entry.link,
                title=entry.get("title") or entry.link,
                published_at=published.isoformat() if published else None,
                content_html=content_html,
            )
        )
    entries.sort(key=lambda e: e.published_at or "", reverse=True)
    feed_info = parsed.feed
    return feed_info.get("title") or site_of(url), site_of(feed_info.get("link") or url), entries


def fetch_feed(url: str, http: httpx.Client, *, etag: str | None = None, last_modified: str | None = None) -> httpx.Response:
    headers = dict(FETCH_HEADERS)
    if etag:
        headers["If-None-Match"] = etag
    if last_modified:
        headers["If-Modified-Since"] = last_modified
    response = http.get(url, headers=headers, timeout=20, follow_redirects=True)
    if response.status_code != 304:
        response.raise_for_status()
    return response


def poll_feed(store: Store, feed: dict, http: httpx.Client, *, now: datetime) -> int:
    checked = now.isoformat(timespec="milliseconds")
    try:
        response = fetch_feed(feed["url"], http, etag=feed["etag"], last_modified=feed["last_modified"])
        if response.status_code == 304:
            store.update_feed(feed["id"], last_checked=checked, last_error=None)
            return 0
        _, _, entries = parse_feed(response.content, feed["url"])
    except Exception as error:
        store.update_feed(feed["id"], last_checked=checked, last_error=str(error)[:500])
        return 0
    oldest = (now - MAX_ENTRY_AGE).isoformat()
    created = 0
    for entry in entries[:ENTRIES_PER_CHECK]:
        if entry.published_at and entry.published_at < oldest:
            continue
        if store.find_by_canonical(entry.url):
            continue
        store.create_item(
            entry.url,
            location="feed",
            feed_id=feed["id"],
            title=entry.title,
            saved_at=checked,
            source_html=entry.content_html,
        )
        created += 1
    store.update_feed(
        feed["id"],
        etag=response.headers.get("etag"),
        last_modified=response.headers.get("last-modified"),
        last_checked=checked,
        last_error=None,
    )
    return created


def poll_all(store: Store, http: httpx.Client, *, now: datetime) -> int:
    return sum(poll_feed(store, feed, http, now=now) for feed in store.list_feeds())


def prune(store: Store, *, now: datetime) -> int:
    stale = store.stale_feed_items((now - FEED_ITEM_LIFETIME).isoformat())
    for item in stale:
        store.delete_item(item["id"])
    store.purge_deleted((now - PURGE_AFTER).isoformat())
    return len(stale)


class FeedPoller:
    """Checks every feed every 30 minutes, or right away when woken (a feed was added)."""

    def __init__(self, store: Store, http: httpx.Client, on_new_item: Callable[[], None]):
        self.store = store
        self.http = http
        self.on_new_item = on_new_item
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="sprig-feeds", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def wake(self) -> None:
        self._wake.set()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()
        self._thread.join(timeout=30)

    def _run(self) -> None:
        while not self._stop.is_set():
            self._wake.clear()
            try:
                now = datetime.now(UTC)
                if poll_all(self.store, self.http, now=now):
                    self.on_new_item()
                prune(self.store, now=now)
            except Exception:
                log.exception("feed pass failed")
            self._wake.wait(POLL_INTERVAL)
