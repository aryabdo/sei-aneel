# 🤖 PAINEEL Automation System - Interactive Edition

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.6+](https://img.shields.io/badge/python-3.6+-blue.svg)](https://www.python.org/downloads/)
[![Platform](https://img.shields.io/badge/platform-windows%20%7C%20linux-lightgrey.svg)]()

**Sistema de automação interativo para monitoramento de processos PAINEEL com interface colorida, resolução automática de CAPTCHA e integração com Google Sheets.**

Além do monitoramento de processos, o projeto inclui os utilitários **pauta_aneel** e **sorteio_aneel**.  Todos os módulos podem ser instalados e gerenciados pelo script `sei-aneel.sh`, que apresenta um menu principal para instalar, atualizar, configurar, executar manualmente ou agendar cada ferramenta. Cada utilitário grava seus logs em `/opt/pauta-aneel/logs` e `/opt/sorteio-aneel/logs`, evitando erros de permissão em `/tmp`.

[🚀 Instalação Rápida](#instalação-rápida) •
[🎮 Demo Interativo](#demo-interativo) •
[📖 Documentação](#documentação) •
[⚙️ Configuração](#configuração) •
[🐛 Problemas](#solução-de-problemas)

</div>

---

## ✨ Características

### Interface Interativa (Novo v1.1.0)
- 🎮 **Interface colorida** com barra de progresso em tempo real
- ⏸️ **Controle de execução** - pause/retome com CTRL+C
- 📊 **Estatísticas visuais** - ETA, taxa de sucesso, contadores
- 🐛 **Modo passo-a-passo** para debug detalhado
- 🎯 **Limitação de processos** para testes rápidos

### Funcionalidades Core
- 🔄 **Extração automatizada** de dados de processos PAINEEL
- 🧩 **Resolução automática de CAPTCHA** usando 2captcha e OCR local (Tesseract)
- 📊 **Integração com Google Sheets** para armazenamento de dados
- 📧 **Sistema de notificações avançado** por email com detecção de mudanças
- 🔍 **Detecção inteligente de mudanças** com sistema de snapshots
-  **Sistema de backup** automático
- ⏰ **Agendamento** para execução automática
- 🔍 **Testes de conectividade** para todos os serviços
- 📝 **Logs detalhados** com rotação automática
- 🖥️ **Suporte cross-platform** (Windows e Linux)

## 🎮 Demo Interativo

Veja todas as funcionalidades interativas em ação:

```bash
# Execute o demo para ver a interface
python demo_interactive.py
```

**Recursos Demonstrados:**
- Barra de progresso colorida
- Mensagens de status em tempo real
- Tratamento visual de erros
- Resumo estatístico final
- Controles interativos

## 🚀 Instalação Rápida

### Ubuntu 24.04+
```bash
git clone https://github.com/aryabdo/sei-aneel.git
cd sei-aneel
bash sei-aneel.sh
```

### Método 1: Windows (PowerShell - Recomendado)
```powershell
# Execute como Administrador
.\install_windows.ps1
```

### Método 2: Linux (GitHub)
```bash
curl -sSL https://raw.githubusercontent.com/aryabdo/sei-aneel/main/github_install.sh | sudo bash
```

### Método 3: Manual
```bash
git clone https://github.com/aryabdo/sei-aneel.git
cd sei-aneel

# Windows
.\install_windows.ps1

# Linux  
sudo bash install.sh
```

```bash
curl -sSL https://raw.githubusercontent.com/aryabdo/sei-aneel/main/github_install.sh | sudo bash
```

### Método 2: Clone e Instalação

```bash
git clone https://github.com/aryabdo/sei-aneel.git
cd sei-aneel
sudo bash install.sh
```

## 📋 Pré-requisitos

### 🖥️ Sistemas Operacionais Suportados
- Windows 10+ com PowerShell
- Ubuntu 18.04+ / Debian 9+
- CentOS 7+ / RHEL 7+ / Fedora 30+

### 📦 Dependências (Instaladas Automaticamente)
- Python 3.6+
- Chrome/Chromium
- Git
- Cron

## ⚙️ Configuração

### 1️⃣ Menu Interativo (Mais Fácil)
```bash
sei-aneel menu
```

### 2️⃣ Configuração Direta por Comandos
```bash
# Configurar SMTP
sei-aneel config smtp

# Configurar Google Drive
sei-aneel config drive

# Configurar 2captcha
sei-aneel config captcha
```

### 3️⃣ Configuração Manual
```bash
nano ~/.sei_aneel/config.ini
```

## 🎯 Uso

### ▶️ Execução Manual
```bash
sei-aneel run
```

### ⏰ Agendamento Automático
```bash
sei-aneel menu
# Selecione: "Gerenciamento de Cron"
```

### 🔍 Testes de Conectividade
```bash
sei-aneel test
```

### 📊 Visualizar Logs
```bash
sei-aneel logs
```

## 📁 Estrutura do Projeto

```
sei-aneel/
├── 🐍 sei_aneel.py              # Script principal
├── ⚙️ config_manager.py         # Gerenciamento de configurações
├── 🔍 connectivity_tester.py    # Testes de conectividade
├── 💾 backup_manager.py         # Sistema de backup
├── 🛠️ install.sh               # Instalador principal
├── 🚀 github_install.sh        # Instalador do GitHub
├── 📋 requirements.txt         # Dependências Python
├── 📖 README.md                # Esta documentação
└── 📝 logs/                    # Diretório de logs
```

## 🛠️ Comandos Disponíveis

| Comando | Descrição |
|---------|-----------|
| `sei-aneel menu` | 🎛️ Menu interativo completo |
| `sei-aneel run` | ▶️ Executar o sistema manualmente |
| `sei-aneel config` | ⚙️ Gerenciar configurações |
| `sei-aneel test` | 🔍 Testar conectividade |
| `sei-aneel backup` | 💾 Gerenciar backups |
| `sei-aneel logs` | 📊 Visualizar logs |
| `sei-aneel status` | ℹ️ Status do sistema |

## 🔧 Configurações Necessárias

### 1️⃣ Google Sheets API
1. Crie um projeto no [Google Cloud Console](https://console.cloud.google.com/)
2. Ative a API Google Sheets
3. Crie uma conta de serviço
4. Baixe o arquivo JSON de credenciais
5. Configure via menu interativo

### 2️⃣ Email SMTP
Configure seu servidor SMTP:
- 🌐 Servidor
- 🔌 Porta
- 👤 Usuário
- 🔐 Senha
- 📧 Destinatários

### 3️⃣ 2captcha (Opcional)
1. Crie conta em [2captcha.com](https://2captcha.com)
2. Obtenha sua API Key
3. Configure via menu interativo

### 4️⃣ Sistema de Notificações
O sistema agora inclui notificações inteligentes que detectam:
- 🆕 **Novos processos** adicionados ao monitoramento
- 📄 **Novos documentos** em processos existentes
- 🔄 **Atualizações de andamento** em processos
- ❌ **Falhas de processamento** que requerem atenção

Emails são enviados automaticamente quando mudanças são detectadas, com formatação HTML profissional e ícones visuais para fácil identificação.

## 💾 Sistema de Backup

O sistema possui backup automático de:
- ⚙️ Configurações
- 📝 Logs
- 📊 Histórico de execução

Gerenciar backups:
```bash
sei-aneel backup
```

Os arquivos são guardados localmente em `backups/` e, quando configurado `google_drive.backup_folder_id`, também são enviados para o Google Drive (por exemplo, `Meu Drive/Servidor/Backup/Sistema PAINEEL`). Apenas os três backups mais recentes são mantidos, removendo os mais antigos automaticamente.

## 📝 Logs

📍 **Localização dos logs:**
- `/opt/sei-aneel/logs/`
- `~/.sei_aneel/logs/`

🔍 **Visualizar logs:**
```bash
sei-aneel logs
```

## 🐛 Solução de Problemas

### ❌ Chrome/Chromium não encontrado
```bash
# Ubuntu/Debian
sudo apt-get install chromium-browser

# CentOS/RHEL/Fedora
sudo yum install chromium
```

### 🚫 Permissões negadas
```bash
sudo bash install.sh
```

### 🔧 Problemas com pip
```bash
python3 -m pip install --upgrade pip
```

### 🌐 Problemas de conectividade
```bash
sei-aneel test
```

### 📧 Problemas de email
1. Verifique configurações SMTP
2. Teste com `sei-aneel test`
3. Verifique logs: `sei-aneel logs`

## 🤝 Contribuição

1. 🍴 Fork o projeto
2. 🌿 Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. 💾 Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. 📤 Push para a branch (`git push origin feature/AmazingFeature`)
5. 🔄 Abra um Pull Request

## 📄 Licença

Este projeto está licenciado sob a MIT License - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

<div align="center">

**Feito com ❤️ para automatização de processos PAINEEL**

[⬆️ Voltar ao topo](#-sei-aneel-automation-system)

</div>
