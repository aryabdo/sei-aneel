#!/usr/bin/env python3
"""Gerencia a planilha de processos no Google Sheets."""

import argparse
import re
import sys

import gspread
from oauth2client.service_account import ServiceAccountCredentials

from sei_aneel.config import load_config


def connect_sheet(conf):
    try:
        creds_file = conf['google_drive']['credentials_file']
        sheet_name = conf['google_drive']['sheet_name']
        worksheet_name = conf['google_drive']['worksheet_name']
        scope = ['https://spreadsheets.google.com/feeds',
                 'https://www.googleapis.com/auth/drive']
        creds = ServiceAccountCredentials.from_json_keyfile_name(creds_file, scope)
        client = gspread.authorize(creds)
        return client.open(sheet_name).worksheet(worksheet_name)
    except Exception as e:
        print(f"Erro ao conectar à planilha: {e}")
        raise


def normalize(num: str) -> str:
    return re.sub(r'\D', '', num or '')


def add_process(sheet, numero):
    sheet.append_row([numero, '', '', '', '', '', '', '', '', '', ''])
    print(f'Processo {numero} adicionado.')


def remove_process(sheet, numero):
    col = sheet.col_values(1)
    numero_norm = normalize(numero)
    for idx, val in enumerate(col[1:], start=2):
        if normalize(val) == numero_norm:
            sheet.delete_rows(idx)
            print(f'Processo {numero} removido.')
            return
    print('Processo não encontrado.')


def update_process(sheet, old, new):
    col = sheet.col_values(1)
    old_norm = normalize(old)
    for idx, val in enumerate(col[1:], start=2):
        if normalize(val) == old_norm:
            sheet.update_acell(f'A{idx}', new)
            print(f'Processo {old} atualizado para {new}.')
            return
    print('Processo não encontrado.')


def main():
    parser = argparse.ArgumentParser(description='Gerencia a planilha de processos no Google Sheets.')
    parser.add_argument('action', choices=['add', 'remove', 'update'], help='Ação a executar')
    parser.add_argument('numero', help='Número do processo')
    parser.add_argument('novo_numero', nargs='?', help='Novo número para atualização')
    args = parser.parse_args()

    conf = load_config()
    sheet = connect_sheet(conf)

    if args.action == 'add':
        add_process(sheet, args.numero)
    elif args.action == 'remove':
        remove_process(sheet, args.numero)
    else:  # update
        if not args.novo_numero:
            print('Uso: manage_processes.py update <número_antigo> <número_novo>')
            sys.exit(1)
        update_process(sheet, args.numero, args.novo_numero)


if __name__ == '__main__':
    main()
