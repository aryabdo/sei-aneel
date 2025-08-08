#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
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
import json
from pathlib import Path

# Garante que ``config_loader`` possa ser importado independentemente do local
# de execução do script.
CONFIG_ENV = os.environ.get("SEI_ANEEL_CONFIG")
if CONFIG_ENV:
    ROOT_DIR = Path(CONFIG_ENV).resolve().parent.parent
else:
    ROOT_DIR = Path(__file__).resolve()
    for parent in ROOT_DIR.parents:
        if (parent / "config_loader.py").exists():
            ROOT_DIR = parent
            break

if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from config_loader import load_config

# Diretório de dados e arquivos de log
DATA_DIR = os.environ.get("SORTEIO_DATA_DIR", os.path.join(os.path.expanduser("~"), ".sorteio_aneel"))
os.makedirs(DATA_DIR, exist_ok=True)
LOG_FILE = os.environ.get("SORTEIO_LOG_FILE", os.path.join(DATA_DIR, "sorteio_aneel.log"))

# === Registro de data/hora de execução no log ===
def registrar_log(mensagem):
    try:
        with open(LOG_FILE, "a") as f:
            for line in mensagem.strip().split("\n"):
                f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {line}\n")
    except Exception as e:
        print(f"Erro ao registrar log: {e}")

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

BASE_URL = "https://www2.aneel.gov.br/aplicacoes_liferay/noticias_area/?idAreaNoticia=424"
SITE_PREFIX = "https://www2.aneel.gov.br"

LAST_RESULT_FILE = os.environ.get(
    "LAST_RESULT_FILE", os.path.join(DATA_DIR, "ultimo_resultado_aneel.json")
)

# Termos de pesquisa definidos no arquivo de configuração global
KEYWORDS = CONFIG.get("keywords", {}).get("sorteio", [])

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

def parse_date(date_str):
    try:
        return datetime.strptime(date_str, "%d/%m/%Y")
    except Exception:
        return None

def ler_ultimo_resultado():
    try:
        with open(LAST_RESULT_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return {"data_encontrada": None, "items": []}

def salvar_ultimo_resultado(data_encontrada, items):
    try:
        with open(LAST_RESULT_FILE, "w") as f:
            json.dump({
                "data_encontrada": data_encontrada,
                "items": items
            }, f)
    except Exception as e:
        registrar_log(f"Erro ao salvar último resultado: {e}")

def find_nearest_date_link(target_date=None):
    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(BASE_URL, timeout=30, headers=headers)
    if not response.ok:
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
        registrar_log(f"Erro ao acessar documento: {response.status_code}")
        return []
    soup = BeautifulSoup(response.text, "html.parser")
    all_tr = soup.find_all("tr")
    main_tr = max(all_tr, key=lambda tr: len(tr.get_text()), default=None)
    if not main_tr:
        registrar_log("Nenhum <tr> relevante encontrado.")
        return []
    full_text = main_tr.get_text(separator=" ", strip=True)
    marker_regex = re.compile(r'(?<!\d)(\d{1,3})\. Processo: \d{5,}\.')
    matches = list(marker_regex.finditer(full_text))
    items = []
    for idx, match in enumerate(matches):
        start = match.start()
        end = matches[idx+1].start() if idx+1 < len(matches) else len(full_text)
        item = full_text[start:end].strip()
        items.append(item)
    final_results = []
    for item in items:
        if palavra_chave_no_texto(item, KEYWORDS):
            item_clean = re.sub(r'\s+', ' ', item).strip()
            final_results.append(item_clean)
    return final_results

def gerar_pdf_da_pagina(url, pdf_file):
    try:
        headers = {'User-Agent': 'Mozilla/5.0'}
        html = requests.get(url, headers=headers, timeout=30).text
        with tempfile.NamedTemporaryFile(delete=False, suffix=".html") as tmp_html:
            tmp_html.write(html.encode("utf-8"))
            html_path = tmp_html.name
        result = subprocess.run(
            ["wkhtmltopdf", "--quiet", html_path, pdf_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        if result.returncode != 0:
            registrar_log(f"Erro ao gerar PDF (wkhtmltopdf): {result.stderr.decode()}")
            os.remove(html_path)
            return False
        os.remove(html_path)
        return True
    except Exception as e:
        registrar_log(f"Erro ao gerar PDF: {e}")
        return False

def send_email(subject, body, pdf_path=None):
    msg = MIMEMultipart()
    msg["From"] = SMTP_USER
    destinatarios = [e.strip() for e in EMAIL_TO.replace(';', ',').split(',') if e.strip()]
    msg["To"] = ", ".join(destinatarios)
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
        registrar_log("PDF não gerado ou está vazio, não será anexado.")
        body += "\n\nATENÇÃO: Não foi possível anexar o PDF da página, pois ocorreu um erro na geração do arquivo.\n"
    msg.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_USER, destinatarios, msg.as_string())
        print("E-mail enviado com sucesso.")
        registrar_log(f"E-mail enviado para {EMAIL_TO}")
        registrar_log("Corpo do e-mail:\n" + body)
    except Exception as e:
        print(f"Erro ao enviar e-mail: {e}")
        registrar_log(f"Falha ao enviar e-mail: {e}")

def main():
    if len(sys.argv) > 1:
        data_pesquisa = sys.argv[1]
        forcar_envio = True
    else:
        data_pesquisa = None
        forcar_envio = False

    hoje = datetime.now()
    hoje_str = hoje.strftime("%d/%m/%Y")
    url, link_text, data_encontrada = find_nearest_date_link(data_pesquisa or hoje_str)
    pdf_path = None

    if not url or not data_encontrada:
        print("Nenhum link associado à data encontrada.")
        subject = f"{hoje_str} Busca Sorteio ANEEL - Nenhuma data encontrada"
        body = "Nao encontrado sorteio para data indicada! Atenciosamente, Ary Abdo!"
        if forcar_envio:
            send_email(subject, body)
        registrar_log("Nenhum link associado à data encontrada. Nenhum e-mail enviado.")
        return

    items = extract_items_from_tr(url)
    ultimo_resultado = ler_ultimo_resultado()
    items_anteriores = ultimo_resultado.get("items", [])
    data_encontrada_anterior = ultimo_resultado.get("data_encontrada")

    if not forcar_envio and items == items_anteriores:
        print("Nenhuma atualização nos itens encontrados.")
        registrar_log("Nenhuma atualização nos itens encontrados.")
        return

    if url:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp_pdf:
            pdf_path = tmp_pdf.name
        sucesso_pdf = gerar_pdf_da_pagina(url, pdf_path)
        if not sucesso_pdf:
            print("PDF não gerado, mas tentando anexar se existir.")

    subject = f"{hoje_str} Busca Sorteio ANEEL - {data_encontrada} - {link_text}"
    if items:
        body = (
            "Foram encontrados os processos listados abaixo no sorteio realizado pela ANEEL:\n\n"
            + "\n\n".join(items)
            + "\n\nAtenciosamente,\nAry Abdo"
        )
        for item in items:
            registrar_log(f"Processo encontrado: {item}")
    else:
        body = "Ola! Nao foram encontrados processos sorteados na data de pesquisa!\n\nAtenciosamente, Ary Abdo!"
        registrar_log("Nenhum processo relevante encontrado.")

    print("Itens relevantes encontrados:" if items else "Nenhum item relevante encontrado.")
    print(body)
    send_email(subject, body, pdf_path)
    if not forcar_envio:
        salvar_ultimo_resultado(data_encontrada, items)
    if pdf_path and os.path.exists(pdf_path):
        os.remove(pdf_path)

if __name__ == "__main__":
    main()
