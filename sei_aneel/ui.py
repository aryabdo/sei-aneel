"""Interactive command-line UI helpers."""
from colorama import Fore

class InteractiveUI:
    """Interface interativa para o usuário"""

    def __init__(self):
        self.running = True
        self.paused = False
        self.step_mode = False

    def print_header(self):
        print(f"\n{Fore.CYAN}{'='*70}")
        print(f"{Fore.CYAN}║{' '*20}{Fore.YELLOW}PAINEEL - Sistema de Monitoramento{' '*19}{Fore.CYAN}║")
        print(f"{Fore.CYAN}║{' '*25}{Fore.GREEN}Versão 1.1.0 - Interativo{' '*24}{Fore.CYAN}║")
        print(f"{Fore.CYAN}{'='*70}")

    def print_menu(self):
        print(f"\n{Fore.GREEN}📋 Opções disponíveis durante execução:")
        print(f"{Fore.YELLOW}  [CTRL+C] {Fore.WHITE}- Pausar/Retomar execução")
        print(f"{Fore.YELLOW}  [s]      {Fore.WHITE}- Alternar modo passo-a-passo")
        print(f"{Fore.YELLOW}  [q]      {Fore.WHITE}- Parar execução graciosamente")
        print(f"{Fore.YELLOW}  [i]      {Fore.WHITE}- Mostrar informações do processo atual")
        print(f"{Fore.YELLOW}  [h]      {Fore.WHITE}- Mostrar esta ajuda")

    def print_status(self, current: int, total: int, processo: str, status: str = ""):
        percentage = (current / total) * 100 if total > 0 else 0
        bar_length = 30
        filled_length = int(bar_length * current // total) if total > 0 else 0
        bar = '█' * filled_length + '-' * (bar_length - filled_length)

        status_color = Fore.GREEN if status == "sucesso" else Fore.RED if status == "falha" else Fore.YELLOW

        print(
            f"\r{Fore.CYAN}Progresso: {Fore.WHITE}[{Fore.GREEN}{bar}{Fore.WHITE}] {percentage:.1f}% "
            f"{Fore.CYAN}({current}/{total}) {Fore.WHITE}| {Fore.YELLOW}Processo: {processo[:20]}{'...' if len(processo) > 20 else ''} "
            f"{status_color}{status}",
            end="",
            flush=True,
        )

    def wait_for_input(self):
        if self.step_mode:
            input(f"\n{Fore.YELLOW}Pressione ENTER para continuar para o próximo processo...")

    def handle_pause(self):
        if self.paused:
            print(f"\n\n{Fore.YELLOW}⏸️  Execução pausada. Pressione ENTER para continuar...")
            input()
            self.paused = False
            print(f"{Fore.GREEN}▶️  Execução retomada.")
