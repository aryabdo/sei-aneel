#!/usr/bin/env python3
"""
SEI ANEEL Automation System
Sistema de monitoramento automatizado de processos SEI ANEEL

Autor: Desenvolvido para automação de processos ANEEL
Data: 2025
"""

import subprocess
import sys
import json
import os
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path
import argparse
from datetime import datetime, timedelta
import colorama
from colorama import Fore, Back, Style
import threading
import signal

# Inicializa colorama para Windows
colorama.init(autoreset=True)

# Instala 2captcha-python forçadamente em ambientes restritos.
try:
    import twocaptcha
except ImportError:
    subprocess.check_call([
        sys.executable, "-m", "pip", "install", "--upgrade", "2captcha-python", "--break-system-packages"
    ])
    import twocaptcha

import time
import re
import csv
import gspread
import pytesseract
import smtplib
import platform
import logging
import shutil
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from PIL import Image, ImageOps, ImageFilter
from oauth2client.service_account import ServiceAccountCredentials
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.common.keys import Keys

class InteractiveUI:
    """Interface interativa para o usuário"""
    
    def __init__(self):
        self.running = True
        self.paused = False
        self.step_mode = False
        
    def print_header(self):
        """Exibe cabeçalho colorido"""
        print(f"\n{Fore.CYAN}{'='*70}")
        print(f"{Fore.CYAN}║{' '*20}{Fore.YELLOW}SEI ANEEL - Sistema de Monitoramento{' '*19}{Fore.CYAN}║")
        print(f"{Fore.CYAN}║{' '*25}{Fore.GREEN}Versão 1.1.0 - Interativo{' '*24}{Fore.CYAN}║")
        print(f"{Fore.CYAN}{'='*70}")
        
    def print_menu(self):
        """Exibe menu de opções"""
        print(f"\n{Fore.GREEN}📋 Opções disponíveis durante execução:")
        print(f"{Fore.YELLOW}  [CTRL+C] {Fore.WHITE}- Pausar/Retomar execução")
        print(f"{Fore.YELLOW}  [s]      {Fore.WHITE}- Alternar modo passo-a-passo")
        print(f"{Fore.YELLOW}  [q]      {Fore.WHITE}- Parar execução graciosamente")
        print(f"{Fore.YELLOW}  [i]      {Fore.WHITE}- Mostrar informações do processo atual")
        print(f"{Fore.YELLOW}  [h]      {Fore.WHITE}- Mostrar esta ajuda")
        
    def print_status(self, current: int, total: int, processo: str, status: str = ""):
        """Exibe status atual colorido"""
        percentage = (current / total) * 100 if total > 0 else 0
        bar_length = 30
        filled_length = int(bar_length * current // total) if total > 0 else 0
        bar = '█' * filled_length + '-' * (bar_length - filled_length)
        
        status_color = Fore.GREEN if status == "sucesso" else Fore.RED if status == "falha" else Fore.YELLOW
        
        print(f"\r{Fore.CYAN}Progresso: {Fore.WHITE}[{Fore.GREEN}{bar}{Fore.WHITE}] {percentage:.1f}% "
              f"{Fore.CYAN}({current}/{total}) {Fore.WHITE}| {Fore.YELLOW}Processo: {processo[:20]}{'...' if len(processo) > 20 else ''} "
              f"{status_color}{status}", end="", flush=True)
        
    def wait_for_input(self):
        """Aguarda entrada do usuário em modo passo-a-passo"""
        if self.step_mode:
            input(f"\n{Fore.YELLOW}Pressione ENTER para continuar para o próximo processo...")
            
    def handle_pause(self):
        """Gerencia pausa da execução"""
        if self.paused:
            print(f"\n\n{Fore.YELLOW}⏸️  Execução pausada. Pressione ENTER para continuar...")
            input()
            self.paused = False
            print(f"{Fore.GREEN}▶️  Execução retomada.")

class ProgressTracker:
    """Rastreador de progresso avançado"""
    
    def __init__(self):
        self.start_time = None
        self.processed = 0
        self.total = 0
        self.successes = 0
        self.failures = 0
        self.updates = 0
        self.inserts = 0
        
    def start(self, total_processes: int):
        """Inicia rastreamento"""
        self.start_time = datetime.now()
        self.total = total_processes
        
    def update_stats(self, status: str):
        """Atualiza estatísticas"""
        self.processed += 1
        if status == "atualizado":
            self.successes += 1
            self.updates += 1
        elif status == "inserido":
            self.successes += 1
            self.inserts += 1
        else:
            self.failures += 1
            
    def get_eta(self) -> str:
        """Calcula tempo estimado para conclusão"""
        if not self.start_time or self.processed == 0:
            return "Calculando..."
            
        elapsed = datetime.now() - self.start_time
        rate = self.processed / elapsed.total_seconds()
        remaining = (self.total - self.processed) / rate if rate > 0 else 0
        
        eta = datetime.now() + timedelta(seconds=remaining)
        return eta.strftime("%H:%M:%S")
        
    def print_summary(self):
        """Exibe resumo final"""
        if not self.start_time:
            return
            
        elapsed = datetime.now() - self.start_time
        
        print(f"\n\n{Fore.CYAN}{'='*60}")
        print(f"{Fore.CYAN}║{' '*20}{Fore.YELLOW}RESUMO DA EXECUÇÃO{' '*21}{Fore.CYAN}║")
        print(f"{Fore.CYAN}{'='*60}")
        print(f"{Fore.WHITE}⏱️  Tempo total: {Fore.GREEN}{elapsed}")
        print(f"{Fore.WHITE}📊 Processos: {Fore.CYAN}{self.processed}/{self.total}")
        print(f"{Fore.WHITE}✅ Sucessos: {Fore.GREEN}{self.successes}")
        print(f"{Fore.WHITE}❌ Falhas: {Fore.RED}{self.failures}")
        print(f"{Fore.WHITE}🔄 Atualizações: {Fore.YELLOW}{self.updates}")
        print(f"{Fore.WHITE}📝 Inserções: {Fore.BLUE}{self.inserts}")
        
        if self.processed > 0:
            success_rate = (self.successes / self.processed) * 100
            rate_color = Fore.GREEN if success_rate >= 80 else Fore.YELLOW if success_rate >= 60 else Fore.RED
            print(f"{Fore.WHITE}📈 Taxa de sucesso: {rate_color}{success_rate:.1f}%")
            
        print(f"{Fore.CYAN}{'='*60}")

class KeyboardHandler:
    """Gerenciador de entradas de teclado"""
    
    def __init__(self, ui: InteractiveUI, tracker: ProgressTracker):
        self.ui = ui
        self.tracker = tracker
        self.original_handler = None
        
    def setup_signal_handler(self):
        """Configura handler para CTRL+C"""
        def signal_handler(signum, frame):
            self.ui.paused = not self.ui.paused
            if self.ui.paused:
                print(f"\n\n{Fore.YELLOW}⏸️  Execução pausada por solicitação do usuário.")
                print(f"{Fore.GREEN}Pressione CTRL+C novamente para retomar ou 'q' para sair.")
            else:
                print(f"\n{Fore.GREEN}▶️  Execução retomada.")
                
        self.original_handler = signal.signal(signal.SIGINT, signal_handler)
        
    def restore_signal_handler(self):
        """Restaura handler original"""
        if self.original_handler:
            signal.signal(signal.SIGINT, self.original_handler)

class ConfigManager:
    """Gerenciador de configurações do sistema"""
    
    def __init__(self, config_path: str = None):
        if config_path is None:
            if platform.system() == "Windows":
                config_path = os.path.join(os.getcwd(), "config", "configs.json")
            else:
                config_path = "/opt/sei-aneel/config/configs.json"
        
        self.config_path = config_path
        self.config = self.load_config()
    
    def load_config(self) -> Dict[str, Any]:
        """Carrega configurações do arquivo JSON"""
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            raise FileNotFoundError(f"Arquivo de configuração não encontrado: {self.config_path}")
        except json.JSONDecodeError as e:
            raise ValueError(f"Erro ao decodificar JSON: {e}")
    
    def get(self, key: str, default: Any = None) -> Any:
        """Obtém valor de configuração usando notação de ponto"""
        keys = key.split('.')
        value = self.config
        try:
            for k in keys:
                value = value[k]
            return value
        except (KeyError, TypeError):
            return default
    
    def validate_required_configs(self) -> List[str]:
        """Valida configurações obrigatórias"""
        required_configs = [
            'smtp.server',
            'smtp.user', 
            'smtp.password',
            'twocaptcha.api_key',
            'google_drive.credentials_file',
            'paths.tesseract',
            'paths.chromedriver'
        ]
        
        missing = []
        for config in required_configs:
            if not self.get(config):
                missing.append(config)
        
        return missing
    
    def print_config_summary(self):
        """Exibe resumo das configurações"""
        print(f"\n{Fore.CYAN}📋 Resumo das Configurações:")
        print(f"{Fore.WHITE}  📧 Email: {Fore.GREEN if self.get('smtp.server') else Fore.RED}{'Configurado' if self.get('smtp.server') else 'Não configurado'}")
        print(f"{Fore.WHITE}  🔑 2captcha: {Fore.GREEN if self.get('twocaptcha.api_key') else Fore.RED}{'Configurado' if self.get('twocaptcha.api_key') else 'Não configurado'}")
        print(f"{Fore.WHITE}  📊 Google Drive: {Fore.GREEN if self.get('google_drive.credentials_file') else Fore.RED}{'Configurado' if self.get('google_drive.credentials_file') else 'Não configurado'}")
        print(f"{Fore.WHITE}  🌐 ChromeDriver: {Fore.GREEN if self.get('paths.chromedriver') else Fore.RED}{'Configurado' if self.get('paths.chromedriver') else 'Não configurado'}")
        print(f"{Fore.WHITE}  👁️  Tesseract: {Fore.GREEN if self.get('paths.tesseract') else Fore.RED}{'Configurado' if self.get('paths.tesseract') else 'Não configurado'}")

class Logger:
    """Sistema de logging avançado"""
    
    def __init__(self, config: ConfigManager):
        self.config = config
        self.logger = self._setup_logger()
    
    def _setup_logger(self) -> logging.Logger:
        """Configura o sistema de logging"""
        logger = logging.getLogger("sei_aneel")
        
        # Remove handlers existentes
        for handler in logger.handlers[:]:
            logger.removeHandler(handler)
        
        # Configura nível de log
        log_level = getattr(logging, self.config.get('logging.level', 'INFO').upper())
        logger.setLevel(log_level)
        
        # Formatter
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s'
        )
        
        # Handler para arquivo - ajusta path baseado no SO
        if platform.system() == "Windows":
            log_dir = Path(os.getcwd()) / "logs"
        else:
            log_dir = Path("/opt/sei-aneel/logs")
        
        log_dir.mkdir(exist_ok=True)
        
        file_handler = logging.handlers.RotatingFileHandler(
            log_dir / "sei_aneel.log",
            maxBytes=self._parse_size(self.config.get('logging.max_file_size', '10MB')),
            backupCount=self.config.get('logging.backup_count', 5),
            encoding='utf-8'
        )
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
        
        # Handler para console
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        return logger
    
    def _parse_size(self, size_str: str) -> int:
        """Converte string de tamanho para bytes"""
        size_str = size_str.upper().strip()
        multipliers = {'KB': 1024, 'MB': 1024**2, 'GB': 1024**3}
        
        for suffix, multiplier in multipliers.items():
            if size_str.endswith(suffix):
                return int(float(size_str[:-len(suffix)]) * multiplier)
        
        return int(size_str)  # Assume bytes se não especificado

# Import do logging.handlers que foi esquecido
import logging.handlers

def configurar_paths(config: ConfigManager) -> Dict[str, Optional[str]]:
    """
    Configura os caminhos dos executáveis baseado no sistema operacional e configurações.
    
    Args:
        config: Instância do ConfigManager
        
    Returns:
        Dict contendo os caminhos para tesseract, chromedriver e chrome_binary
    """
    paths_config = config.get('paths', {})
    
    if platform.system() == "Windows":
        # Para Windows, ajusta os paths base para o diretório atual se não especificado
        base_dir = Path(os.getcwd())
        data_dir = base_dir / "data"
        data_dir.mkdir(exist_ok=True)
        
        return {
            "tesseract": paths_config.get('tesseract', r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
            "chromedriver": paths_config.get('chromedriver', str(base_dir / "chromedriver.exe")),
            "chrome_binary": paths_config.get('chrome_binary')
        }
    else:  # Linux
        return {
            "tesseract": paths_config.get('tesseract', "/usr/bin/tesseract"),
            "chromedriver": paths_config.get('chromedriver', "/opt/sei-aneel/bin/chromedriver"),
            "chrome_binary": paths_config.get('chrome_binary', "/usr/bin/chromium-browser")
        }

def operacao_com_retry(func, max_retries: int = 3, delay: float = 2, logger=None) -> Any:
    """
    Executa uma função com retry automático em caso de falha.
    
    Args:
        func: Função a ser executada
        max_retries: Número máximo de tentativas
        delay: Delay inicial entre tentativas (aumenta exponencialmente)
        logger: Logger para registrar tentativas
    
    Returns:
        Resultado da função executada
        
    Raises:
        Exception: Se todas as tentativas falharem
    """
    last_exception = None
    for tentativa in range(max_retries):
        try:
            return func()
        except Exception as e:
            last_exception = e
            if tentativa == max_retries - 1:
                if logger:
                    logger.error(f"Falha após {max_retries} tentativas: {e}")
                raise
            if logger:
                logger.warning(f"Erro na tentativa {tentativa+1}/{max_retries}, tentando novamente em {delay}s: {e}")
            time.sleep(delay)
            delay *= 2
    
    # Esta linha nunca deve ser alcançada, mas é boa prática
    raise last_exception

def validar_configuracoes(config: ConfigManager, paths: Dict[str, str], logger) -> bool:
    """
    Valida se todas as configurações e arquivos necessários estão presentes.
    
    Args:
        config: Instância do ConfigManager
        paths: Dicionário com caminhos dos executáveis
        logger: Logger para registrar erros
    
    Returns:
        True se todas as configurações estão válidas
    """
    erros = []
    
    # Verifica configurações obrigatórias
    missing_configs = config.validate_required_configs()
    if missing_configs:
        erros.extend([f"Configuração obrigatória não definida: {cfg}" for cfg in missing_configs])
    
    # Verifica se o arquivo de credenciais existe
    creds_file = config.get('google_drive.credentials_file')
    if creds_file and not os.path.exists(creds_file):
        erros.append(f"Arquivo de credenciais Google Drive não encontrado: {creds_file}")
    
    # Verifica se o chromedriver existe
    if not os.path.exists(paths["chromedriver"]):
        erros.append(f"ChromeDriver não encontrado: {paths['chromedriver']}")
    
    # Verifica se o tesseract existe
    if not os.path.exists(paths["tesseract"]):
        erros.append(f"Tesseract não encontrado: {paths['tesseract']}")
    
    if erros:
        for erro in erros:
            logger.error(erro)
        return False
    
    return True

def validar_numero_processo(numero: str) -> bool:
    """Valida se o número do processo é válido"""
    if not numero or not isinstance(numero, str):
        return False
    numero_str = str(numero).strip()
    if not numero_str:
        return False
    numero_limpo = re.sub(r'\D', '', numero_str)
    return len(numero_limpo) >= 5

def normalizar_numero(numero: str) -> str:
    """Remove caracteres não numéricos do número do processo"""
    return re.sub(r'\D', '', numero or "")

class CaptchaHandler:
    """Gerenciador de resolução de CAPTCHA"""
    
    def __init__(self, driver, config: ConfigManager, logger, ui: InteractiveUI = None):
        self.driver = driver
        self.config = config
        self.logger = logger
        self.ui = ui
        
        api_key = config.get('twocaptcha.api_key')
        if not api_key:
            self.logger.error("ERRO: Chave API do 2captcha não configurada")
            raise ValueError("Chave API do 2captcha é obrigatória")
        
        self.solver = twocaptcha.TwoCaptcha(api_key)
        
        # Ajusta temp_dir baseado no SO
        if platform.system() == "Windows":
            self.temp_dir = Path(os.getcwd()) / "temp"
        else:
            self.temp_dir = Path("/opt/sei-aneel/temp")
        
        self.temp_dir.mkdir(exist_ok=True)

    def ocr_captcha_pil(self, img_path: str) -> str:
        """
        Processa imagem de captcha usando OCR local com otimizações.
        
        Args:
            img_path: Caminho para a imagem do captcha
            
        Returns:
            Texto extraído do captcha
        """
        try:
            img = Image.open(img_path)
            # Pipeline de processamento de imagem otimizado
            img = img.convert('L')  # Converte para escala de cinza
            img = ImageOps.autocontrast(img)  # Melhora contraste
            
            # Binarização com threshold adaptativo
            threshold = 130
            img = img.point(lambda x: 255 if x > threshold else 0)
            
            # Filtro para reduzir ruído
            img = img.filter(ImageFilter.MedianFilter(size=3))
            
            # Configuração otimizada do Tesseract
            ocr_config = r'--psm 8 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
            captcha_text = pytesseract.image_to_string(img, config=ocr_config)
            
            return captcha_text.strip()
        except Exception as e:
            self.logger.error(f"Erro no OCR local: {e}")
            return ""

    def resolver_captcha(self, max_tentativas: int = None) -> str:
        """Resolve CAPTCHA usando 2captcha com fallback para OCR local"""
        if max_tentativas is None:
            max_tentativas = self.config.get('execution.captcha_max_tries', 5)
            
        for tentativa in range(1, max_tentativas + 1):
            if self.ui:
                print(f"\n{Fore.YELLOW}🔍 Resolvendo captcha - Tentativa {tentativa}/{max_tentativas}")
            self.logger.info(f"Tentativa {tentativa} de {max_tentativas} para resolver captcha via 2captcha")
            
            try:
                img = WebDriverWait(self.driver, 20).until(
                    EC.presence_of_element_located((By.ID, "imgCaptcha"))
                )
                time.sleep(1)
                captcha_bytes = img.screenshot_as_png
                img_path = self.temp_dir / f"captcha_{tentativa}.png"
                
                with open(img_path, "wb") as f:
                    f.write(captcha_bytes)
                
                # Tenta resolver com 2captcha
                try:
                    if self.ui:
                        print(f"{Fore.CYAN}  🌐 Enviando para 2captcha...")
                    result = self.solver.normal(str(img_path))
                    captcha_text = result['code']
                    if captcha_text and len(captcha_text) >= 4:
                        if self.ui:
                            print(f"{Fore.GREEN}  ✅ Captcha resolvido: {captcha_text}")
                        self.logger.info(f"Captcha resolvido via 2captcha: {captcha_text}")
                        return captcha_text
                except Exception as e:
                    if self.ui:
                        print(f"{Fore.YELLOW}  ⚠️  2captcha falhou, tentando OCR local...")
                    self.logger.warning(f"2captcha falhou: {e}. Tentando fallback OCR local.")
                    
                    # Fallback para OCR local
                    texto = self.ocr_captcha_pil(str(img_path))
                    texto_limpo = ''.join(filter(str.isalnum, texto))
                    if texto_limpo and len(texto_limpo) >= 4:
                        if self.ui:
                            print(f"{Fore.GREEN}  ✅ Captcha resolvido via OCR: {texto_limpo}")
                        self.logger.info(f"Captcha resolvido via fallback OCR: {texto_limpo}")
                        return texto_limpo
                
                # Tenta recarregar o captcha
                try:
                    reload_btn = self.driver.find_element(By.ID, "imgRecaptcha")
                    reload_btn.click()
                    if self.ui:
                        print(f"{Fore.YELLOW}  🔄 Recarregando captcha...")
                    self.logger.info("Aguardando 3 segundos entre tentativas de captcha...")
                    time.sleep(3)
                except:
                    self.logger.info("Aguardando 3 segundos entre tentativas de captcha...")
                    time.sleep(3)
                    
            except Exception as e:
                self.logger.error(f"Erro na tentativa {tentativa} de captcha: {e}")
                time.sleep(3)
        
        if self.ui:
            print(f"{Fore.RED}  ❌ Falha ao resolver captcha após {max_tentativas} tentativas")
        self.logger.warning("Falha ao resolver captcha após múltiplas tentativas")
        return ""

    def limpar_captchas(self):
        """Remove arquivos temporários de captcha"""
        try:
            for arquivo in self.temp_dir.glob('captcha_*.png'):
                arquivo.unlink()
        except Exception as e:
            self.logger.warning(f"Erro ao limpar captchas: {e}")

class SEIAneel:
    """Classe principal para interação com o SEI ANEEL"""
    
    def __init__(self, driver, config: ConfigManager, logger, ui: InteractiveUI = None):
        self.driver = driver
        self.config = config
        self.logger = logger
        self.ui = ui
        self.captcha_handler = CaptchaHandler(driver, config, logger, ui)

    def pesquisar_e_entrar_processo(self, numero_processo: str) -> bool:
        """
        Pesquisa e acessa um processo específico no SEI ANEEL
        
        Args:
            numero_processo: Número do processo a ser pesquisado
            
        Returns:
            True se conseguiu acessar o processo, False caso contrário
        """
        if self.ui:
            print(f"\n{Fore.CYAN}🔍 Acessando processo: {Fore.YELLOW}{numero_processo}")
            
        url = ("https://sei.aneel.gov.br/sei/modulos/pesquisa/"
               "md_pesq_processo_pesquisar.php?acao_externa=protocolo_pesquisar"
               "&acao_origem_externa=protocolo_pesquisar&id_orgao_acesso_externo=0")
        
        self.driver.get(url)
        WebDriverWait(self.driver, 20).until(EC.presence_of_element_located((By.TAG_NAME, "body")))

        # Localiza o campo de processo
        campo_proc = None
        selectors = [
            (By.ID, "txtProtocoloPesquisa"),
            (By.XPATH, "//input[@name='txtProtocoloPesquisa']"),
            (By.XPATH, "//input[contains(@placeholder, 'Processo')]")
        ]
        
        for selector in selectors:
            try:
                campo_proc = WebDriverWait(self.driver, 10).until(
                    EC.presence_of_element_located(selector)
                )
                break
            except:
                continue
        
        if not campo_proc:
            if self.ui:
                print(f"{Fore.RED}  ❌ Campo de processo não encontrado")
            self.logger.error("Campo de processo não encontrado")
            return False

        # Preenche o número do processo
        numero_processo = str(numero_processo).strip()
        campo_proc.clear()
        campo_proc.send_keys(numero_processo)
        time.sleep(0.3)
        
        # Verifica se foi preenchido corretamente
        valor_atual = campo_proc.get_attribute('value')
        if valor_atual != numero_processo:
            if self.ui:
                print(f"{Fore.YELLOW}  ⚠️  Tentando preenchimento via JavaScript...")
            self.logger.warning(f"Valor do campo diferente do esperado ({valor_atual} != {numero_processo}), tentando JS")
            self.driver.execute_script(f"arguments[0].value = '{numero_processo}';", campo_proc)
            valor_atual = campo_proc.get_attribute('value')
            if valor_atual != numero_processo:
                if self.ui:
                    print(f"{Fore.RED}  ❌ Falha ao preencher campo do processo")
                self.logger.error("Falha ao preencher corretamente o campo do processo.")
                return False

        if self.ui:
            print(f"{Fore.GREEN}  ✅ Campo preenchido: {numero_processo}")
        self.logger.info(f"Campo preenchido corretamente com: {numero_processo}")

        # Resolve o captcha
        try:
            campo_captcha = self.driver.find_element(By.ID, "txtInfraCaptcha")
        except:
            if self.ui:
                print(f"{Fore.RED}  ❌ Campo de captcha não encontrado")
            self.logger.error("Campo de captcha não encontrado")
            return False
            
        captcha = self.captcha_handler.resolver_captcha()
        if not captcha:
            if self.ui:
                print(f"{Fore.RED}  ❌ Não foi possível resolver captcha")
            self.logger.error("Não foi possível resolver captcha")
            return False
            
        campo_captcha.clear()
        campo_captcha.send_keys(captcha)

        # Clica no botão pesquisar
        try:
            botao = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.ID, "sbmPesquisar"))
            )
            botao.click()
            if self.ui:
                print(f"{Fore.CYAN}  🔍 Pesquisando processo...")
            self.logger.info("Botão Pesquisar clicado")
            time.sleep(5)
        except Exception as e:
            if self.ui:
                print(f"{Fore.RED}  ❌ Erro ao pesquisar")
            self.logger.error(f"Erro ao clicar no botão pesquisar: {e}")
            return False

        # Procura o link do processo nos resultados
        numero_proc_normalizado = normalizar_numero(numero_processo)
        links_processo = self.driver.find_elements(By.XPATH, '//a')
        
        for link in links_processo:
            link_texto = link.text.strip()
            link_texto_normalizado = normalizar_numero(link_texto)
            if link.is_displayed() and link_texto_normalizado == numero_proc_normalizado:
                if self.ui:
                    print(f"{Fore.GREEN}  ✅ Processo encontrado: {link_texto}")
                self.logger.info(f"Link do processo encontrado: '{link_texto}'")
                try:
                    link.click()
                except Exception:
                    self.driver.execute_script("arguments[0].click();", link)
                time.sleep(2)
                
                # Muda para nova aba se necessário
                abas = self.driver.window_handles
                if len(abas) > 1:
                    self.driver.switch_to.window(abas[-1])
                return True
        
        if self.ui:
            print(f"{Fore.RED}  ❌ Processo não encontrado nos resultados")
        self.logger.warning(f"Link do processo {numero_processo} não encontrado na lista de links clicáveis.")
        return False

    def extrair_detalhes_processo(self) -> Dict[str, str]:
        """Extrai detalhes básicos do processo"""
        dados = {}
        try:
            tabela = self.driver.find_element(By.ID, "tblCabecalho")
            linhas = tabela.find_elements(By.TAG_NAME, "tr")
            
            for linha in linhas:
                tds = linha.find_elements(By.TAG_NAME, "td")
                if len(tds) == 2:
                    chave = tds[0].text.strip().replace(":", "")
                    valor = tds[1].text.strip().replace("\n", " ").replace("\r", "")
                    
                    # Tratamento especial para interessados
                    if chave.lower() == "interessados":
                        subelementos = tds[1].find_elements(By.XPATH, ".//*")
                        if subelementos:
                            lista_interessados = []
                            for elem in subelementos:
                                texto = elem.text.strip()
                                if texto and texto not in lista_interessados:
                                    lista_interessados.append(texto)
                            valor = "; ".join(lista_interessados)
                    
                    dados[chave] = valor
        except Exception as e:
            self.logger.error(f"Erro ao extrair detalhes do processo: {e}")
        
        return dados

    def extrair_lista_protocolos_concatenado(self) -> Tuple[str, str, str, str, str]:
        """Extrai lista de protocolos/documentos"""
        try:
            tabela = self.driver.find_element(By.ID, "tblDocumentos")
            linhas = tabela.find_elements(By.XPATH, ".//tr")[1:]  # Pula cabeçalho
            
            doc_nrs, doc_tipos, doc_datas, doc_inclusoes, doc_unidades = [], [], [], [], []
            
            for linha in linhas:
                tds = linha.find_elements(By.TAG_NAME, "td")
                if len(tds) >= 6:
                    doc_nrs.append(tds[1].text.strip())
                    doc_tipos.append(tds[2].text.strip())
                    doc_datas.append(tds[3].text.strip())
                    doc_inclusoes.append(tds[4].text.strip())
                    doc_unidades.append(tds[5].text.strip())
            
            return (
                "\n".join(doc_nrs),
                "\n".join(doc_tipos),
                "\n".join(doc_datas),
                "\n".join(doc_inclusoes),
                "\n".join(doc_unidades),
            )
        except Exception as e:
            self.logger.error(f"Erro ao extrair lista de protocolos: {e}")
            return "", "", "", "", ""

    def extrair_andamentos_concatenado(self) -> Tuple[str, str, str]:
        """Extrai andamentos do processo"""
        try:
            linhas = self.driver.find_elements(By.XPATH, "//tr[contains(@class, 'andamento')]")
            datas, unidades, descricoes = [], [], []
            
            for linha in linhas:
                tds = linha.find_elements(By.TAG_NAME, "td")
                if len(tds) == 3:
                    datas.append(tds[0].text.strip())
                    unidades.append(tds[1].text.strip())
                    descricoes.append(tds[2].text.strip())
            
            return "\n".join(datas), "\n".join(unidades), "\n".join(descricoes)
        except Exception as e:
            self.logger.error(f"Erro ao extrair andamentos: {e}")
            return "", "", ""

# Continuarei com as outras classes na próxima mensagem devido ao limite de caracteres...

class PlanilhaHandler:
    """Gerenciador de interação com Google Sheets"""
    
    def __init__(self, config: ConfigManager, logger):
        self.config = config
        self.logger = logger
        self.sheet = self._iniciar_sheet()
    
    def _iniciar_sheet(self):
        """Inicializa conexão com Google Sheets"""
        def _init():
            scope = ["https://spreadsheets.google.com/feeds", "https://www.googleapis.com/auth/drive"]
            creds_file = self.config.get('google_drive.credentials_file')
            creds = ServiceAccountCredentials.from_json_keyfile_name(creds_file, scope)
            client = gspread.authorize(creds)
            sheet_name = self.config.get('google_drive.sheet_name')
            worksheet_name = self.config.get('google_drive.worksheet_name')
            return client.open(sheet_name).worksheet(worksheet_name)
        
        return operacao_com_retry(_init, logger=self.logger)
    
    def normalizar_numero(self, numero: str) -> str:
        """Remove caracteres não numéricos"""
        return re.sub(r"\D", "", numero)
    
    def find_row_by_proc_number(self, proc_number: str) -> Optional[int]:
        """Encontra linha do processo na planilha"""
        def _find_row():
            proc_col = self.sheet.col_values(1)
            proc_number_norm = self.normalizar_numero(proc_number)
            for idx, val in enumerate(proc_col):
                if self.normalizar_numero(val) == proc_number_norm:
                    return idx + 1
            return None
        
        return operacao_com_retry(_find_row, logger=self.logger)
    
    def atualizar_ou_inserir_processo(self, linha: List[str], proc_number: str) -> str:
        """Atualiza processo existente ou insere novo"""
        row_idx = self.find_row_by_proc_number(proc_number)
        
        if row_idx:
            self.logger.info(f"Atualizando linha {row_idx} para processo {proc_number}")
            operacao_com_retry(
                lambda: self.sheet.update(values=[linha], range_name=f"A{row_idx}:K{row_idx}"),
                logger=self.logger
            )
            return "atualizado"
        else:
            self.logger.info(f"Inserindo novo processo {proc_number}")
            operacao_com_retry(lambda: self.sheet.append_row(linha), logger=self.logger)
            return "inserido"
    
    def get_all_processos(self) -> List[str]:
        """Obtém todos os números de processo da planilha"""
        def _get_processos():
            return self.sheet.col_values(1)[1:]  # Pula cabeçalho
        
        return operacao_com_retry(_get_processos, logger=self.logger)
    
    def get_all_values(self) -> List[List[str]]:
        """Obtém todos os valores da planilha"""
        def _get_values():
            return self.sheet.get_all_values()
        
        return operacao_com_retry(_get_values, logger=self.logger)

def main() -> List[Dict[str, str]]:
    """
    Função principal do script de monitoramento SEI ANEEL.
    
    Returns:
        Lista com resultados do processamento de cada processo
    """
    parser = argparse.ArgumentParser(description='SEI ANEEL Automation System')
    
    # Define default config path baseado no SO
    if platform.system() == "Windows":
        default_config = os.path.join(os.getcwd(), "config", "configs.json")
    else:
        default_config = '/opt/sei-aneel/config/configs.json'
    
    parser.add_argument('--config', default=default_config,
                       help='Caminho para arquivo de configuração')
    parser.add_argument('--verbose', action='store_true',
                       help='Ativa logs detalhados')
    parser.add_argument('--interactive', action='store_true', default=True,
                       help='Modo interativo com interface colorida')
    parser.add_argument('--step-mode', action='store_true',
                       help='Modo passo-a-passo para debug')
    parser.add_argument('--max-processes', type=int,
                       help='Número máximo de processos a processar')
    parser.add_argument('--processo', nargs='*',
                       help='Números de processo específicos para consulta')
    args = parser.parse_args()
    
    # Inicializa interface interativa
    ui = InteractiveUI() if args.interactive else None
    tracker = ProgressTracker()
    
    if ui:
        ui.print_header()
        ui.step_mode = args.step_mode
        if ui.step_mode:
            print(f"{Fore.YELLOW}⚠️  Modo passo-a-passo ativado")
    
    # Carrega configurações
    try:
        config = ConfigManager(args.config)
        if ui:
            print(f"{Fore.GREEN}✅ Configurações carregadas de: {args.config}")
            config.print_config_summary()
    except (FileNotFoundError, ValueError) as e:
        error_msg = f"Erro ao carregar configurações: {e}"
        if ui:
            print(f"{Fore.RED}❌ {error_msg}")
        else:
            print(error_msg)
        return []
    
    # Configura logging
    logger_manager = Logger(config)
    logger = logger_manager.logger
    
    logger.info("Iniciando script de monitoramento SEI ANEEL")
    
    # Configura paths
    paths = configurar_paths(config)
    
    # Cria diretórios necessários baseado no SO
    if platform.system() == "Windows":
        data_dir = Path(os.getcwd()) / "data"
    else:
        data_dir = Path("/opt/sei-aneel/data")
    
    data_dir.mkdir(parents=True, exist_ok=True)
    
    # Valida configurações antes de iniciar
    if not validar_configuracoes(config, paths, logger):
        error_msg = "Falha na validação das configurações. Abortando execução."
        if ui:
            print(f"\n{Fore.RED}❌ {error_msg}")
        logger.error(error_msg)
        return []
    
    if ui:
        print(f"\n{Fore.GREEN}✅ Validação de configurações concluída")
        ui.print_menu()
    
    # Configura Tesseract
    pytesseract.pytesseract.tesseract_cmd = paths["tesseract"]
    
    # Configura Chrome
    chrome_options = Options()
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-blink-features=AutomationControlled")
    chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
    chrome_options.add_experimental_option('useAutomationExtension', False)
    
    if platform.system() != "Windows":
        chrome_options.binary_location = paths["chrome_binary"]
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--window-size=1920,1080")
        chrome_options.add_argument("--disable-gpu")
    
    keyboard_handler = None
    try:
        # Inicializa componentes
        if ui:
            print(f"\n{Fore.CYAN}🚀 Inicializando navegador...")
        service = Service(executable_path=paths["chromedriver"])
        driver = webdriver.Chrome(service=service, options=chrome_options)
        driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
        
        if ui:
            print(f"{Fore.GREEN}✅ Navegador inicializado")
            print(f"{Fore.CYAN}📊 Conectando à planilha Google...")
        
        planilha_handler = PlanilhaHandler(config, logger)
        
        if ui:
            print(f"{Fore.GREEN}✅ Planilha conectada")
            keyboard_handler = KeyboardHandler(ui, tracker)
            keyboard_handler.setup_signal_handler()
        
    except Exception as e:
        error_msg = f"Erro na inicialização: {e}"
        if ui:
            print(f"\n{Fore.RED}❌ {error_msg}")
        logger.error(error_msg)
        return []
    
    resultados = []
    try:
        # Obtém processos
        if args.processo:
            processos_brutos = args.processo
        else:
            if ui:
                print(f"\n{Fore.CYAN}📋 Obtendo lista de processos...")
            processos_brutos = planilha_handler.get_all_processos()
        processos_validos = []
        
        for proc in processos_brutos:
            if validar_numero_processo(proc):
                processos_validos.append(re.sub(r'\D', '', proc.strip()))
        
        processos_unicos = list(set(processos_validos))
        
        # Aplica limite se especificado
        if args.max_processes and args.max_processes > 0:
            processos_unicos = processos_unicos[:args.max_processes]
            if ui:
                print(f"{Fore.YELLOW}⚠️  Limitado a {args.max_processes} processos")
        
        if not processos_unicos:
            error_msg = "Nenhum número de processo válido encontrado na planilha!"
            if ui:
                print(f"\n{Fore.RED}❌ {error_msg}")
            logger.error(f"ERRO: {error_msg}")
            return []
        
        if ui:
            print(f"{Fore.GREEN}✅ {len(processos_unicos)} processos válidos encontrados")
        
        logger.info(f"Total de {len(processos_unicos)} processos válidos para processar")
        if len(processos_unicos) >= 5:
            logger.info(f"Primeiros 5 processos: {', '.join(processos_unicos[:5])}...")
        else:
            logger.info(f"Processos: {', '.join(processos_unicos)}")
        
        # Configurações de execução
        max_execution_time = config.get('execution.max_execution_time', 1800)
        max_retry_attempts = config.get('execution.max_retry_attempts', 3)
        
        tempo_inicio = datetime.now()
        tempo_limite = tempo_inicio + timedelta(seconds=max_execution_time)
        
        processos_falha = set()
        
        # Inicia rastreamento
        tracker.start(len(processos_unicos))
        
        if ui:
            print(f"\n{Fore.CYAN}🔄 Iniciando processamento...")
            print(f"{Fore.WHITE}Tempo limite: {tempo_limite.strftime('%H:%M:%S')}")
            print(f"{Fore.WHITE}ETA inicial: {tracker.get_eta()}")
        
        # Processa cada processo
        for i, proc in enumerate(processos_unicos):
            if ui:
                ui.handle_pause()
                
            if datetime.now() >= tempo_limite:
                if ui:
                    print(f"\n\n{Fore.YELLOW}⏰ Tempo máximo de execução atingido.")
                logger.warning("Tempo máximo de execução atingido.")
                break
            
            if ui:
                ui.print_status(i+1, len(processos_unicos), proc, "processando")
                ui.wait_for_input()
            
            logger.info(f"Processando {i+1}/{len(processos_unicos)}: {proc}")
            resultado = processar_processo(proc, driver, planilha_handler, config, logger, ui)
            resultados.append(resultado)
            tracker.update_stats(resultado["status"])
            
            if ui:
                status_color = "sucesso" if resultado["status"] in ["atualizado", "inserido"] else "falha"
                ui.print_status(i+1, len(processos_unicos), proc, status_color)
                print(f"\n{Fore.WHITE}ETA: {tracker.get_eta()}")
            
            if resultado["status"] == "falha":
                processos_falha.add(proc)
        
        # Retry para processos que falharam
        for tentativa in range(2, max_retry_attempts + 1):
            if not processos_falha or datetime.now() >= tempo_limite:
                break
            
            if ui:
                print(f"\n\n{Fore.YELLOW}🔄 Tentativa {tentativa} para processos não atualizados ({len(processos_falha)} processos)...")
            logger.info(f"Iniciando tentativa {tentativa} para processos não atualizados...")
            novos_falha = set()
            
            for j, proc in enumerate(list(processos_falha)):
                if ui:
                    ui.handle_pause()
                    
                if datetime.now() >= tempo_limite:
                    if ui:
                        print(f"\n{Fore.YELLOW}⏰ Tempo máximo atingido durante tentativas de repetição.")
                    logger.warning("Tempo máximo atingido durante tentativas de repetição.")
                    break
                
                if ui:
                    ui.print_status(j+1, len(processos_falha), proc, "reprocessando")
                
                resultado = processar_processo(proc, driver, planilha_handler, config, logger, ui)
                resultados.append(resultado)
                tracker.update_stats(resultado["status"])
                
                if resultado["status"] == "falha":
                    novos_falha.add(proc)
                else:
                    processos_falha.discard(proc)
            
            processos_falha = novos_falha
        
        # Verifica mudanças e envia email se configurado
        if config.get('email.recipients'):
            if ui:
                print(f"\n\n{Fore.CYAN}📧 Verificando mudanças e enviando notificações...")
            verificar_e_enviar_notificacoes(planilha_handler, list(processos_falha), config, logger)
            if ui:
                print(f"{Fore.GREEN}✅ Notificações processadas")
        
        if ui:
            print(f"\n\n{Fore.GREEN}🎉 Processamento finalizado com sucesso!")
            tracker.print_summary()
        logger.info("Processamento finalizado com sucesso.")
        
    except KeyboardInterrupt:
        if ui:
            print(f"\n\n{Fore.YELLOW}⏹️  Execução interrompida pelo usuário.")
        logger.info("Execução interrompida pelo usuário.")
    except Exception as e:
        if ui:
            print(f"\n\n{Fore.RED}❌ Erro durante processamento: {e}")
        logger.error(f"Erro durante processamento: {e}")
    finally:
        if keyboard_handler:
            keyboard_handler.restore_signal_handler()
        driver.quit()
        if ui:
            print(f"\n{Fore.CYAN}🔚 Recursos liberados. Obrigado por usar o SEI ANEEL!")
    
    return resultados

def processar_processo(proc: str, driver, planilha_handler: PlanilhaHandler, 
                      config: ConfigManager, logger, ui: InteractiveUI = None) -> Dict[str, str]:
    """Processa um processo individual"""
    if not validar_numero_processo(proc):
        if ui:
            print(f"{Fore.RED}  ❌ Processo inválido: {proc}")
        logger.warning(f"Ignorando processo inválido: '{proc}'")
        return {"processo": proc, "status": "invalido"}
    
    if ui:
        print(f"\n{Fore.CYAN}📋 Processando: {Fore.WHITE}{proc}")
    logger.info(f"Processando: {proc}")
    sei = SEIAneel(driver, config, logger, ui)
    
    try:
        sucesso = sei.pesquisar_e_entrar_processo(proc)
        if not sucesso:
            if ui:
                print(f"{Fore.RED}  ❌ Falha ao acessar processo")
            logger.warning(f"Processo {proc} pulado após falha.")
            return {"processo": proc, "status": "falha"}
        
        if ui:
            print(f"{Fore.CYAN}  📄 Extraindo detalhes...")
        detalhes = sei.extrair_detalhes_processo()
        doc_nr, doc_tipo, doc_data, doc_incl, doc_uni = sei.extrair_lista_protocolos_concatenado()
        and_datas, and_unids, and_descrs = sei.extrair_andamentos_concatenado()
        
        linha = [
            detalhes.get("Processo", ""),
            detalhes.get("Tipo", ""),
            detalhes.get("Interessados", ""),
            doc_nr,
            doc_tipo,
            doc_data,
            doc_incl,
            doc_uni,
            and_datas,
            and_unids,
            and_descrs,
        ]
        
        if ui:
            print(f"{Fore.CYAN}  💾 Salvando na planilha...")
        status = planilha_handler.atualizar_ou_inserir_processo(linha, detalhes.get("Processo", ""))
        sei.captcha_handler.limpar_captchas()
        
        status_msg = "✅ Atualizado" if status == "atualizado" else "📝 Inserido" if status == "inserido" else "❌ Falha"
        status_color = Fore.GREEN if status in ["atualizado", "inserido"] else Fore.RED
        
        if ui:
            print(f"{status_color}  {status_msg}")
        
        return {"processo": detalhes.get("Processo", ""), "status": status}
    except Exception as e:
        if ui:
            print(f"{Fore.RED}  ❌ Erro: {str(e)[:50]}...")
        logger.error(f"Erro ao processar {proc}: {e}")
        return {"processo": proc, "status": "falha"}
    finally:
        try:
            driver.delete_all_cookies()
        except:
            pass

def verificar_e_enviar_notificacoes(planilha_handler: PlanilhaHandler, 
                                   processos_falha: List[str], 
                                   config: ConfigManager, logger):
    """Verifica mudanças e envia notificações por email"""
    try:
        # Carrega snapshot anterior se existir - ajusta path baseado no SO
        if platform.system() == "Windows":
            snapshot_path = Path(os.getcwd()) / "data" / "snapshot.json"
        else:
            snapshot_path = Path("/opt/sei-aneel/data/snapshot.json")
        
        snapshot_path.parent.mkdir(parents=True, exist_ok=True)
        
        snapshot_anterior = {}
        if snapshot_path.exists():
            try:
                with open(snapshot_path, 'r', encoding='utf-8') as f:
                    snapshot_anterior = json.load(f)
                logger.info("Snapshot anterior carregado")
            except Exception as e:
                logger.warning(f"Erro ao carregar snapshot anterior: {e}")
        
        # Obtém dados atuais da planilha
        dados_atuais = planilha_handler.get_all_values()
        if not dados_atuais:
            logger.warning("Nenhum dado obtido da planilha")
            return
        
        cabecalho = dados_atuais[0]
        linhas_dados = dados_atuais[1:]
        
        # Cria snapshot atual
        snapshot_atual = {}
        mudancas_detectadas = []
        
        for linha in linhas_dados:
            if not linha or not linha[0]:  # Pula linhas vazias
                continue
                
            numero_processo = normalizar_numero(linha[0])
            if not numero_processo:
                continue
            
            # Dados relevantes para comparação (exclui timestamps que mudam sempre)
            dados_processo = {
                'tipo': linha[1] if len(linha) > 1 else '',
                'interessados': linha[2] if len(linha) > 2 else '',
                'documentos_nr': linha[3] if len(linha) > 3 else '',
                'documentos_tipo': linha[4] if len(linha) > 4 else '',
                'andamentos_data': linha[8] if len(linha) > 8 else '',
                'andamentos_descricao': linha[10] if len(linha) > 10 else ''
            }
            
            snapshot_atual[numero_processo] = dados_processo
            
            # Verifica mudanças
            if numero_processo in snapshot_anterior:
                dados_anteriores = snapshot_anterior[numero_processo]
                
                # Compara andamentos (principal indicador de mudança)
                if dados_processo['andamentos_descricao'] != dados_anteriores.get('andamentos_descricao', ''):
                    mudancas_detectadas.append({
                        'processo': linha[0],
                        'tipo_mudanca': 'andamento',
                        'descricao': 'Novos andamentos detectados',
                        'dados_linha': dict(zip(cabecalho, linha))
                    })
                    logger.info(f"Mudança de andamento detectada no processo {linha[0]}")

                # Compara documentos
                elif dados_processo['documentos_nr'] != dados_anteriores.get('documentos_nr', ''):
                    mudancas_detectadas.append({
                        'processo': linha[0],
                        'tipo_mudanca': 'documento',
                        'descricao': 'Novos documentos detectados',
                        'dados_linha': dict(zip(cabecalho, linha))
                    })
                    logger.info(f"Mudança de documento detectada no processo {linha[0]}")
            else:
                # Processo novo
                mudancas_detectadas.append({
                    'processo': linha[0],
                    'tipo_mudanca': 'novo',
                    'descricao': 'Processo adicionado ao monitoramento',
                    'dados_linha': dict(zip(cabecalho, linha))
                })
                logger.info(f"Novo processo detectado: {linha[0]}")
        
        # Salva snapshot atual
        try:
            with open(snapshot_path, 'w', encoding='utf-8') as f:
                json.dump(snapshot_atual, f, ensure_ascii=False, indent=2)
            logger.info("Snapshot atual salvo")
        except Exception as e:
            logger.error(f"Erro ao salvar snapshot: {e}")
        
        # Envia email se houver mudanças ou falhas
        if mudancas_detectadas or processos_falha:
            enviar_notificacao_email(mudancas_detectadas, processos_falha, config, logger)
        else:
            logger.info("Nenhuma mudança detectada, email não enviado")
            
    except Exception as e:
        logger.error(f"Erro na verificação de mudanças: {e}")

def enviar_notificacao_email(mudancas: List[Dict], processos_falha: List[str], 
                           config: ConfigManager, logger):
    """Envia email de notificação sobre mudanças detectadas"""
    try:
        smtp_config = config.get('smtp', {})
        email_config = config.get('email', {})
        
        if not all([smtp_config.get('server'), smtp_config.get('user'),
                   smtp_config.get('password'), email_config.get('recipients')]):
            logger.warning("Configurações de email incompletas, pulando envio")
            return

        if not mudancas and not processos_falha:
            logger.info("Nenhuma mudança ou falha para notificar, email não enviado")
            return

        def organizar_colunas(dados: Dict[str, str], campos: List[str], chave_ord: str) -> Dict[str, str]:
            listas = {c: [s.strip() for s in dados.get(c, '').splitlines() if s.strip()] for c in campos}
            total = max((len(v) for v in listas.values()), default=0)
            registros = []
            for i in range(total):
                registros.append({c: listas[c][i] if i < len(listas[c]) else '' for c in campos})

            def parse_data(valor: str):
                for fmt in ('%d/%m/%Y %H:%M:%S', '%d/%m/%Y %H:%M', '%d/%m/%Y'):
                    try:
                        return datetime.strptime(valor, fmt)
                    except ValueError:
                        continue
                return datetime.min

            registros.sort(key=lambda r: parse_data(r.get(chave_ord, '')), reverse=True)
            return {c: '<br>'.join(r[c] for r in registros if r[c]) for c in campos}

        # Prepara conteúdo do email
        assunto = f"SEI ANEEL - Relatório de Monitoramento ({datetime.now().strftime('%d/%m/%Y %H:%M')})"
        
        timestamp_str = datetime.now().strftime('%d/%m/%Y às %H:%M:%S')
        corpo_html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                .header {{ color: #2c5aa0; border-bottom: 2px solid #2c5aa0; padding-bottom: 10px; }}
                .section {{ margin: 20px 0; }}
                .mudanca {{ background-color: #e8f4f8; border-left: 4px solid #2c5aa0; padding: 10px; margin: 5px 0; }}
                .falha {{ background-color: #f8e8e8; border-left: 4px solid #d32f2f; padding: 10px; margin: 5px 0; }}
                .processo {{ font-weight: bold; color: #1976d2; }}
                .tipo {{ color: #666; font-style: italic; }}
                .timestamp {{ color: #888; font-size: 0.9em; }}
                table.detalhes {{ border-collapse: collapse; margin-top: 5px; }}
                table.detalhes th, table.detalhes td {{ border: 1px solid #ddd; padding: 4px 8px; text-align: left; font-size: 0.9em; }}
                table.detalhes th {{ background-color: #f0f0f0; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h2>Relatório de Monitoramento SEI ANEEL</h2>
                <div class="timestamp">Gerado em: {timestamp_str}</div>
            </div>
        """
        
        if mudancas:
            corpo_html += f"""
            <div class="section">
                <h3>📋 Mudanças Detectadas ({len(mudancas)})</h3>
            """
            
            for mudanca in mudancas:
                icone = "🔄" if mudanca['tipo_mudanca'] == 'andamento' else "📄" if mudanca['tipo_mudanca'] == 'documento' else "🆕"
                detalhes_html = ""
                dados = mudanca.get('dados_linha', {})
                if dados:
                    linhas = [
                        f"<tr><th>PROCESSOS</th><td>{mudanca['processo']}</td></tr>",
                        f"<tr><th>Tipo do processo</th><td>{dados.get('Tipo do processo', '')}</td></tr>",
                        f"<tr><th>Interessados</th><td>{dados.get('Interessados', '')}</td></tr>",
                    ]

                    tabela_basica = f"<table class=\"detalhes\">{''.join(linhas)}</table>"

                    doc_campos = ['Documento', 'Tipo do documento', 'Data do documento', 'Data de Inclusão', 'Unidade']
                    and_campos = ['Data/Hora do Andamento', 'Unidade do Andamento', 'Descrição do Andamento']
                    docs = organizar_colunas(dados, doc_campos, 'Data de Inclusão')
                    andamentos = organizar_colunas(dados, and_campos, 'Data/Hora do Andamento')
                    tabela_colunas = f"""
                    <table class=\"detalhes\">
                        <tr>
                            <th>Documento</th><th>Tipo do documento</th><th>Data do documento</th>
                            <th>Data de Inclusão</th><th>Unidade</th>
                            <th>Data/Hora do Andamento</th><th>Unidade do Andamento</th><th>Descrição do Andamento</th>
                        </tr>
                        <tr>
                            <td>{docs.get('Documento', '')}</td>
                            <td>{docs.get('Tipo do documento', '')}</td>
                            <td>{docs.get('Data do documento', '')}</td>
                            <td>{docs.get('Data de Inclusão', '')}</td>
                            <td>{docs.get('Unidade', '')}</td>
                            <td>{andamentos.get('Data/Hora do Andamento', '')}</td>
                            <td>{andamentos.get('Unidade do Andamento', '')}</td>
                            <td>{andamentos.get('Descrição do Andamento', '')}</td>
                        </tr>
                    </table>
                    """
                    detalhes_html = tabela_basica + tabela_colunas
                corpo_html += f"""
                <div class="mudanca">
                    {icone} <span class="processo">{mudanca['processo']}</span><br>
                    <span class="tipo">{mudanca['tipo_mudanca'].title()}: {mudanca['descricao']}</span>
                    {detalhes_html}
                </div>
                """
            corpo_html += "</div>"
        
        if processos_falha:
            corpo_html += f"""
            <div class="section">
                <h3>⚠️ Processos com erro ou não localizados ({len(processos_falha)})</h3>
            """
            for processo in processos_falha:
                corpo_html += f"""
                <div class="falha">
                    ❌ <span class="processo">{processo}</span><br>
                    <span class="tipo">Erro no processamento ou processo não localizado - requer atenção manual</span>
                </div>
                """
            corpo_html += "</div>"
        
        corpo_html += """
            <div class="section">
                <p><small>Este é um email automático do sistema de monitoramento SEI ANEEL.</small></p>
            </div>
        </body>
        </html>
        """
        
        # Configura e envia email
        recipients = [r.strip() for r in email_config.get('recipients', []) if r.strip()]
        if not recipients:
            logger.warning("Nenhum destinatário de email configurado, pulando envio")
            return

        msg = MIMEMultipart('alternative')
        msg['Subject'] = assunto
        msg['From'] = smtp_config['user']
        msg['To'] = ', '.join(recipients)

        # Adiciona versão HTML
        parte_html = MIMEText(corpo_html, 'html', 'utf-8')
        msg.attach(parte_html)

        # Envia email
        server = smtplib.SMTP(smtp_config['server'], smtp_config.get('port', 587))
        if smtp_config.get('starttls', False):
            server.starttls()
        server.login(smtp_config['user'], smtp_config['password'])

        text = msg.as_string()
        server.sendmail(smtp_config['user'], recipients, text)
        server.quit()

        logger.info(f"Email de notificação enviado para {len(recipients)} destinatário(s)")
        
    except Exception as e:
        logger.error(f"Erro ao enviar email de notificação: {e}")

if __name__ == "__main__":
    try:
        resultados = main()
        sucesso = len([r for r in resultados if r["status"] in ["atualizado", "inserido"]])
        total = len(resultados)
        
        print(f"\n{Fore.CYAN}{'='*50}")
        print(f"{Fore.GREEN}🎉 Processamento concluído!")
        print(f"{Fore.WHITE}📊 Resultados: {Fore.GREEN}{sucesso}{Fore.WHITE}/{Fore.CYAN}{total} {Fore.WHITE}processos processados com sucesso")
        
        if total > 0:
            taxa_sucesso = (sucesso / total) * 100
            if taxa_sucesso >= 80:
                print(f"{Fore.GREEN}✨ Excelente taxa de sucesso: {taxa_sucesso:.1f}%")
            elif taxa_sucesso >= 60:
                print(f"{Fore.YELLOW}⚠️  Taxa de sucesso moderada: {taxa_sucesso:.1f}%")
            else:
                print(f"{Fore.RED}⚠️  Taxa de sucesso baixa: {taxa_sucesso:.1f}% - verifique os logs")
        
        print(f"{Fore.CYAN}{'='*50}")
        
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}⏹️  Execução interrompida pelo usuário.")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Fore.RED}❌ Erro fatal na execução do script: {e}")
        sys.exit(1)
