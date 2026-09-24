# Matriz MITRE ATT&CK — ConectaEduca

## Escopo

Esta matriz relaciona cenários acadêmicos do ConectaEduca a técnicas MITRE
ATT&CK e aos controles realmente presentes no projeto.

A associação ATT&CK descreve o comportamento simulado. Ela não afirma que o
ambiente sofreu ataque real.

| Cenário | ATT&CK | Tática principal | Controle ConectaEduca | Teste/Evidência | Estado |
|---|---|---|---|---|---|
| Exploração da aplicação pública | T1190 Exploit Public-Facing Application | Initial Access | DMZ, Nginx, WAF/ModSecurity CRS, hardening PHP | probes XSS/SQLi/path traversal + HTTP esperado + WAF/Wazuh | baseline validado; DAST dedicado pendente |
| Descoberta de serviços | T1046 Network Service Discovery | Discovery | pfSense, segmentação, allowlist de portas, Suricata | varredura autorizada entre zonas e comparação OPEN/BLOCK | planejado para Pentest A/B |
| Uso de conta legítima mínima | T1078 Valid Accounts | múltiplas | identidades `teste`, RBAC/ACL/policies mínimas | login positivo seguido de ações fora de escopo negadas | parcialmente validado; checklist sem sudo obrigatório |
| SSH como serviço remoto | T1021.004 Remote Services: SSH | Lateral Movement | pfSense, contas sem sudo, SSH restrito, logging | conexão somente onde autorizada + tentativa lateral bloqueada | executar conforme permissão institucional |
| RDP como serviço remoto | T1021.001 Remote Desktop Protocol | Lateral Movement | pfSense/segmentação | tentativa cross-zone negada | comportamento de rede já observado; repetir se necessário |
| Força bruta/guessing controlado | T1110 / T1110.001 Password Guessing | Credential Access | rate limiting, lockout OpenBao, autenticação de serviços | poucas tentativas sintéticas dentro do limite acadêmico | planejar sem teste volumétrico |
| Credenciais em arquivos | T1552.001 Credentials In Files | Credential Access | secrets fora do Git, runtime 0600, Gitleaks, tmpfs | busca controlada por arquivos candidatos sem exfiltrar conteúdo | planejado |
| Chaves privadas expostas | T1552.004 Private Keys | Credential Access | exclusões de backup, PKI protegida, permissões | provar negação/permissões e ausência no bundle/backup genérico | planejado |
| API/artefato de container como caminho de credencial | T1552.007 Container API | Credential Access | `teste` fora do grupo docker, sem Docker socket nas GUIs | `teste` deve falhar ao administrar Docker; inspeção de mounts | gate pré-pentest |
| Escape de container para host | T1611 Escape to Host | Privilege Escalation | non-root, rootfs RO, cap_drop ALL, NNP, sem privileged/socket | inspeção de runtime + tentativa segura proibida | planejado |
| Desabilitar/alterar controles | T1562.001 Impair Defenses: Disable or Modify Tools | Defense Evasion | `teste` sem sudo, ACL Wazuh/OpenBao/Bacula, serviços protegidos | ações administrativas não destrutivas devem ser negadas | planejado |
| Movimento lateral por serviço remoto | T1021 Remote Services | Lateral Movement | pfSense + menor privilégio | tentativa de alcançar serviço/porta fora da allowlist | planejado |
| Exfiltração por canal de rede | T1041 Exfiltration Over C2 Channel (analogia de laboratório) | Exfiltration | egress mínimo pfSense, DLP/Ferret, Wazuh | marcador sintético, volume pequeno, destino autorizado de laboratório | planejado; não usar dados reais |
| Abuso de privilégio em banco | T1078 + autorização SQL | Privilege Escalation | roles SQL read-only | SELECT permitido; DML/DDL negado | MariaDB/Catalog devem ser revalidados sem sudo |
| Acesso indevido a segredos | T1078 + T1552.001 | Credential Access | OpenBao userpass + policy mínima | path laboratório permitido; SMTP/path vizinho/admin negados | caminho humano deve ser validado antes do Pentest A |

## Cenários acadêmicos obrigatórios

### Movimento lateral

Cobertura principal: T1046, T1021/T1021.004 e T1078.

Resultado esperado: descoberta pode observar somente a superfície permitida e
a posse da conta `teste` não deve atravessar zonas nem ampliar autorização.

### Escalação de privilégios

Cobertura principal: T1078, T1611 e T1552.007.

Resultado esperado: `teste` permanece sem sudo/wheel/docker, não administra
containers e não converte uma identidade read-only em acesso administrativo.

### Evasão de defesa

Cobertura principal: T1562.001 e T1078.

Resultado esperado: a conta de pentest não consegue desligar ou reconfigurar
Wazuh, Suricata, WAF, Ferret, OpenBao ou Bacula fora das ACLs previstas.

### Vazamento / exfiltração

Cobertura principal: T1552.001, T1552.004 e T1041.

Resultado esperado: arquivos sensíveis não ficam disponíveis à identidade
mínima; egress não autorizado é bloqueado/observado; DLP/SIEM geram telemetria
quando aplicável.

## Regra de evidência

Cada teste deve registrar:

1. técnica ATT&CK;
2. origem e alvo;
3. identidade usada;
4. pré-condição;
5. ação segura executada;
6. resultado esperado;
7. resultado observado;
8. controle que impediu/detectou;
9. telemetria correspondente;
10. evidência e SHA-256.
