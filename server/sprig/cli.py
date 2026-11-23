"""The `sprig` command: run the server, make device tokens, import from Reader."""

import argparse
import json
import os
import secrets
import sys
from pathlib import Path

import httpx

from sprig.reader_import import import_opml, import_reader
from sprig.store import Store

DEFAULT_HOME = "~/sprig-hub"
DEFAULT_PORT = 8792


def home() -> Path:
    path = Path(os.environ.get("SPRIG_HOME", DEFAULT_HOME)).expanduser()
    path.mkdir(parents=True, exist_ok=True)
    return path


def open_store() -> Store:
    return Store(home() / "sprig.sqlite")


def load_tokens() -> dict[str, str]:
    tokens_file = home() / "tokens.json"
    return json.loads(tokens_file.read_text()) if tokens_file.exists() else {}


def add_token(label: str) -> str:
    tokens = load_tokens()
    token = secrets.token_urlsafe(32)
    tokens[token] = label
    tokens_file = home() / "tokens.json"
    descriptor = os.open(tokens_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        json.dump(tokens, handle, indent=1)
    tokens_file.chmod(0o600)
    return token


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="sprig", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    serve = commands.add_parser("serve", help="run the API, the worker and the feed poller")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=DEFAULT_PORT)
    token = commands.add_parser("token", help="manage device tokens")
    token.add_argument("action", choices=["add"])
    token.add_argument("label", help="which device, e.g. iphone")
    commands.add_parser("import-reader", help="import Reader's inbox and Later (needs READWISE_TOKEN)")
    opml = commands.add_parser("import-opml", help="subscribe to every feed in an OPML file")
    opml.add_argument("file", type=Path)
    args = parser.parse_args(argv)

    if args.command == "serve":
        from sprig.service import run

        if not load_tokens():
            sys.exit("No device tokens yet. Make one with: sprig token add iphone")
        run(open_store(), load_tokens(), host=args.host, port=args.port)
    elif args.command == "token":
        print(add_token(args.label))
    elif args.command == "import-reader":
        reader_token = os.environ.get("READWISE_TOKEN")
        if not reader_token:
            sys.exit("Set READWISE_TOKEN (from readwise.io/access_token) first.")
        with httpx.Client() as http:
            counts = import_reader(open_store(), reader_token, http)
        print(", ".join(f"{count} {label}" for label, count in counts.items()) or "nothing to import")
        print("The running server picks these up within a minute.")
    elif args.command == "import-opml":
        if not args.file.exists():
            sys.exit(f"No such file: {args.file}")
        print(f"{import_opml(open_store(), args.file)} feeds added")
