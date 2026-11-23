"""Turns a saved link into a readable, timed, tagged item, in a background worker."""

import html
import logging
import threading
import time
from urllib.parse import urlsplit

import httpx
import lxml.html

from sprig.extract import Extracted, extract_article, site_of
from sprig.store import Store
from sprig.tagger import Tagger
from sprig.timing import minutes_for, word_count
from sprig.tweets import article_to_extracted, fetch_thread, shared_link, thread_to_extracted
from sprig.urls import tweet_id
from sprig.x_articles import article_owner, fetch_article

log = logging.getLogger(__name__)

MIN_WORDS = 50  # below this the page is a paywall or a stub: send him to the web
EXCERPT_CHARS = 200
MAX_TAG_ATTEMPTS = 5
RETAG_INTERVAL = 3600
IDLE_WAIT = 60
FETCH_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    ),
    "Accept-Language": "en",
}


class FetchError(Exception):
    pass


class SharesLink(Exception):
    """The tweet only points at a page; save that page instead."""

    def __init__(self, url: str):
        self.url = url


def html_text(content_html: str) -> str:
    if not content_html.strip():
        return ""
    return lxml.html.fromstring(f"<div>{content_html}</div>").text_content()


def text_as_html(text: str) -> str:
    return "".join(f"<p>{html.escape(p.strip())}</p>" for p in text.split("\n\n") if p.strip())


def link_only(url: str, title: str | None = None, site: str | None = None) -> Extracted:
    last_segment = urlsplit(url).path.rstrip("/").rsplit("/", 1)[-1]
    return Extracted(
        title=title or last_segment or url,
        author=None,
        site=site or site_of(url),
        published_at=None,
        html="",
        text="",
    )


def fetch_page(url: str, http: httpx.Client) -> Extracted:
    if urlsplit(url).scheme not in ("http", "https"):
        raise FetchError(f"not a web link: {url}")
    try:
        response = http.get(url, headers=FETCH_HEADERS, timeout=20, follow_redirects=True)
        response.raise_for_status()
    except Exception as error:
        raise FetchError(str(error) or type(error).__name__) from error
    if "html" not in response.headers.get("content-type", "text/html"):
        return link_only(url)
    return extract_article(response.text, str(response.url))


def load(item: dict, http: httpx.Client) -> Extracted:
    url = item["url"]
    if status_id := tweet_id(url):
        try:
            thread = fetch_thread(status_id, http)
        except Exception as error:
            log.warning("tweet %s unavailable: %s", status_id, error)
            handle = urlsplit(item["canonical_url"]).path.split("/")[1]
            return link_only(url, title=item["title"] or f"Post by @{handle}", site=f"@{handle}")
        if len(thread) == 1 and (link := shared_link(thread[0])):
            raise SharesLink(link)
        if owner := article_owner(thread[-1]):
            return article_to_extracted(thread, owner, fetch_article(owner["id_str"], http))
        return thread_to_extracted(thread)
    if item["source_html"]:
        return extract_article(item["source_html"], url)
    try:
        return fetch_page(url, http)
    except FetchError:
        if not item["shared_text"]:
            raise
        return Extracted(item["title"] or url, None, site_of(url), None, text_as_html(item["shared_text"]), item["shared_text"])


def process_item(store: Store, item_id: str, *, http: httpx.Client, tagger: Tagger | None) -> dict:
    item = store.get_item(item_id)
    try:
        try:
            extracted = load(item, http)
        except SharesLink as shared:
            item = store.swap_url(item_id, shared.url)
            if item["deleted"]:
                return item
            extracted = load(item, http)
    except Exception as error:
        # Anything, not just a failed fetch: an item left pending would block the queue behind it.
        log.warning("processing %s failed: %r", item_id, error)
        return store.update_item(item_id, status="failed", last_error=str(error)[:500] or repr(error), site=site_of(item["url"]))
    words = word_count(extracted.text)
    has_real_title = extracted.title != item["url"]
    # Tweets are short by nature; only an empty one (endpoint down) sends him to the web.
    min_words = 1 if item["kind"] == "tweet" else MIN_WORDS
    store.update_item(
        item_id,
        status="ready" if words >= min_words else "web_only",
        title=extracted.title if has_real_title or not item["title"] else item["title"],
        author=extracted.author,
        site=extracted.site,
        published_at=extracted.published_at,
        excerpt=" ".join(extracted.text.split())[:EXCERPT_CHARS],
        content_html=extracted.html,
        word_count=words,
        minutes=minutes_for(words),
        last_error=None,
    )
    if tagger is None or item["topics_source"] == "you":  # his own topics survive a re-fetch
        return store.get_item(item_id)
    return tag_item(store, item_id, tagger)


def tag_item(store: Store, item_id: str, tagger: Tagger) -> dict:
    item = store.get_item(item_id)
    attempts = item["tag_attempts"] + 1
    try:
        topics = tagger.tag(
            title=item["title"] or item["url"],
            site=item["site"] or "",
            text=html_text(item["content_html"]),
            topics=store.topics(),
            corrections=store.corrections(),
        )
    except Exception as error:
        log.warning("tagging %s failed: %s", item_id, error)
        return store.update_item(item_id, tag_attempts=attempts, last_error=f"tagging: {error}"[:500])
    return store.update_item(item_id, topics=topics, topics_source="claude", tag_attempts=attempts)


def retag_untagged(store: Store, tagger: Tagger) -> int:
    items = store.untagged(MAX_TAG_ATTEMPTS)
    for item in items:
        tag_item(store, item["id"], tagger)
    return len(items)


class Worker:
    """Works through pending items one at a time; wake() when a new one arrives."""

    def __init__(self, store: Store, http: httpx.Client, tagger: Tagger | None):
        self.store = store
        self.http = http
        self.tagger = tagger
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._retag_requested = False
        self._last_retag = 0.0
        self._thread = threading.Thread(target=self._run, name="sprig-worker", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def wake(self) -> None:
        self._wake.set()

    def request_retag(self) -> None:
        """Topics changed: re-tag queued items now rather than at the next hourly pass."""
        self._retag_requested = True
        self._wake.set()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()
        self._thread.join(timeout=30)

    def _run(self) -> None:
        while not self._stop.is_set():
            self._wake.clear()
            try:
                while (item := self.store.next_pending()) and not self._stop.is_set():
                    process_item(self.store, item["id"], http=self.http, tagger=self.tagger)
                hourly_due = time.monotonic() - self._last_retag > RETAG_INTERVAL
                if self.tagger and (self._retag_requested or hourly_due):
                    self._retag_requested = False
                    self._last_retag = time.monotonic()
                    retag_untagged(self.store, self.tagger)
            except Exception:
                log.exception("worker pass failed")
            self._wake.wait(IDLE_WAIT)
