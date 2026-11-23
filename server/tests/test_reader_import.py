import json
import stat

import httpx

from sprig import cli
from sprig.reader_import import import_opml, import_reader

from conftest import FIXTURES


def reader_api(seen: list) -> httpx.Client:
    def handler(request):
        seen.append(request)
        location = request.url.params["location"]
        page = 2 if request.url.params.get("pageCursor") == "cursor-2" else 1
        return httpx.Response(200, json=json.loads((FIXTURES / f"reader_{location}_{page}.json").read_text()))

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_import_pages_both_locations_and_keeps_saved_at(store):
    store.create_item("https://already.example.com/saved")
    seen = []
    counts = import_reader(store, "rw-token", reader_api(seen), sleep=lambda s: None)

    assert counts == {"imported": 3, "already saved": 1, "no link": 1}
    assert all(r.headers["authorization"] == "Token rw-token" for r in seen)
    assert {r.url.params["location"] for r in seen} == {"new", "later"}
    assert all(r.url.params["withHtmlContent"] == "true" for r in seen)

    items = {i["url"]: store.get_item(i["id"]) for i in store.changes_since(0)[1]}
    article = items["https://blog.example.com/postgres"]
    assert article["source_html"] == "<article><p>Saved by Reader.</p></article>"
    assert article["saved_at"].startswith("2026-09-01") and article["location"] == "inbox"
    assert items["https://twitter.com/karpathy/status/102"]["kind"] == "tweet"


def test_import_waits_out_rate_limits(store):
    calls = []

    def handler(request):
        calls.append(1)
        if len(calls) == 1:
            return httpx.Response(429, headers={"Retry-After": "7"})
        return httpx.Response(200, json={"count": 0, "nextPageCursor": None, "results": []})

    slept = []
    import_reader(store, "t", httpx.Client(transport=httpx.MockTransport(handler)), sleep=slept.append)
    assert slept == [7]


def test_import_opml_adds_feeds_including_nested(store):
    assert import_opml(store, FIXTURES / "feeds.opml") == 3
    assert {f["url"] for f in store.list_feeds()} == {
        "https://blog.example.com/feed.xml",
        "https://notes.example.org/atom",
        "https://broken.example.net/rss",
    }
    assert import_opml(store, FIXTURES / "feeds.opml") == 0


def test_token_add_writes_private_file(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SPRIG_HOME", str(tmp_path))
    cli.main(["token", "add", "iphone"])
    token = capsys.readouterr().out.strip()
    tokens_file = tmp_path / "tokens.json"
    assert json.loads(tokens_file.read_text()) == {token: "iphone"}
    assert stat.S_IMODE(tokens_file.stat().st_mode) == 0o600
    assert len(token) >= 32
