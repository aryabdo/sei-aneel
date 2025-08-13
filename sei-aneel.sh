#!/bin/bash
set -euo pipefail
# Cores para saída colorida
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
NC='\e[0m'

SCRIPT_DIR="/opt/sei-aneel"
CONFIG_DIR="$SCRIPT_DIR/config"
CONFIG_FILE="$CONFIG_DIR/configs.json"
TERMS_FILE="$CONFIG_DIR/search_terms.txt"
LOG_DIR="$SCRIPT_DIR/logs"
REPO_URL="https://github.com/aryabdo/sei-aneel.git"
UPDATE_SCRIPT="$SCRIPT_DIR/update_repo.sh"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# garante que o diretório de logs principal exista
mkdir -p "$LOG_DIR"

# Arquivo de log do script e utilitários de interface
SCRIPT_LOG_FILE="$LOG_DIR/sei-aneel.log"

log() {
  mkdir -p "$LOG_DIR"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ${1:-}" >> "$SCRIPT_LOG_FILE"
}

show_header() {
  local title="${1:-}"
  clear
  echo -e "${BLUE}================================${NC}"
  echo -e "${BLUE}        PAINEEL - ${title}        ${NC}"
  echo -e "${BLUE}================================${NC}"
}

# Pausa a execução até que o usuário pressione Enter
pause() {
  read -p $'\e[33mPressione Enter para continuar...\e[0m'
}

# Usuário ativo no terminal (considera execução via sudo)
CURRENT_USER="${USER:-$(whoami)}"
ACTIVE_USER="${SUDO_USER:-$CURRENT_USER}"
CRONTAB_CMD="crontab"
if [ "$CURRENT_USER" = "root" ]; then
  CRONTAB_CMD="crontab -u $ACTIVE_USER"
fi

export PAINEEL_CONFIG="$CONFIG_FILE"

# Diretórios para módulos adicionais
PAUTA_DIR="/opt/pauta-aneel"
PAUTA_LOG_DIR="$PAUTA_DIR/logs"

SORTEIO_DIR="/opt/sorteio-aneel"
SORTEIO_LOG_DIR="$SORTEIO_DIR/logs"

# garante que os diretórios de log dos módulos existam
mkdir -p "$PAUTA_LOG_DIR" "$SORTEIO_LOG_DIR"

install_sei() {
  log "Iniciando instalação do PAINEEL"
  read -p "Caminho do credentials.json: " CRED
  read -p "Chave API 2captcha: " CAPTCHA
  read -p "Servidor SMTP: " SMTP_SERVER
  read -p "Porta SMTP [587]: " SMTP_PORT
  SMTP_PORT=${SMTP_PORT:-587}
  read -p "Usuário SMTP: " SMTP_USER
  read -s -p "Senha SMTP: " SMTP_PASS; echo
  read -p "Usar STARTTLS? (y/N): " SMTP_TLS
  read -p "Emails destinatários (separados por vírgula): " EMAILS

  sudo rm -rf "$SCRIPT_DIR"
  sudo mkdir -p "$SCRIPT_DIR" "$LOG_DIR" "$CONFIG_DIR"
  sudo cp -r sei_aneel "$SCRIPT_DIR/"
  sudo cp sei-aneel.py manage_processes.py backup_manager.py test_connectivity.py requirements.txt update_repo.sh "$SCRIPT_DIR/"
  sudo cp "$CRED" "$CONFIG_DIR/credentials.json"
  sudo chown -R "$ACTIVE_USER":"$ACTIVE_USER" "$SCRIPT_DIR"

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip tesseract-ocr chromium-browser chromium-chromedriver
  sudo pip3 install --break-system-packages -r "$SCRIPT_DIR/requirements.txt"

  STARTTLS=false
  [[ "${SMTP_TLS,,}" == "y" ]] && STARTTLS=true

  IFS=',' read -ra ADDR <<< "$EMAILS"
  EMAIL_JSON=$(printf '"%s",' "${ADDR[@]}")
  EMAIL_JSON="${EMAIL_JSON%,}"

  cat <<CFG > "$CONFIG_FILE"
{
  "smtp": {
    "server": "$SMTP_SERVER",
    "port": $SMTP_PORT,
    "user": "$SMTP_USER",
    "password": "$SMTP_PASS",
    "starttls": $STARTTLS
  },
  "twocaptcha": {"api_key": "$CAPTCHA"},
  "google_drive": {
    "credentials_file": "$CONFIG_DIR/credentials.json",
    "sheet_name": "Processos ANEEL",
    "worksheet_name": "Processos"
  },
  "email": {"recipients": [$EMAIL_JSON]},
  "paths": {
    "tesseract": "/usr/bin/tesseract",
    "chromedriver": "/usr/bin/chromedriver",
    "chrome_binary": "/usr/bin/chromium-browser"
  },
  "execution": {
    "captcha_max_tries": 5,
    "max_retry_attempts": 5
  },
  "logging": {"level": "INFO"}
}
CFG

  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'sei-aneel.py' | $CRONTAB_CMD -
  echo -e "${GREEN}Instalação concluída.${NC}"
  log "Instalação do PAINEEL concluída"
}

remove_sei() {
  log "Removendo PAINEEL"
  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'sei-aneel.py' | $CRONTAB_CMD -
  sudo rm -rf "$SCRIPT_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
  log "PAINEEL removido"
}

install_pauta() {
  log "Iniciando instalação da Pauta ANEEL"
  sudo rm -rf "$PAUTA_DIR"
  sudo mkdir -p "$PAUTA_LOG_DIR"
  sudo cp sei_aneel/pauta_aneel/pauta_aneel.py "$PAUTA_DIR/"
  sudo cp requirements.txt "$PAUTA_DIR/"
  sudo chown -R "$ACTIVE_USER":"$ACTIVE_USER" "$PAUTA_DIR"

  sudo mkdir -p "$SCRIPT_DIR"
  sudo cp -r sei_aneel "$SCRIPT_DIR/" 2>/dev/null

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
  sudo pip3 install --break-system-packages -r "$PAUTA_DIR/requirements.txt"

cat <<RUN > "$PAUTA_DIR/run.sh"
#!/bin/bash
DIR="\$(dirname "\$0")"
cd "\$DIR"
mkdir -p "\$DIR/logs"
export PAINEEL_CONFIG="$CONFIG_FILE"
PAUTA_DATA_DIR="\$DIR"
PAUTA_LOG_FILE="\$DIR/logs/pauta_aneel.log"
XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp}
PYTHONPATH="$SCRIPT_DIR:\${PYTHONPATH:-}" python3 "\$DIR/pauta_aneel.py" "\$@"
RUN
  chmod +x "$PAUTA_DIR/run.sh"

  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'pauta_aneel.py' | $CRONTAB_CMD -
  echo -e "${GREEN}Instalação concluída.${NC}"
  log "Instalação da Pauta ANEEL concluída"
}

update_pauta() {
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' RETURN
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo rm -rf "$PAUTA_DIR"
  sudo mkdir -p "$PAUTA_DIR" "$PAUTA_LOG_DIR"
  sudo cp "$TMP_DIR/sei_aneel/pauta_aneel/pauta_aneel.py" "$PAUTA_DIR/"
  sudo cp "$TMP_DIR/requirements.txt" "$PAUTA_DIR/"
  sudo chown -R "$ACTIVE_USER":"$ACTIVE_USER" "$PAUTA_DIR"
  sudo pip3 install --break-system-packages -r "$PAUTA_DIR/requirements.txt"
  cat <<RUN > "$PAUTA_DIR/run.sh"
#!/bin/bash
DIR="\$(dirname "\$0")"
cd "\$DIR"
mkdir -p "\$DIR/logs"
export PAINEEL_CONFIG="$CONFIG_FILE"
PAUTA_DATA_DIR="\$DIR"
PAUTA_LOG_FILE="\$DIR/logs/pauta_aneel.log"
XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp}
PYTHONPATH="$SCRIPT_DIR:\${PYTHONPATH:-}" python3 "\$DIR/pauta_aneel.py" "\$@"
RUN
  chmod +x "$PAUTA_DIR/run.sh"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_pauta() {
  log "Removendo Pauta ANEEL"
  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'pauta_aneel.py' | $CRONTAB_CMD -
  sudo rm -rf "$PAUTA_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
  log "Pauta ANEEL removida"
}


force_run_pauta() {
  DEFAULT_DATE=$(date +%d/%m/%Y)
  read -p $'\e[33mData da busca (dd/mm/aaaa) ['"$DEFAULT_DATE"$']: \e[0m' DATA
  DATA=${DATA:-$DEFAULT_DATE}
  log "Execução manual da Pauta ANEEL em $DATA"
  if [ -x "$PAUTA_DIR/run.sh" ]; then
    mkdir -p "$PAUTA_LOG_DIR"
    log_file="$PAUTA_LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
    "$PAUTA_DIR/run.sh" "$DATA" | tee "$log_file"
  else
    local_log_dir="$REPO_DIR/logs/pauta-aneel"
    mkdir -p "$local_log_dir"
    log_file="$local_log_dir/exec_$(date +%Y%m%d_%H%M%S).log"
    PYTHONPATH="$REPO_DIR:${PYTHONPATH:-}" PAINEEL_CONFIG="$CONFIG_FILE" \
      python3 "$REPO_DIR/sei_aneel/pauta_aneel/pauta_aneel.py" "$DATA" | tee "$log_file"
  fi
}

install_sorteio() {
  log "Iniciando instalação do Sorteio ANEEL"
  sudo rm -rf "$SORTEIO_DIR"
  sudo mkdir -p "$SORTEIO_LOG_DIR"
  sudo cp sei_aneel/sorteio_aneel/sorteio_aneel.py "$SORTEIO_DIR/"
  sudo cp requirements.txt "$SORTEIO_DIR/"
  sudo chown -R "$ACTIVE_USER":"$ACTIVE_USER" "$SORTEIO_DIR"

  sudo mkdir -p "$SCRIPT_DIR"
  sudo cp -r sei_aneel "$SCRIPT_DIR/" 2>/dev/null

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
  sudo pip3 install --break-system-packages -r "$SORTEIO_DIR/requirements.txt"

cat <<RUN > "$SORTEIO_DIR/run.sh"
#!/bin/bash

DIR="\$(dirname "\$0")"
cd "\$DIR"
mkdir -p "\$DIR/logs"
export PAINEEL_CONFIG="$CONFIG_FILE"
SORTEIO_DATA_DIR="\$DIR"
SORTEIO_LOG_FILE="\$DIR/logs/sorteio_aneel.log"
PYTHONPATH="$SCRIPT_DIR:\${PYTHONPATH:-}" python3 "\$DIR/sorteio_aneel.py" "\$@"
RUN
  chmod +x "$SORTEIO_DIR/run.sh"

  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'sorteio_aneel.py' | $CRONTAB_CMD -
  echo -e "${GREEN}Instalação concluída.${NC}"
  log "Instalação do Sorteio ANEEL concluída"
}

update_sorteio() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo rm -rf "$SORTEIO_DIR"
  sudo mkdir -p "$SORTEIO_DIR" "$SORTEIO_LOG_DIR"
  sudo cp "$TMP_DIR/sei_aneel/sorteio_aneel/sorteio_aneel.py" "$SORTEIO_DIR/"
  sudo cp "$TMP_DIR/requirements.txt" "$SORTEIO_DIR/"
  sudo chown -R "$ACTIVE_USER":"$ACTIVE_USER" "$SORTEIO_DIR"
  sudo pip3 install --break-system-packages -r "$SORTEIO_DIR/requirements.txt"
cat <<RUN > "$SORTEIO_DIR/run.sh"
#!/bin/bash

DIR="\$(dirname "\$0")"
cd "\$DIR"
mkdir -p "\$DIR/logs"
export PAINEEL_CONFIG="$CONFIG_FILE"
SORTEIO_DATA_DIR="\$DIR"
SORTEIO_LOG_FILE="\$DIR/logs/sorteio_aneel.log"
PYTHONPATH="$SCRIPT_DIR:\${PYTHONPATH:-}" python3 "\$DIR/sorteio_aneel.py" "\$@"
RUN
  chmod +x "$SORTEIO_DIR/run.sh"
  rm -rf "$TMP_DIR"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_sorteio() {
  log "Removendo Sorteio ANEEL"
  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'sorteio_aneel.py' | $CRONTAB_CMD -
  sudo rm -rf "$SORTEIO_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
  log "Sorteio ANEEL removido"
}

# Instalação global e utilitários
install_all_modules() {
  install_sei
  install_pauta
  install_sorteio
}

select_install_menu() {
  while true; do
    echo -e "${CYAN}1) PAINEEL${NC}"
    echo -e "${CYAN}2) Pauta ANEEL${NC}"
    echo -e "${CYAN}3) Sorteio ANEEL${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) install_sei; pause ;;
      2) install_pauta; pause ;;
      3) install_sorteio; pause ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

install_dependencies_only() {
  sudo apt-get update
  sudo apt-get install -y python3 python3-pip tesseract-ocr chromium-browser chromium-chromedriver
  sudo pip3 install --break-system-packages -r requirements.txt
  sudo mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$PAUTA_DIR" "$PAUTA_LOG_DIR" "$SORTEIO_DIR" "$SORTEIO_LOG_DIR"
  sudo touch "$CONFIG_FILE"
  sudo chown -R "$ACTIVE_USER":"$ACTIVE_USER" "$SCRIPT_DIR" "$PAUTA_DIR" "$SORTEIO_DIR"
  echo -e "${GREEN}Dependências instaladas.${NC}"
}

update_global() {
  if [ -f "$UPDATE_SCRIPT" ]; then
    sudo bash "$UPDATE_SCRIPT"
  else
    echo -e "${RED}Script de atualização não encontrado em $UPDATE_SCRIPT.${NC}"
  fi
}

remove_all_modules() {
  remove_sei
  remove_pauta
  remove_sorteio
}

installation_menu() {
  while true; do
    show_header "Instalação"
    echo -e "${CYAN}1) Instalar todos módulos${NC}"
    echo -e "${CYAN}2) Selecionar módulos${NC}"
    echo -e "${CYAN}3) Dependências${NC}"
    echo -e "${CYAN}4) Atualização Global${NC}"
    echo -e "${CYAN}5) Remoção${NC}"
    echo -e "${CYAN}6) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) install_all_modules; pause ;;
      2) select_install_menu; pause ;;
      3) install_dependencies_only; pause ;;
      4) update_global; pause ;;
      5) remove_all_modules; pause ;;
      6) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}


force_run_sorteio() {
  DEFAULT_DATE=$(date +%d/%m/%Y)
  read -p $'\e[33mData da busca (dd/mm/aaaa) ['"$DEFAULT_DATE"$']: \e[0m' DATA
  DATA=${DATA:-$DEFAULT_DATE}
  log "Execução manual do Sorteio ANEEL em $DATA"
  if [ -x "$SORTEIO_DIR/run.sh" ]; then
    mkdir -p "$SORTEIO_LOG_DIR"
    log_file="$SORTEIO_LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
    "$SORTEIO_DIR/run.sh" "$DATA" | tee "$log_file"
  else
    local_log_dir="$REPO_DIR/logs/sorteio-aneel"
    mkdir -p "$local_log_dir"
    log_file="$local_log_dir/exec_$(date +%Y%m%d_%H%M%S).log"
    PYTHONPATH="$REPO_DIR:${PYTHONPATH:-}" PAINEEL_CONFIG="$CONFIG_FILE" \
      python3 "$REPO_DIR/sei_aneel/sorteio_aneel/sorteio_aneel.py" "$DATA" | tee "$log_file"
  fi
}


config_twocaptcha() {
  read -p "Nova chave 2captcha: " KEY
  python3 - "$CONFIG_FILE" "$KEY" <<'PY'
import json,sys
path, key = sys.argv[1:3]
with open(path) as f: data=json.load(f)
data.setdefault('twocaptcha',{})['api_key']=key
with open(path,'w') as f: json.dump(data,f,indent=2)
PY
}

config_smtp() {
  read -p "Servidor SMTP: " S
  read -p "Porta [587]: " P; P=${P:-587}
  read -p "Usuário: " U
  read -s -p "Senha: " PW; echo
  read -p "Usar STARTTLS? (y/N): " TLS
  python3 - "$CONFIG_FILE" "$S" "$P" "$U" "$PW" "$TLS" <<'PY'
import json,sys
path,server,port,user,pw,tls=sys.argv[1:7]
with open(path) as f: data=json.load(f)
smtp=data.setdefault('smtp',{})
smtp.update({'server':server,'port':int(port), 'user':user, 'password':pw, 'starttls': tls.lower()=='y'})
with open(path,'w') as f: json.dump(data,f,indent=2)
PY
}

config_google() {
  read -p "Caminho credentials.json: " C
  read -p "Nome da planilha [Processos ANEEL]: " SN; SN=${SN:-Processos ANEEL}
  read -p "Nome da aba [Processos]: " WS; WS=${WS:-Processos}
  read -p "ID da pasta de backup no Drive: " BF
  sudo cp "$C" "$CONFIG_DIR/credentials.json"
  python3 - "$CONFIG_FILE" "$CONFIG_DIR/credentials.json" "$SN" "$WS" "$BF" <<'PY'
import json,sys
path,cred,sheet,ws,bf=sys.argv[1:6]
with open(path) as f: data=json.load(f)
GD=data.setdefault('google_drive',{})
GD.update({'credentials_file':cred,'sheet_name':sheet,'worksheet_name':ws,'backup_folder_id':bf})
with open(path,'w') as f: json.dump(data,f,indent=2)
PY
}

config_exec() {
  read -p "Tentativas captcha [5]: " C; C=${C:-5}
  read -p "Tentativas reprocessamento [5]: " R; R=${R:-5}
  python3 - "$CONFIG_FILE" "$C" "$R" <<'PY'
import json,sys
path,c,r=sys.argv[1:4]
with open(path) as f: data=json.load(f)
ex=data.setdefault('execution',{})
ex.update({'captcha_max_tries':int(c),'max_retry_attempts':int(r)})
with open(path,'w') as f: json.dump(data,f,indent=2)
PY
}

add_email() {
  read -p "Email para adicionar: " EM
  python3 - "$CONFIG_FILE" "$EM" <<'PY'
import json,sys
path,email=sys.argv[1:3]
with open(path) as f: data=json.load(f)
rec=data.setdefault('email',{}).setdefault('recipients',[])
if email not in rec:
    rec.append(email)
with open(path,'w') as f: json.dump(data,f,indent=2)
PY
}

remove_email() {
  read -p "Email para remover: " EM
  python3 - "$CONFIG_FILE" "$EM" <<'PY'
import json,sys
path,email=sys.argv[1:3]
with open(path) as f: data=json.load(f)
rec=data.setdefault('email',{}).setdefault('recipients',[])
if email in rec:
    rec.remove(email)
with open(path,'w') as f: json.dump(data,f,indent=2)
PY
}

list_emails() {
  python3 - "$CONFIG_FILE" <<'PY'
import json,sys
path=sys.argv[1]
with open(path) as f: data=json.load(f)
for e in data.get('email',{}).get('recipients',[]):
    print(e)
PY
}

manage_emails() {
  while true; do
    show_header "Gerenciar Emails"
    echo -e "${CYAN}1) Listar${NC}"
    echo -e "${CYAN}2) Adicionar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) list_emails; pause ;;
      2) add_email; pause ;;
      3) remove_email; pause ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

manage_processes_menu() {
  while true; do
    show_header "Gerenciar processos"
    echo -e "${CYAN}1) Adicionar processo${NC}"
    echo -e "${CYAN}2) Remover processo${NC}"
    echo -e "${CYAN}3) Atualizar processo${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) read -p "Número: " N; python3 "$SCRIPT_DIR/manage_processes.py" add "$N"; pause ;;
      2) read -p "Número: " N; python3 "$SCRIPT_DIR/manage_processes.py" remove "$N"; pause ;;
      3) read -p "Número antigo: " O; read -p "Número novo: " N; python3 "$SCRIPT_DIR/manage_processes.py" update "$O" "$N"; pause ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

force_run() {
  while true; do
    show_header "Execução Manual"
    echo -e "${CYAN}1) Executar todos os processos${NC}"
    echo -e "${CYAN}2) Executar processos específicos${NC}"
    echo -e "${CYAN}3) Enviar tabela por email${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    log_file="$LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
    case $op in
      1) log "Execução manual: todos os processos"; python3 "$SCRIPT_DIR/sei-aneel.py" | tee "$log_file"; pause ;;
      2) read -p $'\e[33mNúmero(s) de processo (separados por espaço): \e[0m' PROC; log "Execução manual: processos $PROC"; python3 "$SCRIPT_DIR/sei-aneel.py" --processo $PROC | tee "$log_file"; pause ;;
      3) log "Execução manual: envio de tabela por email"; python3 "$SCRIPT_DIR/sei-aneel.py" --email-tabela | tee "$log_file"; pause ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

# Helpers para selecionar campos de agendamento
select_minutes() {
  echo -e "${CYAN}Minutos:${NC}" >&2
  echo "1) 0" >&2
  echo "2) */15 (a cada 15 minutos)" >&2
  echo "3) Personalizado" >&2
  read -p $'\e[33mOpção [1]: \e[0m' choice
  case $choice in
    2) echo "*/15" ;;
    3) read -p "Informe minutos (ex: 0,30): " custom; echo "$custom" ;;
    *) echo "0" ;;
  esac
}

select_hours() {
  echo -e "${CYAN}Horas:${NC}" >&2
  echo "1) * (todas)" >&2
  echo "2) Horário comercial (8-18)" >&2
  echo "3) Personalizado" >&2
  read -p $'\e[33mOpção [1]: \e[0m' choice
  case $choice in
    2) echo "8-18" ;;
    3) read -p "Informe horas (ex: 0,12): " custom; echo "$custom" ;;
    *) echo "*" ;;
  esac
}

select_monthdays() {
  echo -e "${CYAN}Dias do mês:${NC}" >&2
  echo "1) *" >&2
  echo "2) Dia 1" >&2
  echo "3) Personalizado" >&2
  read -p $'\e[33mOpção [1]: \e[0m' choice
  case $choice in
    2) echo "1" ;;
    3) read -p "Informe dias (ex: 1-31): " custom; echo "$custom" ;;
    *) echo "*" ;;
  esac
}

select_months() {
  echo -e "${CYAN}Meses:${NC}" >&2
  echo "1) *" >&2
  echo "2) Janeiro-Dezembro (1-12)" >&2
  echo "3) Personalizado" >&2
  read -p $'\e[33mOpção [1]: \e[0m' choice
  case $choice in
    2) echo "1-12" ;;
    3) read -p "Informe meses (ex: 1,6,12): " custom; echo "$custom" ;;
    *) echo "*" ;;
  esac
}

select_weekdays() {
  echo -e "${CYAN}Dias da semana:${NC}" >&2
  echo "1) *" >&2
  echo "2) Segunda a Sexta" >&2
  echo "3) Quarta e Sexta" >&2
  echo "4) Sexta a Segunda" >&2
  echo "5) Personalizado" >&2
  read -p $'\e[33mOpção [1]: \e[0m' choice
  case $choice in
    2) echo "1-5" ;;
    3) echo "3,5" ;;
    4) echo "5,6,0,1" ;;
    5) echo "Use números 0-6 (0=Domingo)." >&2; read -p "Informe dias (ex: 1-3): " custom; echo "$custom" ;;
    *) echo "*" ;;
  esac
}

schedule_cron() {
  MIN=$(select_minutes)
  H=$(select_hours)
  M=$(select_monthdays)
  MO=$(select_months)
  D=$(select_weekdays)
  echo -e "${CYAN}Scripts para agendar (separados por espaço):${NC}"
  echo -e "${CYAN}1) PAINEEL${NC}"
  echo -e "${CYAN}2) Pauta ANEEL${NC}"
  echo -e "${CYAN}3) Sorteio ANEEL${NC}"
  read -p $'\e[33mOpções: \e[0m' OPTS
  local CURRENT
  CURRENT=$($CRONTAB_CMD -l 2>/dev/null || true)
  for op in $OPTS; do
    case $op in
      1)
        CURRENT=$(echo "$CURRENT" | grep -v 'sei-aneel.py')
        CURRENT="$CURRENT\n$MIN $H $M $MO $D /usr/bin/python3 $SCRIPT_DIR/sei-aneel.py >> $LOG_DIR/cron.log 2>&1"
        ;;
      2)
        CURRENT=$(echo "$CURRENT" | grep -v 'pauta_aneel.py')
        if [ -x "$PAUTA_DIR/run.sh" ]; then
          CURRENT="$CURRENT\n$MIN $H $M $MO $D $PAUTA_DIR/run.sh \$(date +\%d/\%m/\%Y) >> $PAUTA_LOG_DIR/cron.log 2>&1"
        else
          local_log_dir="$REPO_DIR/logs/pauta-aneel"
          mkdir -p "$local_log_dir"
          CURRENT="$CURRENT\n$MIN $H $M $MO $D /usr/bin/python3 $REPO_DIR/sei_aneel/pauta_aneel/pauta_aneel.py \$(date +\%d/\%m/\%Y) >> $local_log_dir/cron.log 2>&1"
        fi
        ;;
      3)
        CURRENT=$(echo "$CURRENT" | grep -v 'sorteio_aneel.py')
        if [ -x "$SORTEIO_DIR/run.sh" ]; then
          CURRENT="$CURRENT\n$MIN $H $M $MO $D $SORTEIO_DIR/run.sh \$(date +\%d/\%m/\%Y) >> $SORTEIO_LOG_DIR/cron.log 2>&1"
        else
          local_log_dir="$REPO_DIR/logs/sorteio-aneel"
          mkdir -p "$local_log_dir"
          CURRENT="$CURRENT\n$MIN $H $M $MO $D /usr/bin/python3 $REPO_DIR/sei_aneel/sorteio_aneel/sorteio_aneel.py \$(date +\%d/\%m/\%Y) >> $local_log_dir/cron.log 2>&1"
        fi
        ;;
      *)
        echo -e "${RED}Opção inválida: $op${NC}"
        ;;
    esac
  done
  echo -e "$CURRENT" | sed '/^$/d' | $CRONTAB_CMD -
  echo -e "${GREEN}Cron agendado.${NC}"
}

list_cron() {
  local found=false
  while IFS=: read -r user _; do
    local entries
    entries=$(crontab -u "$user" -l 2>/dev/null || true)
    if [ -n "$entries" ]; then
      found=true
      echo -e "${CYAN}Usuário: $user${NC}"
      echo "$entries"
    fi
  done < /etc/passwd
  if [ -f /etc/crontab ]; then
    found=true
    echo -e "${CYAN}Arquivo /etc/crontab:${NC}"
    cat /etc/crontab
  fi
  for f in /etc/cron.d/*; do
    [ -f "$f" ] || continue
    found=true
    echo -e "${CYAN}Arquivo $f:${NC}"
    cat "$f"
  done
  if [ "$found" = false ]; then
    echo -e "${YELLOW}Nenhum agendamento encontrado.${NC}"
  fi
}

remove_cron() {
  mapfile -t ENTRIES < <($CRONTAB_CMD -l 2>/dev/null | grep -E '(sei-aneel.py|pauta_aneel.py|sorteio_aneel.py)' || true)
  if [ ${#ENTRIES[@]} -eq 0 ]; then
    echo -e "${YELLOW}Nenhum agendamento encontrado.${NC}"
    return
  fi
  list_cron
  read -p $'\e[33mNúmero do agendamento a excluir: \e[0m' IDX
  if [[ "$IDX" =~ ^[0-9]+$ ]] && [ "$IDX" -ge 1 ] && [ "$IDX" -le "${#ENTRIES[@]}" ]; then
    local LINE="${ENTRIES[$IDX-1]}"
    ($CRONTAB_CMD -l 2>/dev/null || true) | grep -vF "$LINE" | $CRONTAB_CMD -
    echo -e "${GREEN}Agendamento removido.${NC}"
  else
    echo -e "${RED}Opção inválida.${NC}"
  fi
}

clear_all_cron() {
  ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v -E '(sei-aneel.py|pauta_aneel.py|sorteio_aneel.py)' | $CRONTAB_CMD -
  echo -e "${GREEN}Agendamentos removidos.${NC}"
}

cron_menu() {
  while true; do
    show_header "Agendamentos"
    echo -e "${CYAN}1) Incluir/Editar agendamento${NC}"
    echo -e "${CYAN}2) Apagar registro${NC}"
    echo -e "${CYAN}3) Listar agendamentos${NC}"
    echo -e "${CYAN}4) Apagar todos agendamentos${NC}"
    echo -e "${CYAN}5) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron; pause ;;
      2) remove_cron; pause ;;
      3) list_cron; pause ;;
      4) clear_all_cron; pause ;;
      5) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

schedule_backup_local() {
  read -p "Minutos [0]: " MIN; MIN=${MIN:-0}
  read -p "Horas [*]: " H; H=${H:-*}
  read -p "Dias do mês [*]: " M; M=${M:-*}
  read -p "Meses [*]: " MO; MO=${MO:-*}
  read -p "Dias da semana [*]: " D; D=${D:-*}
  ( ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'backup_manager.py local'; echo "$MIN $H $M $MO $D /usr/bin/python3 $SCRIPT_DIR/backup_manager.py local >> $LOG_DIR/cron.log 2>&1" ) | $CRONTAB_CMD -
  echo -e "${GREEN}Cron agendado.${NC}"
}

schedule_backup_gdrive() {
  read -p "Minutos [0]: " MIN; MIN=${MIN:-0}
  read -p "Horas [*]: " H; H=${H:-*}
  read -p "Dias do mês [*]: " M; M=${M:-*}
  read -p "Meses [*]: " MO; MO=${MO:-*}
  read -p "Dias da semana [*]: " D; D=${D:-*}
  ( ($CRONTAB_CMD -l 2>/dev/null || true) | grep -v 'backup_manager.py gdrive'; echo "$MIN $H $M $MO $D /usr/bin/python3 $SCRIPT_DIR/backup_manager.py gdrive >> $LOG_DIR/cron.log 2>&1" ) | $CRONTAB_CMD -
  echo -e "${GREEN}Cron agendado.${NC}"
}

view_logs() {
  local dir="${1:-$LOG_DIR}"
  mkdir -p "$dir"
  if compgen -G "$dir/*" > /dev/null; then
    ls -1 --color=always "$dir"
    read -p $'\e[33mArquivo de log para visualizar: \e[0m' LOGF
    [ -f "$dir/$LOGF" ] && less -R "$dir/$LOGF" || echo -e "${RED}Arquivo não encontrado.${NC}"
  else
    echo -e "${YELLOW}Nenhum log disponível em $dir.${NC}"
  fi
}

test_connectivity() {
  python3 "$SCRIPT_DIR/test_connectivity.py"
}


# Gerenciamento dos termos de pesquisa utilizados pelos módulos Python
list_terms() {
  if [ -f "$TERMS_FILE" ]; then
    nl -ba "$TERMS_FILE"
  else
    echo -e "${YELLOW}Arquivo de termos não encontrado.${NC}"
  fi
}

add_term() {
  local terms
  read -p $'\\e[33mNovos termos (separados por vírgula): \\e[0m' terms
  IFS=',' read -ra NEW_TERMS <<< "$terms"
  touch "$TERMS_FILE"
  local added=false
  for term in "${NEW_TERMS[@]}"; do
    term=$(echo "$term" | xargs)
    [ -z "$term" ] && continue
    if grep -Fxq "$term" "$TERMS_FILE" 2>/dev/null; then
      echo -e "${YELLOW}Termo já existente: $term${NC}"
    else
      echo "$term" >> "$TERMS_FILE"
      echo -e "${GREEN}Termo adicionado: $term${NC}"
      added=true
    fi
  done
  $added || echo -e "${YELLOW}Nenhum termo novo adicionado.${NC}"
}

remove_term() {
  if [ ! -f "$TERMS_FILE" ]; then
    echo -e "${YELLOW}Nenhum termo cadastrado.${NC}"
    return
  fi
  mapfile -t TERMS < "$TERMS_FILE"
  if [ ${#TERMS[@]} -eq 0 ]; then
    echo -e "${YELLOW}Nenhum termo cadastrado.${NC}"
    return
  fi
  for i in "${!TERMS[@]}"; do
    echo "$((i+1))) ${TERMS[$i]}"
  done
  read -p $'\e[33mNúmero do termo a excluir: \e[0m' IDX
  if [[ "$IDX" =~ ^[0-9]+$ ]] && [ "$IDX" -ge 1 ] && [ "$IDX" -le "${#TERMS[@]}" ]; then
    unset 'TERMS[IDX-1]'
    printf "%s\n" "${TERMS[@]}" > "$TERMS_FILE"
    echo -e "${GREEN}Termo removido.${NC}"
  else
    echo -e "${RED}Opção inválida.${NC}"
  fi
}

search_terms_menu() {
  while true; do
    show_header "Termos de Pesquisa"
    echo -e "${CYAN}1) Listar${NC}"
    echo -e "${CYAN}2) Incluir${NC}"
    echo -e "${CYAN}3) Excluir${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) list_terms; pause ;;
      2) add_term; pause ;;
      3) remove_term; pause ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

setup_rclone_gdrive() {
  read -p "Arquivo credentials.json [$CONFIG_DIR/credentials.json]: " C
  C=${C:-$CONFIG_DIR/credentials.json}
  rclone config create gdrive drive scope drive.file service_account_file "$C"
  echo -e "${GREEN}rclone gdrive configurado.${NC}"
}

backup_menu() {
  while true; do
    show_header "Backup"
    echo -e "${CYAN}1) Backup local${NC}"
    echo -e "${CYAN}2) Backup Google Drive${NC}"
    echo -e "${CYAN}3) Configurar rclone gdrive${NC}"
    echo -e "${CYAN}4) Restaurar backup${NC}"
    echo -e "${CYAN}5) Agendar backup local${NC}"
    echo -e "${CYAN}6) Agendar backup Google Drive${NC}"
    echo -e "${CYAN}7) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) python3 "$SCRIPT_DIR/backup_manager.py" local; pause ;;
      2) python3 "$SCRIPT_DIR/backup_manager.py" gdrive; pause ;;
      3) setup_rclone_gdrive; pause ;;
      4) python3 "$SCRIPT_DIR/backup_manager.py" restore; pause ;;
      5) schedule_backup_local; pause ;;
      6) schedule_backup_gdrive; pause ;;
      7) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

connection_config_menu() {
  while true; do
    show_header "Configurações de conexão"
    echo -e "${CYAN}1) Configurar 2captcha${NC}"
    echo -e "${CYAN}2) Configurar SMTP${NC}"
    echo -e "${CYAN}3) Configurar Google Drive${NC}"
    echo -e "${CYAN}4) Configurar tentativas${NC}"
    echo -e "${CYAN}5) Gerenciar emails${NC}"
    echo -e "${CYAN}6) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) config_twocaptcha ;;
      2) config_smtp ;;
      3) config_google ;;
      4) config_exec ;;
      5) manage_emails ;;
      6) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

show_status() {
  echo -e "${CYAN}Diretório do script:${NC} $SCRIPT_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    echo -e "${CYAN}Arquivo de configuração:${NC} $CONFIG_FILE"
  else
    echo -e "${YELLOW}Arquivo de configuração não encontrado.${NC}"
  fi
  if [ -f "$TERMS_FILE" ]; then
    local count
    count=$(wc -l < "$TERMS_FILE")
    echo -e "${CYAN}Termos de busca:${NC} $count"
  else
    echo -e "${CYAN}Termos de busca:${NC} 0"
  fi
  cron_entry=$($CRONTAB_CMD -l 2>/dev/null | grep 'sei-aneel.py' || true)
  if [ -n "$cron_entry" ]; then
    echo -e "${CYAN}Cron PAINEEL:${NC} $(echo "$cron_entry" | awk '{print $1,$2,$3,$4,$5}')"
  else
    echo -e "${YELLOW}Cron PAINEEL:${NC} inativo"
  fi
  cron_entry=$($CRONTAB_CMD -l 2>/dev/null | grep 'pauta_aneel.py' || true)
  if [ -n "$cron_entry" ]; then
    echo -e "${CYAN}Cron Pauta ANEEL:${NC} $(echo "$cron_entry" | awk '{print $1,$2,$3,$4,$5}')"
  else
    echo -e "${YELLOW}Cron Pauta ANEEL:${NC} inativo"
  fi
  cron_entry=$($CRONTAB_CMD -l 2>/dev/null | grep 'sorteio_aneel.py' || true)
  if [ -n "$cron_entry" ]; then
    echo -e "${CYAN}Cron Sorteio ANEEL:${NC} $(echo "$cron_entry" | awk '{print $1,$2,$3,$4,$5}')"
  else
    echo -e "${YELLOW}Cron Sorteio ANEEL:${NC} inativo"
  fi
}

config_menu() {
  while true; do
    show_header "Configurações"
    echo -e "${CYAN}1) Termos de Pesquisa${NC}"
    echo -e "${CYAN}2) Configurações de conexão${NC}"
    echo -e "${CYAN}3) Teste de conectividade${NC}"
    echo -e "${CYAN}4) Backup${NC}"
    echo -e "${CYAN}5) Instalação${NC}"
    echo -e "${CYAN}6) Agendamentos${NC}"
    echo -e "${CYAN}7) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) search_terms_menu; pause ;;
      2) connection_config_menu; pause ;;
      3) test_connectivity; pause ;;
      4) backup_menu; pause ;;
      5) installation_menu; pause ;;
      6) cron_menu; pause ;;
      7) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

sei_menu() {
  while true; do
    show_header "PAINEEL"
    echo -e "${CYAN}1) Gerenciar processos${NC}"
    echo -e "${CYAN}2) Execução Manual${NC}"
    echo -e "${CYAN}3) Ver logs${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) manage_processes_menu; pause ;;
      2) force_run; pause ;;
      3) view_logs "$LOG_DIR"; pause ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

# Menu para Pauta ANEEL
pauta_menu() {
  while true; do
    show_header "Pauta ANEEL"
    echo -e "${CYAN}1) Execução Manual${NC}"
    echo -e "${CYAN}2) Ver logs${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) force_run_pauta; pause ;;
      2) view_logs "$PAUTA_LOG_DIR"; pause ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

# Menu para Sorteio ANEEL
sorteio_menu() {
  while true; do
    show_header "Sorteio ANEEL"
    echo -e "${CYAN}1) Execução Manual${NC}"
    echo -e "${CYAN}2) Ver logs${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) force_run_sorteio; pause ;;
      2) view_logs "$SORTEIO_LOG_DIR"; pause ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}

# Menu principal
main_menu() {
  while true; do
    show_header "Menu Principal"
    echo -e "${CYAN}1) PAINEEL${NC}"
    echo -e "${CYAN}2) Pauta ANEEL${NC}"
    echo -e "${CYAN}3) Sorteio ANEEL${NC}"
    echo -e "${CYAN}4) Configurações${NC}"
    echo -e "${CYAN}5) Sair${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) sei_menu; pause ;;
      2) pauta_menu; pause ;;
      3) sorteio_menu; pause ;;
      4) config_menu; pause ;;
      5) exit 0 ;;
      *) echo -e "${RED}Opção inválida${NC}"; pause ;;
    esac
  done
}
case "${1:-}" in
  menu|"")
    main_menu;;
  run)
    log "Execução manual via CLI"
    python3 "$SCRIPT_DIR/sei-aneel.py";;
  config)
    config_menu;;
  test)
    test_connectivity;;
  backup)
    backup_menu;;
  cron)
    cron_menu;;
  logs)
    view_logs "$LOG_DIR";;
  status)
    show_status;;
  *)
    echo "Uso: $0 {menu|run|config|test|backup|logs|status}";
    exit 1;;
esac
