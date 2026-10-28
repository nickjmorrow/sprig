"""Regression tests for the whole-branch review's findings."""

import pytest

from bouquet import pipeline
from bouquet.pipeline import process_item

from conftest import fixture_text
from test_pipeline import FakeTagger, no_network


def test_unexpected_error_fails_the_item_instead_of_stalling_the_queue(store, monkeypatch):
    def broken_extract(html, url):
        raise ValueError("lxml choked")

    monkeypatch.setattr(pipeline, "extract_article", broken_extract)
    bad = store.create_item("https://example.com/bad", source_html="<p>odd</p>", saved_at="2026-10-01T00:00:00.000+00:00")
    done = process_item(store, bad["id"], http=no_network(), tagger=FakeTagger())
    assert done["status"] == "failed" and "lxml choked" in done["last_error"]
    assert store.next_pending() is None


def test_set_topics_is_all_or_nothing(store, monkeypatch):
    item = store.create_item("https://example.com/a")
    store.update_item(item["id"], topics=["AI"], topics_source="claude")
    before = store.topics()

    def explode(*args, **kwargs):
        raise RuntimeError("crash mid-way")

    monkeypatch.setattr(store, "update_item", explode)
    with pytest.raises(RuntimeError):
        store.set_topics(["Machine learning"])
    assert store.topics() == before


def test_save_link_is_idempotent(store):
    first, created = store.save_link("https://example.com/a?utm_source=x")
    again, created_again = store.save_link("https://example.com/a")
    assert created and not created_again and first["id"] == again["id"]


def test_reset_when_device_is_behind_the_purge(store):
    old = store.create_item("https://example.com/old")
    seq_after_create = store.changes_since(0)[0]
    store.delete_item(old["id"])
    assert store.purge_deleted("9999") == 1
    store.create_item("https://example.com/new")
    assert store.needs_reset(seq_after_create) is True
    assert store.needs_reset(store.changes_since(0)[0]) is False
    assert store.needs_reset(0) is False


def test_reset_when_server_seq_went_backwards(store):
    store.create_item("https://example.com/a")
    assert store.needs_reset(10_000) is True


def test_changes_route_sends_full_snapshot_on_reset(store):
    from fastapi.testclient import TestClient

    from bouquet.api import create_app

    store.create_item("https://example.com/a")
    api = TestClient(create_app(store, {"t": "iphone"}))
    body = api.get("/api/changes?since=10000", headers={"Authorization": "Bearer t"}).json()
    assert body["reset"] is True and len(body["items"]) == 1
    assert api.get(f"/api/changes?since={body['seq']}", headers={"Authorization": "Bearer t"}).json()["reset"] is False
