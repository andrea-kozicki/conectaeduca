# ConectaEduca — preparação verificável antes de voltar às VMs

**Fotografia: 18/11/2026.** Este é um plano de mudança e coleta, não um relatório de que as VMs foram verificadas. Nenhum comando deste documento foi executado em EP125, EP126, pfSense ou openSUSE.

**Fontes:** [auditoria por PR](../portfolio/PR_AUDITORIA_INDIVIDUAL_20261118.md), CI do GitHub, merges source-only #262/#264/#265/#267/#268/#270 e a [matriz JSON deste roteiro](CE-PREVM-GATES-20261118.json). A PR #215 teve PIN/hash do bootstrap e fila EP126 reconciliados, com **8/8 workflows e Snyk aprovados**, mas **continua DRAFT**, pois os scripts operacionais requerem revisão de TLS/privacidade e aceite contextual.

## O que está pronto sem VM

- Patches Ferret UI V4/V5 conferidos em fonte e testes sintéticos. **Não equivale à imagem/GUI em execução na EP126.**
- Dependências Composer corrigidas na `main` sem downgrade de phpseclib; instalação na VM **não** verificada.
- Fixture DLP-04 fictícia (#268), com controles de SHA-256, modo 0600 e anti-symlink. Não confirma Ferret nem Wazuh em operação.
- Comparador ZT-01 totalmente offline (#270), com relatório privado, sidecar SHA-256 e saída sanitizada. Não demonstra MFA ou autorização.
- Gate WAF de header interno (#272), com 8 testes sintéticos e 7/7 workflows. Confirma o contrato do Compose versionado; a substituição real do header e o peer recebido no PHP continuam pendentes.
- Template GA-07 de rotação **não ativável** e 3 testes sintéticos do `logrotate` (#274). A política de retenção, UID e ingestão Wazuh pós-rotação permanecem PENDING_VM.
- Auditoria individual das PRs, bloqueios e motivo para não mesclar PRs históricas completas.
- Inventário Git pré-VM [#276](https://github.com/andrea-kozicki/conectaeduca/pull/276): **10/10 testes sintéticos, 7/7 workflows e Snyk aprovados**. `--role ep125`/`--role ep126` só imprime plano por padrão; coleta local posterior exige `--execute-readonly`, hostname exato, UID não-root e autorização. Não consulta Docker, HTTP ou repositório remoto. Retorna **contagens por área**, não hashes individuais dos arquivos ou validação de runtime.

## Pré-VM: comandos que podem ser revisados agora (apenas plano)

```bash
python3 scripts/evidencias/ce_prevm_git_inventory.py --role ep125
python3 scripts/evidencias/ce_prevm_git_inventory.py --role ep126
```

Não usam rede nem leem o checkout local, pois `--execute-readonly` não foi fornecido. **Não executar ainda o modo de coleta nas VMs.** Mesmo uma futura coleta aprovada somente dará HEAD/cached origin-main e contagens classificadas: não prova arquivos de configuração ativos, permissões, snapshots, bind mounts, WAF, MFA, OpenBao, Ferret ou Wazuh. Continuam **12/12 gates PENDING_VM**.
## Critérios universais antes da primeira sessão nas VMs

1. Confirmar autorização institucional, janela e responsáveis; separar coleta read-only de operações mutantes.
2. Revalidar baseline atual de GitHub, snapshots e estado de cada VM. **Não presumir** que snapshots de 08–09/11 ainda cobrem o estado atual.
3. Registrar comandos revisados individualmente, seus efeitos esperados, entrada e saída sanitizadas; não utilizar `sudo -s` ou `sudo su`.
4. Exigir rollback específico e verificável antes de mudanças em imagem, Compose, OpenBao, regras Wazuh, Git checkout, firewall ou autenticação.
5. Evitar despejar configurações Docker brutas, variáveis `.env`, tokens, SecretID, unseal shares, dados pessoais e logs completos em chat/GitHub/Trello.
6. Ao primeiro sinal de diferença entre baseline, arquivo Git e serviço ativo: **parar e reconciliar**, sem aplicar merge, reset ou redeploy automático.

## Fila de execução proposta após a preparação

| Prioridade | Ativo | Gate | Evidência mínima para aceite |
| --- | --- | --- | --- |
| P0 | EP125 | CE-BASELINE-EP125 | Approved current hypervisor snapshot and rollback reference |
| P0 | EP126 | CE-BASELINE-EP126 | Approved current hypervisor snapshot and rollback reference |
| P0 | EP125 | CE-EP125-WAF-PA02 | Authorized negative direct-backend tests from agreed test origin |
| P0 | EP125 | CE-EP125-AUTH-MFA | Authorized browser tests with synthetic identities across positive and negative cases |
| P1 | EP125 | CE-EP125-AUDIT-RETENTION | Existing audit log path, ACL, retention policy and rotation configuration inventory |
| P0 | EP125 | CE-EP125-ZT-DMZ | Actual connector identity, network and resource mapping from authorized panel |
| P0 | EP126 | CE-EP126-WAZUH-DLP | Effective manager rule IDs and agent state confirmed read-only |
| P0 | EP126 | CE-EP126-FERRET | Running image digest, UI version and operational CLI baseline compared against source gate |
| P0 | EP126 | CE-EP126-OPENBAO | Read-only mount/policy/AppRole inventory without exposing secrets |
| P1 | EP126 | CE-EP126-BACULA | Read-only Director/FD and schedules status |
| P0 | openSUSE | CE-CLIENT-TWINGATE-ZT01 | Client connected state and trusted CA assessed |
| P1 | EP126 | CE-PA03-LOCAL-SUDO | Support ownership and intended behavior of local sudo wrapper confirmed |

**Todas as linhas acima estão em `PENDING_VM`.** A ordem exata será confirmada após inventário e autorização; o código que passou na CI não valida serviços reais. A matriz tem ações de parada para cada gate, que prevalecem sobre esta tabela abreviada.

## Pendências exclusivamente documentais

- Pentest B (#218, #219, #235): confrontar com relatório final, corrigir alegações não comprovadas e sanitizar dados públicos.
- Zero Trust (#200, #214, #232): manter datas de execução, decisões de acesso e status reais separados de planos históricos.
- Auditoria Wazuh/retention (#203, #225): revisar privacidade, acessos e documentação antes da configuração nas VMs.

## Ordem de ataque quando as VMs estiverem disponíveis

**Primeira janela:** inventário read-only de EP125/EP126, comparações de Git e hashes, fotografias de runtime e checagem de snapshots. Não alterar serviços.

**Segunda janela, após reconciliar:** testar rotas de WAF, fronteiras Zero Trust e login/MFA com contas institucionais autorizadas e dados sintéticos; produzir relatório observacional, sem PASS automático por código HTTP ou TCP.

**Janelas posteriores:** só se identificada necessidade e houver aceite, executar mudanças específicas em Wazuh/DLP, Ferret, OpenBao, Bacula e logrotate; cada uma com rollback e verificação E2E dirigidos. Nada de PR histórica inteira ou `git reset` sem análise de conteúdo.

**Critério de passagem para VM:** os gates source-only estão versionados e a matriz automatizada passou na CI; **os gates de runtime continuam pendentes**. O roteiro não substitui autorização institucional.
