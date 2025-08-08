import json
import os
from pathlib import Path

DEFAULT_CONFIG_PATH = os.environ.get(
    "SEI_ANEEL_CONFIG",
    "/opt/sei-aneel/config/configs.json"
)

def load_config(path: str = None):
    config_path = path or DEFAULT_CONFIG_PATH
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)

    smtp = config.setdefault('smtp', {})
    smtp.setdefault('port', 587)
    smtp.setdefault('starttls', False)
    return config
