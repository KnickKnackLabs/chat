from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib" / "tui"))

from render.wrapping import render_body, render_prose


class WrappingTest(unittest.TestCase):
    def test_justifies_wrapped_lines_but_not_last_line(self) -> None:
        lines = render_prose(
            "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu",
            width=40,
            justify=True,
        )

        self.assertEqual(lines[0], "alpha  beta gamma delta epsilon zeta eta")
        self.assertEqual(lines[1], "theta iota kappa lambda mu")

    def test_preserves_markdownish_lines(self) -> None:
        body = "- bullet one has enough words to exceed the width significantly\nplain prose after bullet should wrap and justify nicely enough"

        self.assertEqual(
            render_body(body, width=40, justify=True),
            [
                "- bullet one has enough words to exceed the width significantly",
                "plain prose after bullet should wrap and",
                "justify nicely enough",
            ],
        )


if __name__ == "__main__":
    unittest.main()
