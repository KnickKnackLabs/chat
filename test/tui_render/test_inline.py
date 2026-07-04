from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib" / "tui"))

from render.ansi import BODY, BOLD, INLINE_CODE, RESET
from render.inline import colorize_body_segments


class InlineStylingTest(unittest.TestCase):
    def test_inline_code_is_colored_without_visible_backticks(self) -> None:
        rendered = colorize_body_segments("at `a963f70`.", enabled=True, base_code=BODY)

        self.assertIn(f"{BOLD}{INLINE_CODE}a963f70{RESET}{BODY}.", rendered)
        self.assertNotIn("`a963f70`", rendered)

    def test_mentions_are_colored(self) -> None:
        rendered = colorize_body_segments("hello @alice", enabled=True, base_code=BODY)

        self.assertIn("@alice", rendered)
        self.assertIn(BOLD, rendered)
        self.assertIn(RESET, rendered)

    def test_disabled_color_preserves_plain_text(self) -> None:
        self.assertEqual(
            colorize_body_segments("hello @alice at `a963f70`", enabled=False),
            "hello @alice at `a963f70`",
        )


if __name__ == "__main__":
    unittest.main()
