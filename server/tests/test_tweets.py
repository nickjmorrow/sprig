import json

import httpx

from bouquet.tweets import fetch_thread, syndication_token, thread_to_extracted

from conftest import FIXTURES


def fixture_client(requested: list[str]) -> httpx.Client:
    def handler(request: httpx.Request) -> httpx.Response:
        tweet_id = request.url.params["id"]
        requested.append(tweet_id)
        path = FIXTURES / f"tweet_{tweet_id}.json"
        if not path.exists():
            return httpx.Response(404)
        return httpx.Response(200, json=json.loads(path.read_text()))

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_token_matches_react_tweet_formula():
    # Expected values computed with Node: ((id / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '')
    assert syndication_token("20") == "6dq1a2xwd93"
    assert syndication_token("1849390342150627492") == "4he14bl34o7"
    assert syndication_token("1234567890123456789") == "2zqic77uqyk"


def test_thread_walks_up_same_author():
    requested = []
    thread = fetch_thread("102", fixture_client(requested))
    assert [t["id_str"] for t in thread] == ["100", "101", "102"]


def test_thread_stops_at_other_author():
    thread = fetch_thread("200", fixture_client([]))
    assert [t["id_str"] for t in thread] == ["200"]


def test_thread_html_has_links_media_and_quote():
    result = thread_to_extracted(fetch_thread("102", fixture_client([])))
    assert result.site == "@karpathy"
    assert result.title.startswith("Andrej Karpathy: Agent evals keep lying to you")
    assert '<a href="https://example.com/evals">example.com/evals</a>' in result.html
    assert "https://t.co/abc" not in result.html
    assert '<img src="https://pbs.twimg.com/media/chart.jpg"' in result.html
    assert 'class="tweet quoted"' in result.html and "original eval paper" in result.html
    assert "3/3" in result.html
    assert result.published_at == "2026-10-24T10:00:00.000Z"
    assert "grade the final answer" in result.text


def test_html_escapes_tweet_text():
    tweet = json.loads((FIXTURES / "tweet_100.json").read_text())
    tweet["text"] = "a <script>x</script> & b"
    tweet["display_text_range"] = [0, len(tweet["text"])]
    assert "<script>" not in thread_to_extracted([tweet]).html
