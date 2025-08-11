#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rastrea pautas publicadas pela ANEEL e dispara alertas."""

import os
import requests
from bs4 import BeautifulSoup
from datetime import datetime
import re
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import unicodedata
import tempfile
import subprocess
from urllib.parse import urljoin
import hashlib
import html
import logging
import shutil
import sys

try:
    from ..config import load_config, load_search_terms
    from ..email_utils import format_html_email
    from ..log_utils import get_logger
except ImportError:  # pragma: no cover - allow direct execution
    from pathlib import Path

    # Allow running the script directly by adding the project root to ``sys.path``
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from sei_aneel.config import load_config, load_search_terms
    from sei_aneel.email_utils import format_html_email
    from sei_aneel.log_utils import get_logger

# Diretório de dados e arquivos de log
DATA_DIR = os.environ.get("PAUTA_DATA_DIR", os.path.join(os.path.expanduser("~"), ".pauta_aneel"))
os.makedirs(DATA_DIR, exist_ok=True)
LOG_FILE = os.environ.get("PAUTA_LOG_FILE", os.path.join(DATA_DIR, "pauta_aneel.log"))
HASH_RESULT_FILE = os.environ.get("HASH_RESULT_FILE", os.path.join(DATA_DIR, "ultimo_resultado_aneel_425.txt"))

# === Registro de data/hora de execução no log ===
logger = get_logger(__name__, log_file=LOG_FILE)

def registrar_log(mensagem):
    logger.info(mensagem)

registrar_log("Início da execução")
# ================================================

# Configurações de e-mail a partir de arquivo de configuração
CONFIG = load_config()
SMTP_CONF = CONFIG.get("smtp", {})
SMTP_SERVER = SMTP_CONF.get("server", "")
SMTP_PORT = SMTP_CONF.get("port", 587)
SMTP_USER = SMTP_CONF.get("user", "")
SMTP_PASSWORD = SMTP_CONF.get("password", "")
EMAIL_TO = ",".join(CONFIG.get("email", {}).get("recipients", []))

BASE_URL = "https://www2.aneel.gov.br/aplicacoes_liferay/noticias_area/?idAreaNoticia=425"
SITE_PREFIX = "https://www2.aneel.gov.br"

# Termos de pesquisa centralizados em ``search_terms.txt``
KEYWORDS = load_search_terms()

def normalize(s):
    if not isinstance(s, str):
        return ""
    nfkd = unicodedata.normalize('NFKD', s)
    return "".join([c for c in nfkd if not unicodedata.combining(c)]).lower()

def palavra_chave_no_texto(texto, palavras_chave):
    texto_norm = normalize(texto)
    for chave in palavras_chave:
        chave_norm = normalize(chave)
        if chave_norm in texto_norm or chave_norm + "s" in texto_norm:
            return True
    return False


def should_notify(items, erro=False):
    """Retorna True se deve enviar notificação."""
    return erro or not items



def parse_date(date_str):
    try:
        return datetime.strptime(date_str, "%d/%m/%Y")
    except Exception:
        return None

def find_nearest_date_link(target_date=None):
    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(BASE_URL, timeout=30, headers=headers)
    if not response.ok:
        logger.error(f"Erro ao acessar ANEEL: {response.status_code}")
        registrar_log(f"Erro ao acessar ANEEL: {response.status_code}")
        return None, None, None
    soup = BeautifulSoup(response.text, "html.parser")
    tables = soup.find_all("table")
    found_rows = []
    for table in tables:
        rows = table.find_all("tr")
        for row in rows:
            tds = row.find_all("td")
            if len(tds) >= 2:
                date_text = tds[0].get_text(strip=True)
                date_found = parse_date(date_text)
                link_tag = tds[1].find("a", href=True)
                if date_found and link_tag:
                    link_found = link_tag["href"]
                    link_text = link_tag.get_text(strip=True)
                    found_rows.append((date_found, link_found, link_text))
    found_rows.sort(key=lambda x: x[0])
    if target_date is None:
        target_date = datetime.now()
    else:
        if isinstance(target_date, str):
            target_date = parse_date(target_date)
        if not target_date:
            logger.error("Data inválida informada.")
            registrar_log("Data inválida informada.")
            return None, None, None
    for date_found, link_found, link_text in found_rows:
        if date_found >= target_date:
            url_final = link_found if link_found.startswith("http") else SITE_PREFIX + link_found
            return url_final, link_text, date_found.strftime("%d/%m/%Y")
    return None, None, None

def extract_items_from_tr(url):
    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(url, timeout=30, headers=headers)
    response.encoding = response.apparent_encoding
    if not response.ok:
        logger.error(f"Erro ao acessar documento: {response.status_code}")
        registrar_log(f"Erro ao acessar documento: {response.status_code}")
        return []
    soup = BeautifulSoup(response.text, "html.parser")

    if soup.body:
        content_elements = []
        for tag in soup.body.descendants:
            if tag.name in ['p', 'div', 'li']:
                content_elements.append(tag)
    else:
        content_elements = soup.find_all(['p', 'div', 'li'])

    idx = 0
    final_results = []
    while idx < len(content_elements):
        el = content_elements[idx]
        texto = el.get_text(separator=" ", strip=True)
        m_proc = re.match(r'^\d+\.\s*Processo\s*:\s*[\d\.]+/\d{4}-\d{2}', texto)
        if m_proc:
            bloco_texto = texto
            bloco_idx_start = idx
            processo_numero = None
            processo_numero_pdf = ""
            m_proc_n = re.search(r'Processo\s*:\s*([\d\.]+/\d{4}-\d{2})', bloco_texto)
            if m_proc_n:
                processo_numero = m_proc_n.group(1)
                processo_numero_pdf = re.sub(r'[\./-]', '', processo_numero)
            pdfs = []
            doc_count = 0
            idx_next = idx + 1
            bloco_extra_text = ""
            while idx_next < len(content_elements):
                texto_next = content_elements[idx_next].get_text(separator=" ", strip=True)
                if re.match(r'^\d+\.\s*Processo\s*:\s*[\d\.]+/\d{4}-\d{2}', texto_next):
                    break
                for a in content_elements[idx_next].find_all('a', href=True):
                    href = a['href']
                    if 'pdf' in href.lower():
                        doc_count += 1
                        pdf_url = urljoin(url, href)
                        doc_index = f" - doc{doc_count}" if doc_count > 1 else ""
                        pdf_filename = f"Minutas de voto e ato - {processo_numero_pdf}{doc_index}.pdf"
                        pdfs.append({"pdf_url": pdf_url, "pdf_filename": pdf_filename})
                bloco_extra_text += " " + texto_next
                idx_next += 1
            bloco_texto_full = bloco_texto + bloco_extra_text
            if palavra_chave_no_texto(bloco_texto_full, KEYWORDS):
                final_results.append({
                    "text": bloco_texto_full.strip(),
                    "processo_numero": processo_numero,
                    "processo_numero_pdf": processo_numero_pdf,
                    "pdfs": pdfs
                })
            idx = idx_next
        else:
            idx += 1
    return final_results

def gerar_pdf_da_pagina(url, pdf_file):
    try:
        if not shutil.which("wkhtmltopdf"):
            logger.error("wkhtmltopdf não encontrado")
            return False
        env = os.environ.copy()
        env.setdefault("XDG_RUNTIME_DIR", "/tmp")
        result = subprocess.run(
            ["wkhtmltopdf", "--quiet", "--load-error-handling", "ignore", url, pdf_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env
        )
        if result.returncode != 0:
            logger.error("Erro ao gerar PDF (wkhtmltopdf): %s", result.stderr.decode())
            registrar_log(f"Erro ao gerar PDF (wkhtmltopdf): {result.stderr.decode()}")
            return False
        return True
    except Exception as e:
        logger.error(f"Erro ao gerar PDF: {e}")
        registrar_log(f"Erro ao gerar PDF: {e}")
        return False

def send_email(subject, body_plain, body_html, pdf_path=None):
    msg = MIMEMultipart()
    msg["From"] = SMTP_USER
    msg["To"] = EMAIL_TO
    msg["Subject"] = subject
    pdf_attached = False
    if pdf_path and os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 0:
        from email.mime.base import MIMEBase
        from email import encoders
        with open(pdf_path, "rb") as f:
            part = MIMEBase('application', "pdf")
            part.set_payload(f.read())
            encoders.encode_base64(part)
            part.add_header('Content-Disposition', 'attachment', filename=os.path.basename(pdf_path))
            msg.attach(part)
            pdf_attached = True
    else:
        logger.warning("PDF não gerado ou está vazio, não será anexado.")
        aviso = (
            "\n\nATENÇÃO: Não foi possível anexar o PDF da página, pois ocorreu um erro na geração do arquivo.\n"
        )
        body_plain += aviso
        body_html = body_html.replace("</body></html>", f"<p>{aviso}</p></body></html>")

    alternative_part = MIMEMultipart('alternative')
    alternative_part.attach(MIMEText(body_plain, "plain", "utf-8"))
    alternative_part.attach(MIMEText(body_html, "html", "utf-8"))
    msg.attach(alternative_part)

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.login(SMTP_USER, SMTP_PASSWORD)
            to_emails = [email.strip() for email in EMAIL_TO.split(",")]
            server.sendmail(SMTP_USER, to_emails, msg.as_string())
        logger.info("E-mail enviado com sucesso.")
        registrar_log(f"E-mail enviado para {EMAIL_TO}")
        registrar_log("Corpo do e-mail:\n" + body_plain + "\n---")
    except Exception as e:
        logger.error(f"Erro ao enviar e-mail: {e}")
        registrar_log(f"Falha ao enviar e-mail: {e}")

def hash_do_resultado(itens):
    texto = "\n".join([item['text'] for item in itens])
    return hashlib.sha256(texto.encode('utf-8')).hexdigest()

def ler_ultimo_hash(arquivo):
    try:
        with open(arquivo, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

def salvar_hash(arquivo, hash_str):
    with open(arquivo, "w") as f:
        f.write(hash_str)

def main():
    if len(sys.argv) > 1:
        data_pesquisa = sys.argv[1]
        execucao_manual = True
    else:
        data_pesquisa = None
        execucao_manual = False
    hoje = datetime.now()
    hoje_str = hoje.strftime("%d/%m/%Y")
    url, link_text, data_encontrada = find_nearest_date_link(data_pesquisa or hoje_str)
    pdf_path = None
    if not url or not data_encontrada:
        logger.info("Nenhum link associado à data encontrada.")
        subject = f"{hoje_str} Busca Pauta ANEEL - Nenhuma data encontrada"
        body = "Nao encontrada pauta para data indicada! Atenciosamente, Ary Abdo!"
        content_html = (
            "<div class=\"section\">"
            "<p>Nao encontrada pauta para data indicada!</p>"
            "<p>Atenciosamente,<br>Ary Abdo</p>"
            "</div>"
        )
        body_html = format_html_email("Pauta da Próxima Reunião ANEEL", content_html)
        if should_notify([], True):
            send_email(subject, body, body_html)
        registrar_log("Nenhum link associado à data encontrada.")
        return

    if url:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp_pdf:
            pdf_path = tmp_pdf.name
        sucesso_pdf = gerar_pdf_da_pagina(url, pdf_path)
        if not sucesso_pdf:
            logger.warning("PDF não gerado, mas tentando anexar se existir.")

    items = extract_items_from_tr(url)
    subject = f"{hoje_str} Busca Pauta ANEEL - {data_encontrada} - {link_text}"

    if items:
        body = "Foram encontrados os processos listados abaixo na pauta da próxima reuniao da ANEEL:\n\n"
        content_html = (
            "<div class=\"section\">"
            f"<h3>📋 Processos Encontrados ({len(items)})</h3>"
            "<ul>"
        )
        for item in items:
            body += item["text"] + "\n"
            item_html = html.escape(item["text"])
            content_html += f"<li class=\"item\">{item_html}"
            registrar_log("Processo encontrado:\n" + item["text"])
            if item["pdfs"]:
                content_html += "<ul>"
                for pdf in item["pdfs"]:
                    body += f"(Acesse o documento PDF: {pdf['pdf_url']})\n"
                    link_html = html.escape(pdf['pdf_filename'])
                    content_html += f"<li><a href='{pdf['pdf_url']}'>{link_html}</a></li>"
                content_html += "</ul>"
                body += "\n"
            else:
                body += "Documentos nao disponibilizados.\n\n"
                content_html += "<p>Documentos nao disponibilizados.</p>"
            content_html += "</li>"
        body += "\nAtenciosamente,\nAry Abdo"
        content_html += "</ul><p>Atenciosamente,<br>Ary Abdo</p></div>"
        body_html = format_html_email("Pauta da Próxima Reunião ANEEL", content_html)
    else:
        body = "Ola! Nao foram encontrados processos listados na pauta na data de pesquisa!\n\nAtenciosamente, Ary Abdo!"
        content_html = (
            "<div class=\"section\">"
            "<p>Ola! Nao foram encontrados processos listados na pauta na data de pesquisa!</p>"
            "<p>Atenciosamente,<br>Ary Abdo</p>"
            "</div>"
        )
        body_html = format_html_email("Pauta da Próxima Reunião ANEEL", content_html)
        registrar_log("Nenhum processo relevante encontrado.")

    logger.info("Itens relevantes encontrados:" if items else "Nenhum item relevante encontrado.")
    logger.info(body)

    hash_arquivo = HASH_RESULT_FILE
    hash_atual = hash_do_resultado(items)
    hash_antigo = ler_ultimo_hash(hash_arquivo)
    notificar = should_notify(items)

    if execucao_manual or notificar or (hash_atual != hash_antigo):
        send_email(subject, body, body_html, pdf_path)
        salvar_hash(hash_arquivo, hash_atual)
        registrar_log("Conteúdo alterado/enviado. Hash atualizado.")
    else:
        logger.info("Nenhuma atualização no conteúdo da pauta ANEEL.")
        registrar_log("Nenhuma atualização na data da pauta ANEEL.")

    if pdf_path and os.path.exists(pdf_path):
        os.remove(pdf_path)

if __name__ == "__main__":
    main()
