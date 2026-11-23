"""Pick 1-3 topics for an item from Nicholas's list, using Claude Haiku (API key, or Claude Code)."""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import anthropic

MODEL = "claude-haiku-5-5"
CLAUDE_CODE_TIMEOUT = 120
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
        schema = topic_schema(topics)
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


def topic_schema(topics: list[str]) -> dict:
    return {
        "type": "object",
        "properties": {"topics": {"type": "array", "items": {"type": "string", "enum": topics + [OTHER]}}},
        "required": ["topics"],
        "additionalProperties": False,
    }


class ClaudeCodeTagger:
    """Tags through Edgar's signed-in Claude Code (headless `claude -p`), like Hob: no API key needed."""

    def __init__(self, binary: str | None = None, run=subprocess.run):
        """Without a binary, finds Claude Code on every call: the app replaces its copy when it updates."""
        self.binary = binary
        self.run = run

    def tag(self, *, title: str, site: str, text: str, topics: list[str], corrections: list[dict]) -> list[str]:
        prompt = build_prompt(title=title, site=site, text=text, topics=topics, corrections=corrections)
        binary = self.binary or claude_code_binary()
        if not binary:
            raise RuntimeError("Claude Code isn't installed")
        cmd = [
            binary, "-p",
            "--output-format", "json",
            "--model", "haiku",
            "--json-schema", json.dumps(topic_schema(topics)),
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources", "project",
            "--no-session-persistence",
        ]
        env = {"PATH": "/opt/homebrew/bin:/usr/bin:/bin", "HOME": str(Path.home()), "USER": os.environ.get("USER", "")}
        done = self.run(cmd, input=prompt, capture_output=True, text=True, timeout=CLAUDE_CODE_TIMEOUT, env=env, cwd=tempfile.gettempdir())
        # (not ~: there --setting-sources project would load ~/.claude's settings and hooks)
        try:
            reply = json.loads(done.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeError(f"claude exited {done.returncode}: {done.stderr.strip()[-300:]}") from error
        if reply.get("is_error"):
            raise RuntimeError(f"claude: {reply.get('result')}")
        answer = reply.get("structured_output") or json.loads(reply.get("result") or "{}")
        return pick_topics(answer.get("topics", []), topics)


def claude_code_binary() -> str | None:
    """$CLAUDE_BIN, else the copy the Claude app keeps current, else Homebrew's (as Hob finds it)."""
    if os.environ.get("CLAUDE_BIN"):
        return os.environ["CLAUDE_BIN"]
    base = Path.home() / "Library/Application Support/Claude/claude-code"
    found = sorted(base.glob("*/*/claude.app/Contents/MacOS/claude"), key=lambda p: p.stat().st_mtime, reverse=True)
    if found:
        return str(found[0])
    homebrew = Path("/opt/homebrew/bin/claude")
    return str(homebrew) if homebrew.exists() else None


def make_tagger() -> "Tagger | ClaudeCodeTagger | None":
    """The API when there's a key; otherwise Claude Code if it's installed; otherwise no tagging."""
    if api := Tagger.from_env():
        return api
    return ClaudeCodeTagger() if claude_code_binary() else None


def pick_topics(suggested: list[str], topics: list[str]) -> list[str]:
    picked = []
    for topic in suggested:
        if topic in topics and topic not in picked:
            picked.append(topic)
    return picked[:MAX_TOPICS] or [OTHER]
