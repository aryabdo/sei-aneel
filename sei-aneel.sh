#!/bin/bash
SCRIPT_DIR="/opt/sei-aneel"
CONFIG_DIR="$SCRIPT_DIR/config"
CONFIG_FILE="$CONFIG_DIR/configs.json"
LOG_DIR="$SCRIPT_DIR/logs"
REPO_URL="https://github.com/aryabdo/sei-aneel.git"

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
  echo "Instalação concluída."
}

update_sei() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR"
  REQS_CHANGED=0
  if [ ! -f "$SCRIPT_DIR/requirements.txt" ] || \
     ! cmp -s "$TMP_DIR/requirements.txt" "$SCRIPT_DIR/requirements.txt"; then
    REQS_CHANGED=1
  fi
  sudo cp "$TMP_DIR/sei-aneel.py" "$TMP_DIR/manage_processes.py" \
          "$TMP_DIR/test_connectivity.py" "$TMP_DIR/sei-aneel.sh" \
          "$TMP_DIR/requirements.txt" "$SCRIPT_DIR/"
  if [ $REQS_CHANGED -eq 1 ]; then
    sudo pip3 install --break-system-packages -r "$SCRIPT_DIR/requirements.txt"
  fi
  sudo chown -R "$USER":"$USER" "$SCRIPT_DIR"
  rm -rf "$TMP_DIR"
  echo "Atualização concluída."
}

remove_sei() {
  crontab -l 2>/dev/null | grep -v 'sei-aneel.py' | crontab -
  sudo rm -rf "$SCRIPT_DIR"
  echo "Remoção concluída."
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
    echo "1) Configurar 2captcha"
    echo "2) Configurar SMTP"
    echo "3) Configurar Google Drive"
    echo "4) Configurar tentativas"
    echo "5) Voltar"
    read -p "Opção: " op
    case $op in
      1) config_twocaptcha ;;
      2) config_smtp ;;
      3) config_google ;;
      4) config_exec ;;
      5) break ;;
      *) echo "Opção inválida" ;;
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
    echo "1) Listar"
    echo "2) Adicionar"
    echo "3) Remover"
    echo "4) Voltar"
    read -p "Opção: " op
    case $op in
      1) list_emails "$CONFIG_FILE" ;;
      2) add_email ;;
      3) remove_email ;;
      4) break ;;
      *) echo "Opção inválida" ;;
    esac
  done
}

manage_processes_menu() {
  while true; do
    echo "1) Adicionar processo"
    echo "2) Remover processo"
    echo "3) Atualizar processo"
    echo "4) Voltar"
    read -p "Opção: " op
    case $op in
      1) read -p "Número: " N; python3 "$SCRIPT_DIR/manage_processes.py" add "$N" ;;
      2) read -p "Número: " N; python3 "$SCRIPT_DIR/manage_processes.py" remove "$N" ;;
      3) read -p "Número antigo: " O; read -p "Número novo: " N; python3 "$SCRIPT_DIR/manage_processes.py" update "$O" "$N" ;;
      4) break ;;
      *) echo "Opção inválida" ;;
    esac
  done
}

force_run() {
  while true; do
    echo "1) Executar todos os processos"
    echo "2) Executar processos específicos"
    echo "3) Voltar"
    read -p "Opção: " op
    log_file="$LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
    case $op in
      1) python3 "$SCRIPT_DIR/sei-aneel.py" | tee "$log_file" ;;
      2) read -p "Número(s) de processo (separados por espaço): " PROC; python3 "$SCRIPT_DIR/sei-aneel.py" --processo $PROC | tee "$log_file" ;;
      3) break ;;
      *) echo "Opção inválida" ;;
    esac
  done
}

schedule_cron() {
  read -p "Dias da semana [*]: " D; D=${D:-*}
  read -p "Horas (ex: 5,13,16): " H
  (crontab -l 2>/dev/null | grep -v 'sei-aneel.py'; echo "0 $H * * $D /usr/bin/python3 $SCRIPT_DIR/sei-aneel.py >> $LOG_DIR/cron.log 2>&1") | crontab -
  echo "Cron agendado."
}

remove_cron() {
  crontab -l 2>/dev/null | grep -v 'sei-aneel.py' | crontab -
  echo "Cron removido."
}

cron_menu() {
  while true; do
    echo "1) Agendar/Alterar cron"
    echo "2) Remover cron"
    echo "3) Voltar"
    read -p "Opção: " op
    case $op in
      1) schedule_cron ;;
      2) remove_cron ;;
      3) break ;;
      *) echo "Opção inválida" ;;
    esac
  done
}

view_logs() {
  if [ -d "$LOG_DIR" ]; then
    ls -1 "$LOG_DIR"
    read -p "Arquivo de log para visualizar: " LOGF
    [ -f "$LOG_DIR/$LOGF" ] && less "$LOG_DIR/$LOGF" || echo "Arquivo não encontrado."
  else
    echo "Diretório de logs inexistente."
  fi
}

test_connectivity() {
  python3 "$SCRIPT_DIR/test_connectivity.py"
}

menu() {
  while true; do
    echo "1) Instalar"
    echo "2) Atualizar"
    echo "3) Remover"
    echo "4) Configurar"
    echo "5) Gerenciar emails"
    echo "6) Gerenciar processos"
    echo "7) Testar conectividade"
    echo "8) Executar forçado"
    echo "9) Gerenciar cron"
    echo "10) Ver logs"
    echo "11) Sair"
    read -p "Opção: " OP
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

      *) echo "Opção inválida" ;;
    esac
  done
}

menu
