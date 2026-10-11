# PA-06 — observabilidade e histórico; PA-07 — abertura (11/10/2026)

> Complemento **exclusivamente documental**, posterior ao snapshot de 09/10. Evidências originais, screenshots e logs não foram commitados. Relatório acadêmico **v22** (39 páginas, DOCX/PDF) permanece artefato separado. O freeze de EP125/EP126 não foi alterado.

## PA-06.A/B — inventários passivos

- EP125, 11/10/2026 20:20:38 UTC, `teste`, UID/EUID 1001, CapEff 0: Wazuh Agent, Suricata e auditd declarados `active/running`; arquivos/diretórios protegidos sem escrita estimada em caminhos avaliados. TXT SHA-256: `6faaa784f656167ae0e62c2c9aab211208885606e64c03d630670c137e80d91c` (sidecar verificado).
- EP126, 11/10/2026 20:25:42 UTC, mesma identidade: Wazuh Agent, auditd e Bacula FD `active/running`; Suricata não detectado como unidade de host EP126 (a implantação de sensor de rede avaliada está na DMZ); processos de container podem não ser observáveis como unidades. TXT SHA-256: `19f9e16370656a2d1bdb5d044bdec55b2a67a60428648a2b183927809395402d` (sidecar verificado). O cabeçalho dessa evidência menciona PA-06.A por erro editorial; versão e host identificam PA-06.B.
- Sem sudo, leitura do conteúdo de logs/segredos, Docker API, alteração de serviços ou ensaio de evasão.

## PA-06.C — Wazuh readonly e SCA

- Agentes `001 ep125-pucpr` e `002 ep126-pucpr` vistos `active`, Wazuh v4.14.7, grupos `conectaeduca-dmz` / `conectaeduca-interna`. Threat Hunting exibia 34.560 registros no período de 24h selecionado; **não atribuir causalidade** ao PA-06.A/B.
- Política SCA DMZ: **10 passed, 0 failed, 0 N/A = 100%**; política interna: **8 passed, 0 failed, 1 N/A = 100% dos checks aplicáveis**. CIS Ubuntu 24.04 v1.0.0 apresentou 114 passed/156 failed/9 N/A = 42% no recorte visual de ambas as VMs. Nenhum score representa segurança integral.
- Causa do N/A no check interno **12108** confirmada no próprio Wazuh: `FILE_EXISTS(/var/run/docker.sock) -> RETURN_INVALID: Not a regular file.`. A regra original usa `f:/var/run/docker.sock` para socket Unix. PA-06.B observou o socket (0660 UID0 GID999). **Falha de cobertura da regra SCA**, não de execução do Docker. Correção sob change control futuro.
- O operador precisou ultrapassar um aviso HTTPS do Dashboard; a confiança do certificado não foi comprovada e requer avaliação separada.

## PA-06.D — Auditd indexado

- Na busca do agente 001, CSV exportado exibiu 316 linhas: regra 80730 (Auditd: SELinux permission check.) **315 alertas level3** e regra 591 (Log file rotated.) **um level3**. SHA-256 calculado sobre o CSV recebido `d24f5172abb492230e63ea5d8b4735737b6028e6bbaf1bb59f2f7731e5813411`, sem sidecar de origem.
- Expansão de um evento: `decoder.name=auditd`, `location=/var/log/audit/audit.log`, `data.audit.type=AVC`, `data.audit.uid=0`. Evidência de ingestão/decodificação histórica no Wazuh. Não demonstra SELinux enforcing, ataque root ou detecção de evasão.

## PA-06.E — correlação de arquivo sintético FIM/YARA

Consulta read-only de 90 dias recuperou, em 02/09/2026, três ocorrências `110201` (criação FIM, level7) e três `110211` (match YARA benigno, level12); `110200` não retornou hit no recorte.

Par de eventos correlacionado por **igualdade integral do caminho do arquivo sintético** no diretório `/var/tmp/conectaeduca-fim-demo-ep125/`, agente 001 e ordem temporal:
- `110201` FIM: `2026-09-02T23:35:26.560Z`, `syscheck.event=added`, `mode=realtime`, decoder `syscheck_new_entry`.
- `110211` YARA: `2026-09-02T23:35:28.851Z`, decoder `conectaeduca_yara_decoder`, rule `ConectaEduca_Benign_Demo`, location `/var/ossec/logs/active-responses.log`.
- Diferença **2,291 s**. Não há ID transacional comum que prove isoladamente cada execução interna, mas a correlação histórica do mesmo arquivo é forte.

**PA-06:** PASS **somente da correlação histórica de detecção FIM/YARA**; eixo global **PARCIAL / EM TESTE**, sem verificação atual de evasão, adulteração de defesa ou bloqueio de malware.

## PA-07 — gate de entrada

O eixo PA-07 investiga exposição de dados (T1005), canais de exfiltração (T1041) e proteção de backup/recuperação (T1490), partindo de identidade `teste` sem privilégios e somente dentro do escopo autorizado. Pipeline Ferret `inbox/ -> reports/raw/ -> sanitizador -> events/dlp.jsonl -> Wazuh` e Bacula/restore de implantação são **controles preexistentes**, não evidência de execução ofensiva PA-07.

O tijolo **PA-07.A/EP126**, preparado e **não executado na VM** nesta data, faz somente triagem de metadados de diretórios candidatos com lstat/os.access, sem ler conteúdo, listar diretórios, invocar Docker/MariaDB/OpenBao/Bacula ou abrir conexões. A execução gerará TXT + SHA-256 fora do Git. Não presumir exposição, detecção DLP ou egresso bloqueado.

## Governança da evidência

Fontes: TXT/sidecars PA-06.A/B, screenshots e trechos expandidos Wazuh compartilhados em chat (sem sidecars individuais), CSV Auditd (hash calculado ao receber), regras SCA/YARA versionadas no repositório e documentação histórica. Nenhum `full_log`, JSON bruto, valor de cookie/token/senha, arquivo de backup, conteúdo DLP ou imagem de perfil foi versionado. Sem mudança em VM/serviço, sem ativação de Twingate e sem merge automático.
