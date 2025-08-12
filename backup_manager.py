"""Ferramentas para gerar backups locais ou no Google Drive."""

import argparse
import os
import zipfile
from datetime import datetime
from pathlib import Path
import logging
import tempfile

from sei_aneel.config import DEFAULT_CONFIG_PATH, load_config
from sei_aneel.log_utils import get_logger

logger = get_logger(__name__)

MAX_BACKUPS = 3


def _cleanup_old_backups(backup_dir: Path, max_backups: int = MAX_BACKUPS) -> None:
    backups = sorted(backup_dir.glob('sei_aneel_backup_*.zip'))
    for old in backups[:-max_backups]:
        try:
            old.unlink()
            logger.info(f'Removido backup antigo: {old}')
        except Exception as e:
            logger.warning(f'Falha ao remover {old}: {e}')

def _zip_dirs(
    base_dir: Path,
    target_dirs: list[Path] | None = None,
    exclude_dirs: list[Path] | None = None,
) -> Path:
    base_dir = base_dir.resolve()
    if target_dirs is None:
        target_dirs = [base_dir]
    exclude_dirs = [d.resolve() for d in (exclude_dirs or [])]

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_dir = base_dir / 'backups'
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_file = backup_dir / f'sei_aneel_backup_{timestamp}.zip'

    with zipfile.ZipFile(backup_file, 'w', zipfile.ZIP_DEFLATED) as zf:
        for d in target_dirs:
            if d.exists():
                for root, _, files in os.walk(d):
                    root_path = Path(root).resolve()
                    if any(str(root_path).startswith(str(ex)) for ex in exclude_dirs):
                        continue
                    for f in files:
                        full_path = root_path / f
                        zf.write(full_path, full_path.relative_to(base_dir))
    return backup_file

def backup_local(config_path: str = DEFAULT_CONFIG_PATH) -> Path:
    cfg_path = Path(config_path)
    base_dir = cfg_path.parent.parent
    backup_file = _zip_dirs(base_dir, exclude_dirs=[base_dir / 'backups'])
    logger.info(f'Backup local criado em {backup_file}')
    _cleanup_old_backups(backup_file.parent)
    return backup_file


def upload_to_drive(file_path: Path, credentials_file: str, folder_id: str, max_backups: int = MAX_BACKUPS):
    try:
        from google.oauth2.service_account import Credentials
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except Exception as e:
        logger.error(f'Bibliotecas do Google não disponíveis: {e}')
        return

    scopes = ['https://www.googleapis.com/auth/drive']
    creds = Credentials.from_service_account_file(credentials_file, scopes=scopes)
    service = build('drive', 'v3', credentials=creds)
    file_metadata = {'name': file_path.name, 'parents': [folder_id]}
    media = MediaFileUpload(str(file_path), resumable=False)
    service.files().create(
        body=file_metadata,
        media_body=media,
        fields='id',
        supportsAllDrives=True,
    ).execute()
    logger.info('Backup enviado ao Google Drive.')

    query = f"'{folder_id}' in parents and name contains 'sei_aneel_backup_'"
    results = service.files().list(
        q=query,
        spaces='drive',
        fields='files(id, name, createdTime)',
        supportsAllDrives=True,
        includeItemsFromAllDrives=True,
    ).execute()
    files = sorted(results.get('files', []), key=lambda x: x['createdTime'])
    for f in files[:-max_backups]:
        service.files().delete(fileId=f['id']).execute()
        logger.info(f"Backup antigo removido do Drive: {f['name']}")

def backup_gdrive(config_path: str = DEFAULT_CONFIG_PATH) -> None:
    config = load_config(config_path)
    creds_file = config.get('google_drive', {}).get('credentials_file')
    folder_id = config.get('google_drive', {}).get('backup_folder_id')
    if not creds_file or not folder_id:
        logger.error(
            'Credenciais do Google Drive ou ID da pasta de backup não definidos no arquivo de configuração.'
        )
        return
    backup_file = backup_local(config_path)
    upload_to_drive(backup_file, creds_file, folder_id)


def _restore_zip(zip_path: Path, base_dir: Path) -> None:
    """Extract ``zip_path`` into ``base_dir`` replacing existing files."""

    with zipfile.ZipFile(zip_path, 'r') as zf:
        zf.extractall(base_dir)
    logger.info(f'Backup restaurado a partir de {zip_path}')


def restore_local(config_path: str = DEFAULT_CONFIG_PATH) -> None:
    cfg_path = Path(config_path)
    base_dir = cfg_path.parent.parent
    backup_dir = base_dir / 'backups'
    backups = sorted(backup_dir.glob('sei_aneel_backup_*.zip'), reverse=True)
    if not backups:
        logger.error('Nenhum backup local encontrado.')
        return

    for idx, bkp in enumerate(backups, start=1):
        print(f"{idx}) {bkp.name}")

    choice = input('Selecione o backup: ')
    if not choice.isdigit() or int(choice) < 1 or int(choice) > len(backups):
        logger.error('Opção inválida.')
        return

    _restore_zip(backups[int(choice) - 1], base_dir)


def restore_gdrive(config_path: str = DEFAULT_CONFIG_PATH) -> None:
    config = load_config(config_path)
    creds_file = config.get('google_drive', {}).get('credentials_file')
    folder_id = config.get('google_drive', {}).get('backup_folder_id')
    if not creds_file or not folder_id:
        logger.error(
            'Credenciais do Google Drive ou ID da pasta de backup não definidos no arquivo de configuração.'
        )
        return

    try:
        from google.oauth2.service_account import Credentials
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaIoBaseDownload
    except Exception as e:
        logger.error(f'Bibliotecas do Google não disponíveis: {e}')
        return

    scopes = ['https://www.googleapis.com/auth/drive']
    creds = Credentials.from_service_account_file(creds_file, scopes=scopes)
    service = build('drive', 'v3', credentials=creds)

    query = f"'{folder_id}' in parents and name contains 'sei_aneel_backup_'"
    results = service.files().list(
        q=query,
        spaces='drive',
        fields='files(id, name, createdTime)',
        supportsAllDrives=True,
        includeItemsFromAllDrives=True,
    ).execute()
    files = sorted(results.get('files', []), key=lambda x: x['createdTime'], reverse=True)
    if not files:
        logger.error('Nenhum backup encontrado no Google Drive.')
        return

    for idx, f in enumerate(files, start=1):
        created = f.get('createdTime', '')[:19].replace('T', ' ')
        print(f"{idx}) {f['name']} ({created})")

    choice = input('Selecione o backup: ')
    if not choice.isdigit() or int(choice) < 1 or int(choice) > len(files):
        logger.error('Opção inválida.')
        return

    selected = files[int(choice) - 1]
    request = service.files().get_media(fileId=selected['id'])
    fd, tmp_path = tempfile.mkstemp(suffix='.zip')
    try:
        with os.fdopen(fd, 'wb') as fh:
            downloader = MediaIoBaseDownload(fh, request)
            done = False
            while not done:
                _, done = downloader.next_chunk()

        cfg_path = Path(config_path)
        base_dir = cfg_path.parent.parent
        _restore_zip(Path(tmp_path), base_dir)
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


def restore_menu(config_path: str = DEFAULT_CONFIG_PATH) -> None:
    print('1) Backup local')
    print('2) Backup Google Drive')
    op = input('Opção: ')
    if op == '1':
        restore_local(config_path)
    elif op == '2':
        restore_gdrive(config_path)
    else:
        logger.error('Opção inválida.')

def main():
    parser = argparse.ArgumentParser(description='Gerenciador de backups PAINEEL')
    parser.add_argument(
        'mode',
        choices=['local', 'gdrive', 'restore'],
        help='Ação a executar: gerar backup local, no Google Drive ou restaurar',
    )
    parser.add_argument('--config', default=DEFAULT_CONFIG_PATH, help='Caminho para configs.json')
    args = parser.parse_args()

    if args.mode == 'local':
        backup_local(args.config)
    elif args.mode == 'gdrive':
        backup_gdrive(args.config)
    else:
        restore_menu(args.config)

if __name__ == '__main__':
    main()
