# FREEZE-01 — checklist operacional

## Objetivo

Congelar a ref acadêmica somente depois que os gates de repositório e host
estiverem fechados, preservando rastreabilidade entre commit, runtime e
evidências.

## Pré-condições de repositório

Antes de tocar nas VMs:

- PRs de segurança/dependências previstos para o freeze mergeados;
- `main` canônica estabilizada;
- Repository Static Integrity PASS;
- PHPUnit PASS;
- Semgrep PASS;
- Gitleaks PASS;
- Snyk Code final PASS;
- APPSEC-04 e APPSEC-05 revalidados na `main`;
- `prefreeze_repo_gate.py` PASS;
- `git diff --check` sem saída;
- worktree limpa.

Registrar o SHA canônico de `main` como `FREEZE_COMMIT`.

## Pré-condições de host

EP125 e EP126 devem:

- estar sincronizadas com `FREEZE_COMMIT`;
- possuir worktree limpa;
- concluir os readiness zero-sudo aplicáveis;
- preservar serviços/containers sem regressão;
- ter inventário final de portas, usuários, containers e versões;
- possuir evidências TXT + SHA-256 dos gates live finais.

OPS-01 deve estar fechado ou explicitamente documentado como boundary externo
não resolvido. Não mascarar boundary como PASS.

## Backup antes do freeze

Como BAC-05 usa execução manual no laboratório:

- registrar o último ponto de recuperação válido;
- registrar idade/freshness;
- executar backup manual adicional somente se necessário para a janela real de
  apresentação/teste;
- não inventar Schedule automático.

## Congelamento

1. registrar `FREEZE_COMMIT`;
2. gerar/validar handoffs a partir desse commit;
3. preservar hashes dos bundles;
4. registrar versões efetivas de imagens/artefatos relevantes;
5. tirar snapshot institucional das VMs, se disponível/autorizado;
6. não ativar Twingate antes do Pentest A;
7. não alterar hardening após o freeze sem abrir change control + reteste.

## Pacote de evidências

Organizar somente material sanitizado em:

```text
evidencias-finais/
  01-arquitetura-segmentacao/
  02-aplicacao-waf-rbac/
  03-dados-segredos-containers/
  04-wazuh-fim/
  05-dlp-privacidade/
  06-bacula/
  07-zero-sudo/
  08-pentest-s01-s13/
  09-twingate-comparativo/
```

Depois da revisão humana:

```bash
python3 scripts/evidencias/gerar_manifesto_evidencias_finais.py \
  ~/evidencias-finais
```

Esperado:

```text
FAIL=0
MANIFEST_READY=YES
```

## Saída mínima do FREEZE-01

Registrar:

```text
FREEZE_COMMIT=<sha40>
REPO_GATES=PASS
APPSEC04=PASS
APPSEC05=PASS
EP125_SYNC=PASS
EP126_SYNC=PASS
ZERO_SUDO_READINESS=PASS
OPS01=<PASS|BOUNDARY_EXPLICIT>
BACKUP_FRESHNESS=<observado>
EVIDENCE_MANIFEST=PASS
TWINGATE_ACTIVE=NO
FREEZE01=PASS
```

Campos que dependem de evidência live só podem ser preenchidos depois do teste.
