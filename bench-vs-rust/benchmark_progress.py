"""Single-line progress display shared by comparison benchmark runners."""
from __future__ import annotations

import atexit
import sys


class BenchmarkProgress:
    def __init__(self, total: int) -> None:
        self.total = total
        self.completed = 0
        self._width = 0
        self._finished = False
        atexit.register(self._finish_failed)

    def running(self, label: str) -> None:
        self._render(f"benchmark: running {self.completed + 1}/{self.total} ({label})")

    def preparing(self, label: str) -> None:
        self._render(f"benchmark: preparing ({label})")

    def advance(self) -> None:
        self.completed += 1

    def finish(self) -> None:
        self._finished = True
        self._render(f"benchmark: completed ({self.completed}/{self.total})", newline=True)

    def fail(self) -> None:
        self._finish_failed()

    def _finish_failed(self) -> None:
        if not self._finished:
            self._finished = True
            self._render(f"benchmark: failed ({self.completed}/{self.total} completed)", newline=True)

    def _render(self, message: str, *, newline: bool = False) -> None:
        padded = message.ljust(self._width)
        self._width = max(self._width, len(message))
        sys.stdout.write("\r" + padded + ("\n" if newline else ""))
        sys.stdout.flush()
