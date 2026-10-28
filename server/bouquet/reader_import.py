"""One-time move from Readwise Reader: the inbox and Later lists, and OPML feed exports."""

import time
import xml.etree.ElementTree as ElementTree
from collections import Counter
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

import httpx

from bouquet.extract import site_of
from bouquet.store import Store

READER_LIST_URL = "https://readwise.io/api/v3/list/"
READER_LOCATIONS = ("new", "later")
READER_HOSTS = {"read.readwise.io", "readwise.io"}
DEFAULT_RETRY_SECONDS = 60


def reader_pages(location: str, token: str, http: httpx.Client, sleep: Callable[[float], None]):
    cursor = None
    while True:
        params = {"location": location, "withHtmlContent": "true"}
        if cursor:
            params["pageCursor"] = cursor
        response = http.get(READER_LIST_URL, params=params, headers={"Authorization": f"Token {token}"}, timeout=60)
        if response.status_code == 429:
            sleep(int(response.headers.get("Retry-After", DEFAULT_RETRY_SECONDS)))
            continue
        response.raise_for_status()
        page = response.json()
        yield page["results"]
        cursor = page.get("nextPageCursor")
        if not cursor:
            return


def original_link(document: dict) -> str | None:
    for url in (document.get("source_url"), document.get("url")):
        if url and urlsplit(url).netloc not in READER_HOSTS:
            return url
    return None


def as_utc_iso(timestamp: str | None) -> str | None:
    if not timestamp:
        return None
    return datetime.fromisoformat(timestamp).isoformat(timespec="milliseconds")


def import_reader(
    store: Store, token: str, http: httpx.Client, *, sleep: Callable[[float], None] = time.sleep
) -> Counter:
    counts = Counter()
    for location in READER_LOCATIONS:
        for documents in reader_pages(location, token, http, sleep):
            for document in documents:
                url = original_link(document)
                if url is None:
                    counts["no link"] += 1
                elif store.find_by_canonical(url):
                    counts["already saved"] += 1
                else:
                    store.create_item(
                        url,
                        title=document.get("title"),
                        saved_at=as_utc_iso(document.get("saved_at")),
                        source_html=document.get("html_content") or None,
                    )
                    counts["imported"] += 1
    return counts


def import_opml(store: Store, path: str | Path) -> int:
    """Adds every feed in the file; the poller checks each on its next pass."""
    added = 0
    for outline in ElementTree.parse(path).iter("outline"):
        url = outline.get("xmlUrl")
        if not url or store.find_feed(url):
            continue
        store.add_feed(url, outline.get("title") or outline.get("text") or site_of(url), site_of(url))
        added += 1
    return added
