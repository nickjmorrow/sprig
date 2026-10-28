# Running the Bouquet server

(Setup steps are added with the CLI.)

## Tweets: what works without X's paid API

Bouquet reads tweets through `cdn.syndication.twimg.com/tweet-result`, the endpoint X's own embedded tweets use. It returns one tweet, plus the tweet it replies to, so Bouquet can walk **up** a thread: sharing the **last** tweet of a thread saves the whole thread (up to 25 tweets). Sharing the first tweet saves only that tweet.

Spike, 2026-10-27: the only keyless source of later tweets was the embedded-timeline endpoint (`syndication.twitter.com/srv/timeline-profile/screen-name/<handle>`), and it answered `429 Too Many Requests` on the first call. Nothing else returns replies without signing in, so walking down a thread stays a known gap.
