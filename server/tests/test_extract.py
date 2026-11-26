import re

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


CAPTIONED = """<html><head><title>Captions</title></head><body><article>
<p>Padding words to make this paragraph long enough to be kept by the extractor for sure, really quite long.</p>
<figure><img src="/a.png" alt="A chart"><figcaption>Figure 1: a <em>chart</em> caption</figcaption></figure>
<p>More padding text. More padding text. More padding text. More padding text. More padding text. More padding.</p>
<figure><picture><source srcset="/b.webp 1x, /b@2x.webp 2x"><img data-src="/b.png" src="data:image/gif;base64,AAAA"></picture>
<figcaption><p>Second caption.</p><p>Credit: Someone</p></figcaption></figure>
<p>An ordinary paragraph that follows the second figure and must stay a paragraph, with padding words.</p>
<img src="/plain.png"><p>No figure around this one, so this stays a paragraph too, with more padding words.</p>
</article></body></html>"""


def test_image_captions_come_through_whole_and_once():
    html = re.sub(r">\s+<", "><", extract_article(CAPTIONED, "https://example.com/post").html)
    # trafilatura alone leaves "<p><i>chart</i>caption</p>": the words before the <em> are gone.
    assert '<img src="https://example.com/a.png" alt="A chart"><figcaption>Figure 1: a chart caption</figcaption>' in html
    assert '<img src="https://example.com/b.png"><figcaption>Second caption. Credit: Someone</figcaption>' in html
    assert html.count("Second caption") == 1 and html.count("Credit: Someone") == 1 and html.count("<figcaption>") == 2
    assert "<p>An ordinary paragraph that follows" in html and "<p>No figure around this one" in html


CATALOG = """<html><head><title>Learning Path</title></head><body><main>
<p>This site hosts our course materials. You are logging into it to reach them, on a separate platform.</p>
<p><a href="/">Back</a></p><img src="/logo.png" alt="Go home">
<h1>Learning Path</h1>
<p><a href="/">Home</a>/</p><p><a href="/paths">Learning paths</a>/ Learning Path</p>
<p>Take a customer from a first use case to a working pilot, on site, with enough words here to be kept.</p>
<a href="/courses/one"><span>1</span><h4>Capabilities and Limits</h4><p>About 60 min. The limits you will be explaining
to users from the first day of a pilot, in enough words to be kept by the extractor.</p></a>
<a href="/courses/two"><span>2</span><h4>Fluency for Builders</h4><p>About 45 min. Delegation, description, discernment
and diligence, applied to building, again in enough words to be kept.</p></a>
<p>Plain closing paragraph with a normal <a href="/x">inline link</a> that must stay exactly as it is, padded out.</p>
</main></body></html>"""


def test_course_cards_and_site_chrome_read_cleanly():
    html = re.sub(r">\s+<", "><", extract_article(CATALOG, "https://example.com/path").html)
    # Nothing from above the headline, no second copy of the title, no breadcrumb trail.
    assert "logging into" not in html and "Back" not in html and "logo.png" not in html
    assert "<h1>" not in html and "Learning paths" not in html
    # Each card: the link on its heading only, the blurb an ordinary paragraph.
    assert '<h4><a href="https://example.com/courses/one">1. Capabilities and Limits</a></h4><p>About 60 min.' in html
    assert '<h4><a href="https://example.com/courses/two">2. Fluency for Builders</a></h4>' in html
    assert 'a normal <a href="https://example.com/x">inline link</a> that must stay' in html


def test_a_long_introduction_above_the_headline_is_kept():
    intro = "<p>" + "A real opening paragraph before the headline. " * 20 + "</p>"
    page = f"<html><head><title>Late Title</title></head><body><article>{intro}<h1>Late Title</h1><p>{'Body text. ' * 30}</p></article></body></html>"
    assert "A real opening paragraph" in extract_article(page, "https://example.com/late").html
