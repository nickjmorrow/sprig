"""Wires the store, background worker, feed poller and API together and serves them."""

import logging

import httpx
import uvicorn

from sprig.api import create_app
from sprig.feeds import FeedPoller
from sprig.pipeline import Worker
from sprig.store import Store
from sprig.tagger import make_tagger

log = logging.getLogger("sprig")


def run(store: Store, tokens: dict[str, str], *, host: str, port: int) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    http = httpx.Client()
    tagger = make_tagger()
    if tagger is None:
        log.warning("No ANTHROPIC_API_KEY and no Claude Code: items won't be tagged")
    else:
        log.info("Tagging with %s", type(tagger).__name__)
    worker = Worker(store, http, tagger)
    poller = FeedPoller(store, http, on_new_item=worker.wake)
    app = create_app(
        store,
        tokens,
        on_new_item=worker.wake,
        on_retag=worker.request_retag,
        on_new_feed=poller.wake,
        http=http,
    )
    worker.start()
    poller.start()
    try:
        uvicorn.run(app, host=host, port=port, log_level="info")
    finally:
        poller.stop()
        worker.stop()
