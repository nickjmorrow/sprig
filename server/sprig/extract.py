"""Clean article text and metadata out of a web page."""

import re
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit

import lxml.etree
import lxml.html
import trafilatura

DROP_TAGS = ("script", "style", "iframe", "form", "noscript", "object", "embed")
KEEP_ATTRIBUTES = {"href", "src", "alt"}
URL_ATTRIBUTES = ("href", "src")
HEADING_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6"}
BLOCK_TAGS = HEADING_TAGS | {"p", "ul", "ol", "blockquote", "pre", "table"}
BREADCRUMB_SEPARATOR = re.compile(r"[/›»>|]")
BREADCRUMB_WORDS = 8  # "/ Claude Forward Deployed Engineer": the current page, unlinked, may end the trail
PREAMBLE_WORDS = 100  # more than this above the headline is content, not site chrome
IMAGE_SOURCE_ATTRIBUTES = ("src", "data-src", "data-lazy-src", "data-original")
INLINE_PARENTS = {"p", "li", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6", "a", "strong", "b", "i", "em", "blockquote"}


@dataclass
class Extracted:
    title: str
    author: str | None
    site: str
    published_at: str | None
    html: str
    text: str
    kind: str | None = None  # set when the content turned out to be another kind than the link suggested


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


def figure_captions(html: str, url: str) -> dict[str, str]:
    """Each captioned image on the page: every address it might load from, to its caption."""
    captions = {}
    for figure in lxml.html.fromstring(html).iter("figure"):
        # Paragraphs inside a caption (text, then a credit) need a space between them.
        pieces = [part.text_content() for found in figure.iter("figcaption") for part in (found.findall(".//p") or [found])]
        caption = " ".join(" ".join(pieces).split())
        if not caption:
            continue
        for image in figure.iter("img", "source"):
            sources = [image.get(name) for name in IMAGE_SOURCE_ATTRIBUTES]
            sources += [candidate.split()[0] for candidate in (image.get("srcset") or "").split(",") if candidate.strip()]
            for source in sources:
                if source and not source.startswith("data:"):
                    captions[urljoin(url, source)] = caption
    return captions


def add_captions(content, captions: dict[str, str]) -> None:
    """trafilatura leaves a caption as an ordinary paragraph after its image, sometimes with words
    missing, or drops it. Put the page's own caption there as a <figcaption>."""
    for image in list(content.iter("img")):
        caption = captions.get(image.get("src"))
        if not caption:
            continue
        anchor = image
        while anchor.getnext() is None and not (anchor.tail or "").strip() and anchor.getparent() is not content:
            anchor = anchor.getparent()
        squashed = "".join(caption.split())
        figcaption = lxml.etree.Element("figcaption")
        figcaption.text, figcaption.tail, anchor.tail = caption, anchor.tail, None
        anchor.getparent().insert(anchor.getparent().index(anchor) + 1, figcaption)
        # The caption's own pieces (its text, then often a credit line) may follow as paragraphs: drop them.
        while not (figcaption.tail or "").strip():
            following = figcaption.getnext()
            remains = "".join("".join(following.itertext()).split()) if following is not None and following.tag == "p" else ""
            if not remains or remains not in squashed:
                break
            figcaption.tail = following.tail
            following.getparent().remove(following)


def unwrap_block_links(root) -> None:
    """A card that is one big link (a number, a heading, a blurb) would read as a wall of underlined
    text. Keep the link on its heading only and let the rest be ordinary blocks."""
    for link in list(root.iter("a")):
        blocks = [child for child in link if child.tag in BLOCK_TAGS]
        if not blocks:
            # A card's bold title runs straight into its blurb once the layout is gone: part them.
            for bold in link.iter("strong", "b"):
                if (bold.tail or "")[:1].isalnum():
                    bold.tail = " " + bold.tail
            continue
        parent, lead = link.getparent(), (link.text or "").strip()
        titled = next((block for block in blocks if block.tag in HEADING_TAGS), blocks[0])
        pieces = []
        if lead and not lead.isdigit():
            pieces.append(paragraph(lead))
        for child in list(link):
            tail, child.tail = (child.tail or "").strip(), None
            if child is titled:
                inner = lxml.etree.Element("a", href=link.get("href", ""))
                inner.text = (f"{lead}. " if lead.isdigit() else "") + (child.text or "")
                inner.extend(list(child))
                child.text = None
                child.append(inner)
            pieces.append(child)
            if tail:
                pieces.append(paragraph(tail))
        if (link.tail or "").strip():
            pieces.append(paragraph(link.tail.strip()))
        position = parent.index(link)
        parent.remove(link)
        parent[position:position] = pieces
        if parent.tag == "p" and not (parent.text or "").strip() and parent.getparent() is not None:
            # Blocks can't sit inside a paragraph: lift them out of the one that held the link.
            outer = parent.getparent()
            at = outer.index(parent)
            children = list(parent)
            if children:
                children[-1].tail = parent.tail
            outer.remove(parent)
            outer[at:at] = children


def paragraph(text: str):
    element = lxml.etree.Element("p")
    element.text = text
    return element


def drop_breadcrumbs(root) -> None:
    """Home / Section / Page: a paragraph that is only links and separators is site navigation."""
    for candidate in list(root.iter("p")):
        links = candidate.findall("a")
        loose = (candidate.text or "") + "".join(link.tail or "" for link in links)
        if links and len(links) == len(candidate) and BREADCRUMB_SEPARATOR.search(loose) and len(loose.split()) <= BREADCRUMB_WORDS:
            tail, parent = candidate.tail, candidate.getparent()
            previous = candidate.getprevious()
            parent.remove(candidate)
            if tail and tail.strip():
                if previous is not None:
                    previous.tail = (previous.tail or "") + tail
                else:
                    parent.text = (parent.text or "") + tail


def restore_structure(body: str | None, xml: str | None, captions: dict[str, str] | None = None) -> str:
    """Put back what trafilatura's HTML output flattens. It writes all code as <pre> (a block as
    <pre><pre>, inline code as a <pre> mid-sentence, which would break the line) and every list as
    <ul>; its XML output still says which lists were numbered. Image captions come from the page itself."""
    if not body:
        return ""
    # Parsed as XML: an HTML parser would lift a <pre> out of its paragraph before we could see it.
    root = lxml.etree.fromstring(body.encode())
    for pre in list(root.iter("pre")):
        parent = pre.getparent()
        is_inline = parent.tag in INLINE_PARENTS and pre.find("pre") is None and "\n" not in "".join(pre.itertext())
        if parent.tag == "pre" or is_inline:
            pre.tag = "code"
    lists = list(root.iter("ul"))
    numbered = [found.get("rend") == "ol" for found in lxml.etree.fromstring(xml.encode()).iter("list")] if xml else []
    if len(lists) == len(numbered):
        for element, is_numbered in zip(lists, numbered):
            if is_numbered:
                element.tag = "ol"
    unwrap_block_links(root)
    drop_breadcrumbs(root)
    content = root.find("body") if root.find("body") is not None else root
    add_captions(content, captions or {})
    return (content.text or "") + "".join(lxml.etree.tostring(child, encoding="unicode", method="html") for child in content)


def extract_article(html: str, url: str) -> Extracted:
    metadata = trafilatura.extract_metadata(html, default_url=url)
    body = trafilatura.extract(
        html,
        url=url,
        output_format="html",
        include_links=True,
        include_images=True,
        include_tables=True,
        include_formatting=True,
    )
    structure = trafilatura.extract(html, url=url, output_format="xml", include_tables=True)
    text = trafilatura.extract(html, url=url, output_format="txt") or ""
    title = (metadata.title if metadata else None) or url
    return Extracted(
        title=title,
        author=metadata.author if metadata else None,
        site=site_of(url),
        published_at=metadata.date if metadata else None,
        html=drop_title_heading(clean_html(restore_structure(body, structure, figure_captions(html, url)), url), title),
        text=text,
    )


def drop_title_heading(html: str, title: str) -> str:
    """The reader shows the title itself, so the page's own <h1> repeating it would print it twice.
    What sits above that headline (a logo, a login note, "Back") is the site's chrome: drop it too."""
    wanted = " ".join(title.split()).casefold()
    for found in re.finditer(r"<h1>.*?</h1>", html, re.DOTALL):
        heading = " ".join(lxml.html.fromstring(found.group(0)).text_content().split()).casefold()
        if heading != wanted:
            continue
        above = html[: found.start()]
        if above.strip() and word_count_of(above) > PREAMBLE_WORDS:
            return html
        return html[found.end() :].lstrip()
    return html


def word_count_of(html: str) -> int:
    return len(lxml.html.fromstring(f"<div>{html}</div>").text_content().split())
