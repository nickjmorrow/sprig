from sprig.extract import clean_html, extract_article
from sprig.timing import word_count

from conftest import fixture_text

URL = "https://blog.example.com/postgres-mvcc"


def test_extracts_body_and_meta():
    result = extract_article(fixture_text("article.html"), URL)
    assert result.title == "How Postgres decides which version of a row you see"
    assert result.author == "Ada Lovelace"
    assert result.site == "blog.example.com"
    assert result.published_at.startswith("2026-10-20")
    assert word_count(result.text) > 700
    assert "<script" not in result.html
    assert "Buy our database" not in result.text


def test_thin_page_keeps_title_from_head():
    result = extract_article(fixture_text("thin.html"), "https://news.example.com/story")
    assert word_count(result.text) < 50
    assert result.title == "Members only: the whole story"


def test_clean_html_strips_attributes_and_absolutizes():
    assert clean_html('<p onclick="x" class="y">hi</p>', URL) == "<p>hi</p>"
    assert clean_html('<img src="/a.png" alt="A" width="5">', URL) == '<img src="https://blog.example.com/a.png" alt="A">'


def test_clean_html_drops_scripts():
    assert clean_html("<p>a</p><script>bad()</script>", URL) == "<p>a</p>"


def test_drops_leading_h1_that_repeats_the_title():
    result = extract_article(fixture_text("article.html"), URL)
    assert not result.html.lstrip().startswith("<h1>")


FORMATTED = """<html><head><title>Formatting</title></head><body><article>
<p>This is a <strong>bold claim</strong> with <em>emphasis</em> and some <code>inline_code()</code> in a sentence
that is long enough for the extractor to keep without any trouble at all.</p>
<ol><li>First step of the thing</li><li>Second step of the thing</li></ol>
<ul><li>A plain bullet</li></ul>
<pre><code>def f():
    return 1
</code></pre>
<p>More padding text. More padding text. More padding text. More padding text. More padding text.</p>
</article></body></html>"""


def test_keeps_bold_italics_inline_code_and_numbered_lists():
    html = extract_article(FORMATTED, "https://example.com/post").html
    assert "<strong>bold claim</strong>" in html and "<i>emphasis</i>" in html
    assert "some <code>inline_code()</code> in a sentence" in html
    assert "<ol><li>First step of the thing</li>" in html and "<ul><li>A plain bullet</li></ul>" in html
    assert "<pre><code>def f():\n    return 1\n</code></pre>" in html
