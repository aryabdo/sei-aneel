"""Ferramentas para gerar backups locais ou no Google Drive."""

import argparse
import os
import sys
import zipfile
from datetime import datetime
from pathlib import Path
import logging

# Assegura acesso ao módulo de configuração central independentemente do
# diretório de execução do script.
ROOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT_DIR))

from config import DEFAULT_CONFIG_PATH, load_config
from log_utils import get_logger

logger = get_logger(__name__)

def _zip_dirs(base_dir: Path, target_dirs: list[Path]) -> Path:
    base_dir = base_dir.resolve()
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_dir = base_dir / 'backups'
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_file = backup_dir / f'sei_aneel_backup_{timestamp}.zip'
    with zipfile.ZipFile(backup_file, 'w', zipfile.ZIP_DEFLATED) as zf:
        for d in target_dirs:
            if d.exists():
                for root, _, files in os.walk(d):
                    for f in files:
                        full_path = Path(root) / f
                        zf.write(full_path, full_path.relative_to(base_dir))
    return backup_file

def backup_local(config_path: str = DEFAULT_CONFIG_PATH) -> Path:
    cfg_path = Path(config_path)
    base_dir = cfg_path.parent.parent
    target_dirs = [base_dir / 'config', base_dir / 'logs']
    backup_file = _zip_dirs(base_dir, target_dirs)
    logger.info(f'Backup local criado em {backup_file}')
    return backup_file

def upload_to_drive(file_path: Path, credentials_file: str):
    try:
        from google.oauth2.service_account import Credentials
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except Exception as e:
        logger.error(f'Bibliotecas do Google não disponíveis: {e}')
        return

    scopes = ['https://www.googleapis.com/auth/drive.file']
    creds = Credentials.from_service_account_file(credentials_file, scopes=scopes)
    service = build('drive', 'v3', credentials=creds)
    file_metadata = {'name': file_path.name}
    media = MediaFileUpload(str(file_path), resumable=False)
    service.files().create(body=file_metadata, media_body=media, fields='id').execute()
    logger.info('Backup enviado ao Google Drive.')

def backup_gdrive(config_path: str = DEFAULT_CONFIG_PATH) -> None:
    config = load_config(config_path)
    creds_file = config.get('google_drive', {}).get('credentials_file')
    if not creds_file:
        logger.error('Arquivo de credenciais do Google Drive não definido.')
        return
    backup_file = backup_local(config_path)
    upload_to_drive(backup_file, creds_file)

def main():
    parser = argparse.ArgumentParser(description='Gerenciador de backups SEI ANEEL')
    parser.add_argument('mode', choices=['local', 'gdrive'], help='Tipo de backup a executar')
    parser.add_argument('--config', default=DEFAULT_CONFIG_PATH, help='Caminho para configs.json')
    args = parser.parse_args()

    if args.mode == 'local':
        backup_local(args.config)
    else:
        backup_gdrive(args.config)

if __name__ == '__main__':
    main()
