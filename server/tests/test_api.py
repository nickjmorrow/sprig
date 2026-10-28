import pytest
from fastapi.testclient import TestClient

from bouquet.api import create_app

TOKEN = "secret-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


class Calls:
    def __init__(self):
        self.new_item = 0
        self.retag = 0


@pytest.fixture
def calls():
    return Calls()


@pytest.fixture
def api(store, calls):
    def on_new_item():
        calls.new_item += 1

    def on_retag():
        calls.retag += 1

    return TestClient(create_app(store, {TOKEN: "iphone"}, on_new_item=on_new_item, on_retag=on_retag))


def save(api, url, **extra):
    return api.post("/api/items", json={"url": url, **extra}, headers=AUTH)


def patch(api, item_id, at, **changes):
    return api.patch(f"/api/items/{item_id}", json={"changes": changes, "at": at}, headers=AUTH)


def test_requires_token(api):
    assert api.get("/health").json() == {"ok": True}
    assert api.get("/api/changes?since=0").status_code == 401
    assert api.get("/api/changes?since=0", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_post_item_201_then_200_dedupe(api, calls):
    first = save(api, "https://example.com/a")
    assert first.status_code == 201 and first.json()["status"] == "pending"
    again = save(api, "https://example.com/a?utm_source=x#top")
    assert again.status_code == 200 and again.json()["id"] == first.json()["id"]
    assert calls.new_item == 1


def test_post_rejects_non_web_links(api):
    assert save(api, "not a link").status_code == 422
    assert save(api, "javascript:alert(1)").status_code == 422


def test_post_keeps_shared_title_and_text(api, store):
    item = save(api, "https://example.com/a", title="Shared", text="Some text").json()
    stored = store.get_item(item["id"])
    assert stored["title"] == "Shared" and stored["shared_text"] == "Some text"


def test_post_archived_moves_to_inbox(api):
    item = save(api, "https://example.com/a").json()
    patch(api, item["id"], "2026-10-27T10:00:00Z", location="archive")
    again = save(api, "https://example.com/a").json()
    assert again["location"] == "inbox"


def test_changes_since(api):
    item = save(api, "https://example.com/a").json()
    body = api.get("/api/changes?since=0", headers=AUTH).json()
    assert [i["id"] for i in body["items"]] == [item["id"]]
    assert body["topics"][0] == "AI" and body["feeds"] == []
    assert "source_html" not in body["items"][0]
    assert api.get(f"/api/changes?since={body['seq']}", headers=AUTH).json()["items"] == []


def test_patch_last_write_wins(api):
    item_id = save(api, "https://example.com/a").json()["id"]
    assert patch(api, item_id, "2026-10-27T10:00:02Z", favorite=True).json()["favorite"] is True
    assert patch(api, item_id, "2026-10-27T10:00:01Z", favorite=False).json()["favorite"] is True
    late = patch(api, item_id, "2026-10-27T10:00:03Z", location="archive", progress=0.5).json()
    assert late["location"] == "archive" and late["progress"] == 0.5 and late["favorite"] is True


def test_patch_compares_times_across_offsets(api):
    item_id = save(api, "https://example.com/a").json()["id"]
    patch(api, item_id, "2026-10-27T10:00:00Z", favorite=True)
    # 05:30-05:00 is 10:30Z: newer, so it wins.
    assert patch(api, item_id, "2026-10-27T05:30:00-05:00", favorite=False).json()["favorite"] is False


def test_patch_validates(api):
    item_id = save(api, "https://example.com/a").json()["id"]
    assert patch(api, item_id, "2026-10-27T10:00:00Z", location="trash").status_code == 422
    assert patch(api, item_id, "2026-10-27T10:00:00Z", topics=["Nope"]).status_code == 422
    assert patch(api, item_id, "2026-10-27T10:00:00Z", topics=[]).status_code == 422
    assert patch(api, "missing", "2026-10-27T10:00:00Z", favorite=True).status_code == 404


def test_patch_topics_records_correction(api, store):
    item_id = save(api, "https://example.com/a", title="Sourdough").json()["id"]
    store.update_item(item_id, topics=["Engineering"])
    done = patch(api, item_id, "2026-10-27T10:00:00Z", topics=["Cooking & baking"]).json()
    assert done["topics"] == ["Cooking & baking"] and done["topics_source"] == "you"
    correction = store.corrections()[0]
    assert correction["before"] == ["Engineering"] and correction["after"] == ["Cooking & baking"]
    assert correction["title"] == "Sourdough"


def test_put_topics_rename(api, store, calls):
    claude_item = save(api, "https://example.com/1").json()["id"]
    yours_two = save(api, "https://example.com/2").json()["id"]
    yours_one = save(api, "https://example.com/3").json()["id"]
    store.update_item(claude_item, topics=["AI"], topics_source="claude", tag_attempts=1)
    store.update_item(yours_two, topics=["AI", "Science"], topics_source="you")
    store.update_item(yours_one, topics=["AI"], topics_source="you")
    renamed = ["Machine learning" if t == "AI" else t for t in store.topics()]
    assert api.put("/api/topics", json={"topics": renamed}, headers=AUTH).status_code == 200

    assert store.topics() == renamed
    assert store.get_item(claude_item)["topics"] == [] and store.get_item(claude_item)["tag_attempts"] == 0
    assert store.get_item(yours_two)["topics"] == ["Science"]
    assert store.get_item(yours_one)["topics"] == ["Other"]
    assert calls.retag == 1


def test_put_topics_add_queues_inbox_retag(api, store):
    inbox = save(api, "https://example.com/1").json()["id"]
    archived = save(api, "https://example.com/2").json()["id"]
    store.update_item(inbox, topics=["Science"], topics_source="claude")
    store.update_item(archived, topics=["Science"], topics_source="claude", location="archive")
    api.put("/api/topics", json={"topics": store.topics() + ["Tattoos"]}, headers=AUTH)
    assert store.get_item(inbox)["topics"] == []
    assert store.get_item(archived)["topics"] == ["Science"]


def test_put_topics_validates(api):
    assert api.put("/api/topics", json={"topics": []}, headers=AUTH).status_code == 422
    assert api.put("/api/topics", json={"topics": ["A", "A"]}, headers=AUTH).status_code == 422
    assert api.put("/api/topics", json={"topics": ["Other"]}, headers=AUTH).status_code == 422
    assert api.put("/api/topics", json={"topics": [" "]}, headers=AUTH).status_code == 422


def test_retry_failed(api, store, calls):
    item_id = save(api, "https://example.com/a").json()["id"]
    store.update_item(item_id, status="failed", last_error="404")
    assert api.post(f"/api/items/{item_id}/retry", headers=AUTH).json()["status"] == "pending"
    assert calls.new_item == 2
