# Running the Bouquet server

The server keeps everything in `~/bouquet-hub` (`bouquet.sqlite`, `tokens.json`; set `BOUQUET_HOME` to move it) and listens on `127.0.0.1:8792`.

## On Edgar

1. Copy the repo to `~/Projects/bouquet` and install: `cd ~/Projects/bouquet/server && uv sync`.
2. Make a token per device and paste it into the app's Settings: `uv run bouquet token add iphone`.
3. Put the Anthropic key in Bitwarden as `env:ANTHROPIC_API_KEY` and run `secrets.py pull` from Edgar's login session, so `~/.zshrc.local` has it. Without it everything works except tagging.
4. Run it under launchd:
   ```bash
   cp server/ops/com.nicholai.bouquet.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.nicholai.bouquet.plist
   ```
   Log: `~/Library/Logs/bouquet.log`. `curl localhost:8792/health` → `{"ok":true}`.
5. Put it on the tailnet (tailnet only, never Funnel):
   ```bash
   /Applications/Tailscale.app/Contents/MacOS/Tailscale serve --bg --https=8453 http://127.0.0.1:8792
   ```
   The app's server address is then `https://<hub-host>:8453`.

## Moving off Reader

- **Inbox and Later:** make a token at readwise.io/access_token, then `READWISE_TOKEN=… uv run bouquet import-reader`. Reader's saved copy of each page is used when it has one, so paywalled articles come along.
- **Feeds:** Reader → Settings → Export OPML, then `uv run bouquet import-opml ~/Downloads/<file>.opml`.

Both write to the same database the running server uses; it processes new items within a minute.

## Tweets: what works without X's paid API

Bouquet reads tweets through `cdn.syndication.twimg.com/tweet-result`, the endpoint X's own embedded tweets use. It returns one tweet, plus the tweet it replies to, so Bouquet can walk **up** a thread: sharing the **last** tweet of a thread saves the whole thread (up to 25 tweets). Sharing the first tweet saves only that tweet.

Spike, 2026-10-27: the only keyless source of later tweets was the embedded-timeline endpoint (`syndication.twitter.com/srv/timeline-profile/screen-name/<handle>`), and it answered `429 Too Many Requests` on the first call. Nothing else returns replies without signing in, so walking down a thread stays a known gap.
