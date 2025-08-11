"""Centralized configuration utilities for PAINEEL modules.

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
from typing import Any, Dict, List

# Directory where configuration files are stored.  ``PAINEEL_CONFIG`` can be
# used to override the location of ``configs.json``; otherwise the project uses
# ``/opt/sei-aneel/config/configs.json``.
CONFIG_DIR = Path("/opt/sei-aneel/config")
DEFAULT_CONFIG_PATH = Path(
    os.environ.get("PAINEEL_CONFIG", CONFIG_DIR / "configs.json")
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

# Caminho do arquivo que concentra os termos de pesquisa
DEFAULT_TERMS_PATH = CONFIG_DIR / "search_terms.txt"

# Lista de termos padrão utilizada para preencher o arquivo quando inexistente
_DEFAULT_SEARCH_TERMS = sorted(
    set(_DEFAULT_PAUTA_KEYWORDS + _DEFAULT_SORTEIO_KEYWORDS)
)


def ensure_terms_file(path: Path = DEFAULT_TERMS_PATH) -> None:
    """Garante a existência do arquivo de termos de pesquisa."""

    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        with open(path, "w", encoding="utf-8") as f:
            for term in _DEFAULT_SEARCH_TERMS:
                f.write(f"{term}\n")


def load_search_terms(path: str | Path | None = None) -> List[str]:
    """Carrega os termos de pesquisa a partir de ``search_terms.txt``."""

    terms_path = Path(path) if path else DEFAULT_TERMS_PATH
    ensure_terms_file(terms_path)
    with open(terms_path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


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

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except json.JSONDecodeError:
        config = {}

    # Apply defaults so callers can rely on the presence of expected keys.
    smtp = config.setdefault("smtp", {})
    smtp.setdefault("port", 587)
    smtp.setdefault("starttls", False)

    config.setdefault("email", {}).setdefault("recipients", [])

    return config


__all__ = [
    "load_config",
    "DEFAULT_CONFIG_PATH",
    "ensure_config_file",
    "load_search_terms",
]
