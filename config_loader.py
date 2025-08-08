"""Utility helpers to load configuration for all modules.

The project relies on a single JSON file to store every piece of
configuration.  This module exposes a ``load_config`` function used by all
Python scripts.  Defaults for optional values are applied here so the rest
of the code base can assume the presence of the expected keys.
"""

import json
import os
from pathlib import Path
from typing import Any, Dict

# Default location of the configuration file.  It can be overridden through
# the ``SEI_ANEEL_CONFIG`` environment variable which is also exported by the
# shell installer scripts.
DEFAULT_CONFIG_PATH = os.environ.get(
    "SEI_ANEEL_CONFIG",
    "/opt/sei-aneel/config/configs.json",
)

# Fallback keyword lists used by ``pauta_aneel`` and ``sorteio_aneel`` in case
# the user does not specify custom terms in the configuration file.
DEFAULT_PAUTA_KEYWORDS = [
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

DEFAULT_SORTEIO_KEYWORDS = [
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


def load_config(path: str | None = None) -> Dict[str, Any]:
    """Return configuration dictionary from JSON file.

    Parameters
    ----------
    path: str | None
        Optional path to the configuration file.  When ``None`` it falls back
        to ``DEFAULT_CONFIG_PATH``.
    """

    config_path = path or DEFAULT_CONFIG_PATH
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    # Apply defaults
    smtp = config.setdefault("smtp", {})
    smtp.setdefault("port", 587)
    smtp.setdefault("starttls", False)

    keywords = config.setdefault("keywords", {})
    keywords.setdefault("pauta", DEFAULT_PAUTA_KEYWORDS)
    keywords.setdefault("sorteio", DEFAULT_SORTEIO_KEYWORDS)

    config.setdefault("email", {}).setdefault("recipients", [])

    return config

