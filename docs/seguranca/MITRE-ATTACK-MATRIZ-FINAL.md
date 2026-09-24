# Matriz MITRE ATT&CK — ConectaEduca

## Escopo

A matriz relaciona cenários acadêmicos a técnicas ATT&CK e aos controles do projeto. A associação descreve comportamento simulado em laboratório; não afirma ocorrência de ataque real.

| Cenário | ATT&CK | Controle ConectaEduca | Evidência/teste | Estado |
|---|---|---|---|---|
| Exploração de aplicação pública | T1190 Exploit Public-Facing Application | DMZ, Nginx, WAF/CRS, hardening PHP | probes XSS/SQLi/path traversal + WAF/Wazuh | baseline validado; DAST dedicado pendente |
| Descoberta de serviços | T1046 Network Service Discovery | pfSense, segmentação, Suricata | varredura autorizada e comparação OPEN/BLOCK | Pentest A/B |
| Uso de conta legítima mínima | T1078 Valid Accounts | identidades `teste`, RBAC/ACL/policies | login permitido + ações fora de escopo negadas | gate sem sudo obrigatório |
| SSH | T1021.004 Remote Services: SSH | pfSense, usuário sem sudo, logging | conexão somente onde autorizada e tentativa lateral negada | conforme permissão institucional |
| RDP | T1021.001 Remote Desktop Protocol | pfSense/segmentação | tentativa cross-zone negada | comportamento já observado |
| Password guessing controlado | T1110.001 Password Guessing | rate limiting, lockout e autenticação | poucas tentativas sintéticas, não volumétricas | planejado |
| Credenciais em arquivos | T1552.001 Credentials In Files | runtime 0600, secrets fora do Git, Gitleaks | busca controlada sem revelar conteúdo | planejado |
| Chaves privadas | T1552.004 Private Keys | PKI protegida e exclusões de backup | permissões/negação + ausência em bundles genéricos | planejado |
| Container API | T1552.007 Container API | `teste` fora do grupo docker; GUIs sem socket | provar que o pentester não administra Docker | gate pré-pentest |
| Escape de container | T1611 Escape to Host | non-root, rootfs RO, cap_drop, NNP | inspeção de runtime + teste seguro de fronteira | planejado |
| Desabilitar controles | T1562.001 Impair Defenses | `teste` sem sudo + ACLs mínimas | ações administrativas não destrutivas devem ser negadas | planejado |
| Movimento lateral | T1021 Remote Services | pfSense + menor privilégio | alcançar somente portas/serviços permitidos | planejado |
| Exfiltração por rede | T1041 Exfiltration Over C2 Channel, usada como analogia de laboratório | egress mínimo, Ferret/DLP, Wazuh | marcador sintético pequeno para destino autorizado | planejado |

## Cenários acadêmicos principais

**Movimento lateral:** T1046, T1021/T1021.004 e T1078. A conta `teste` não deve atravessar zonas nem ampliar autorização.

**Escalação de privilégios:** T1078, T1611 e T1552.007. `teste` deve permanecer fora de sudo/wheel/docker e não administrar containers.

**Evasão de defesa:** T1562.001. A identidade mínima não deve conseguir desligar/reconfigurar Wazuh, Suricata, WAF, Ferret, OpenBao ou Bacula.

**Vazamento/exfiltração:** T1552.001, T1552.004 e T1041. Usar somente dados/marcadores sintéticos; nunca exfiltrar informação real.

## Regra de evidência

Cada execução deve registrar técnica ATT&CK, origem/alvo, identidade usada, pré-condição, ação segura, esperado, observado, controle preventivo/detectivo, telemetria e evidência + SHA-256.
