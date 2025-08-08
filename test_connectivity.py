#!/usr/bin/env python3
import json
import smtplib
import urllib.request

import gspread
from oauth2client.service_account import ServiceAccountCredentials

CONFIG_PATH = '/opt/sei-aneel/config/configs.json'


def load_config():
    with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)


def test_twocaptcha(api_key):
    try:
        url = f'https://2captcha.com/res.php?key={api_key}&action=getbalance'
        with urllib.request.urlopen(url, timeout=10) as resp:
            resp.read()
        print('2captcha: OK')
    except Exception as e:
        print(f'2captcha: {e}')


def test_smtp(conf):
    try:
        server = smtplib.SMTP(conf['server'], conf.get('port', 587), timeout=10)
        if conf.get('starttls', False):
            server.starttls()
        server.login(conf['user'], conf['password'])
        server.quit()
        print('SMTP: OK')
    except Exception as e:
        print(f'SMTP: {e}')


def test_sheet(conf):
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
    conf = load_config()
    test_twocaptcha(conf.get('twocaptcha', {}).get('api_key', ''))
    test_smtp(conf.get('smtp', {}))
    test_sheet(conf)


if __name__ == '__main__':
    main()
