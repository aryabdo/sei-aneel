#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

import gspread
from oauth2client.service_account import ServiceAccountCredentials

from config_loader import load_config


def connect_sheet(conf):
    creds_file = conf['google_drive']['credentials_file']
    sheet_name = conf['google_drive']['sheet_name']
    worksheet_name = conf['google_drive']['worksheet_name']
    scope = ['https://spreadsheets.google.com/feeds',
             'https://www.googleapis.com/auth/drive']
    creds = ServiceAccountCredentials.from_json_keyfile_name(creds_file, scope)
    client = gspread.authorize(creds)
    return client.open(sheet_name).worksheet(worksheet_name)


def normalize(num: str) -> str:
    return re.sub(r'\D', '', num or '')


def add_process(sheet, numero):
    sheet.append_row([numero, '', '', '', '', '', '', '', '', '', ''])
    print(f'Processo {numero} adicionado.')


def remove_process(sheet, numero):
    col = sheet.col_values(1)
    numero_norm = normalize(numero)
    for idx, val in enumerate(col, start=1):
        if normalize(val) == numero_norm:
            sheet.delete_rows(idx)
            print(f'Processo {numero} removido.')
            return
    print('Processo não encontrado.')


def update_process(sheet, old, new):
    col = sheet.col_values(1)
    old_norm = normalize(old)
    for idx, val in enumerate(col, start=1):
        if normalize(val) == old_norm:
            sheet.update_acell(f'A{idx}', new)
            print(f'Processo {old} atualizado para {new}.')
            return
    print('Processo não encontrado.')


def main():
    if len(sys.argv) < 3:
        print('Uso: manage_processes.py [add|remove|update] <número> [novo número]')
        sys.exit(1)

    action = sys.argv[1]
    conf = load_config()
    sheet = connect_sheet(conf)

    if action == 'add':
        add_process(sheet, sys.argv[2])
    elif action == 'remove':
        remove_process(sheet, sys.argv[2])
    elif action == 'update':
        if len(sys.argv) < 4:
            print('Uso: manage_processes.py update <número_antigo> <número_novo>')
            sys.exit(1)
        update_process(sheet, sys.argv[2], sys.argv[3])
    else:
        print('Ação inválida. Use add, remove ou update.')
        sys.exit(1)


if __name__ == '__main__':
    main()
