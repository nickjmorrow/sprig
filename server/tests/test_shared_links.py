"""A tweet that only shares a link is saved as the linked page instead."""

import json

import httpx

from sprig.pipeline import process_item
from sprig.tweets import shared_link

from conftest import FIXTURES, fixture_text


def tweet(tweet_id: str) -> dict:
    return json.loads((FIXTURES / f"tweet_{tweet_id}.json").read_text())


def web(request: httpx.Request) -> httpx.Response:
    if request.url.host == "cdn.syndication.twimg.com":
        return httpx.Response(200, json=tweet(request.url.params["id"]))
    return httpx.Response(200, text=fixture_text("article.html"), headers={"content-type": "text/html"})


def client() -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(web))


def test_shared_link_found_for_short_link_tweet():
    assert shared_link(tweet("300")) == "https://blog.example.com/death-spiral"


def test_no_shared_link_when_the_tweet_has_its_own_substance():
    assert shared_link(tweet("301")) is None


def test_links_to_other_tweets_dont_count():
    assert shared_link(tweet("302")) is None


def test_tweet_item_becomes_the_linked_article(store):
    item = store.create_item("https://x.com/threepointone/status/300?s=12", title="new post")
    done = process_item(store, item["id"], http=client(), tagger=None)
    assert done["kind"] == "article"
    assert done["url"] == "https://blog.example.com/death-spiral"
    assert done["canonical_url"] == "https://blog.example.com/death-spiral"
    assert done["status"] == "ready" and done["site"] == "blog.example.com"
    assert done["title"] == "How Postgres decides which version of a row you see"


def test_swap_onto_an_article_already_saved_keeps_one_copy(store):
    existing = store.create_item("https://blog.example.com/death-spiral")
    store.update_item(existing["id"], location="archive")
    item = store.create_item("https://x.com/threepointone/status/300")
    done = process_item(store, item["id"], http=client(), tagger=None)
    assert done["deleted"] is True
    assert store.get_item(existing["id"])["location"] == "inbox"


def test_thread_or_substantive_tweet_stays_a_tweet(store):
    item = store.create_item("https://x.com/someone/status/301")
    done = process_item(store, item["id"], http=client(), tagger=None)
    assert done["kind"] == "tweet" and done["url"] == "https://x.com/someone/status/301"
    # The page it points at comes along under the tweet, so the entry isn't just a pointer.
    assert 'class="tweet"' in done["content_html"]
    assert "<hr><h2>How Postgres decides which version of a row you see</h2>" in done["content_html"]
    assert done["minutes"] >= 2


def test_tweet_stays_as_it_is_when_the_linked_page_is_unavailable(store):
    def down(request: httpx.Request) -> httpx.Response:
        return web(request) if request.url.host == "cdn.syndication.twimg.com" else httpx.Response(403)

    item = store.create_item("https://x.com/someone/status/301")
    done = process_item(store, item["id"], http=httpx.Client(transport=httpx.MockTransport(down)), tagger=None)
    assert done["status"] == "ready" and "<hr>" not in done["content_html"]
