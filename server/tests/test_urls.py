from sprig.urls import canonical_url, tweet_id


def test_canonical_url_twitter_becomes_x_and_drops_share_params():
    assert canonical_url("https://twitter.com/a/status/1?s=20") == "https://x.com/a/status/1"


def test_canonical_url_lowercases_host_drops_tracking_and_fragment():
    assert canonical_url("HTTPS://Example.com/p?utm_source=x&id=3#top") == "https://example.com/p?id=3"


def test_canonical_url_drops_trailing_slash_on_paths_only():
    assert canonical_url("https://example.com/post/") == "https://example.com/post"
    assert canonical_url("https://example.com/") == "https://example.com/"


def test_canonical_url_mobile_twitter():
    assert canonical_url("https://mobile.twitter.com/a/status/1?t=abc") == "https://x.com/a/status/1"


def test_tweet_id():
    assert tweet_id("https://x.com/jack/status/20") == "20"
    assert tweet_id("https://mobile.twitter.com/a/status/99/photo/1") == "99"
    assert tweet_id("https://example.com") is None
