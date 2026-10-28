"""The HTTP API the iPhone app and share extension talk to."""

import secrets
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Literal
from urllib.parse import urlsplit

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field, field_validator

from bouquet.store import Store
from bouquet.tagger import MAX_TOPICS, OTHER

PUBLIC_FEED_FIELDS = ("id", "url", "title", "site", "last_checked", "last_error")


class NewItem(BaseModel):
    url: str
    title: str | None = None
    text: str | None = None

    @field_validator("url")
    @classmethod
    def must_be_web_link(cls, url: str) -> str:
        url = url.strip()
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https") or not parts.netloc:
            raise ValueError("expected an http or https link")
        return url


class Changes(BaseModel):
    location: Literal["inbox", "feed", "archive"] | None = None
    favorite: bool | None = None
    progress: float | None = Field(default=None, ge=0, le=1)
    topics: list[str] | None = Field(default=None, min_length=1, max_length=MAX_TOPICS)


class Patch(BaseModel):
    changes: Changes
    at: datetime

    @field_validator("at")
    @classmethod
    def must_have_timezone(cls, at: datetime) -> datetime:
        if at.tzinfo is None:
            raise ValueError("expected a time with a timezone, e.g. 2026-10-27T10:00:00Z")
        return at


class TopicList(BaseModel):
    topics: list[str] = Field(min_length=1)

    @field_validator("topics")
    @classmethod
    def must_be_distinct_names(cls, topics: list[str]) -> list[str]:
        cleaned = [topic.strip() for topic in topics]
        if any(not topic for topic in cleaned):
            raise ValueError("topic names can't be blank")
        if len(set(cleaned)) != len(cleaned):
            raise ValueError("topic names must be distinct")
        if OTHER in cleaned:
            raise ValueError(f'"{OTHER}" is built in')
        return cleaned


def create_app(
    store: Store,
    tokens: dict[str, str],
    *,
    on_new_item: Callable[[], None] = lambda: None,
    on_retag: Callable[[], None] = lambda: None,
) -> FastAPI:
    app = FastAPI(title="Bouquet")

    def require_token(request: Request) -> str:
        scheme, _, token = request.headers.get("authorization", "").partition(" ")
        for known, label in tokens.items():
            if scheme.lower() == "bearer" and secrets.compare_digest(token, known):
                return label
        raise HTTPException(401, "missing or unknown token")

    def existing_item(item_id: str) -> dict:
        item = store.get_item(item_id)
        if item is None or item["deleted"]:
            raise HTTPException(404, "no such item")
        return item

    authed = [Depends(require_token)]

    @app.get("/health")
    def health():
        return {"ok": True}

    @app.post("/api/items", dependencies=authed)
    def save_item(new: NewItem, response: Response):
        if existing := store.find_by_canonical(new.url):
            if existing["location"] != "inbox":
                existing = store.apply_patch(existing["id"], {"location": "inbox"}, Store.now())
            return Store.public(existing)
        item = store.create_item(new.url, title=new.title, shared_text=new.text)
        on_new_item()
        response.status_code = 201
        return Store.public(item)

    @app.get("/api/changes", dependencies=authed)
    def changes(since: int = 0):
        seq, items = store.changes_since(since)
        feeds = [{key: feed[key] for key in PUBLIC_FEED_FIELDS} for feed in store.list_feeds()]
        return {"seq": seq, "items": items, "topics": store.topics(), "feeds": feeds}

    @app.patch("/api/items/{item_id}", dependencies=authed)
    def patch_item(item_id: str, patch: Patch):
        existing_item(item_id)
        changes = patch.changes.model_dump(exclude_none=True)
        if "topics" in changes:
            allowed = set(store.topics()) | {OTHER}
            if unknown := [topic for topic in changes["topics"] if topic not in allowed]:
                raise HTTPException(422, f"unknown topics: {', '.join(unknown)}")
        at = patch.at.astimezone(UTC).isoformat(timespec="milliseconds")
        return Store.public(store.apply_patch(item_id, changes, at))

    @app.post("/api/items/{item_id}/retry", dependencies=authed)
    def retry_item(item_id: str):
        existing_item(item_id)
        item = store.update_item(item_id, status="pending", last_error=None)
        on_new_item()
        return Store.public(item)

    @app.put("/api/topics", dependencies=authed)
    def put_topics(topic_list: TopicList):
        store.set_topics(topic_list.topics)
        on_retag()
        return {"topics": store.topics()}

    return app
