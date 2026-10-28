"""Pick 1-3 topics for an item from Nicholas's list, using Claude Haiku."""

import json
import os

import anthropic

MODEL = "claude-haiku-5-5"
MAX_WORDS = 1500
MAX_TOPICS = 3
OTHER = "Other"


def build_prompt(*, title: str, site: str, text: str, topics: list[str], corrections: list[dict]) -> str:
    lines = [
        "Sort this saved item into the reader's topics.",
        f"Pick 1 to {MAX_TOPICS} topics from this list, most fitting first: {json.dumps(topics)}.",
        f'Pick "{OTHER}" only when none of them fit.',
    ]
    if corrections:
        lines.append("\nThe reader corrected these earlier picks; follow their taste:")
        for correction in corrections:
            lines.append(
                f"- {correction['title']} ({correction['site']}): you picked {json.dumps(correction['before'])}, "
                f"they changed it to {json.dumps(correction['after'])}"
            )
    excerpt = " ".join(text.split()[:MAX_WORDS])
    lines.append(f"\nTitle: {title}\nSource: {site}\n\n{excerpt}")
    return "\n".join(lines)


class Tagger:
    def __init__(self, client, model: str = MODEL):
        self.client = client
        self.model = model

    @classmethod
    def from_env(cls) -> "Tagger | None":
        if not os.environ.get("ANTHROPIC_API_KEY"):
            return None
        return cls(anthropic.Anthropic())

    def tag(self, *, title: str, site: str, text: str, topics: list[str], corrections: list[dict]) -> list[str]:
        allowed = topics + [OTHER]
        schema = {
            "type": "object",
            "properties": {"topics": {"type": "array", "items": {"type": "string", "enum": allowed}}},
            "required": ["topics"],
            "additionalProperties": False,
        }
        prompt = build_prompt(title=title, site=site, text=text, topics=topics, corrections=corrections)
        response = self.client.messages.create(
            model=self.model,
            max_tokens=1024,
            messages=[{"role": "user", "content": prompt}],
            output_config={"effort": "low", "format": {"type": "json_schema", "schema": schema}},
        )
        if response.stop_reason in ("refusal", "max_tokens"):
            raise RuntimeError(f"tagging stopped early: {response.stop_reason}")
        reply = next(block.text for block in response.content if block.type == "text")
        return pick_topics(json.loads(reply)["topics"], topics)


def pick_topics(suggested: list[str], topics: list[str]) -> list[str]:
    picked = []
    for topic in suggested:
        if topic in topics and topic not in picked:
            picked.append(topic)
    return picked[:MAX_TOPICS] or [OTHER]
