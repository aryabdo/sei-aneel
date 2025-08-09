#!/bin/bash
# Atualiza o projeto SEI ANEEL preservando o arquivo de configuração

REPO_URL="https://github.com/aryabdo/sei-aneel.git"
TARGET_DIR="/opt/sei-aneel"
CONFIG_DIR="$TARGET_DIR/config"

# cria diretório temporário para backup
TEMP_DIR=$(mktemp -d)

if [ -d "$CONFIG_DIR" ]; then
  cp -r "$CONFIG_DIR" "$TEMP_DIR/" 2>/dev/null
fi

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

rm -rf "$TEMP_DIR"

# ajusta permissões
sudo chown -R "$USER":"$USER" "$TARGET_DIR"

echo "Atualização concluída."
