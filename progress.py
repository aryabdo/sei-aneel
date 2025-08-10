"""Progress tracking utilities."""
from datetime import datetime, timedelta
from colorama import Fore

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
        self.start_time = datetime.now()
        self.total = total_processes

    def update_stats(self, status: str):
        self.processed += 1
        if status == "atualizado":
            self.successes += 1
            self.updates += 1
        elif status == "inserido":
            self.successes += 1
            self.inserts += 1
        elif status == "processado":
            self.successes += 1
        else:
            self.failures += 1

    def get_eta(self) -> str:
        if not self.start_time or self.processed == 0:
            return "Calculando..."
        elapsed = datetime.now() - self.start_time
        rate = self.processed / elapsed.total_seconds()
        remaining = (self.total - self.processed) / rate if rate > 0 else 0
        eta = datetime.now() + timedelta(seconds=remaining)
        return eta.strftime("%H:%M:%S")

    def print_summary(self) -> None:
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
