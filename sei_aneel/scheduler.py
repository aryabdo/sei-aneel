"""Utilities for installing cron jobs for automation scripts."""
from __future__ import annotations

from pathlib import Path
import sys
try:
    from crontab import CronTab
except Exception:  # pragma: no cover - cron may be unavailable
    CronTab = None


def ensure_cron(hours: list[int], script_path: str, comment: str) -> None:
    """Ensure cron jobs exist for running *script_path* at given *hours* daily.

    Parameters
    ----------
    hours: list[int]
        List of hours (0-23) when the script should run, using minute 0.
    script_path: str
        Path to the script to schedule.
    comment: str
        Comment used to identify cron jobs so duplicates are avoided.
    """
    if CronTab is None:
        return
    try:
        cron = CronTab(user=True)
    except Exception:
        return

    cron.remove_all(comment=comment)
    command = f"{sys.executable} {Path(script_path).resolve()}"
    for hour in hours:
        job = cron.new(command=command, comment=comment)
        job.setall(f"0 {int(hour)} * * *")
    cron.write()
