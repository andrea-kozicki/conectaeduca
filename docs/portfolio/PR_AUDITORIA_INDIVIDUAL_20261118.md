# ConectaEduca — Auditoria individual das PRs abertas (18/11/2026)

**Escopo:** 23 PRs históricas abertas consultadas em 18/11/2026, antes da criação da candidata #265. **Fonte:** metadados, relações de arquivos e patches das 23 PRs; leitura aprofundada dos scripts de #224, #225, #226 e #228; comparação de todos os pacotes do composer.lock nas #216, #234 e #236 contra a main. Isto **não** significa execução dos códigos ou inspeção manual exaustiva de todas as linhas.

**Baseline GitHub:** main após [#262](https://github.com/andrea-kozicki/conectaeduca/pull/262) (patches UI Ferret), [#263](https://github.com/andrea-kozicki/conectaeduca/pull/263) (triagem) e [#264](https://github.com/andrea-kozicki/conectaeduca/pull/264) (PHPMailer). Sem acesso às VMs, contêineres, tokens ou serviços institucionais.

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
| [#216](https://github.com/andrea-kozicki/conectaeduca/pull/216) | 1: composer.lock eleva phpdotenv, altera 2 Symfony polyfills e regride phpseclib 4.0.3→4.0.2 | NÃO MESCLAR ORIGINAL: #265 isola phpdotenv 5.8.0, condicionado a CI |
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

## Decisões de governança

- **Igualdade de Git blob não comprova igualdade de runtime.** Regras e processadores absorvidos na main não justificam merge de scripts operacionais legados.
- **CI verde não é homologação institucional.** Não executar instalação, sincronização de checkout, mudança de IAM/policies ou reconfiguração de rede sem baseline atualizado, aprovação e rollback.
- **Histórico público permanece público.** Sanitizar a ponta de uma branch não remove identificadores de commits antigos; revisar privacidade e custódia antes de nova publicação.
- **Alterações em composer.lock requerem inspeção de todo o grafo.** As PRs #216/#234/#236 demonstraram downgrade colateral de phpseclib; a #236 já foi substituída pela #264 e a #216 tem candidata isolada #265.
- **Não encerrar ou mesclar em lote** as 23 PRs: classificação não equivale a autorização para alterar o histórico.

## Próximas prioridades sem VM

1. Terminar CI/aceite da #265 e tratar PHPUnit #234 por atualização Composer isolada; não rebaixar phpseclib.
2. Auditar testes/fixtures puramente offline do Pentest B #219 e do preflight #215 antes de qualquer nova extração.
3. Conciliar documentos #214/#218/#232/#235 com relatórios finais e limitações de privacidade.
4. Preservar bloqueios de #200/#205/#213/#217/#224/#225/#226/#228/#230 até evidência operacional e mudança autorizada.

**Limite temporal:** status de CI, conflitos e PRs abertas pode mudar. Este arquivo é uma triagem datada e **não** uma instrução para implantar código.
