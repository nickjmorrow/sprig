import json

import httpx

from sprig.pipeline import process_item
from sprig.x_articles import body_html, fetch_article

from conftest import FIXTURES

ARTICLE = json.loads((FIXTURES / "fxtwitter_400.json").read_text())["tweet"]["article"]


def x_client(fxtwitter_status: int = 200) -> httpx.Client:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.fxtwitter.com":
            if fxtwitter_status != 200:
                return httpx.Response(fxtwitter_status)
            assert request.url.path == "/i/status/400"
            return httpx.Response(200, json=json.loads((FIXTURES / "fxtwitter_400.json").read_text()))
        return httpx.Response(200, json=json.loads((FIXTURES / f"tweet_{request.url.params['id']}.json").read_text()))

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_inline_styles_and_links_use_utf16_offsets():
    # The emoji is two UTF-16 units; offsets after it would land one character late if counted in code points.
    html = body_html(ARTICLE)
    assert "<p>🔁 <b>Every</b> agent <i>is a l</i>oop, see the " in html
    assert '<a href="https://example.com/docs?a=1&amp;b=2">docs</a> &lt;now&gt;.</p>' in html


def test_blocks_become_headings_lists_images_code_and_rules():
    html = body_html(ARTICLE)
    assert "<h2>The layers</h2><ul><li>act</li><li>check</li></ul><ol><li>first</li></ol>" in html
    assert '<img src="https://pbs.twimg.com/media/diagram.jpg" alt="">' in html
    assert "<pre><code>while True:\n    act() &lt; check()</code></pre><hr>" in html
    assert '<a href="https://x.com/i/status/555">Post on X</a>' in html


def test_fetch_article_is_none_when_fxtwitter_is_down():
    assert fetch_article("400", x_client(fxtwitter_status=503)) is None


def test_tweet_that_only_links_its_article_becomes_the_article(store):
    item = store.create_item("https://x.com/adawrites/status/400")
    done = process_item(store, item["id"], http=x_client(), tagger=None)
    assert done["status"] == "ready" and done["title"] == "Loops all the way down"
    assert done["site"] == "@adawrites" and done["author"] == "Ada Writer"
    assert done["minutes"] >= 2 and done["excerpt"].startswith("🔁 Every agent is a loop")
    assert done["content_html"].startswith('<img src="https://pbs.twimg.com/media/cover.png" alt=""><p>')
    assert 'class="tweet"' not in done["content_html"]


def test_article_falls_back_to_title_and_preview_without_fxtwitter(store):
    item = store.create_item("https://x.com/adawrites/status/400")
    done = process_item(store, item["id"], http=x_client(fxtwitter_status=503), tagger=None)
    assert done["status"] == "ready" and done["title"] == "Loops all the way down"
    assert "<p>Every agent is a loop…</p>" in done["content_html"]
    assert '<a href="https://x.com/i/article/9001">Read the rest on X</a>' in done["content_html"]


def test_quote_of_an_article_keeps_the_tweet_and_adds_the_article(store):
    item = store.create_item("https://x.com/fan/status/401")
    done = process_item(store, item["id"], http=x_client(), tagger=None)
    assert done["title"].startswith("Fan: Someone finally wrote down")
    assert 'class="tweet quoted"' in done["content_html"]
    assert "<hr><h2>Loops all the way down</h2>" in done["content_html"]
    assert done["minutes"] >= 2
