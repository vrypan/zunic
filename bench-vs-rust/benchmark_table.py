"""Small dependency-free terminal tables for the benchmark drivers."""
from __future__ import annotations

from dataclasses import dataclass
import os
import sys


@dataclass(frozen=True)
class Ratio:
    """Rust time divided by Zunic time; values above one favor Zunic."""

    value: float

    def text(self) -> str:
        return f"{self.value:.2f}×"


def _use_color() -> bool:
    if "NO_COLOR" in os.environ or os.environ.get("TERM") == "dumb":
        return False
    return sys.stdout.isatty() or "FORCE_COLOR" in os.environ


def _paint(text: str, value: float, color: bool) -> str:
    if not color:
        return text
    if value > 1.05:
        return f"\033[32m{text}\033[0m"
    if value < 0.95:
        return f"\033[31m{text}\033[0m"
    return text


def table(headers: list[str], rows: list[list[object]], *, color: bool | None = None) -> str:
    """Render an aligned table, coloring Ratio cells after padding."""
    if color is None:
        color = _use_color()
    plain = [[cell.text() if isinstance(cell, Ratio) else str(cell) for cell in row] for row in rows]
    widths = [len(header) for header in headers]
    for row in plain:
        if len(row) != len(headers):
            raise ValueError("table row has the wrong number of columns")
        widths = [max(width, len(cell)) for width, cell in zip(widths, row)]

    def border(left: str, middle: str, right: str) -> str:
        return left + middle.join("─" * (width + 2) for width in widths) + right

    def render(row: list[object], values: list[str]) -> str:
        cells = []
        for index, (original, value, width) in enumerate(zip(row, values, widths)):
            padded = value.ljust(width) if index == 0 else value.rjust(width)
            if isinstance(original, Ratio):
                padded = _paint(padded, original.value, color)
            cells.append(f" {padded} ")
        return "│" + "│".join(cells) + "│"

    output = [border("┌", "┬", "┐"), render(list(headers), list(headers)), border("├", "┼", "┤")]
    output.extend(render(row, values) for row, values in zip(rows, plain))
    output.append(border("└", "┴", "┘"))
    return "\n".join(output)


def report(title: str, sections: list[tuple[str, list[str], list[list[object]]]], notes: list[str]) -> str:
    output = [f"\n{title}", "=" * len(title)]
    for heading, headers, rows in sections:
        output.extend(("", heading, table(headers, rows)))
    output.extend(("", "Ratio = Rust / Zunic: \033[32mgreen\033[0m > 1.05× (Zunic faster), "
                   "\033[31mred\033[0m < 0.95× (Zunic slower).") if _use_color() else
                  ("", "Ratio = Rust / Zunic: > 1.05× Zunic faster; < 0.95× Zunic slower."))
    if notes:
        output.extend(("", *notes))
    return "\n".join(output)
