from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib" / "tui"))

from render.layout import render_message
from render.options import RenderOptions


class LayoutTest(unittest.TestCase):
    def test_header_separator_layout(self) -> None:
        lines = render_message(
            {"timestamp": "2026-07-04 03:41", "sender": "c0da", "id": "abc", "body": "card layout"},
            options=RenderOptions(width=20, justify=False, header_separator=True, message_padding=0),
            color=False,
        )

        self.assertEqual(
            lines,
            [
                "2026-07-04 03:41  c0da  abc",
                "━━━━━━━━━━━━━━━━━━━━",
                "card layout",
                "",
                "",
            ],
        )

    def test_message_padding_applies_to_the_whole_card(self) -> None:
        lines = render_message(
            {"timestamp": "ts", "sender": "bob", "id": "id", "body": "alpha beta gamma delta"},
            options=RenderOptions(width=20, justify=False, header_separator=True, message_padding=2),
            color=False,
        )

        self.assertEqual(
            lines,
            [
                "  ts  bob  id",
                "  ━━━━━━━━━━━━━━━━━━",
                "  alpha beta gamma",
                "  delta",
                "",
                "",
            ],
        )


if __name__ == "__main__":
    unittest.main()
