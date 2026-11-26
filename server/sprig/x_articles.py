"""X Articles (long posts a tweet links as x.com/i/article/…), read through FxTwitter.

X's embed endpoint gives only an article's title, preview and cover. FxTwitter, an open-source
X mirror, returns the body as Draft.js blocks, which this turns into reader HTML.
"""

import html
import logging
import re

import httpx

log = logging.getLogger(__name__)

FXTWITTER_URL = "https://api.fxtwitter.com/i/status/{tweet_id}"
BLOCK_TAGS = {"unstyled": "p", "header-one": "h2", "header-two": "h3", "header-three": "h4", "blockquote": "blockquote"}
LIST_TAGS = {"unordered-list-item": "ul", "ordered-list-item": "ol"}
STYLE_TAGS = {"Bold": "b", "Italic": "i"}
MARKDOWN_ESCAPE = re.compile(r"\\([\\`*_{}\[\]()#+\-.!~|>])")  # \~ and \) in a table cell mean ~ and )
AUTO_LINKS = {
    "urls": lambda text: text if "://" in text else f"https://{text}",
    "mentions": lambda text: f"https://x.com/{text}",
    "hashtags": lambda text: f"https://x.com/hashtag/{text}",
}


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


def body_html(article: dict, tweet_cards: dict[str, str] | None = None) -> str:
    """tweet_cards: rendered cards for the posts the article embeds, by tweet id."""
    content = article["content"]
    entities = {int(entry["key"]): entry["value"] for entry in content.get("entityMap", [])}
    media = {item["media_id"]: item.get("media_info") or {} for item in article.get("media_entities") or []}
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
            for r in block["entityRanges"]:
                if r["key"] in entities:
                    parts.append(embed_html(entities[r["key"]], media, tweet_cards or {}))
        elif block["text"].strip():
            tag = BLOCK_TAGS.get(block["type"], "p")
            parts.append(f"<{tag}>{inline_html(block, entities)}</{tag}>")
    if open_list:
        parts.append(f"</{open_list}>")
    return "".join(parts)


def embed_html(entity: dict, media: dict[str, dict], tweet_cards: dict[str, str]) -> str:
    data = entity["data"]
    if entity["type"] == "DIVIDER":
        return "<hr>"
    if entity["type"] == "MEDIA":
        shown = "".join(media_html(media.get(item["mediaId"]) or {}) for item in data.get("mediaItems", []))
        caption = f"<figcaption>{html.escape(data['caption'])}</figcaption>" if shown and data.get("caption") else ""
        return shown + caption
    if entity["type"] == "MARKDOWN":
        markdown = data["markdown"].strip()
        if markdown.startswith("|"):
            return table_html(markdown)
        return f"<pre><code>{html.escape(strip_fence(markdown))}</code></pre>"
    if entity["type"] == "TWEET":
        link = f'<p><a href="https://x.com/i/status/{html.escape(data["tweetId"])}">Post on X</a></p>'
        return tweet_cards.get(data["tweetId"], link)
    return ""


def media_html(info: dict) -> str:
    """An image, or a player for a video or GIF (X serves GIFs as silent looping video)."""
    if url := info.get("original_img_url"):
        return f'<img src="{html.escape(url)}" alt="">'
    clips = [v for v in info.get("variants") or [] if v.get("content_type") == "video/mp4"]
    if not clips:
        return ""
    best = max(clips, key=lambda v: v.get("bit_rate") or 0)
    poster = (info.get("preview_image") or {}).get("original_img_url", "")
    looping = " loop muted" if info.get("__typename") == "ApiGif" else ""
    return f'<video controls playsinline preload="none"{looping} poster="{html.escape(poster)}" src="{html.escape(best["url"])}"></video>'


def table_html(markdown: str) -> str:
    """A Markdown pipe table: a header row, a |---| rule, then the rows."""
    rows = [[table_cell(cell) for cell in line.strip().strip("|").split("|")] for line in markdown.split("\n") if line.strip()]
    head = "".join(f"<th>{cell}</th>" for cell in rows[0])
    body = "".join("<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>" for row in rows[2:])
    return f"<table><tr>{head}</tr>{body}</table>"


def table_cell(text: str) -> str:
    cell = html.escape(MARKDOWN_ESCAPE.sub(r"\1", text.strip()))
    cell = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", cell)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", cell)


def strip_fence(markdown: str) -> str:
    lines = markdown.strip().split("\n")
    if lines[0].startswith("```") and lines[-1].startswith("```"):
        lines = lines[1:-1]
    return "\n".join(lines)


def inline_html(block: dict, entities: dict[int, dict]) -> str:
    """Bold, italic, links and line breaks. Draft.js counts offsets in UTF-16 units, so slice the text that way."""
    text = block["text"]
    units = text.encode("utf-16-le")
    length = len(units) // 2
    spans = [(r["offset"], r["offset"] + r["length"], STYLE_TAGS.get(r["style"]), None) for r in block["inlineStyleRanges"]]
    for r in block["entityRanges"]:
        entity = entities.get(r["key"]) or {}
        if entity.get("type") == "LINK" and entity["data"].get("url"):
            spans.append((r["offset"], r["offset"] + r["length"], None, entity["data"]["url"]))
    # What X links by itself (bare addresses, @mentions, #tags) comes with code-point indices instead.
    for kind, target in AUTO_LINKS.items():
        for found in (block.get("data") or {}).get(kind, []):
            start, end = (len(text[:index].encode("utf-16-le")) // 2 for index in (found["fromIndex"], found["toIndex"]))
            spans.append((start, end, None, target(found["text"])))
    edges = sorted({0, length} | {min(edge, length) for start, end, _, _ in spans for edge in (start, end)})
    parts = []
    for start, end in zip(edges, edges[1:]):
        piece = html.escape(units[2 * start : 2 * end].decode("utf-16-le", errors="ignore")).replace("\n", "<br>")
        covering = [span for span in spans if span[0] <= start and end <= span[1]]
        for tag in sorted({span[2] for span in covering if span[2]}):
            piece = f"<{tag}>{piece}</{tag}>"
        if url := next((span[3] for span in covering if span[3]), None):
            piece = f'<a href="{html.escape(url)}">{piece}</a>'
        parts.append(piece)
    return "".join(parts)
