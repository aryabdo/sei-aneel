#!/usr/bin/env python3
"""Verifica a conectividade com serviços externos usados pelo projeto."""

import argparse
import json
import smtplib
import urllib.request

import gspread
from oauth2client.service_account import ServiceAccountCredentials

from sei_aneel.config import load_config


def check_twocaptcha(api_key):
    """Testa a conectividade com o serviço 2captcha."""
    try:
        url = f'https://2captcha.com/res.php?key={api_key}&action=getbalance'
        with urllib.request.urlopen(url, timeout=10) as resp:
            resp.read()
        print('2captcha: OK')
    except Exception as e:
        print(f'2captcha: {e}')


def check_smtp(conf):
    """Testa a conectividade com o servidor SMTP configurado."""
    try:
        server = smtplib.SMTP(conf['server'], conf.get('port', 587), timeout=10)
        if conf.get('starttls', False):
            server.starttls()
        server.login(conf['user'], conf['password'])
        server.quit()
        print('SMTP: OK')
    except Exception as e:
        print(f'SMTP: {e}')


def check_sheet(conf):
    """Testa a conectividade com a planilha do Google configurada."""
    try:
        scope = ['https://spreadsheets.google.com/feeds',
                 'https://www.googleapis.com/auth/drive']
        creds = ServiceAccountCredentials.from_json_keyfile_name(
            conf['google_drive']['credentials_file'], scope)
        client = gspread.authorize(creds)
        client.open(conf['google_drive']['sheet_name']).worksheet(
            conf['google_drive']['worksheet_name'])
        print('Google Sheets: OK')
    except Exception as e:
        print(f'Google Sheets: {e}')


def main():
    parser = argparse.ArgumentParser(description='Verifica a conectividade com serviços externos usados pelo projeto.')
    parser.add_argument('--skip-smtp', action='store_true', help='Ignora teste de SMTP')
    parser.add_argument('--skip-sheet', action='store_true', help='Ignora teste do Google Sheets')
    parser.add_argument('--skip-captcha', action='store_true', help='Ignora teste do 2captcha')
    args = parser.parse_args()

    conf = load_config()
    if not args.skip_captcha:
        check_twocaptcha(conf.get('twocaptcha', {}).get('api_key', ''))
    if not args.skip_smtp:
        check_smtp(conf.get('smtp', {}))
    if not args.skip_sheet:
        check_sheet(conf)


if __name__ == '__main__':
    main()
