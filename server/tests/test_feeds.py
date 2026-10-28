from datetime import UTC, datetime, timedelta

import httpx
from fastapi.testclient import TestClient

from bouquet.api import create_app
from bouquet.feeds import parse_feed, poll_feed, prune

from conftest import fixture_bytes

NOW = datetime(2026, 10, 27, 12, 0, tzinfo=UTC)
FEED_URL = "https://blog.example.com/feed.xml"


def serving(body: bytes, seen: list | None = None, status: int = 200) -> httpx.Client:
    def handler(request):
        if seen is not None:
            seen.append(request)
        if status != 200:
            return httpx.Response(status)
        return httpx.Response(200, content=body, headers={"etag": '"v1"', "content-type": "application/rss+xml"})

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_parse_rss():
    title, site, entries = parse_feed(fixture_bytes("feed.xml"), FEED_URL)
    assert (title, site) == ("Example Engineering", "blog.example.com")
    assert [e.title for e in entries] == ["Full content post", "Summary only post", "Old post"]
    assert entries[0].content_html.startswith("<p>Sentence number 0")
    assert entries[1].content_html is None
    assert entries[0].published_at.startswith("2026-10-24")


def test_parse_atom():
    title, site, entries = parse_feed(fixture_bytes("feed.atom"), "https://notes.example.org/atom")
    assert (title, site) == ("Atom Notes", "notes.example.org")
    assert entries[0].url == "https://notes.example.org/entry-1"


def test_poll_creates_recent_entries_only(store):
    feed = store.add_feed(FEED_URL, "Example Engineering", "blog.example.com")
    assert poll_feed(store, feed, serving(fixture_bytes("feed.xml")), now=NOW) == 2
    items = store.changes_since(0)[1]
    assert {i["title"] for i in items} == {"Full content post", "Summary only post"}
    assert all(i["location"] == "feed" and i["feed_id"] == feed["id"] for i in items)
    full = next(i for i in items if i["title"] == "Full content post")
    assert store.get_item(full["id"])["source_html"].startswith("<p>")
    assert store.get_feed(feed["id"])["etag"] == '"v1"'


def test_poll_skips_known_urls(store):
    store.create_item("https://blog.example.com/full")
    feed = store.add_feed(FEED_URL, "Example Engineering", "blog.example.com")
    assert poll_feed(store, feed, serving(fixture_bytes("feed.xml")), now=NOW) == 1


def test_conditional_get_and_304(store):
    feed = store.add_feed(FEED_URL, "Example Engineering", "blog.example.com")
    store.update_feed(feed["id"], etag='"v1"')
    seen = []
    assert poll_feed(store, store.get_feed(feed["id"]), serving(b"", seen, status=304), now=NOW) == 0
    assert seen[0].headers["if-none-match"] == '"v1"'


def test_poll_records_errors(store):
    feed = store.add_feed(FEED_URL, "Example Engineering", "blog.example.com")
    assert poll_feed(store, feed, serving(b"", status=500), now=NOW) == 0
    assert "500" in store.get_feed(feed["id"])["last_error"]


def test_prune_deletes_only_stale_unkept_feed_items(store):
    old = (NOW - timedelta(days=31)).isoformat()
    stale = store.create_item("https://a.example/1", location="feed", saved_at=old)
    kept = store.create_item("https://a.example/2", location="inbox", saved_at=old)
    starred = store.create_item("https://a.example/3", location="feed", saved_at=old)
    store.update_item(starred["id"], favorite=True)
    fresh = store.create_item("https://a.example/4", location="feed", saved_at=NOW.isoformat())
    seq_before = store.changes_since(0)[0]

    assert prune(store, now=NOW) == 1
    _, changed = store.changes_since(seq_before)
    assert [(i["id"], i["deleted"]) for i in changed] == [(stale["id"], True)]
    assert all(store.get_item(i["id"])["deleted"] is False for i in (kept, starred, fresh))
    # A deleted item's link can be saved again.
    assert store.create_item("https://a.example/1")["deleted"] is False


def test_feed_routes(store):
    token = {"Authorization": "Bearer t"}
    woken = []
    app = create_app(store, {"t": "iphone"}, http=serving(fixture_bytes("feed.xml")), on_new_feed=lambda: woken.append(1))
    api = TestClient(app)
    added = api.post("/api/feeds", json={"url": FEED_URL}, headers=token)
    assert added.status_code == 201 and added.json()["title"] == "Example Engineering"
    assert woken == [1]
    assert [f["url"] for f in api.get("/api/feeds", headers=token).json()] == [FEED_URL]
    assert api.post("/api/feeds", json={"url": FEED_URL}, headers=token).status_code == 200

    poll_feed(store, store.get_feed(added.json()["id"]), serving(fixture_bytes("feed.xml")), now=NOW)
    feed_items = store.changes_since(0)[1]
    store.apply_patch(feed_items[0]["id"], {"location": "inbox"}, "2026-10-27T12:00:00.000+00:00")
    assert api.delete(f"/api/feeds/{added.json()['id']}", headers=token).status_code == 204
    remaining = [i for i in store.changes_since(0)[1]]
    assert [i["id"] for i in remaining] == [feed_items[0]["id"]]
    assert api.get("/api/feeds", headers=token).json() == []


def test_adding_something_that_is_not_a_feed(store):
    app = create_app(store, {"t": "iphone"}, http=serving(b"<html><body>hi</body></html>"))
    response = TestClient(app).post("/api/feeds", json={"url": "https://example.com"}, headers={"Authorization": "Bearer t"})
    assert response.status_code == 422
