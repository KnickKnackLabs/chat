from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib" / "tui"))

from render.wrapping import balanced_wrap_tokens, render_body, render_prose, tokenize


class WrappingTest(unittest.TestCase):
    def test_justifies_wrapped_lines_but_not_last_line(self) -> None:
        lines = render_prose(
            "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu",
            width=40,
            justify=True,
        )

        self.assertEqual(lines[0], "alpha  beta gamma delta epsilon zeta eta")
        self.assertEqual(lines[1], "theta iota kappa lambda mu")

    def test_balanced_wrap_avoids_giant_single_gap(self) -> None:
        paragraph = "Restart handback: next c0da work is the NVR headless-ingress slice. Start in `ricon-family/nvr` clean at `c90ff78`. Implement the smallest first pass: reserved headless/service path reads `shiv:sms listen --json`, rejects non-allowlisted senders, maps sender to opaque family/conversation id, and writes private per-conversation event records."

        greedy = render_prose(paragraph, width=40, justify=True, justify_style="greedy")
        balanced = render_prose(paragraph, width=40, justify=True, justify_style="balanced")

        self.assertIn("`shiv:sms listen --json`,        rejects", greedy)
        self.assertNotIn("`shiv:sms listen --json`,        rejects", balanced)
        self.assertIn("path   reads   `shiv:sms listen --json`,", balanced)

    def test_balanced_wrap_chooses_paragraph_level_breaks(self) -> None:
        tokens = tokenize("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu")

        self.assertEqual(
            balanced_wrap_tokens(tokens, 40),
            [
                ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta"],
                ["theta", "iota", "kappa", "lambda", "mu"],
            ],
        )

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
