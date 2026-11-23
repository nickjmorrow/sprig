"""Reading time from word counts."""

WPM = 238  # average adult silent-reading speed


def word_count(text: str) -> int:
    return len(text.split())


def minutes_for(words: int) -> int:
    return max(1, round(words / WPM))
