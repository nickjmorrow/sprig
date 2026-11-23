"""X Articles (long posts a tweet links as x.com/i/article/…), read through FxTwitter.

X's embed endpoint gives only an article's title, preview and cover. FxTwitter, an open-source
X mirror, returns the body as Draft.js blocks, which this turns into reader HTML.
"""

import html
import logging

import httpx

log = logging.getLogger(__name__)

FXTWITTER_URL = "https://api.fxtwitter.com/i/status/{tweet_id}"
BLOCK_TAGS = {"unstyled": "p", "header-one": "h2", "header-two": "h3", "header-three": "h4", "blockquote": "blockquote"}
LIST_TAGS = {"unordered-list-item": "ul", "ordered-list-item": "ol"}
STYLE_TAGS = {"Bold": "b", "Italic": "i"}


def article_owner(tweet: dict) -> dict | None:
    """The tweet carrying an article: this one, or the one it quotes."""
    if tweet.get("article"):
        return tweet
    quoted = tweet.get("quoted_tweet") or {}
    return quoted if quoted.get("article") else None


def fetch_article(tweet_id: str, http: httpx.Client) -> dict | None:
    """The full article, or None when FxTwitter can't supply it (the caller falls back to the preview)."""
    try:
        response = http.get(FXTWITTER_URL.format(tweet_id=tweet_id), headers={"User-Agent": "sprig-reader"}, timeout=20)
        response.raise_for_status()
        article = response.json()["tweet"].get("article") or {}
    except Exception as error:
        log.warning("article for tweet %s unavailable: %r", tweet_id, error)
        return None
    return article if (article.get("content") or {}).get("blocks") else None


def cover_html(article: dict) -> str:
    url = ((article.get("cover_media") or {}).get("media_info") or {}).get("original_img_url")
    return f'<img src="{html.escape(url)}" alt="">' if url else ""


def preview_html(summary: dict) -> str:
    """What the embed endpoint knows about an article: enough to say what it is and link to it."""
    link = f"https://x.com/i/article/{summary['rest_id']}"
    return f'<p>{html.escape(summary.get("preview_text", ""))}…</p><p><a href="{link}">Read the rest on X</a></p>'


def body_text(article: dict) -> str:
    content = article["content"]
    parts = [block["text"] for block in content["blocks"] if block["type"] != "atomic"]
    parts += [e["value"]["data"]["markdown"] for e in content.get("entityMap", []) if e["value"]["type"] == "MARKDOWN"]
    return "\n\n".join(part for part in parts if part.strip())


def body_html(article: dict) -> str:
    content = article["content"]
    entities = {int(entry["key"]): entry["value"] for entry in content.get("entityMap", [])}
    images = {
        media["media_id"]: media["media_info"]["original_img_url"]
        for media in article.get("media_entities") or []
        if (media.get("media_info") or {}).get("original_img_url")
    }
    parts: list[str] = []
    open_list = None
    for block in content["blocks"]:
        list_tag = LIST_TAGS.get(block["type"])
        if open_list and list_tag != open_list:
            parts.append(f"</{open_list}>")
            open_list = None
        if list_tag:
            if not open_list:
                parts.append(f"<{list_tag}>")
                open_list = list_tag
            parts.append(f"<li>{inline_html(block, entities)}</li>")
        elif block["type"] == "atomic":
            parts.extend(embed_html(entities[r["key"]], images) for r in block["entityRanges"] if r["key"] in entities)
        elif block["text"].strip():
            tag = BLOCK_TAGS.get(block["type"], "p")
            parts.append(f"<{tag}>{inline_html(block, entities)}</{tag}>")
    if open_list:
        parts.append(f"</{open_list}>")
    return "".join(parts)


def embed_html(entity: dict, images: dict[str, str]) -> str:
    data = entity["data"]
    if entity["type"] == "DIVIDER":
        return "<hr>"
    if entity["type"] == "MEDIA":
        urls = [images.get(item["mediaId"]) for item in data.get("mediaItems", [])]
        return "".join(f'<img src="{html.escape(url)}" alt="">' for url in urls if url)
    if entity["type"] == "MARKDOWN":
        return f"<pre><code>{html.escape(strip_fence(data['markdown']))}</code></pre>"
    if entity["type"] == "TWEET":
        return f'<p><a href="https://x.com/i/status/{html.escape(data["tweetId"])}">Post on X</a></p>'
    return ""


def strip_fence(markdown: str) -> str:
    lines = markdown.strip().split("\n")
    if lines[0].startswith("```") and lines[-1].startswith("```"):
        lines = lines[1:-1]
    return "\n".join(lines)


def inline_html(block: dict, entities: dict[int, dict]) -> str:
    """Bold, italic and links. Draft.js counts offsets in UTF-16 units, so slice the text that way."""
    units = block["text"].encode("utf-16-le")
    length = len(units) // 2
    spans = [(r["offset"], r["offset"] + r["length"], STYLE_TAGS.get(r["style"]), None) for r in block["inlineStyleRanges"]]
    for r in block["entityRanges"]:
        entity = entities.get(r["key"]) or {}
        if entity.get("type") == "LINK" and entity["data"].get("url"):
            spans.append((r["offset"], r["offset"] + r["length"], None, entity["data"]["url"]))
    edges = sorted({0, length} | {min(edge, length) for start, end, _, _ in spans for edge in (start, end)})
    parts = []
    for start, end in zip(edges, edges[1:]):
        piece = html.escape(units[2 * start : 2 * end].decode("utf-16-le", errors="ignore"))
        covering = [span for span in spans if span[0] <= start and end <= span[1]]
        for tag in sorted({span[2] for span in covering if span[2]}):
            piece = f"<{tag}>{piece}</{tag}>"
        if url := next((span[3] for span in covering if span[3]), None):
            piece = f'<a href="{html.escape(url)}">{piece}</a>'
        parts.append(piece)
    return "".join(parts)
