import json
from types import SimpleNamespace

import pytest

from sprig.tagger import MAX_WORDS, Tagger, build_prompt

TOPICS = ["AI", "Engineering", "Cooking & baking"]


class FakeMessages:
    def __init__(self, reply: list[str], stop_reason: str = "end_turn"):
        self.reply = reply
        self.stop_reason = stop_reason
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        block = SimpleNamespace(type="text", text=json.dumps({"topics": self.reply}))
        return SimpleNamespace(content=[block], stop_reason=self.stop_reason)


def fake_tagger(reply: list[str], **kwargs) -> tuple[Tagger, FakeMessages]:
    messages = FakeMessages(reply, **kwargs)
    return Tagger(SimpleNamespace(messages=messages)), messages


def tag(tagger: Tagger, text: str = "body", corrections: list[dict] | None = None) -> list[str]:
    return tagger.tag(title="A title", site="example.com", text=text, topics=TOPICS, corrections=corrections or [])


def test_sends_enum_schema_model_and_effort():
    tagger, messages = fake_tagger(["AI"])
    assert tag(tagger) == ["AI"]
    call = messages.calls[0]
    assert call["model"] == "claude-haiku-5-5"
    assert call["output_config"]["effort"] == "low"
    schema = call["output_config"]["format"]["schema"]
    assert schema["properties"]["topics"]["items"]["enum"] == TOPICS + ["Other"]


def test_prompt_includes_corrections_and_truncates_text():
    long_text = " ".join(["word"] * (MAX_WORDS + 500))
    corrections = [{"title": "Sourdough tips", "site": "eats.com", "before": ["Engineering"], "after": ["Cooking & baking"]}]
    prompt = build_prompt(title="T", site="s", text=long_text, topics=TOPICS, corrections=corrections)
    assert prompt.count("word") == MAX_WORDS
    assert "Sourdough tips" in prompt and '["Engineering"]' in prompt and '["Cooking & baking"]' in prompt


def test_unknown_topics_dropped_and_capped_at_three():
    tagger, _ = fake_tagger(["AI", "Bogus", "Engineering", "Cooking & baking", "AI"])
    assert tag(tagger) == ["AI", "Engineering", "Cooking & baking"]


def test_all_unknown_becomes_other():
    tagger, _ = fake_tagger(["Bogus"])
    assert tag(tagger) == ["Other"]


def test_other_alongside_real_topics_is_dropped():
    tagger, _ = fake_tagger(["Other", "AI"])
    assert tag(tagger) == ["AI"]


def test_refusal_raises():
    tagger, _ = fake_tagger(["AI"], stop_reason="refusal")
    with pytest.raises(RuntimeError):
        tag(tagger)


def test_from_env_none_without_key(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    assert Tagger.from_env() is None
