#!/bin/bash
# Atualiza o projeto SEI ANEEL preservando as configuracoes de conexao,
# termos de pesquisa e agendamentos do cron.
set -e

REPO_URL="https://github.com/aryabdo/sei-aneel.git"
TARGET_DIR="/opt/sei-aneel"
LOCAL_REPO="$HOME/sei-aneel"
CONFIG_DIR="$TARGET_DIR/config"
CONFIG_FILE="$CONFIG_DIR/configs.json"

PAUTA_DIR="/opt/pauta-aneel"
PAUTA_LOG_DIR="$PAUTA_DIR/logs"
SORTEIO_DIR="/opt/sorteio-aneel"
SORTEIO_LOG_DIR="$SORTEIO_DIR/logs"

# cria diretório temporário para backup
TEMP_DIR=$(mktemp -d)
CRON_BACKUP="$TEMP_DIR/cron.bak"

# copia configuracoes existentes, se houver
if [ -d "$CONFIG_DIR" ]; then
  cp -a "$CONFIG_DIR" "$TEMP_DIR/" 2>/dev/null
fi

# salva crontab existente, se houver
crontab -l 2>/dev/null > "$CRON_BACKUP"

# garante que não estamos dentro do diretório a ser removido
cd /

# remove instalações antigas e cópia local
sudo rm -rf "$TARGET_DIR" "$PAUTA_DIR" "$SORTEIO_DIR"
rm -rf "$LOCAL_REPO"

# confirma remoção
if [ -d "$TARGET_DIR" ] || [ -d "$PAUTA_DIR" ] || [ -d "$SORTEIO_DIR" ] || [ -d "$LOCAL_REPO" ]; then
  echo "Erro: diretórios antigos não foram removidos." >&2
  exit 1
else
  echo "Diretórios antigos removidos."
fi

# garante que git está instalado
if ! command -v git >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y git
fi

# clona repositório na pasta do usuário
git clone "$REPO_URL" "$LOCAL_REPO"

# verifica clone
if [ ! -d "$LOCAL_REPO/.git" ]; then
  echo "Erro: falha ao clonar repositório." >&2
  exit 1
else
  echo "Repositório clonado em $LOCAL_REPO."
fi

# copia para diretório de instalação
sudo mkdir -p "$TARGET_DIR"
sudo cp -a "$LOCAL_REPO"/. "$TARGET_DIR/"

if [ ! -f "$TARGET_DIR/sei-aneel.py" ]; then
  echo "Erro: cópia para $TARGET_DIR falhou." >&2
  exit 1
fi

# restaura configuracoes
if [ -d "$TEMP_DIR/config" ]; then
  sudo rm -rf "$CONFIG_DIR"
  sudo mv "$TEMP_DIR/config" "$CONFIG_DIR"
  cp -a "$CONFIG_DIR" "$LOCAL_REPO/" 2>/dev/null
  echo "Configurações restauradas."
fi

# instala dependências do sistema e python
sudo apt-get update
sudo apt-get install -y python3 python3-pip tesseract-ocr chromium-browser chromium-chromedriver
sudo pip3 install --break-system-packages -r "$TARGET_DIR/requirements.txt"

# instala/atualiza módulos adicionais
sudo mkdir -p "$PAUTA_DIR" "$PAUTA_LOG_DIR"
sudo cp "$LOCAL_REPO/pauta_aneel/pauta_aneel.py" "$PAUTA_DIR/"
sudo cp "$LOCAL_REPO/requirements.txt" "$PAUTA_DIR/"
sudo chown -R "$USER":"$USER" "$PAUTA_DIR"
sudo pip3 install --break-system-packages -r "$PAUTA_DIR/requirements.txt"
cat <<RUN | sudo tee "$PAUTA_DIR/run.sh" >/dev/null
#!/bin/bash
DIR="\$(dirname "\$0")"
cd "\$DIR"
export SEI_ANEEL_CONFIG="$CONFIG_FILE"
PAUTA_DATA_DIR="\$DIR"
PAUTA_LOG_FILE="\$DIR/logs/pauta_aneel.log"
XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp}
PYTHONPATH="$TARGET_DIR:\$PYTHONPATH" python3 "\$DIR/pauta_aneel.py" "\$@"
RUN
sudo chmod +x "$PAUTA_DIR/run.sh"

sudo mkdir -p "$SORTEIO_DIR" "$SORTEIO_LOG_DIR"
sudo cp "$LOCAL_REPO/sorteio_aneel/sorteio_aneel.py" "$SORTEIO_DIR/"
sudo cp "$LOCAL_REPO/requirements.txt" "$SORTEIO_DIR/"
sudo chown -R "$USER":"$USER" "$SORTEIO_DIR"
sudo pip3 install --break-system-packages -r "$SORTEIO_DIR/requirements.txt"
cat <<RUN | sudo tee "$SORTEIO_DIR/run.sh" >/dev/null
#!/bin/bash
DIR="\$(dirname "\$0")"
cd "\$DIR"
export SEI_ANEEL_CONFIG="$CONFIG_FILE"
SORTEIO_DATA_DIR="\$DIR"
SORTEIO_LOG_FILE="\$DIR/logs/sorteio_aneel.log"
PYTHONPATH="$TARGET_DIR:\$PYTHONPATH" python3 "\$DIR/sorteio_aneel.py" "\$@"
RUN
sudo chmod +x "$SORTEIO_DIR/run.sh"

if [ -f "$PAUTA_DIR/run.sh" ] && [ -f "$SORTEIO_DIR/run.sh" ]; then
  echo "Módulos instalados com sucesso."
else
  echo "Erro: instalação dos módulos falhou." >&2
  exit 1
fi

# restaura crontab se existir
if [ -s "$CRON_BACKUP" ]; then
  crontab "$CRON_BACKUP"
fi

# ajusta permissões
sudo chown -R "$USER":"$USER" "$TARGET_DIR" "$PAUTA_DIR" "$SORTEIO_DIR"

# limpa temporários
rm -rf "$TEMP_DIR"

echo "Atualização global concluída."
