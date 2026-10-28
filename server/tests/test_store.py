from bouquet.store import STARTER_TOPICS, Store


def test_create_and_changes_since(store):
    first = store.create_item("https://example.com/a")
    store.create_item("https://x.com/a/status/1")

    seq, items = store.changes_since(0)
    assert {i["url"] for i in items} == {"https://example.com/a", "https://x.com/a/status/1"}
    assert seq >= 2

    assert store.changes_since(seq)[1] == []

    store.update_item(first["id"], title="Hello")
    later_seq, changed = store.changes_since(seq)
    assert [i["id"] for i in changed] == [first["id"]]
    assert later_seq > seq


def test_create_sets_defaults(store):
    item = store.create_item("https://x.com/a/status/1?s=20")
    assert item["kind"] == "tweet"
    assert item["status"] == "pending"
    assert item["location"] == "inbox"
    assert item["canonical_url"] == "https://x.com/a/status/1"
    assert item["topics"] == []
    assert item["favorite"] is False


def test_find_by_canonical(store):
    item = store.create_item("https://example.com/a?utm_source=x")
    assert store.find_by_canonical("https://Example.com/a#frag")["id"] == item["id"]


def test_next_pending_is_oldest_saved(store):
    store.create_item("https://example.com/new", saved_at="2026-10-02T00:00:00+00:00")
    old = store.create_item("https://example.com/old", saved_at="2026-10-01T00:00:00+00:00")
    assert store.next_pending()["id"] == old["id"]


def test_store_seeds_topics(store):
    assert store.topics() == STARTER_TOPICS
    assert STARTER_TOPICS[0] == "AI" and STARTER_TOPICS[-1] == "News" and len(STARTER_TOPICS) == 12


def test_reopening_keeps_data(tmp_path):
    Store(tmp_path / "db.sqlite").create_item("https://example.com/a")
    assert len(Store(tmp_path / "db.sqlite").changes_since(0)[1]) == 1


def test_public_hides_internal(store):
    item = store.create_item("https://example.com/a", source_html="<p>x</p>", shared_text="x")
    public = Store.public(store.get_item(item["id"]))
    for internal in ("source_html", "shared_text", "field_times", "tag_attempts", "last_error"):
        assert internal not in public
