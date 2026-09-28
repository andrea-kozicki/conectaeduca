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

Os diretórios pós-freeze `08-pentest-s01-s13` e `09-twingate-comparativo`
podem estar vazios neste momento. Já os diretórios pré-freeze `01` a `07`
precisam existir e conter pelo menos uma evidência regular sanitizada cada.

Antes de aceitar o manifesto:

```bash
ROOT="$HOME/evidencias-finais"

for d in \
  01-arquitetura-segmentacao \
  02-aplicacao-waf-rbac \
  03-dados-segredos-containers \
  04-wazuh-fim \
  05-dlp-privacidade \
  06-bacula \
  07-zero-sudo
do
  test -d "$ROOT/$d"
  test "$(find "$ROOT/$d" -type f ! -name SHA256SUMS ! -name MANIFESTO-EVIDENCIAS.txt | wc -l)" -gt 0
done

python3 scripts/evidencias/gerar_manifesto_evidencias_finais.py "$ROOT"

test -s "$ROOT/SHA256SUMS"
(
  cd "$ROOT"
  sha256sum -c SHA256SUMS
)
```

Só aceitar:

```text
PREFREEZE_REQUIRED_DIRS_NONEMPTY=PASS
FAIL=0
MANIFEST_READY=YES
SHA256SUMS_VERIFY=PASS
```

O `MANIFEST_READY=YES` isolado não é suficiente para o freeze, porque o
gerador trata diretórios ausentes como WARN e foi desenhado para suportar o
pacote completo, inclusive diretórios pós-freeze ainda vazios.

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
PREFREEZE_REQUIRED_DIRS_NONEMPTY=PASS
EVIDENCE_MANIFEST=PASS
SHA256SUMS_VERIFY=PASS
TIME01_NTP_RISK_ACCEPTED=YES
TIME01_PFSENSE_CONFIG_PRIVILEGE=UNAVAILABLE
TIME01_CROSS_SOURCE_TIMESTAMP_EXACTNESS=NOT_GUARANTEED
TIME01_SCOPE=ACADEMIC_LAB
TWINGATE_ACTIVE=NO
FREEZE01=PASS
```

Campos que dependem de evidência live só podem ser preenchidos depois do teste.

Os quatro marcadores TIME-01 acima são obrigatórios enquanto a sincronização
temporal do pfSense continuar fora do privilégio acadêmico. Se o suporte
corrigir a sincronização antes do freeze, registrar a melhoria separadamente;
não apagar o histórico da aceitação de risco.
