from sprig.timing import minutes_for, word_count


def test_minutes_has_a_floor_of_one():
    assert minutes_for(0) == 1


def test_minutes_round_at_238_words_a_minute():
    assert minutes_for(238 * 5) == 5
    assert minutes_for(238 * 14 + 100) == 14


def test_word_count_splits_on_any_whitespace():
    assert word_count("a  b\nc") == 3
