"""Centralized configuration utilities for SEI ANEEL modules.

All modules should import :func:`load_config` from this package to obtain
configuration values.  The configuration file is a single JSON document and is
shared across every component of the project.  A default example is provided at
``config/configs.example.json`` and will be copied to the expected location when
missing.
"""

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any, Dict

# Directory where configuration files are stored.  ``SEI_ANEEL_CONFIG`` can be
# used to override the location of ``configs.json``; otherwise the project uses
# ``/opt/sei-aneel/config/configs.json``.
CONFIG_DIR = Path("/opt/sei-aneel/config")
DEFAULT_CONFIG_PATH = Path(
    os.environ.get("SEI_ANEEL_CONFIG", CONFIG_DIR / "configs.json")
)

_EXAMPLE_CONFIG = Path(__file__).with_name("configs.example.json")


def ensure_config_file(path: Path = DEFAULT_CONFIG_PATH) -> None:
    """Ensure that the configuration file exists.

    The parent directory is created automatically.  When the configuration file
    is absent, ``configs.example.json`` is copied as a starting point so new
    installations always have a valid configuration structure.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() and _EXAMPLE_CONFIG.exists():
        shutil.copy(_EXAMPLE_CONFIG, path)


# Default keyword lists used in case the user does not provide their own.
_DEFAULT_PAUTA_KEYWORDS = [
    "consulta publica",
    "tomada de subsidio",
    "consulta externa",
    "audiencia publica",
    "leilao",
    "isa energia",
    "cteep",
    "companhia de transmissao de energia eletrica paulista",
    "interligacao eletrica",
]

_DEFAULT_SORTEIO_KEYWORDS = [
    "consulta publica",
    "reajuste tarifario",
    "rbse",
    "tomada de subsidio",
    "consulta externa",
    "audiencia publica",
    "leilao",
    "isa energia",
    "cteep",
    "companhia de transmissao de energia eletrica paulista",
    "interligacao eletrica",
]


def load_config(path: str | Path | None = None) -> Dict[str, Any]:
    """Return configuration dictionary from JSON file.

    Parameters
    ----------
    path:
        Optional path to the configuration file.  When ``None`` the
        ``DEFAULT_CONFIG_PATH`` is used.  The file and its parent directory are
        created automatically if missing.
    """

    cfg_path = Path(path) if path else DEFAULT_CONFIG_PATH
    ensure_config_file(cfg_path)

    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    # Apply defaults so callers can rely on the presence of expected keys.
    smtp = config.setdefault("smtp", {})
    smtp.setdefault("port", 587)
    smtp.setdefault("starttls", False)

    keywords = config.setdefault("keywords", {})
    keywords.setdefault("pauta", _DEFAULT_PAUTA_KEYWORDS)
    keywords.setdefault("sorteio", _DEFAULT_SORTEIO_KEYWORDS)

    config.setdefault("email", {}).setdefault("recipients", [])

    return config


__all__ = ["load_config", "DEFAULT_CONFIG_PATH", "ensure_config_file"]
