#!/bin/bash
# Atualiza o projeto SEI ANEEL preservando o arquivo de configuração

REPO_URL="https://github.com/aryabdo/sei-aneel.git"
TARGET_DIR="/opt/sei-aneel"
CONFIG_DIR="$TARGET_DIR/config"

# cria diretório temporário para backup
TEMP_DIR=$(mktemp -d)
CRON_BACKUP="$TEMP_DIR/cron.bak"

if [ -d "$CONFIG_DIR" ]; then
  cp -r "$CONFIG_DIR" "$TEMP_DIR/" 2>/dev/null
fi

# salva crontab existente, se houver
crontab -l 2>/dev/null > "$CRON_BACKUP"

# garante que não estamos dentro do diretório a ser removido
cd /

# remove instalação antiga
sudo rm -rf "$TARGET_DIR"

# clona nova versão
sudo git clone "$REPO_URL" "$TARGET_DIR"

# restaura configurações
if [ -d "$TEMP_DIR/config" ]; then
  sudo rm -rf "$CONFIG_DIR"
  sudo mv "$TEMP_DIR/config" "$CONFIG_DIR"
fi

# instala dependências
sudo pip3 install --break-system-packages -r "$TARGET_DIR/requirements.txt"

# restaura crontab se existir
if [ -s "$CRON_BACKUP" ]; then
  crontab "$CRON_BACKUP"
fi

# ajusta permissões
sudo chown -R "$USER":"$USER" "$TARGET_DIR"

rm -rf "$TEMP_DIR"

echo "Atualização concluída."
