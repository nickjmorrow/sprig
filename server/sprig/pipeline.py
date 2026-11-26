"""Turns a saved link into a readable, timed, tagged item, in a background worker."""

import html
import io
import logging
import threading
import time
from urllib.parse import urlsplit

import httpx
import lxml.html
import pypdf

from sprig.extract import Extracted, extract_article, site_of
from sprig.store import Store
from sprig.tagger import Tagger
from sprig.timing import minutes_for, word_count
from sprig.tweets import article_to_extracted, embedded_tweet_cards, fetch_thread, outside_link, shared_link, thread_to_extracted
from sprig.urls import tweet_id
from sprig.x_articles import article_owner, fetch_article

log = logging.getLogger(__name__)

MIN_WORDS = 50  # below this the page is a paywall or a stub: send him to the web
EXCERPT_CHARS = 200
INLINE_TAGS = {"a", "b", "strong", "i", "em", "code", "sub", "sup", "del", "span"}
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
    content_type = response.headers.get("content-type", "text/html")
    if "pdf" in content_type:
        return extract_pdf(response.content, url)
    if "html" not in content_type:
        return link_only(url)
    return extract_article(response.text, str(response.url))


def extract_pdf(data: bytes, url: str) -> Extracted:
    """The app shows the PDF itself; its text is kept for the reading time, topics and search."""
    pdf = link_only(url)
    pdf.kind = "pdf"
    try:
        reader = pypdf.PdfReader(io.BytesIO(data))
        pdf.text = "\n\n".join(page.extract_text() or "" for page in reader.pages)
        title = (reader.metadata.title or "").strip() if reader.metadata else ""
    except Exception as error:  # a damaged or locked file still opens in the app's viewer
        log.warning("no text from %s: %r", url, error)
        return pdf
    pdf.html = text_as_html(pdf.text)
    pdf.title = title or pdf.title
    return pdf


def add_linked_page(extracted: Extracted, link: str, http: httpx.Client) -> None:
    """Put the page a tweet points at under the tweet, so the entry is more than a pointer."""
    try:
        page = fetch_page(link, http)
    except FetchError as error:
        log.info("linked page %s unavailable: %s", link, error)
        return
    if word_count(page.text) < MIN_WORDS:
        return
    extracted.html += f"<hr><h2>{html.escape(page.title)}</h2>{page.html}"
    extracted.text += "\n\n" + page.text


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
            article = fetch_article(owner["id_str"], http)
            cards = embedded_tweet_cards(article, http) if article else {}
            return article_to_extracted(thread, owner, article, cards)
        extracted = thread_to_extracted(thread)
        if link := outside_link(thread[-1]):
            add_linked_page(extracted, link, http)
        return extracted
    if item["source_html"]:
        return extract_article(item["source_html"], url)
    try:
        return fetch_page(url, http)
    except FetchError:
        if not item["shared_text"]:
            raise
        return Extracted(item["title"] or url, None, site_of(url), None, text_as_html(item["shared_text"]), item["shared_text"])


def excerpt_of(extracted: Extracted) -> str:
    """The opening of what the reader will show, so it never quotes page chrome that was cleaned away."""
    if not extracted.html.strip():
        return " ".join(extracted.text.split())[:EXCERPT_CHARS]
    shown = lxml.html.fromstring(f"<div>{extracted.html}</div>")
    for element in shown.iter():
        if element.tag not in INLINE_TAGS:  # words in separate blocks need a space; bold mid-word must not get one
            element.tail = " " + (element.tail or "")
    return " ".join(shown.text_content().split())[:EXCERPT_CHARS]


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
    kind = extracted.kind or item["kind"]
    # A PDF opens in the app whatever its text; a tweet is short by nature.
    min_words = {"pdf": 0, "tweet": 1}.get(kind, MIN_WORDS)
    store.update_item(
        item_id,
        kind=kind,
        status="ready" if words >= min_words else "web_only",
        title=extracted.title if has_real_title or not item["title"] else item["title"],
        author=extracted.author,
        site=extracted.site,
        published_at=extracted.published_at,
        excerpt=excerpt_of(extracted),
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
