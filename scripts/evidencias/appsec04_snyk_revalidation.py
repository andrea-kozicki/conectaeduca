#!/usr/bin/env python3
"""Compatibilidade: a evidência APPSEC-04/05 agora é produzida apenas em CI."""

from appsec_snyk_ci_evidence import main


if __name__ == "__main__":
    raise SystemExit(main())
