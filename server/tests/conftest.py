from pathlib import Path

import pytest

from sprig.store import Store

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def store(tmp_path):
    return Store(tmp_path / "sprig.sqlite")


def fixture_text(name: str) -> str:
    return (FIXTURES / name).read_text()


def fixture_bytes(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()
