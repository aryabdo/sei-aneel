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
TERMS_FILE="$CONFIG_DIR/search_terms.txt"
LOG_DIR="$SCRIPT_DIR/logs"
REPO_URL="https://github.com/aryabdo/sei-aneel.git"
UPDATE_SCRIPT="$SCRIPT_DIR/update_repo.sh"

export SEI_ANEEL_CONFIG="$CONFIG_FILE"

# Diretórios para módulos adicionais
PAUTA_DIR="/opt/pauta-aneel"
PAUTA_LOG_DIR="$PAUTA_DIR/logs"

SORTEIO_DIR="/opt/sorteio-aneel"
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
  sudo mkdir -p "$SCRIPT_DIR" "$LOG_DIR"
  sudo cp -r config "$SCRIPT_DIR/"
  sudo cp sei-aneel.py manage_processes.py backup_manager.py test_connectivity.py requirements.txt update_repo.sh "$SCRIPT_DIR/"
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
  if [ -f "$UPDATE_SCRIPT" ]; then
    sudo bash "$UPDATE_SCRIPT"
  else
    echo -e "${RED}Script de atualização não encontrado em $UPDATE_SCRIPT.${NC}"
  fi
}

remove_sei() {
  crontab -l 2>/dev/null | grep -v 'sei-aneel.py' | crontab -
  sudo rm -rf "$SCRIPT_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
}

install_pauta() {
  sudo rm -rf "$PAUTA_DIR"
  sudo mkdir -p "$PAUTA_LOG_DIR"
  sudo cp pauta_aneel/pauta_aneel.py "$PAUTA_DIR/"
  sudo cp requirements.txt "$PAUTA_DIR/"
  sudo chown -R "$USER":"$USER" "$PAUTA_DIR"

  sudo mkdir -p "$SCRIPT_DIR"
  sudo cp -r config "$SCRIPT_DIR/" 2>/dev/null

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
  sudo pip3 install --break-system-packages -r "$PAUTA_DIR/requirements.txt"

cat <<RUN > "$PAUTA_DIR/run.sh"
#!/bin/bash
DIR="\$(dirname "\$0")"
cd "\$DIR"
export SEI_ANEEL_CONFIG="$CONFIG_FILE"
PAUTA_DATA_DIR="\$DIR"
PAUTA_LOG_FILE="\$DIR/logs/pauta_aneel.log"
XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp}
PYTHONPATH="$SCRIPT_DIR:\$PYTHONPATH" python3 "\$DIR/pauta_aneel.py" "\$@"
RUN
  chmod +x "$PAUTA_DIR/run.sh"

  (crontab -l 2>/dev/null | grep -v 'pauta_aneel.py'; echo "0 7 * * * $PAUTA_DIR/run.sh >> $PAUTA_LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Instalação concluída.${NC}"
}

update_pauta() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo rm -rf "$PAUTA_DIR"
  sudo mkdir -p "$PAUTA_DIR" "$PAUTA_LOG_DIR"
  sudo cp "$TMP_DIR/pauta_aneel/pauta_aneel.py" "$PAUTA_DIR/"
  sudo cp "$TMP_DIR/requirements.txt" "$PAUTA_DIR/"
  sudo chown -R "$USER":"$USER" "$PAUTA_DIR"
  sudo pip3 install --break-system-packages -r "$PAUTA_DIR/requirements.txt"
cat <<RUN > "$PAUTA_DIR/run.sh"
#!/bin/bash
DIR="\$(dirname "\$0")"
cd "\$DIR"
export SEI_ANEEL_CONFIG="$CONFIG_FILE"
PAUTA_DATA_DIR="\$DIR"
PAUTA_LOG_FILE="\$DIR/logs/pauta_aneel.log"
XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp}
PYTHONPATH="$SCRIPT_DIR:\$PYTHONPATH" python3 "\$DIR/pauta_aneel.py" "\$@"
RUN
  chmod +x "$PAUTA_DIR/run.sh"
  rm -rf "$TMP_DIR"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_pauta() {
  crontab -l 2>/dev/null | grep -v 'pauta_aneel.py' | crontab -
  sudo rm -rf "$PAUTA_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
}


force_run_pauta() {
  DEFAULT_DATE=$(date +%d/%m/%Y)
  read -p $'\e[33mData da busca (dd/mm/aaaa) ['"$DEFAULT_DATE"$']: \e[0m' DATA
  DATA=${DATA:-$DEFAULT_DATE}
  log_file="$PAUTA_LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
  "$PAUTA_DIR/run.sh" "$DATA" | tee "$log_file"
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

clear_all_cron_pauta() {
  crontab -r
  echo -e "${GREEN}Todos agendamentos removidos.${NC}"
}

list_cron_pauta() {
  crontab -l 2>/dev/null | grep 'pauta_aneel.py' || echo -e "${YELLOW}Nenhum agendamento encontrado.${NC}"
}

cron_menu_pauta() {
  while true; do
    echo -e "${CYAN}1) Incluir/Editar agendamento${NC}"
    echo -e "${CYAN}2) Apagar registro${NC}"
    echo -e "${CYAN}3) Listar agendamentos${NC}"
    echo -e "${CYAN}4) Apagar todos agendamentos${NC}"
    echo -e "${CYAN}5) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron_pauta ;;
      2) remove_cron_pauta ;;
      3) list_cron_pauta ;;
      4) clear_all_cron_pauta ;;
      5) break ;;
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
  sudo rm -rf "$SORTEIO_DIR"
  sudo mkdir -p "$SORTEIO_LOG_DIR"
  sudo cp sorteio_aneel/sorteio_aneel.py "$SORTEIO_DIR/"
  sudo cp requirements.txt "$SORTEIO_DIR/"
  sudo chown -R "$USER":"$USER" "$SORTEIO_DIR"

  sudo mkdir -p "$SCRIPT_DIR"
  sudo cp -r config "$SCRIPT_DIR/" 2>/dev/null

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
  sudo pip3 install --break-system-packages -r "$SORTEIO_DIR/requirements.txt"

cat <<RUN > "$SORTEIO_DIR/run.sh"
#!/bin/bash

DIR="\$(dirname "\$0")"
cd "\$DIR"
export SEI_ANEEL_CONFIG="$CONFIG_FILE"
SORTEIO_DATA_DIR="\$DIR"
SORTEIO_LOG_FILE="\$DIR/logs/sorteio_aneel.log"
PYTHONPATH="$SCRIPT_DIR:\$PYTHONPATH" python3 "\$DIR/sorteio_aneel.py" "\$@"
RUN
  chmod +x "$SORTEIO_DIR/run.sh"

  (crontab -l 2>/dev/null | grep -v 'sorteio_aneel.py'; echo "0 6 * * * $SORTEIO_DIR/run.sh >> $SORTEIO_LOG_DIR/cron.log 2>&1") | crontab -
  echo -e "${GREEN}Instalação concluída.${NC}"
}

update_sorteio() {
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1
  sudo rm -rf "$SORTEIO_DIR"
  sudo mkdir -p "$SORTEIO_DIR" "$SORTEIO_LOG_DIR"
  sudo cp "$TMP_DIR/sorteio_aneel/sorteio_aneel.py" "$SORTEIO_DIR/"
  sudo cp "$TMP_DIR/requirements.txt" "$SORTEIO_DIR/"
  sudo chown -R "$USER":"$USER" "$SORTEIO_DIR"
  sudo pip3 install --break-system-packages -r "$SORTEIO_DIR/requirements.txt"
cat <<RUN > "$SORTEIO_DIR/run.sh"
#!/bin/bash

DIR="\$(dirname "\$0")"
cd "\$DIR"
export SEI_ANEEL_CONFIG="$CONFIG_FILE"
SORTEIO_DATA_DIR="\$DIR"
SORTEIO_LOG_FILE="\$DIR/logs/sorteio_aneel.log"
PYTHONPATH="$SCRIPT_DIR:\$PYTHONPATH" python3 "\$DIR/sorteio_aneel.py" "\$@"
RUN
  chmod +x "$SORTEIO_DIR/run.sh"
  rm -rf "$TMP_DIR"
  echo -e "${GREEN}Atualização concluída.${NC}"
}

remove_sorteio() {
  crontab -l 2>/dev/null | grep -v 'sorteio_aneel.py' | crontab -
  sudo rm -rf "$SORTEIO_DIR"
  echo -e "${GREEN}Remoção concluída.${NC}"
}

# Instalação global e utilitários
install_all_modules() {
  install_sei
  install_pauta
  install_sorteio
}

select_install_menu() {
  while true; do
    echo -e "${CYAN}1) SEI ANEEL${NC}"
    echo -e "${CYAN}2) Pauta ANEEL${NC}"
    echo -e "${CYAN}3) Sorteio ANEEL${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) install_sei ;;
      2) install_pauta ;;
      3) install_sorteio ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

install_dependencies_only() {
  sudo apt-get update
  sudo apt-get install -y python3 python3-pip tesseract-ocr chromium-browser chromium-chromedriver
  sudo pip3 install --break-system-packages -r requirements.txt
  sudo mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$PAUTA_DIR" "$PAUTA_LOG_DIR" "$SORTEIO_DIR" "$SORTEIO_LOG_DIR"
  sudo touch "$CONFIG_FILE"
  sudo chown -R "$USER":"$USER" "$SCRIPT_DIR" "$PAUTA_DIR" "$SORTEIO_DIR"
  echo -e "${GREEN}Dependências instaladas.${NC}"
}

update_global() {
  update_sei
  update_pauta
  update_sorteio
}

remove_all_modules() {
  remove_sei
  remove_pauta
  remove_sorteio
}

installation_menu() {
  while true; do
    echo -e "${CYAN}1) Instalar todos módulos${NC}"
    echo -e "${CYAN}2) Selecionar módulos${NC}"
    echo -e "${CYAN}3) Dependências${NC}"
    echo -e "${CYAN}4) Atualização Global${NC}"
    echo -e "${CYAN}5) Remoção${NC}"
    echo -e "${CYAN}6) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) install_all_modules ;;
      2) select_install_menu ;;
      3) install_dependencies_only ;;
      4) update_global ;;
      5) remove_all_modules ;;
      6) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}


force_run_sorteio() {
  DEFAULT_DATE=$(date +%d/%m/%Y)
  read -p $'\e[33mData da busca (dd/mm/aaaa) ['"$DEFAULT_DATE"$']: \e[0m' DATA
  DATA=${DATA:-$DEFAULT_DATE}
  log_file="$SORTEIO_LOG_DIR/exec_$(date +%Y%m%d_%H%M%S).log"
  "$SORTEIO_DIR/run.sh" "$DATA" | tee "$log_file"
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

clear_all_cron_sorteio() {
  crontab -r
  echo -e "${GREEN}Todos agendamentos removidos.${NC}"
}

list_cron_sorteio() {
  crontab -l 2>/dev/null | grep 'sorteio_aneel.py' || echo -e "${YELLOW}Nenhum agendamento encontrado.${NC}"
}

cron_menu_sorteio() {
  while true; do
    echo -e "${CYAN}1) Incluir/Editar agendamento${NC}"
    echo -e "${CYAN}2) Apagar registro${NC}"
    echo -e "${CYAN}3) Listar agendamentos${NC}"
    echo -e "${CYAN}4) Apagar todos agendamentos${NC}"
    echo -e "${CYAN}5) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron_sorteio ;;
      2) remove_cron_sorteio ;;
      3) list_cron_sorteio ;;
      4) clear_all_cron_sorteio ;;
      5) break ;;
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

clear_all_cron() {
  crontab -r
  echo -e "${GREEN}Todos agendamentos removidos.${NC}"
}

list_cron() {
  crontab -l 2>/dev/null | grep 'sei-aneel.py' || echo -e "${YELLOW}Nenhum agendamento encontrado.${NC}"
}

cron_menu() {
  while true; do
    echo -e "${CYAN}1) Incluir/Editar agendamento${NC}"
    echo -e "${CYAN}2) Apagar registro${NC}"
    echo -e "${CYAN}3) Listar agendamentos${NC}"
    echo -e "${CYAN}4) Apagar todos agendamentos${NC}"
    echo -e "${CYAN}5) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) schedule_cron ;;
      2) remove_cron ;;
      3) list_cron ;;
      4) clear_all_cron ;;
      5) break ;;
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


# Gerenciamento dos termos de pesquisa utilizados pelos módulos Python
list_terms() {
  if [ -f "$TERMS_FILE" ]; then
    nl -ba "$TERMS_FILE"
  else
    echo -e "${YELLOW}Arquivo de termos não encontrado.${NC}"
  fi
}

add_term() {
  read -p $'\e[33mNovo termo: \e[0m' TERM
  TERM=$(echo "$TERM" | xargs)
  if [ -z "$TERM" ]; then
    echo -e "${RED}Termo inválido.${NC}"
    return
  fi
  touch "$TERMS_FILE"
  if grep -Fxq "$TERM" "$TERMS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}Termo já existente.${NC}"
  else
    echo "$TERM" >> "$TERMS_FILE"
    echo -e "${GREEN}Termo adicionado.${NC}"
  fi
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
    echo -e "${CYAN}1) Listar${NC}"
    echo -e "${CYAN}2) Incluir${NC}"
    echo -e "${CYAN}3) Excluir${NC}"
    echo -e "${CYAN}4) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) list_terms ;;
      2) add_term ;;
      3) remove_term ;;
      4) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

backup_menu() {
  while true; do
    echo -e "${CYAN}1) Backup local${NC}"
    echo -e "${CYAN}2) Backup Google Drive${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) python3 "$SCRIPT_DIR/backup_manager.py" local ;;
      2) python3 "$SCRIPT_DIR/backup_manager.py" gdrive ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

connection_config_menu() {
  while true; do
    echo -e "${CYAN}1) SEI ANEEL${NC}"
    echo -e "${CYAN}2) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) configure_sei ;;
      2) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

config_menu() {
  while true; do
    echo -e "${CYAN}1) Termos de Pesquisa${NC}"
    echo -e "${CYAN}2) Configurações de conexão${NC}"
    echo -e "${CYAN}3) Teste de conectividade${NC}"
    echo -e "${CYAN}4) Configurações CRON${NC}"
    echo -e "${CYAN}5) Backup${NC}"
    echo -e "${CYAN}6) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' op
    case $op in
      1) search_terms_menu ;;
      2) connection_config_menu ;;
      3) test_connectivity ;;
      4) cron_menu ;;
      5) backup_menu ;;
      6) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

sei_menu() {
  while true; do
    echo -e "${CYAN}1) Gerenciar processos${NC}"
    echo -e "${CYAN}2) Testar conectividade${NC}"
    echo -e "${CYAN}3) Execução Manual${NC}"
    echo -e "${CYAN}4) Ver logs${NC}"
    echo -e "${CYAN}5) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) manage_processes_menu ;;
      2) test_connectivity ;;
      3) force_run ;;
      4) view_logs ;;
      5) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

# Menu para Pauta ANEEL
pauta_menu() {
  LOG_DIR="$PAUTA_LOG_DIR"
  while true; do
    echo -e "${CYAN}1) Execução Manual${NC}"
    echo -e "${CYAN}2) Ver logs${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) force_run_pauta ;;
      2) view_logs_pauta ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

# Menu para Sorteio ANEEL
sorteio_menu() {
  LOG_DIR="$SORTEIO_LOG_DIR"
  while true; do
    echo -e "${CYAN}1) Execução Manual${NC}"
    echo -e "${CYAN}2) Ver logs${NC}"
    echo -e "${CYAN}3) Voltar${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) force_run_sorteio ;;
      2) view_logs_sorteio ;;
      3) break ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

# Menu principal
main_menu() {
  while true; do
    echo -e "${CYAN}1) Instalação${NC}"
    echo -e "${CYAN}2) SEI ANEEL${NC}"
    echo -e "${CYAN}3) Pauta ANEEL${NC}"
    echo -e "${CYAN}4) Sorteio ANEEL${NC}"
    echo -e "${CYAN}5) Configurações${NC}"
    echo -e "${CYAN}6) Sair${NC}"
    read -p $'\e[33mOpção: \e[0m' OP
    case $OP in
      1) installation_menu ;;
      2) sei_menu ;;
      3) pauta_menu ;;
      4) sorteio_menu ;;
      5) config_menu ;;
      6) exit 0 ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
  done
}

main_menu
