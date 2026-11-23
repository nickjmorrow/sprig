"""Tweets and self-threads through X's keyless embed endpoint (the one embedded tweets use)."""

import html
import math
from urllib.parse import urlsplit

import httpx

from sprig.extract import Extracted
from sprig.timing import word_count

SYNDICATION_URL = "https://cdn.syndication.twimg.com/tweet-result"
MAX_THREAD = 25
MAX_SHARE_WORDS = 40  # a tweet this short around one link is just pointing at it
X_HOSTS = {"x.com", "twitter.com", "www.x.com", "www.twitter.com", "mobile.twitter.com", "t.co"}
TITLE_CHARS = 80
BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"


def syndication_token(tweet_id: str) -> str:
    """Port of react-tweet's ((id / 1e15) * Math.PI).toString(36).replace(/(0+|\\.)/g, '')."""
    return to_base36(int(tweet_id) / 1e15 * math.pi).replace(".", "").replace("0", "")


def to_base36(value: float) -> str:
    """Number.prototype.toString(36) for a positive float: V8's shortest digits that round-trip."""
    integer = math.floor(value)
    fraction = value - integer
    delta = max(0.5 * (math.nextafter(value, math.inf) - value), math.nextafter(0.0, 1.0))
    digits: list[int] = []
    if fraction >= delta:
        while True:
            fraction *= 36
            delta *= 36
            digit = int(fraction)
            digits.append(digit)
            fraction -= digit
            if (fraction > 0.5 or (fraction == 0.5 and digit & 1)) and fraction + delta > 1:
                while digits and digits[-1] + 1 == 36:
                    digits.pop()
                if digits:
                    digits[-1] += 1
                else:
                    integer += 1
                break
            if fraction < delta:
                break
    head = ""
    while True:
        integer, remainder = divmod(integer, 36)
        head = BASE36[remainder] + head
        if not integer:
            break
    return head + ("." + "".join(BASE36[d] for d in digits) if digits else "")


def fetch_tweet(tweet_id: str, http: httpx.Client) -> dict:
    response = http.get(
        SYNDICATION_URL,
        params={"id": tweet_id, "token": syndication_token(tweet_id), "lang": "en"},
        timeout=20,
    )
    response.raise_for_status()
    tweet = response.json()
    if tweet.get("__typename") not in (None, "Tweet") or "text" not in tweet:
        raise ValueError(f"tweet {tweet_id} is unavailable ({tweet.get('__typename')})")
    return tweet


def fetch_thread(tweet_id: str, http: httpx.Client) -> list[dict]:
    """The shared tweet plus the same author's tweets above it, oldest first."""
    thread = [fetch_tweet(tweet_id, http)]
    while len(thread) < MAX_THREAD:
        top = thread[0]
        parent_id = top.get("in_reply_to_status_id_str")
        if not parent_id or top.get("in_reply_to_screen_name") != top["user"]["screen_name"]:
            break
        try:
            thread.insert(0, fetch_tweet(parent_id, http))
        except (httpx.HTTPError, ValueError):
            break
    return thread


def tweet_text(tweet: dict) -> str:
    note = tweet.get("note_tweet")
    if isinstance(note, dict) and note.get("text"):
        return note["text"]
    start, end = tweet.get("display_text_range") or (0, len(tweet["text"]))
    return tweet["text"][start:end]


def shared_link(tweet: dict) -> str | None:
    """The page a tweet exists to share: its one outside link, when there's little else to it."""
    links = (tweet.get("entities") or {}).get("urls", [])
    outside = {link["expanded_url"] for link in links if urlsplit(link["expanded_url"]).netloc.lower() not in X_HOSTS}
    if len(outside) != 1:
        return None
    text = tweet_text(tweet)
    for link in links:
        text = text.replace(link["url"], "")
    return outside.pop() if word_count(text) <= MAX_SHARE_WORDS else None


def tweet_text_html(tweet: dict) -> str:
    body = html.escape(tweet_text(tweet))
    entities = tweet.get("entities") or {}
    for link in entities.get("urls", []):
        anchor = f'<a href="{html.escape(link["expanded_url"])}">{html.escape(link["display_url"])}</a>'
        body = body.replace(link["url"], anchor)
    for media in entities.get("media", []):
        body = body.replace(media["url"], "")
    paragraphs = [line for line in body.strip().split("\n") if line.strip()]
    return "".join(f"<p>{line}</p>" for line in paragraphs)


def tweet_card(tweet: dict, footer: str = "", quoted: bool = False) -> str:
    user = tweet["user"]
    css_class = "tweet quoted" if quoted else "tweet"
    parts = [
        f'<article class="{css_class}">',
        f"<header><b>{html.escape(user['name'])}</b> <span>@{html.escape(user['screen_name'])}</span></header>",
        tweet_text_html(tweet),
    ]
    for media in tweet.get("mediaDetails") or []:
        parts.append(f'<img src="{html.escape(media["media_url_https"])}" alt="">')
    if quoted_tweet := tweet.get("quoted_tweet"):
        parts.append(tweet_card(quoted_tweet, quoted=True))
    if footer:
        parts.append(f"<footer>{footer}</footer>")
    parts.append("</article>")
    return "".join(parts)


def thread_to_extracted(thread: list[dict]) -> Extracted:
    first = thread[0]
    author = first["user"]
    total = len(thread)
    cards = [tweet_card(tweet, footer=f"{i}/{total}" if total > 1 else "") for i, tweet in enumerate(thread, 1)]
    text = "\n\n".join(tweet_text(tweet) for tweet in thread)
    first_line = " ".join(tweet_text(first).split())
    return Extracted(
        title=f"{author['name']}: {first_line[:TITLE_CHARS]}",
        author=author["name"],
        site=f"@{author['screen_name']}",
        published_at=first.get("created_at"),
        html="".join(cards),
        text=text,
    )
