"""Canonical forms of saved links, so the same page shared twice is one item."""

import re
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

TRACKING_PARAMS = {"ref", "s", "t", "fbclid", "gclid", "mc_cid", "mc_eid"}
TWITTER_HOSTS = {"twitter.com", "www.twitter.com", "mobile.twitter.com", "www.x.com", "mobile.x.com"}
TWEET_PATH = re.compile(r"^/[^/]+/status(?:es)?/(\d+)")


def canonical_url(url: str) -> str:
    parts = urlsplit(url.strip())
    host = parts.netloc.lower()
    if host in TWITTER_HOSTS:
        host = "x.com"
    query = [
        (key, value)
        for key, value in parse_qsl(parts.query, keep_blank_values=True)
        if not key.lower().startswith("utm_") and key.lower() not in TRACKING_PARAMS
    ]
    path = parts.path or "/"
    if host == "x.com" and (match := TWEET_PATH.match(path)):
        path = match.group(0)
        query = []
    if len(path) > 1 and path.endswith("/"):
        path = path.rstrip("/")
    return urlunsplit((parts.scheme.lower(), host, path, urlencode(query), ""))


def tweet_id(url: str) -> str | None:
    canonical = urlsplit(canonical_url(url))
    if canonical.netloc != "x.com":
        return None
    match = TWEET_PATH.match(canonical.path)
    return match.group(1) if match else None
