"""Environment parsing for chat TUI rendering."""

from __future__ import annotations

from dataclasses import dataclass
from os import environ


@dataclass(frozen=True)
class RenderOptions:
    width: int = 88
    justify: bool = False
    header_separator: bool = False
    message_padding: int = 0
    color_mode: str = "auto"


def parse_positive_int(name: str, value: str | None, default: int) -> int:
    resolved = str(default) if value is None else value
    if not resolved.isdigit() or int(resolved) == 0:
        raise ValueError(f"{name} must be a positive integer (got: {resolved})")
    return int(resolved)


def parse_nonnegative_int(name: str, value: str | None, default: int) -> int:
    resolved = str(default) if value is None else value
    if not resolved.isdigit():
        raise ValueError(f"{name} must be a non-negative integer (got: {resolved})")
    return int(resolved)


def parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None or value == "":
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def parse_color_mode(value: str | None, default: str = "auto") -> str:
    mode = default if value is None or value == "" else value.lower()
    if mode not in {"auto", "always", "never"}:
        raise ValueError(f"CHAT_TUI_COLOR must be auto, always, or never (got: {mode})")
    return mode


def validate_options(options: RenderOptions) -> RenderOptions:
    if options.message_padding >= options.width:
        raise ValueError("CHAT_TUI_MESSAGE_PADDING must be less than CHAT_TUI_WRAP_WIDTH")
    return options


def from_env(env: dict[str, str] | None = None) -> RenderOptions:
    source = environ if env is None else env
    return validate_options(
        RenderOptions(
            width=parse_positive_int("CHAT_TUI_WRAP_WIDTH", source.get("CHAT_TUI_WRAP_WIDTH"), 88),
            justify=parse_bool(source.get("CHAT_TUI_JUSTIFY"), False),
            header_separator=parse_bool(source.get("CHAT_TUI_HEADER_SEPARATOR"), False),
            message_padding=parse_nonnegative_int(
                "CHAT_TUI_MESSAGE_PADDING", source.get("CHAT_TUI_MESSAGE_PADDING"), 0
            ),
            color_mode=parse_color_mode(source.get("CHAT_TUI_COLOR"), "auto"),
        )
    )
