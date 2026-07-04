from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib" / "tui"))

from render.options import RenderOptions, from_env


class OptionsTest(unittest.TestCase):
    def test_from_env_parses_renderer_options(self) -> None:
        options = from_env(
            {
                "CHAT_TUI_WRAP_WIDTH": "88",
                "CHAT_TUI_JUSTIFY": "true",
                "CHAT_TUI_HEADER_SEPARATOR": "true",
                "CHAT_TUI_MESSAGE_PADDING": "2",
                "CHAT_TUI_COLOR": "always",
            }
        )

        self.assertEqual(
            options,
            RenderOptions(
                width=88,
                justify=True,
                header_separator=True,
                message_padding=2,
                color_mode="always",
            ),
        )

    def test_padding_must_fit_inside_width(self) -> None:
        with self.assertRaisesRegex(ValueError, "MESSAGE_PADDING"):
            from_env({"CHAT_TUI_WRAP_WIDTH": "2", "CHAT_TUI_MESSAGE_PADDING": "2"})


if __name__ == "__main__":
    unittest.main()
