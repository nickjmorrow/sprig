import json
import subprocess

import pytest

from sprig.tagger import ClaudeCodeTagger, make_tagger

TOPICS = ["AI", "Engineering", "Cooking & baking"]


class FakeRun:
    def __init__(self, reply: dict, returncode: int = 0):
        self.reply = reply
        self.returncode = returncode
        self.calls = []

    def __call__(self, cmd, **kwargs):
        self.calls.append((cmd, kwargs))
        return subprocess.CompletedProcess(cmd, self.returncode, stdout=json.dumps(self.reply), stderr="")


def tag(tagger) -> list[str]:
    return tagger.tag(title="A title", site="example.com", text="body text", topics=TOPICS, corrections=[])


def test_runs_claude_print_with_the_topic_schema_and_no_tools():
    run = FakeRun({"is_error": False, "structured_output": {"topics": ["AI"]}})
    assert tag(ClaudeCodeTagger("/bin/claude", run=run)) == ["AI"]
    cmd, kwargs = run.calls[0]
    assert cmd[:2] == ["/bin/claude", "-p"]
    assert cmd[cmd.index("--model") + 1] == "haiku"
    assert cmd[cmd.index("--tools") + 1] == ""
    assert "--no-session-persistence" in cmd and "--strict-mcp-config" in cmd
    schema = json.loads(cmd[cmd.index("--json-schema") + 1])
    assert schema["properties"]["topics"]["items"]["enum"] == TOPICS + ["Other"]
    assert "A title" in kwargs["input"] and "body text" in kwargs["input"]


def test_reads_a_json_result_when_there_is_no_structured_output():
    run = FakeRun({"is_error": False, "result": '{"topics": ["Engineering", "Bogus"]}'})
    assert tag(ClaudeCodeTagger("/bin/claude", run=run)) == ["Engineering"]


def test_errors_raise_so_the_item_is_retried():
    run = FakeRun({"is_error": True, "result": "Not logged in"})
    with pytest.raises(RuntimeError, match="Not logged in"):
        tag(ClaudeCodeTagger("/bin/claude", run=run))


def test_make_tagger_prefers_an_api_key(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-test")
    assert type(make_tagger()).__name__ == "Tagger"


def test_make_tagger_falls_back_to_claude_code(monkeypatch, tmp_path):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    fake = tmp_path / "claude"
    fake.write_text("#!/bin/sh\n")
    fake.chmod(0o755)
    monkeypatch.setenv("CLAUDE_BIN", str(fake))
    tagger = make_tagger()
    assert isinstance(tagger, ClaudeCodeTagger) and tagger.binary == str(fake)
