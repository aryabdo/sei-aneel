"""Utility helpers for email generation and attachments."""
from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Iterable, Any
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


def create_xlsx(headers: list[str], rows: list[list[str]]) -> bytes:
    """Create a minimal XLSX file and return its bytes.

    This function builds the necessary XML files for a simple worksheet and
    packages them in a ZIP container following the XLSX specification. It
    avoids external dependencies like *openpyxl*.

    Parameters
    ----------
    headers: list[str]
        Column titles to use in the first row.
    rows: list[list[str]]
        Subsequent rows of data where each inner list represents a row.
    """
    from io import BytesIO
    from zipfile import ZipFile, ZIP_DEFLATED

    def esc(value: str) -> str:
        return (value or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

    def col_letter(idx: int) -> str:
        return chr(ord('A') + idx)

    sheet_rows = []
    header_cells = ''.join(
        f'<c t="inlineStr" r="{col_letter(i)}1"><is><t>{esc(h)}</t></is></c>'
        for i, h in enumerate(headers)
    )
    sheet_rows.append(f'<row r="1">{header_cells}</row>')

    row_num = 1
    for row in rows:
        row_num += 1
        cells = ''.join(
            f'<c t="inlineStr" r="{col_letter(i)}{row_num}"><is><t>{esc(v)}</t></is></c>'
            for i, v in enumerate(row)
        )
        sheet_rows.append(f'<row r="{row_num}">{cells}</row>')

    sheet_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>' + ''.join(sheet_rows) + '</sheetData></worksheet>'
    )

    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>"""

    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
</workbook>"""

    workbook_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>"""

    buffer = BytesIO()
    with ZipFile(buffer, 'w', ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', content_types)
        zf.writestr('_rels/.rels', rels)
        zf.writestr('xl/workbook.xml', workbook)
        zf.writestr('xl/_rels/workbook.xml.rels', workbook_rels)
        zf.writestr('xl/worksheets/sheet1.xml', sheet_xml)

    return buffer.getvalue()


def get_recipients(config: Any, script: str) -> list[str]:
    """Return list of emails configured for a given script.

    Parameters
    ----------
    config:
        Configuration dictionary or object with ``get`` method.
    script:
        Identifier of the script (e.g. ``"sei"``, ``"pauta"``).
    """

    recipients = None

    try:
        # ``ConfigManager`` uses dotted notation
        recipients = config.get("email.recipients")
    except Exception:  # pragma: no cover - be tolerant to unexpected objects
        pass

    if recipients is None:
        try:
            recipients = config.get("email", {}).get("recipients", {})
        except Exception:  # pragma: no cover
            recipients = {}

    if isinstance(recipients, dict):
        return [email for email, scripts in recipients.items() if script in scripts]
    elif isinstance(recipients, list):  # backward compatibility
        return recipients
    return []
