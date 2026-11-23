"""Clean article text and metadata out of a web page."""

from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit

import lxml.html
import trafilatura

DROP_TAGS = ("script", "style", "iframe", "form", "noscript", "object", "embed")
KEEP_ATTRIBUTES = {"href", "src", "alt"}
URL_ATTRIBUTES = ("href", "src")


@dataclass
class Extracted:
    title: str
    author: str | None
    site: str
    published_at: str | None
    html: str
    text: str


def site_of(url: str) -> str:
    host = urlsplit(url).netloc.lower()
    return host.removeprefix("www.")


def clean_html(html: str, url: str) -> str:
    if not html.strip():
        return ""
    fragments = lxml.html.fragments_fromstring(html)
    parts = []
    for fragment in fragments:
        if isinstance(fragment, str):
            parts.append(fragment)
            continue
        if fragment.tag in DROP_TAGS:
            continue
        for element in fragment.iter(*DROP_TAGS):
            element.drop_tree()
        for element in fragment.iter():
            if not isinstance(element.tag, str):
                continue
            for name in list(element.attrib):
                if name not in KEEP_ATTRIBUTES:
                    del element.attrib[name]
            for name in URL_ATTRIBUTES:
                if name in element.attrib:
                    element.attrib[name] = urljoin(url, element.attrib[name])
        parts.append(lxml.html.tostring(fragment, encoding="unicode"))
    return "".join(parts)


def extract_article(html: str, url: str) -> Extracted:
    metadata = trafilatura.extract_metadata(html, default_url=url)
    body = trafilatura.extract(
        html,
        url=url,
        output_format="html",
        include_links=True,
        include_images=True,
        include_tables=True,
    )
    text = trafilatura.extract(html, url=url, output_format="txt") or ""
    title = (metadata.title if metadata else None) or url
    return Extracted(
        title=title,
        author=metadata.author if metadata else None,
        site=site_of(url),
        published_at=metadata.date if metadata else None,
        html=drop_title_heading(clean_html(body or "", url), title),
        text=text,
    )


def drop_title_heading(html: str, title: str) -> str:
    """The reader shows the title itself, so a leading <h1> repeating it would print it twice."""
    stripped = html.lstrip()
    if not stripped.startswith("<h1>"):
        return html
    end = stripped.find("</h1>")
    heading = lxml.html.fromstring(stripped[: end + len("</h1>")]).text_content().strip()
    if heading.casefold() != title.strip().casefold():
        return html
    return stripped[end + len("</h1>") :].lstrip()
