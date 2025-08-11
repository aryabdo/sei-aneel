"""Utility helpers for email generation and attachments."""
from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Iterable
from email.mime.base import MIMEBase
from email import encoders


def format_html_email(title: str, content_html: str) -> str:
    """Return a styled HTML document for email bodies.

    Parameters
    ----------
    title: Title shown at the top.
    content_html: Raw HTML to embed.
    """
    timestamp_str = datetime.now().strftime('%d/%m/%Y às %H:%M:%S')
    return f"""<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .header {{ color: #2c5aa0; border-bottom: 2px solid #2c5aa0; padding-bottom: 10px; }}
        .section {{ margin: 20px 0; }}
        .item {{ background-color: #e8f4f8; border-left: 4px solid #2c5aa0; padding: 10px; margin: 5px 0; }}
        .timestamp {{ color: #888; font-size: 0.9em; }}
    </style>
</head>
<body>
    <div class="header">
        <h2>{title}</h2>
        <div class="timestamp">Gerado em: {timestamp_str}</div>
    </div>
    {content_html}
    <div class="section">
        <p><small>Este é um e-mail automático do Sistema PAINEEL - Monitoramento de Processos, Pautas e Sorteios - Desenvolvido por AASN.</small></p>
    </div>
</body></html>"""


def attach_bytes(msg, data: bytes, filename: str, mimetype: str = 'application', subtype: str = 'octet-stream') -> None:
    """Attach raw bytes as a file to ``msg``."""
    part = MIMEBase(mimetype, subtype)
    part.set_payload(data)
    encoders.encode_base64(part)
    part.add_header('Content-Disposition', 'attachment', filename=filename)
    msg.attach(part)


def hash_content(lines: Iterable[str]) -> str:
    """Return SHA256 hash for an iterable of strings."""
    h = hashlib.sha256()
    for line in lines:
        h.update(line.encode('utf-8'))
    return h.hexdigest()
