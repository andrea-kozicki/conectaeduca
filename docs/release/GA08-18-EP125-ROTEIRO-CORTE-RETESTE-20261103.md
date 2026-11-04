# GA-08.18 / PA-02 — checklist de campo, critérios de aborto e reteste EP125

**Preparado em:** 02/11/2026 BRT. **Uso previsto:** janela autorizada após snapshot EP125 em 03/11.
**Classificação:** CHECKLIST DOCUMENTAL; NÃO HABILITA DEPLOY, NÃO EXECUTA SCRIPT, NÃO MODIFICA PR #217.
**Código e procedimento técnico canônicos:** [PR #217](https://github.com/andrea-kozicki/conectaeduca/pull/217), arquivo [GA08-17B-CHANGE-CONTROL-EP125-20261102.md](https://github.com/andrea-kozicki/conectaeduca/blob/fix/pa02-ga08-dual-socket-gated-20261102/docs/release/GA08-17B-CHANGE-CONTROL-EP125-20261102.md) *(caso o nome da branch mude, abrir o arquivo pela lista de arquivos da PR #217)*. Se houver conflito entre este checklist e o documento canônico atualizado, **parar e reconciliar**.

## Adendo 04/11 — situação após tentativa real de corte

Este roteiro foi escrito **antes** da janela de 03/11 e suas tabelas G0 pendentes refletem o planejamento inicial. A responsável concluiu GA08.18F/G/H (preflight e atestação), **executou cutover real**, que falhou em php unhealthy (GA08.19), e **executou rollback Docker real** com PHP/Nginx/WAF healthy (GA08.19R). A verificação HTTP funcional **não está concluída**: teste em 18443 usou porta de laboratório e a saída 19T não incluiu status HTTP. PA-02 permanece ABERTO. O registro técnico autoritativo atualizado está em [Incidente e rollback GA08 03/11](../fase3/GA08-PA02-INCIDENTE-CUTOVER-ROLLBACK-20261103.md). **Não reutilizar o mesmo change ID nem repetir cutover antes de investigação do PHP.**

## 1. Mudança em uma frase
Impedir bypass local do WAF via Nginx TCP/8080 na bridge Docker EP125, usando candidato **socket HTTP Unix WAF→Nginx + socket FastCGI Unix Nginx→PHP-FPM** e segregação das redes de serviço. Preservar a publicação legítima HTTPS/443, aplicativo, autenticação/MFA/RBAC, SQL EP126 e audit.log/Wazuh.

**Evidência original:** WAF negou amostra HTTP com 403, mas acesso direto do host EP125 ao Nginx por bridge retornou 200 sem inspeção WAF. Isso **não é** prova de exploração XSS/SQLi nem exposição WAN do Nginx. O Twingate, sozinho, não filtra o caminho host→bridge.

## 2. Não repetir baterias aprovadas (e seus limites)
| Gate | Evidência observada até 02/11 | Limitação |
| --- | --- | --- |
| GA08.10 | 7/7 contrato e 11/11 Compose PASS | estático |
| GA08.11–12 | HTTP socket + FastCGI socket efêmeros PASS | não produção |
| GA08.13–15 | CRS ModSecurity atual, benigno 200, amostra 403, IDs correlatos | backend TCP anterior |
| GA08.16 v2 | entrypoint WAF/CRS + dual socket em ensaio isolado PASS | sem TLS institucional/app/SQL |
| GA08.17 | baseline de 10 Compose preservado, hashes PASS | não restauração |
| GA08.17A/17C | 8 binds visíveis; seis fontes no host sem acesso; WAF/Nginx **9 Compose**, PHP **10**; 3 serviços healthy/0 restarts | proteção/recuperação de binds não comprovada |
| CI da PR #217 | 6 workflows success no HEAD `67ab035b...` em 02/11 | sem deploy |

## 3. Gate G0 — não iniciar enquanto algum campo estiver vazio
| Campo de confirmação | Preencher somente com informação verificada |
| --- | --- |
| Snapshot EP125 (ID, UTC/BRT, hipervisor, operador) | **PENDENTE** |
| Snapshot inclui discos necessários, e recuperação foi confirmada pelo suporte | **PENDENTE** |
| Seis fontes protegidas dos binds e TLS/CA/segredos recuperáveis; sem divulgá-los | **PENDENTE** |
| Plano de rollback Docker revisado pela operadora, imagens antigas disponíveis | **PENDENTE DE ACEITE** |
| Caminho de retorno pelo snapshot se rollback Docker falhar | **PENDENTE** |
| Janela, responsável, comunicação, tempo de indisponibilidade aceitável | **PENDENTE** |
| Autorização consciente da responsável técnica para o que lhe foi delegado; autorização institucional extra apenas se exigida pela norma local | **PENDENTE** |
| EP126 SQL e telemetria Wazuh acessíveis no momento do teste | **PENDENTE DE CONFIRMAÇÃO** |
| Git EP125 e Compose sem drift inesperado desde o preflight | **PENDENTE DE CONFIRMAÇÃO** |

**Responsabilidades:** a responsável do laboratório pode autorizar/operar a mudança Docker no escopo de suas permissões concedidas, conforme runbook #217; o suporte deve identificar/cobrir/confirmar snapshot e ações fora de seu alcance. Nunca transformar privilégio sudo/Docker em prova de autorização de mudança.

## 4. Preservar a topologia Compose real, não apenas o YAML do Git
- Baseline de **WAF e Nginx: nove arquivos Compose efetivos**, numerados 01–09 no GA08-17B; **PHP: dez arquivos**, incluindo o `deploy/dmz/compose.audit-persistent.yml` local, não versionado, que sustenta auditoria PHP.
- Candidato: além dos arquivos efetivos, overlays `compose.ga08-socket.candidate.yml` e `compose.ga08-dual-socket.candidate.yml` (último na ordem).
- Verificar via preflight protegido a configuração resolvida de **dois conjuntos distintos**; não publicar `docker compose config` bruto, variáveis, chaves ou volumes sensíveis.
- Diretórios HTTP socket UID/GID 101:101 modo 0700 e FastCGI UID/GID 82:82 modo 0770, em paths persistentes aprovados. Proibir `chmod 777`, uso de `/tmp` efêmero e recriação acidental dos binds.
- Parâmetros/serviços/tags/imagens e os scripts de implantação e rollback **já estão versionados na PR #217**, mas intencionalmente sujeitos a interlocks. **Este documento não oferece atalhos para contornar o bloqueio**.
- **Não** usar `docker compose down -v`, `pull`, `build`, `prune`, `git reset --hard` ou reconstrução de stack genérica nesta janela.

## 5. Sequência de campo depois que G0 estiver integralmente satisfeito
1. **Antes:** congelar concorrência; registrar horário, HEAD, hashes do pacote, IDs de imagem, labels dos 9/10 arquivos Compose, estado dos três serviços, TLS com CA confiável e operação positiva da aplicação/SQL/Wazuh. Incluir a verificação de persistência da auditoria PHP.
2. **Verificar configurações e custódia:** `docker compose config --quiet` de cada conjunto com env real; confirmar portas 80/443 WAF, ausência de listener HTTP TCP Nginx, mounts e usuários; verificar CA/segredos apenas por metadados. Se qualquer campo divergir, **abortar**.
3. **Aplicar somente o procedimento controlado da PR #217** mediante seus interlocks e confirmação consciente na janela; observar a sequência PHP→Nginx→WAF e evitar afetar serviços fora do escopo. Nenhum ensaio efêmero habilita execução automática.
4. **Imediatamente após:** verificar 3/3 healthy, HTTP benigno 200, amostra CRS inerte 403 e correlação WAF, acesso real HTTPS com CA, login/MFA/RBAC, operação PHP→SQL EP126 e ingestão de auditoria Wazuh.
5. **PA-02 negativo:** descobrir a bridge/IP **atual** do Nginx (não fixar 172.18.0.2); verificar que o host EP125 não alcança Nginx:8080 diretamente; verificar também peer não autorizado e PHP→Nginx TCP negados; confirmar que o caminho permitido WAF→socket→Nginx→PHP continua vivo.
6. **Aceite ou retorno:** qualquer regressão crítica aciona o plano de rollback (Seção 7), não improvisação. Registre resultado e hashes em pasta de evidências com conteúdo minimizado.

## 6. Matriz GA-08.18 de retestes — não preencher PASS antecipadamente
| ID | Origem → destino | Resultado esperado | Evidência mínima |
| --- | --- | --- | --- |
| P02-POS-01 | navegador/client autorizado → HTTPS/443 WAF EP125 | 200 legítimo, TLS confiável | timestamp, HTTPS, validação CA, tela sanitizada |
| P02-POS-02 | WAF → Nginx socket HTTP → PHP socket FastCGI | operação legítima | health, socket metadata e resultado funcional |
| P02-POS-03 | usuário/empresa/admin conforme fixture → PHP/MFA/RBAC | permissões corretas | allow e deny funcional, sem sessão/cookie |
| P02-POS-04 | PHP EP125 → SQL EP126 e audit.log→Wazuh | consulta autorizada e telemetria | leitura funcional e alertas minimizados |
| P02-POS-05 | marcador benigno / payload CRS sintético → WAF | 200 / 403 com regra CRS | status, identificação de regra e correlação |
| P02-NEG-01 | host EP125 → IP bridge Nginx:8080 | **negação / ausência de TCP listener** | origem, destino **atual**, erro/timeout fechado |
| P02-NEG-02 | contêiner peer não autorizado → upstream | negação | identidade de peer e destino, sem alterar redes |
| P02-NEG-03 | PHP → Nginx:8080 e acesso sem WAF | negação | status de rede e listener |
| P02-REC-01 | rollback para baseline anterior (somente se requerido e autorizado) | recuperar serviço, CA, login, SQL, logs e binds | tempos e hashes; não reportar PASS sem restore efetivo |

**Aceite PA-02:** controles negativos e positivos no mesmo baseline, nenhuma regressão relevante, origem/rota verificadas; risco residual de administrador Docker e de caminhos não ensaiados descrito. A PR #217 pode permanecer DRAFT após um teste preliminar; **não** fechar a issue #204 por mera CI/health.

## 7. Critérios de aborto e recuperação
**Abortar/parar novas recriações se:** snapshot/cobertura não confirmados; segredo ou bind protegido inacessível; Compose 9/10 divergente; serviço unhealthy; HTTPS/TLS/MFA/RBAC/SQL degradado; CRS falhar; auditoria Wazuh desaparecer; rota direta continuar exposta; image ID não corresponder ao manifestado.

**Rollback recomendado:** seguir rigorosamente o GA08-17B e a implementação bloqueada da PR #217, preservando originais. PHP retorna com **10 arquivos**, WAF e Nginx com **9**, sem os dois overlays de socket. Se rollback por Compose não for praticável, acionar suporte para restauração do snapshot, preservando logs sanitizados e a integridade de volumes externos. Não afirmar que o rollback foi testado sem observação real.

## 8. Registro de conclusão de campo
```text
GA08_18=NAO_EXECUTADO
DATA_JANELA=
SNAPSHOT_EP125_ID=
SNAPSHOT_COBERTURA=
OPERADOR=
APROVACAO_ESCOPADA=
HEAD_EP125=
COMPOSE_WAF_NGINX=9
COMPOSE_PHP=10
BASELINE_APP_TLS_SQL_WAZUH=
CUTOVER_APLICADO=
P02_POS_PASS=N/A
P02_NEG_PASS=N/A
ROLLBACK_EXECUTADO=NAO
ESTADO_FINAL=PLANEJADO
EVIDENCIA_LOCAL_SANITIZADA=
SHA256_EVIDENCIA=
LIMITES_RISCO_RESIDUAL=
```

**Referência de continuidade:** [matriz Pentest B](../fase3/PA01-PA07-MATRIZ-PENTEST-A-B-20261102.md) e [handoff 03/11](../fase3/HANDOFF-03NOV-2026-ZT-PA-GA08-GA06.md).
