import io
import json

import httpx
import pytest

from sprig.pipeline import process_item, retag_untagged
from sprig.timing import minutes_for, word_count

from conftest import FIXTURES, fixture_text


class FakeTagger:
    def __init__(self, topics=("Engineering",), error: Exception | None = None):
        self.topics = list(topics)
        self.error = error
        self.calls = []

    def tag(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.topics


def client(handler) -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handler))


def serve_html(body: str, status: int = 200, content_type: str = "text/html; charset=utf-8"):
    return client(lambda request: httpx.Response(status, text=body, headers={"content-type": content_type}))


def no_network():
    def handler(request):
        raise AssertionError(f"unexpected fetch of {request.url}")

    return client(handler)


def test_article_becomes_ready_timed_and_tagged(store):
    item = store.create_item("https://blog.example.com/mvcc")
    done = process_item(store, item["id"], http=serve_html(fixture_text("article.html")), tagger=FakeTagger())
    assert done["status"] == "ready"
    assert done["title"] == "How Postgres decides which version of a row you see"
    assert done["site"] == "blog.example.com"
    assert done["minutes"] == minutes_for(done["word_count"]) and done["word_count"] > 700
    assert done["topics"] == ["Engineering"] and done["topics_source"] == "claude"
    assert done["excerpt"] and len(done["excerpt"]) <= 200
    assert "<p>" in done["content_html"]


def test_uses_source_html_without_fetching(store):
    item = store.create_item("https://blog.example.com/mvcc", source_html=fixture_text("article.html"))
    done = process_item(store, item["id"], http=no_network(), tagger=FakeTagger())
    assert done["status"] == "ready"


def test_404_marks_failed(store):
    item = store.create_item("https://example.com/gone")
    done = process_item(store, item["id"], http=serve_html("nope", status=404), tagger=FakeTagger())
    assert done["status"] == "failed"
    assert "404" in done["last_error"]


def test_timeout_marks_failed(store):
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    item = store.create_item("https://example.com/slow")
    assert process_item(store, item["id"], http=client(handler), tagger=None)["status"] == "failed"


def test_fetch_failure_falls_back_to_shared_text(store):
    shared = " ".join(["shared"] * 300)
    item = store.create_item("https://example.com/x", title="Shared title", shared_text=shared)
    done = process_item(store, item["id"], http=serve_html("", status=500), tagger=None)
    assert done["status"] == "ready" and done["title"] == "Shared title" and done["word_count"] == 300


def pdf_bytes(text: str, title: str | None = None) -> bytes:
    from pypdf import PdfWriter
    from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

    writer = PdfWriter()
    page = writer.add_blank_page(width=612, height=792)
    font = DictionaryObject({NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"), NameObject("/BaseFont"): NameObject("/Helvetica")})
    page[NameObject("/Resources")] = DictionaryObject({NameObject("/Font"): DictionaryObject({NameObject("/F1"): writer._add_object(font)})})
    stream = DecodedStreamObject()
    stream.set_data(f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET".encode())
    page[NameObject("/Contents")] = writer._add_object(stream)
    if title:
        writer.add_metadata({"/Title": title})
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def serve_pdf(body: bytes):
    return client(lambda request: httpx.Response(200, content=body, headers={"content-type": "application/pdf"}))


def test_pdf_is_ready_with_its_text_for_time_and_topics(store):
    item = store.create_item("https://example.com/papers/attention.pdf")
    tagger = FakeTagger()
    body = pdf_bytes(" ".join(["attention"] * 480), title="Attention Is All You Need")
    done = process_item(store, item["id"], http=serve_pdf(body), tagger=tagger)
    assert done["kind"] == "pdf" and done["status"] == "ready"
    assert done["title"] == "Attention Is All You Need" and done["minutes"] == 2
    assert "attention attention" in tagger.calls[0]["text"]


def test_pdf_without_readable_text_still_opens_in_the_app(store):
    item = store.create_item("https://example.com/papers/attention.pdf")
    done = process_item(store, item["id"], http=serve_pdf(b"%PDF"), tagger=None)
    assert done["kind"] == "pdf" and done["status"] == "ready"
    assert done["title"] == "attention.pdf" and done["minutes"] == 1


def test_thin_page_is_web_only_but_tagged(store):
    tagger = FakeTagger()
    item = store.create_item("https://news.example.com/story")
    done = process_item(store, item["id"], http=serve_html(fixture_text("thin.html")), tagger=tagger)
    assert done["status"] == "web_only"
    assert done["topics"] == ["Engineering"]
    assert tagger.calls[0]["title"] == "Members only: the whole story"


def test_tweet_thread(store):
    def handler(request):
        return httpx.Response(200, json=json.loads((FIXTURES / f"tweet_{request.url.params['id']}.json").read_text()))

    item = store.create_item("https://x.com/karpathy/status/102?s=20")
    done = process_item(store, item["id"], http=client(handler), tagger=None)
    assert done["status"] == "ready" and done["site"] == "@karpathy" and done["minutes"] == 1
    assert 'class="tweet"' in done["content_html"]


def test_tweet_endpoint_down_is_web_only(store):
    item = store.create_item("https://x.com/karpathy/status/999")
    done = process_item(store, item["id"], http=serve_html("", status=404), tagger=None)
    assert done["status"] == "web_only" and done["site"] == "@karpathy"


def test_tagger_error_leaves_ready_untagged(store):
    item = store.create_item("https://blog.example.com/mvcc", source_html=fixture_text("article.html"))
    done = process_item(store, item["id"], http=no_network(), tagger=FakeTagger(error=RuntimeError("overloaded")))
    assert done["status"] == "ready" and done["topics"] == []
    assert done["tag_attempts"] == 1 and "overloaded" in done["last_error"]


def test_retag_retries_untagged_until_five_attempts(store):
    item = store.create_item("https://blog.example.com/mvcc", source_html=fixture_text("article.html"))
    process_item(store, item["id"], http=no_network(), tagger=None)
    failing = FakeTagger(error=RuntimeError("down"))
    for _ in range(5):
        assert retag_untagged(store, failing) == 1
    assert retag_untagged(store, failing) == 0
    store.update_item(item["id"], tag_attempts=0)
    assert retag_untagged(store, FakeTagger(["AI"])) == 1
    assert store.get_item(item["id"])["topics"] == ["AI"]


def test_retag_uses_stored_text(store):
    item = store.create_item("https://blog.example.com/mvcc", source_html=fixture_text("article.html"))
    process_item(store, item["id"], http=no_network(), tagger=None)
    tagger = FakeTagger()
    retag_untagged(store, tagger)
    assert word_count(tagger.calls[0]["text"]) > 700


@pytest.mark.parametrize("bad", ["not a url", "ftp://example.com/file"])
def test_unfetchable_urls_fail_cleanly(store, bad):
    item = store.create_item(bad)
    assert process_item(store, item["id"], http=no_network(), tagger=None)["status"] == "failed"


def test_worker_drains_pending_when_woken(store):
    import time

    from sprig.pipeline import Worker

    worker = Worker(store, no_network(), FakeTagger())
    worker.start()
    item = store.create_item("https://blog.example.com/mvcc", source_html=fixture_text("article.html"))
    worker.wake()
    deadline = time.monotonic() + 5
    while store.get_item(item["id"])["status"] == "pending" and time.monotonic() < deadline:
        time.sleep(0.05)
    worker.stop()
    assert store.get_item(item["id"])["topics"] == ["Engineering"]


def test_refetching_keeps_topics_he_set_himself(store):
    item = store.create_item("https://blog.example.com/mvcc", source_html=fixture_text("article.html"))
    store.update_item(item["id"], topics=["Cooking & baking"], topics_source="you")
    tagger = FakeTagger()
    done = process_item(store, item["id"], http=no_network(), tagger=tagger)
    assert done["topics"] == ["Cooking & baking"] and tagger.calls == []
