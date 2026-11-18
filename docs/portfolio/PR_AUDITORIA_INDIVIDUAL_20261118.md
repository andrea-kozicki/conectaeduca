# ConectaEduca — Auditoria individual das PRs abertas (18/11/2026)

**Escopo:** 23 PRs históricas abertas consultadas em 18/11/2026, antes da criação da candidata #265. **Fonte:** metadados, relações de arquivos e patches das 23 PRs; leitura aprofundada dos scripts de #224, #225, #226 e #228; comparação de todos os pacotes do composer.lock nas #216, #234 e #236 contra a main. Isto **não** significa execução dos códigos ou inspeção manual exaustiva de todas as linhas.

**Baseline GitHub:** main após [#262](https://github.com/andrea-kozicki/conectaeduca/pull/262) (patches UI Ferret), [#263](https://github.com/andrea-kozicki/conectaeduca/pull/263) (triagem), [#264](https://github.com/andrea-kozicki/conectaeduca/pull/264) (PHPMailer) e [#265](https://github.com/andrea-kozicki/conectaeduca/pull/265) (phpdotenv). Sem acesso às VMs, contêineres, tokens ou serviços institucionais.

## Resultado por pull request

| PR | Escopo efetivo no diff | Decisão individual |
| --- | --- | --- |
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) | 87 arquivos: arquitetura ZT, scripts GA-08/Bacula e Dockerfile PHP | BLOQUEADA: conflito e Dockerfile; separar documentos históricos de código operacional; não resolver digest por tentativa |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) | 14: auditoria PHP/Wazuh; Compose e AuditLogger já estão na main | PARCIAL: conferir agentes, regras, retenção e coleta antes de importar residuais; não duplicar logs |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) | 15: login híbrido v2, WAF/IP confiável, CSRF, rate limit e testes | BLOQUEADA PARA RUNTIME: exige homologação real de MFA, UX, navegador e fluxos positivos/negativos |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) | 5: regras DLP LOW/MEDIUM/HIGH e testes; XML igual à main, offline recuperado pela #260 | SOBREPOSTA: não mesclar inteira; verificar apenas residual, sem inferir Wazuh ativo |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) | 35: V4/V5 e testes já na main pela #262; V3, imagem, Compose e runbooks restantes | PARCIAL: exigir proveniência, UI real e rollback; não repetir cutover histórico |
| [#213](https://github.com/andrea-kozicki/conectaeduca/pull/213) | 15: Twingate DMZ, composição, scripts de implantação e preflight | BLOQUEIO OPERACIONAL: confirmar conector efetivo, tokens fora do Git e regras antes de eventual reutilização |
| [#214](https://github.com/andrea-kozicki/conectaeduca/pull/214) | 22: evidências ZT, pfSense e cliente, com scripts de diagnóstico | HISTÓRICO/PRIVACIDADE: separar narrativa pública de metadados institucionais; não importar como estado atual |
| [#215](https://github.com/andrea-kozicki/conectaeduca/pull/215) | 10: kits de preflight por VM/cliente, biblioteca Bash e bootstrap | REVISÃO SOURCE-ONLY: classificar efeitos dos comandos e reaproveitar somente testes portáveis |
| [#216](https://github.com/andrea-kozicki/conectaeduca/pull/216) | 1: composer.lock eleva phpdotenv, altera 2 Symfony polyfills e regride phpseclib 4.0.3→4.0.2 | SUBSTITUÍDA: #265 integrada à main somente com phpdotenv 5.8.0, mantendo outras versões |
| [#217](https://github.com/andrea-kozicki/conectaeduca/pull/217) | 36: dual socket GA-08, scripts de implantação/testes e change control anterior | BLOQUEADA: cotejar imagem PA-05, baseline PA-02 e rollback atual |
| [#218](https://github.com/andrea-kozicki/conectaeduca/pull/218) | 10: planos e documentos Pentest B, pfSense e cutovers 02–04/11 | HISTÓRICO: reescrever como recorte temporal após revisão de evidências |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) | 45: kit Pentest B R2/v2, scripts Python de campo e testes sintéticos | EXTRAÇÃO SELETIVA: não substituir o kit R3 por R2; reaproveitar só fixtures/testes sem efeitos |
| [#221](https://github.com/andrea-kozicki/conectaeduca/pull/221) | 5: inventário read-only e diário de reconciliação de 08/11 | PARCIAL/HISTÓRICO: scripts precisam de baseline atualizado; preservar evidências privadas |
| [#224](https://github.com/andrea-kozicki/conectaeduca/pull/224) | 2: sincronização dos checkouts com fetch, reset --mixed e restore, commit pinado | BLOQUEIO FORTE: não executar --apply; inventário read-only e backup aprovados primeiro |
| [#225](https://github.com/andrea-kozicki/conectaeduca/pull/225) | 2: logrotate audit PHP via sudo install; HEAD antigo e checks inode | BLOQUEADA: retenção/PII, ingestão após rotação, duplicatas e estado instalado |
| [#226](https://github.com/andrea-kozicki/conectaeduca/pull/226) | 3: script de cutover Ferret Docker v5 com IDs e rollback best-effort de 08/11 | HISTÓRICO/NÃO REEXECUTAR: baseline e imagem ultrapassados; rollback não ensaiado |
| [#227](https://github.com/andrea-kozicki/conectaeduca/pull/227) | 6: Bash já na main via #237; Fish, bootstrap e alinhador diferentes | PARCIAL: não reintegrar Bash; Fish não é implementação operacional exigida (#239) |
| [#228](https://github.com/andrea-kozicki/conectaeduca/pull/228) | 3: AppRole/ACL/KV2 OpenBao; script escreve policies/mount/role com token administrativo | BLOQUEADA: exige revisão de autorização, estado do cofre, menor privilégio e rollback |
| [#230](https://github.com/andrea-kozicki/conectaeduca/pull/230) | 13: PA-02 Unix HTTP/PA-05 com automações grandes de implantação | BLOQUEADA: comparar com GA-08/PA-05 efetivos, overlays e rollback antes de usar |
| [#232](https://github.com/andrea-kozicki/conectaeduca/pull/232) | 1: consolidado histórico 08/11 com revisão editorial #258 | HISTÓRICO/DIVERGÊNCIA: PA-05 DEP02 PENDENTE_DE_CONCILIACAO; publicação sujeita a evidência primária |
| [#234](https://github.com/andrea-kozicki/conectaeduca/pull/234) | 1: composer.lock altera PHPUnit, coverage, sebastian/version, remove theseer/tokenizer e regride phpseclib | REVISAR GRAFO: não mesclar o lock inteiro; candidato posterior deve ser resolvido por Composer e CI |
| [#235](https://github.com/andrea-kozicki/conectaeduca/pull/235) | 1: Pentest B de 10–12/11 com edição #257; branch continua histórica | HISTÓRICO/PRIVACIDADE: confrontar com relatório final; conflito no corte; não forçar merge |
| [#236](https://github.com/andrea-kozicki/conectaeduca/pull/236) | 1: composer.lock altera PHPMailer e regride phpseclib; CI antiga falhou em Audit locked dependencies | SUBSTITUÍDA: #264 integrada com PHPMailer 7.2.0 mantendo phpseclib 4.0.3 |

## Atualização posterior — substituições #267 e #268 (18/11/2026)

Este registro é **posterior** à fotografia das 23 PRs históricas acima e não reescreve a contagem daquele corte.

| Referência | Resultado comprovado | Limite preservado |
| --- | --- | --- |
| [#234](https://github.com/andrea-kozicki/conectaeduca/pull/234) → [#267](https://github.com/andrea-kozicki/conectaeduca/pull/267) | #267 **integrada à `main`** (`34312a901a3e8341138e2f87afedb3a89e75c808`), PHPUnit 13.4.6, code-coverage 14.5.2, sebastian/version 7.1.0 e theseer/tokenizer removido; 6/6 workflows e Snyk PASS. #234 encerrada **sem merge** pelo Dependabot | Testes PHP e instalação Composer no runner não provam runtime EP125; sem downgrades de PHPMailer/phpdotenv/phpseclib |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) → [#268](https://github.com/andrea-kozicki/conectaeduca/pull/268) | #268 **integrada à `main`** (`59b0aba873b1765aad97ba6394ea1a6983be4f8d`), somente gerador DLP-04 fictício, 7/7 testes offline, workflow isolado; 7/7 Actions e Snyk PASS | #219 permanece DRAFT; fixture não é scan, detecção DLP, prova de exfiltração ou validação de R2/R3 |

**#206 encerrada sem merge (18/11):** revisados os blobs da regra DLP (`8d332c7adb8820789219c5c6e6b048eeecc178d2`) e do validador (`6a7f0a08027d8a38dffacc0e31f4f1c183d30368`), ambos idênticos na `main`. A [#260](https://github.com/andrea-kozicki/conectaeduca/pull/260) já incorporou o teste de contrato em versão com marcador sintético, executado por workflow isolado. A #206 foi fechada individualmente como substituída; isso **não** comprova regra efetivamente carregada no Wazuh nem E2E.

**Pacotes de produção preservados após as integrações:** PHPMailer 7.2.0, phpdotenv 5.8.0 e phpseclib 4.0.3. Nenhum arquivo `Dockerfile`, Compose, regra Wazuh, autenticação, VM ou tenant Twingate foi modificado nesta rodada.

**Próximo recorte source-only:** analisar componentes de #215 antes de extração (o kit contém sonda `curl --insecure` e criação de diretórios locais) e os módulos de teste da #219 que dependem de código ativo não integrado. Se não houver prova de independência/offline, não copiar para a `main`. Documentação #214/#218/#232/#235 segue sujeita à revisão de privacidade.

## Fechamento source-only adicional — 18/11/2026

Este bloco é **posterior** à fotografia original de 23 PRs abertas; não altera suas contagens nem substitui as revisões históricas.

| Referência | Resultado comprovado e limite |
| --- | --- |
| [#215](https://github.com/andrea-kozicki/conectaeduca/pull/215) | Bootstrap histórico corrigido na própria branch: SHA do smoke e commit PIN alinhados à fila atualizada EP126; teste de contrato de 8 blobs com Git, **8/8 workflows + Snyk PASS**. **Continua DRAFT:** faz leituras de Docker, HTTP com `curl --insecure` e `prepare` cria diretórios, sem autorização para execução institucional |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) / [#270](https://github.com/andrea-kozicki/conectaeduca/pull/270) | Comparador ZT-01 isolado, **15/15 testes offline** e **7/7 workflows + Snyk PASS**, merge `887a3a59fc5306690ad853d8a188db3caa96023c`. Continua sem prova de identidade/MFA/RBAC real; #219 DRAFT |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) / [#272](https://github.com/andrea-kozicki/conectaeduca/pull/272) | Contrato estático WAF de origem confiável, **8/8 testes offline** e **7/7 workflows + Snyk PASS**, merge `7e6c724ecc25b602ef8f0cd469abc0b687f83a15`. **Não integra login v2**, não comprova sobrescrita de header em runtime; #205 DRAFT |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) / [#274](https://github.com/andrea-kozicki/conectaeduca/pull/274) | Template `logrotate.conf.in` não ativável + **3/3 testes sintéticos**, incluindo duas rotações em diretório temporário, **7/7 workflows + Snyk PASS**; merge `fbda89d6d17ca2af998da32aae0eb4c5efe64b52`. **Não instalou logrotate, não leu audit.log, não testou Wazuh real**; #203/#225 DRAFT |
| [#271](https://github.com/andrea-kozicki/conectaeduca/pull/271) / [#273](https://github.com/andrea-kozicki/conectaeduca/pull/273) | Matriz de **12 gates PENDING_VM e 3 gates PENDING_DOC_REVIEW**, com teste CI que impede PASS de runtime por mera integração de fonte; ambos integrados, sem mutações institucionais |

**Documentação histórica:** PRs #214/#218/#232/#235 receberam comentários individuais com ressalvas temporais, privacidade e divergências de fonte (incluindo PA-05 DEP02 pendente). Permanecem DRAFT sem merge; nenhum arquivo bruto ou relato sem revisão foi publicado nesta rodada.

**Trello:** comentários de rastreabilidade adicionados aos cartões de reconciliação GitHub↔VM e DOC-01; nenhum card foi marcado como concluído sem evidência de runtime.

**Próximo checkpoint técnico:** comparar inventário GitHub↔EP125/EP126 e snapshots somente quando houver acesso/autorização. Preservar Dockerfile da main e não reexecutar scripts operacionais históricos.

## Decisões de governança

- **Igualdade de Git blob não comprova igualdade de runtime.** Regras e processadores absorvidos na main não justificam merge de scripts operacionais legados.
- **CI verde não é homologação institucional.** Não executar instalação, sincronização de checkout, mudança de IAM/policies ou reconfiguração de rede sem baseline atualizado, aprovação e rollback.
- **Histórico público permanece público.** Sanitizar a ponta de uma branch não remove identificadores de commits antigos; revisar privacidade e custódia antes de nova publicação.
- **Alterações em composer.lock requerem inspeção de todo o grafo.** As PRs #216/#234/#236 demonstraram downgrade colateral de phpseclib; a #236 já foi substituída pela #264 e a #216 foi substituída pela #265 integrada à main.
- **Não encerrar ou mesclar em lote** as 23 PRs: classificação não equivale a autorização para alterar o histórico.

## Próximas prioridades sem VM

1. Tratar PHPUnit #234 por atualização Composer isolada; não rebaixar phpseclib.
2. Auditar testes/fixtures puramente offline do Pentest B #219 e do preflight #215 antes de qualquer nova extração.
3. Conciliar documentos #214/#218/#232/#235 com relatórios finais e limitações de privacidade.
4. Preservar bloqueios de #200/#205/#213/#217/#224/#225/#226/#228/#230 até evidência operacional e mudança autorizada.

**Limite temporal:** status de CI, conflitos e PRs abertas pode mudar. Este arquivo é uma triagem datada e **não** uma instrução para implantar código.

## Atualização de preparação de VMs — #276 (18/11/2026)

- [#276](https://github.com/andrea-kozicki/conectaeduca/pull/276) incorporou inventário Git exclusivamente local com **10 testes sintéticos** e workflow offline; 7/7 GitHub Actions mais Snyk aprovados. Modo padrão `PLAN_ONLY_NOT_EXECUTED` e opção futura `--execute-readonly` bloqueada fora de hostname institucional ou como root.
- A PR #215 permanece DRAFT porque seu bootstrap e checks incluem download, criação de evidências e `curl --insecure`. **Proveniência verificada:** os oito arquivos do manifesto foram comparados por Git blob SHA e coincidem com o PIN imutável `ac4bb727e6adc1b127d1a2e7c1eac94fa69c1882`; isso não homologa execução de probes ou mudanças na VM.
- A PR #221 permanece DRAFT: sua coleta read-only inclui consultas ao Docker/systemd e usa baseline remoto histórico 08/11; #276 não repete esses comportamentos.
- Roteiro de execução autorizada e 12 gates ainda pendentes em [CE-PREVM-GATES-20261118.md](../operacao/CE-PREVM-GATES-20261118.md). **Nenhum dos gates de runtime está fechado por #276.**
