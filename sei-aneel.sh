#!/bin/bash
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
LOG_DIR="$SCRIPT_DIR/logs"
REPO_URL="https://github.com/aryabdo/sei-aneel.git"

# Diretórios para módulos adicionais
PAUTA_DIR="/opt/pauta-aneel"
PAUTA_CONFIG="$PAUTA_DIR/config.env"
PAUTA_LOG_DIR="$PAUTA_DIR/logs"

SORTEIO_DIR="/opt/sorteio-aneel"
SORTEIO_CONFIG="$SORTEIO_DIR/config.env"
SORTEIO_LOG_DIR="$SORTEIO_DIR/logs"

install_sei() {
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
  sudo mkdir -p "$CONFIG_DIR" "$LOG_DIR"
  sudo cp sei-aneel.py manage_processes.py test_connectivity.py requirements.txt "$SCRIPT_DIR/"
  sudo cp "$CRED" "$CONFIG_DIR/credentials.json"
  sudo chown -R "$USER":"$USER" "$SCRIPT_DIR"

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

  (crontab -l 2>/dev/null | grep -v 'sei-aneel.py'; echo "0 5,13,16 * * * /usr/bin/python3 $SCRIPT_DIR/sei-aneel.py >> $LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Instalação concluída.${NC}"
}

update_sei() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo cp "$TMP_DIR/sei-aneel.py" "$TMP_DIR/sei-aneel.sh" "$SCRIPT_DIR/"
  sudo chown "$USER":"$USER" "$SCRIPT_DIR/sei-aneel.py" "$SCRIPT_DIR/sei-aneel.sh"

  rm -rf "$TMP_DIR"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_sei() {
  crontab -l 2>/dev/null | grep -v 'sei-aneel.py' | crontab -
  sudo rm -rf "$SCRIPT_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
}

install_pauta() {
  read -p "Servidor SMTP: " SMTP_SERVER
  read -p "Porta SMTP [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
  read -p "Usuário SMTP: " SMTP_USER
  read -s -p "Senha SMTP: " SMTP_PASS; echo
  read -p "Emails destinatários (separados por vírgula): " EMAILS

  sudo rm -rf "$PAUTA_DIR"
  sudo mkdir -p "$PAUTA_LOG_DIR"
  sudo cp pauta_aneel/pauta_aneel.py "$PAUTA_DIR/"
  sudo cp requirements.txt "$PAUTA_DIR/"
  sudo cp pauta_aneel/keywords.example "$PAUTA_DIR/.pauta_aneel_keywords"
  sudo chown -R "$USER":"$USER" "$PAUTA_DIR"

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
  sudo pip3 install --break-system-packages -r "$PAUTA_DIR/requirements.txt"

  cat <<CFG > "$PAUTA_CONFIG"
SMTP_SERVER=$SMTP_SERVER
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASSWORD=$SMTP_PASS
EMAIL_TO="$EMAILS"
CFG

  cat <<'RUN' > "$PAUTA_DIR/run.sh"
#!/bin/bash
DIR="$(dirname "$0")"
cd "$DIR"
set -a
source "$DIR/config.env"
PAUTA_DATA_DIR="$DIR"
PAUTA_LOG_FILE="$DIR/logs/pauta_aneel.log"
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}
set +a
python3 "$DIR/pauta_aneel.py" "$@"
RUN
  chmod +x "$PAUTA_DIR/run.sh"

  (crontab -l 2>/dev/null | grep -v 'pauta_aneel.py'; echo "0 7 * * * $PAUTA_DIR/run.sh >> $PAUTA_LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Instalação concluída.${NC}"
}

update_pauta() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo cp "$TMP_DIR/pauta_aneel/pauta_aneel.py" "$PAUTA_DIR/"
  sudo cp "$TMP_DIR/pauta_aneel/keywords.example" "$PAUTA_DIR/"
  sudo chown "$USER":"$USER" "$PAUTA_DIR/pauta_aneel.py" "$PAUTA_DIR/keywords.example"
  rm -rf "$TMP_DIR"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_pauta() {
  crontab -l 2>/dev/null | grep -v 'pauta_aneel.py' | crontab -
  sudo rm -rf "$PAUTA_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
}

config_pauta() {
  read -p "Servidor SMTP: " S
  read -p "Porta [587]: " P; P=${P:-587}
  read -p "Usuário: " U
  read -s -p "Senha: " PW; echo
  read -p "Emails destinatários (separados por vírgula): " EM
  cat > "$PAUTA_CONFIG" <<CFG
SMTP_SERVER=$S
SMTP_PORT=$P
SMTP_USER=$U
SMTP_PASSWORD=$PW
EMAIL_TO="$EM"
CFG
}

list_emails_pauta() {
  grep '^EMAIL_TO=' "$PAUTA_CONFIG" | cut -d'=' -f2- | tr -d '"' | tr ',' '\n'
}

add_email_pauta() {
  read -p "Email para adicionar: " EM
  CURRENT=$(grep '^EMAIL_TO=' "$PAUTA_CONFIG" | cut -d'=' -f2- | tr -d '"')
  [[ -z "$CURRENT" ]] && NEW="$EM" || NEW="$CURRENT,$EM"
  sed -i "s|^EMAIL_TO=.*|EMAIL_TO=\"$NEW\"|" "$PAUTA_CONFIG"
}

remove_email_pauta() {
  read -p "Email para remover: " EM
  CURRENT=$(grep '^EMAIL_TO=' "$PAUTA_CONFIG" | cut -d'=' -f2- | tr -d '"')
  IFS=',' read -ra ADDR <<< "$CURRENT"
  NEW=""
  for e in "${ADDR[@]}"; do
    [[ "$e" != "$EM" ]] && NEW="${NEW}${NEW:+,}$e"
  done
  sed -i "s|^EMAIL_TO=.*|EMAIL_TO=\"$NEW\"|" "$PAUTA_CONFIG"
}

manage_emails_pauta() {
  while true; do
    echo -e "${CYAN}1) Listar${NC}"
    echo -e "${CYAN}2) Adicionar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) list_emails_pauta ;;
      2) add_email_pauta ;;
      3) remove_email_pauta ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

force_run_pauta() {
  log_file="$PAUTA_LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
  "$PAUTA_DIR/run.sh" | tee "$log_file"
}

schedule_cron_pauta() {
  read -p "Dias da semana [*]: " D; D=${D:-*}
  read -p "Horas (ex: 7,19): " H
  (crontab -l 2>/dev/null | grep -v 'pauta_aneel.py'; echo "0 $H * * $D $PAUTA_DIR/run.sh >> $PAUTA_LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Cron agendado.${NC}"
}

remove_cron_pauta() {
  crontab -l 2>/dev/null | grep -v 'pauta_aneel.py' | crontab -
  echo -e "${GREEN}Cron removido.${NC}"
}

cron_menu_pauta() {
  while true; do
    echo -e "${CYAN}1) Agendar/Alterar cron${NC}"
    echo -e "${CYAN}2) Remover cron${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron_pauta ;;
      2) remove_cron_pauta ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

view_logs_pauta() {
  if [ -d "$PAUTA_LOG_DIR" ]; then
    ls -1 --color=always "$PAUTA_LOG_DIR"
    read -p $'\e[33mArquivo de log para visualizar: \e[0m' LOGF
    [ -f "$PAUTA_LOG_DIR/$LOGF" ] && less -R "$PAUTA_LOG_DIR/$LOGF" || echo -e "${RED}Arquivo não encontrado.${NC}"
  else
    echo -e "${RED}Diretório de logs inexistente.${NC}"
  fi
}

install_sorteio() {
  read -p "Servidor SMTP: " SMTP_SERVER
  read -p "Porta SMTP [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
  read -p "Usuário SMTP: " SMTP_USER
  read -s -p "Senha SMTP: " SMTP_PASS; echo
  read -p "Emails destinatários (separados por vírgula): " EMAILS

  sudo rm -rf "$SORTEIO_DIR"
  sudo mkdir -p "$SORTEIO_LOG_DIR"
  sudo cp sorteio_aneel/sorteio_aneel.py "$SORTEIO_DIR/"
  sudo cp requirements.txt "$SORTEIO_DIR/"
  sudo cp sorteio_aneel/keywords.example "$SORTEIO_DIR/.sorteio_aneel_keywords"
  sudo chown -R "$USER":"$USER" "$SORTEIO_DIR"

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
  sudo pip3 install --break-system-packages -r "$SORTEIO_DIR/requirements.txt"

  cat <<CFG > "$SORTEIO_CONFIG"
SMTP_SERVER=$SMTP_SERVER
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASSWORD=$SMTP_PASS
EMAIL_TO="$EMAILS"
CFG

  cat <<'RUN' > "$SORTEIO_DIR/run.sh"
#!/bin/bash
DIR="$(dirname "$0")"
cd "$DIR"
set -a
source "$DIR/config.env"
SORTEIO_DATA_DIR="$DIR"
SORTEIO_LOG_FILE="$DIR/logs/sorteio_aneel.log"
set +a
python3 "$DIR/sorteio_aneel.py" "$@"
RUN
  chmod +x "$SORTEIO_DIR/run.sh"

  (crontab -l 2>/dev/null | grep -v 'sorteio_aneel.py'; echo "0 6 * * * $SORTEIO_DIR/run.sh >> $SORTEIO_LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Instalação concluída.${NC}"
}

update_sorteio() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo cp "$TMP_DIR/sorteio_aneel/sorteio_aneel.py" "$SORTEIO_DIR/"
  sudo cp "$TMP_DIR/sorteio_aneel/keywords.example" "$SORTEIO_DIR/"
  sudo chown "$USER":"$USER" "$SORTEIO_DIR/sorteio_aneel.py" "$SORTEIO_DIR/keywords.example"
  rm -rf "$TMP_DIR"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_sorteio() {
  crontab -l 2>/dev/null | grep -v 'sorteio_aneel.py' | crontab -
  sudo rm -rf "$SORTEIO_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
}

config_sorteio() {
  read -p "Servidor SMTP: " S
  read -p "Porta [587]: " P; P=${P:-587}
  read -p "Usuário: " U
  read -s -p "Senha: " PW; echo
  read -p "Emails destinatários (separados por vírgula): " EM
  cat > "$SORTEIO_CONFIG" <<CFG
SMTP_SERVER=$S
SMTP_PORT=$P
SMTP_USER=$U
SMTP_PASSWORD=$PW
EMAIL_TO="$EM"
CFG
}

list_emails_sorteio() {
  grep '^EMAIL_TO=' "$SORTEIO_CONFIG" | cut -d'=' -f2- | tr -d '"' | tr ',' '\n'
}

add_email_sorteio() {
  read -p "Email para adicionar: " EM
  CURRENT=$(grep '^EMAIL_TO=' "$SORTEIO_CONFIG" | cut -d'=' -f2- | tr -d '"')
  [[ -z "$CURRENT" ]] && NEW="$EM" || NEW="$CURRENT,$EM"
  sed -i "s|^EMAIL_TO=.*|EMAIL_TO=\"$NEW\"|" "$SORTEIO_CONFIG"
}

remove_email_sorteio() {
  read -p "Email para remover: " EM
  CURRENT=$(grep '^EMAIL_TO=' "$SORTEIO_CONFIG" | cut -d'=' -f2- | tr -d '"')
  IFS=',' read -ra ADDR <<< "$CURRENT"
  NEW=""
  for e in "${ADDR[@]}"; do
    [[ "$e" != "$EM" ]] && NEW="${NEW}${NEW:+,}$e"
  done
  sed -i "s|^EMAIL_TO=.*|EMAIL_TO=\"$NEW\"|" "$SORTEIO_CONFIG"
}

manage_emails_sorteio() {
  while true; do
    echo -e "${CYAN}1) Listar${NC}"
    echo -e "${CYAN}2) Adicionar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) list_emails_sorteio ;;
      2) add_email_sorteio ;;
      3) remove_email_sorteio ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

force_run_sorteio() {
  log_file="$SORTEIO_LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
  "$SORTEIO_DIR/run.sh" | tee "$log_file"
}

schedule_cron_sorteio() {
  read -p "Dias da semana [*]: " D; D=${D:-*}
  read -p "Horas (ex: 6,18): " H
  (crontab -l 2>/dev/null | grep -v 'sorteio_aneel.py'; echo "0 $H * * $D $SORTEIO_DIR/run.sh >> $SORTEIO_LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Cron agendado.${NC}"
}

remove_cron_sorteio() {
  crontab -l 2>/dev/null | grep -v 'sorteio_aneel.py' | crontab -
  echo -e "${GREEN}Cron removido.${NC}"
}

cron_menu_sorteio() {
  while true; do
    echo -e "${CYAN}1) Agendar/Alterar cron${NC}"
    echo -e "${CYAN}2) Remover cron${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron_sorteio ;;
      2) remove_cron_sorteio ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

view_logs_sorteio() {
  if [ -d "$SORTEIO_LOG_DIR" ]; then
    ls -1 --color=always "$SORTEIO_LOG_DIR"
    read -p $'\e[33mArquivo de log para visualizar: \e[0m' LOGF
    [ -f "$SORTEIO_LOG_DIR/$LOGF" ] && less -R "$SORTEIO_LOG_DIR/$LOGF" || echo -e "${RED}Arquivo não encontrado.${NC}"
  else
    echo -e "${RED}Diretório de logs inexistente.${NC}"
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
  sudo cp "$C" "$CONFIG_DIR/credentials.json"
  python3 - "$CONFIG_FILE" "$CONFIG_DIR/credentials.json" "$SN" "$WS" <<'PY'
import json,sys
path,cred,sheet,ws=sys.argv[1:5]
with open(path) as f: data=json.load(f)
GD=data.setdefault('google_drive',{})
GD.update({'credentials_file':cred,'sheet_name':sheet,'worksheet_name':ws})
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

configure_sei() {
  while true; do
    echo -e "${CYAN}1) Configurar 2captcha${NC}"
    echo -e "${CYAN}2) Configurar SMTP${NC}"
    echo -e "${CYAN}3) Configurar Google Drive${NC}"
    echo -e "${CYAN}4) Configurar tentativas${NC}"
    echo -e "${CYAN}5) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) config_twocaptcha ;;
      2) config_smtp ;;
      3) config_google ;;
      4) config_exec ;;
      5) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
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
    echo -e "${CYAN}1) Listar${NC}"
    echo -e "${CYAN}2) Adicionar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) list_emails "$CONFIG_FILE" ;;
      2) add_email ;;
      3) remove_email ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

manage_processes_menu() {
  while true; do
    echo -e "${CYAN}1) Adicionar processo${NC}"
    echo -e "${CYAN}2) Remover processo${NC}"
    echo -e "${CYAN}3) Atualizar processo${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) read -p "Número: " N; python3 "$SCRIPT_DIR/manage_processes.py" add "$N" ;;
      2) read -p "Número: " N; python3 "$SCRIPT_DIR/manage_processes.py" remove "$N" ;;
      3) read -p "Número antigo: " O; read -p "Número novo: " N; python3 "$SCRIPT_DIR/manage_processes.py" update "$O" "$N" ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

force_run() {
  while true; do
    echo -e "${CYAN}1) Executar todos os processos${NC}"
    echo -e "${CYAN}2) Executar processos específicos${NC}"
    echo -e "${CYAN}3) Enviar tabela por email${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    log_file="$LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
    case $op in
      1) python3 "$SCRIPT_DIR/sei-aneel.py" | tee "$log_file" ;;
      2) read -p $'\e[33mNúmero(s) de processo (separados por espaço): \e[0m' PROC; python3 "$SCRIPT_DIR/sei-aneel.py" --processo $PROC | tee "$log_file" ;;
      3) python3 "$SCRIPT_DIR/sei-aneel.py" --email-tabela | tee "$log_file" ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

schedule_cron() {
  read -p "Dias da semana [*]: " D; D=${D:-*}
  read -p "Horas (ex: 5,13,16): " H
  (crontab -l 2>/dev/null | grep -v 'sei-aneel.py'; echo "0 $H * * $D /usr/bin/python3 $SCRIPT_DIR/sei-aneel.py >> $LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Cron agendado.${NC}"
}

remove_cron() {
  crontab -l 2>/dev/null | grep -v 'sei-aneel.py' | crontab -
  echo -e "${GREEN}Cron removido.${NC}"
}

cron_menu() {
  while true; do
    echo -e "${CYAN}1) Agendar/Alterar cron${NC}"
    echo -e "${CYAN}2) Remover cron${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron ;;
      2) remove_cron ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

view_logs() {
  if [ -d "$LOG_DIR" ]; then
    ls -1 --color=always "$LOG_DIR"
    read -p $'\e[33mArquivo de log para visualizar: \e[0m' LOGF
    [ -f "$LOG_DIR/$LOGF" ] && less -R "$LOG_DIR/$LOGF" || echo -e "${RED}Arquivo não encontrado.${NC}"
  else
    echo -e "${RED}Diretório de logs inexistente.${NC}"
  fi
}

test_connectivity() {
  python3 "$SCRIPT_DIR/test_connectivity.py"
}

sei_menu() {
  while true; do
    echo -e "${CYAN}1) Instalar${NC}"
    echo -e "${CYAN}2) Atualizar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Configurar${NC}"
    echo -e "${CYAN}5) Gerenciar emails${NC}"
    echo -e "${CYAN}6) Gerenciar processos${NC}"
    echo -e "${CYAN}7) Testar conectividade${NC}"
    echo -e "${CYAN}8) Executar forçado${NC}"
    echo -e "${CYAN}9) Gerenciar cron${NC}"
    echo -e "${CYAN}10) Ver logs${NC}"
    echo -e "${CYAN}11) Sair${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) install_sei ;;
      2) update_sei ;;
      3) remove_sei ;;
      4) configure_sei ;;
      5) manage_emails ;;
      6) manage_processes_menu ;;
      7) test_connectivity ;;
      8) force_run ;;
      9) cron_menu ;;
      10) view_logs ;;
      11) exit 0 ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

# Menu para Pauta ANEEL
pauta_menu() {
  CONFIG_FILE="$PAUTA_CONFIG"
  LOG_DIR="$PAUTA_LOG_DIR"
  while true; do
    echo -e "${CYAN}1) Instalar${NC}"
    echo -e "${CYAN}2) Atualizar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Configurar${NC}"
    echo -e "${CYAN}5) Gerenciar emails${NC}"
    echo -e "${CYAN}6) Executar forçado${NC}"
    echo -e "${CYAN}7) Gerenciar cron${NC}"
    echo -e "${CYAN}8) Ver logs${NC}"
    echo -e "${CYAN}9) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) install_pauta ;; 
      2) update_pauta ;; 
      3) remove_pauta ;; 
      4) config_pauta ;; 
      5) manage_emails_pauta ;;
      6) force_run_pauta ;;
      7) cron_menu_pauta ;;
      8) view_logs_pauta ;;
      9) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

# Menu para Sorteio ANEEL
sorteio_menu() {
  CONFIG_FILE="$SORTEIO_CONFIG"
  LOG_DIR="$SORTEIO_LOG_DIR"
  while true; do
    echo -e "${CYAN}1) Instalar${NC}"
    echo -e "${CYAN}2) Atualizar${NC}"
    echo -e "${CYAN}3) Remover${NC}"
    echo -e "${CYAN}4) Configurar${NC}"
    echo -e "${CYAN}5) Gerenciar emails${NC}"
    echo -e "${CYAN}6) Executar forçado${NC}"
    echo -e "${CYAN}7) Gerenciar cron${NC}"
    echo -e "${CYAN}8) Ver logs${NC}"
    echo -e "${CYAN}9) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) install_sorteio ;; 
      2) update_sorteio ;; 
      3) remove_sorteio ;; 
      4) config_sorteio ;; 
      5) manage_emails_sorteio ;;
      6) force_run_sorteio ;;
      7) cron_menu_sorteio ;;
      8) view_logs_sorteio ;;
      9) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

# Menu principal
main_menu() {
  while true; do
    echo -e "${CYAN}1) SEI ANEEL${NC}"
    echo -e "${CYAN}2) Pauta ANEEL${NC}"
    echo -e "${CYAN}3) Sorteio ANEEL${NC}"
    echo -e "${CYAN}4) Sair${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) sei_menu ;;
      2) pauta_menu ;;
      3) sorteio_menu ;;
      4) exit 0 ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

main_menu
