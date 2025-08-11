#!/usr/bin/env python3
"""Entry point for monitoring ANEEL meeting agendas."""
from sei_aneel.scheduler import ensure_cron
from sei_aneel.pauta_aneel.pauta_aneel import main


if __name__ == "__main__":
    ensure_cron([10, 11, 12, 13, 14], __file__, "pauta-aneel")
    main()
