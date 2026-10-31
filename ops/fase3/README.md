# ConectaEduca — Kits operacionais Fase 3 (EP125 e EP126)

**Preparado em 31/10/2026; modo de operação: somente leitura, sem implantação automática.**

Objetivo: concentrar o que falta para o Pentest B e tornar cada intervenção pequena, auditável e reversível. Evita novos inventários completos, trabalha por tarefa e **não confunde PR, CI ou healthcheck com deploy validado**.

## Estrutura

```text
ops/fase3/
├── README.md                   # uso, gates e segurança
├── lib/ce-common.sh            # funções read-only, hashes e evidências
├── ep125/
│   ├── ce-ep125.sh             # lançador exclusivo EP125 (DMZ)
│   └── QUEUE.md                # P0/P1 e critérios
├── ep126/
│   ├── ce-ep126.sh             # lançador exclusivo EP126 (Intranet)
│   └── QUEUE.md                # P0/P1 e critérios
├── opensuse/
│   └── ce-client.sh            # pré-teste do Twingate Client pessoal
└── tests/smoke.sh              # sintaxe, help, bloqueios de ação
```

## Uso a partir de um checkout revisado

Executar **no host correto** e sem `sudo -s`:

```bash
# Na EP125 (ep125-pucpr):
bash ops/fase3/ep125/ce-ep125.sh list
bash ops/fase3/ep125/ce-ep125.sh check waf
bash ops/fase3/ep125/ce-ep125.sh plan waf
bash ops/fase3/ep125/ce-ep125.sh prepare waf
bash ops/fase3/ep125/ce-ep125.sh reconcile

# Na EP126 (ep126-pucpr-br):
bash ops/fase3/ep126/ce-ep126.sh list
bash ops/fase3/ep126/ce-ep126.sh check twingate
bash ops/fase3/ep126/ce-ep126.sh prepare ferret
bash ops/fase3/ep126/ce-ep126.sh reconcile

# Em qualquer Linux com este checkout: apenas checagens estaticas
bash ops/fase3/tests/smoke.sh
```

**IMPORTANTE:** este kit está em uma branch com PR DRAFT. Não está na `main` e **não deve ser obtido por `git pull` na VM**. Fazer revisão, selecionar arquivos/commit e instalar cópia isolada sob `$HOME`, ou aguardar merge autorizado com reconciliação planejada.

## Comandos e efeitos

| Ação | Efeito |
|---|---|
| `list` | Mostra tarefas pendentes por VM |
| `check TASK` | Consulta estado focalizado; sem mudanças |
| `plan TASK` | Imprime plano e condições para a correção |
| `prepare TASK` | **Escreve exclusivamente** pacote de preparação no home do usuário |
| `reconcile` | Consulta o estado Git local, sem fetch, pull, reset ou checkout |
| `postcheck TASK` | Roda as mesmas leituras para comparação após mudança autorizada |
| `apply/deploy/restart/rollback/merge` | **Recusado:** comandos reais ainda precisam ser implementados e revisados por alteração |

Pacotes gerados por `prepare`:

```text
~/ConectaEduca_Fase3_Preparacao/<EP125|EP126>/<task>-<timestamp>.<random>/
├── 00-manifest.txt
├── 01-preflight.txt
├── 02-reconcile.txt
├── 03-change-plan.txt
└── HASHES.sha256
```

É criado com `umask 077`. O kit não copia `.env`, tokens, unseal shares, configuração Docker bruta, dumps de banco ou segredos de aplicação. Os relatórios ainda devem passar por sanitização antes de anexar a GitHub/Trello.

## Gates obrigatórios antes de qualquer alteração real

1. Identificar VM/usuário/serviço e ticket com PR e achado do PA correspondente.
2. Confirmar autorização de mudança e janela institucional, incluindo snapshot/backup e acesso administrativo alternativo.
3. Conferir commit de origem, Compose efetivo, rotas/portas necessárias e dependências.
4. Implementar **patch idempotente específico**, sem `sudo -s`, e revisar previamente o rollback real.
5. Registrar antes/depois com hashes, smoke funcional, testes positivos e negativos, e monitoramento de efeitos no Wazuh.
6. Atualizar o `diario.md` da VM pelo registrador apropriado **após** receber a evidência real. Não escrever resultados esperados como se fossem observados.

## Estado atual a preservar

**EP125:** PHP-FPM 8.5.12 aplicado; auditoria PHP persistente e E2E Wazuh demonstrados. Não reaplicar esses marcos. A principal prioridade é o Connector DMZ e o bypass WAF/Nginx; revisão de PR #205 e de retenção ficam em outras trilhas.

**EP126:** Connector Twingate institucional `healthy` e Remote Network Connected; Resource Wazuh criado com política `CE-SOC-MFA-1DIA`, mas acesso E2E e confiança TLS pendentes. Ferret 2.4.3 em produção, v5 candidata. Bacula Director saudável, agendamento/restore não aceitos. OpenBao unsealed, ainda há validações de AppRole/custódia.

**OpenSUSE pessoal:** Connector Docker foi isolado; isto NÃO implica que o Twingate Client esteja conectado. Último teste do Client retornou `not-running`, e o alias Wazuh não foi resolvido. O script `opensuse/ce-client.sh` apenas consulta; para ativação interativa, a documentação oficial Linux orienta executar `twingate start` **sem sudo**, depois `twingate status` e `twingate resources`. O `twingate start` aciona apenas o Client, não o Connector Docker pessoal.

## Inventário de PRs abertas na verificação de 31/10

- #200 desenho ZT; #203 audit log; #205 login/MFA; #206 confidence DLP; #207 Ferret UI; #213 Connector DMZ; #214 documentação Connectors.
- Estes scripts devem ser usados como preflight para revisar cada PR, e não como sinal de autorização de merge.

## Prazos do Trello

- Freeze interno **07/11/2026**; Pentest B **08–14/11**; revisão final **15–16/11**; apresentação **17/11**.

## Limitações honestas

Esses scripts não foram executados nas VMs neste commit. O teste estático verifica sintaxe e recusa de ações proibidas. A precisão das portas, paths e nomes deve ser confirmada na primeira coleta focalizada de cada tarefa. `health=healthy` não demonstra acesso por identidade, MFA efetivo, backup restaurável, segregação interzona ou prevenção de vazamento.
