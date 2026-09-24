# Roteiro de demonstração final — ConectaEduca

## Objetivo

Fornecer uma sequência curta e reproduzível para demonstrar a arquitetura,
os controles preventivos/detectivos e o princípio do menor privilégio sem
depender de improviso durante a avaliação.

A demonstração deve priorizar **controle + evidência + teste negativo**, e não
uma visita extensa a cada tela.

## Ordem sugerida

### 1. Arquitetura e segmentação

Mostrar o diagrama final e explicar:

- EP125 = DMZ;
- EP126 = rede interna;
- pfSense entre as zonas;
- serviços públicos separados de banco, cofre, SIEM e backup;
- fluxos mínimos liberados e tráfego lateral negado por padrão.

Evidência desejada:

- regra/alias relevante no pfSense;
- teste permitido conhecido;
- teste lateral negado conhecido.

### 2. pfSense / Suricata

Mostrar:

- interfaces e regras principais;
- Suricata ativo;
- evento de laboratório já conhecido ou novo probe seguro;
- correlação temporal com Wazuh quando aplicável.

Se o SSH estiver habilitado pelo professor/suporte, ele pode complementar a
WebGUI para consultas e evidências de shell. Não usar SSH como justificativa
para ampliar privilégios do usuário de pentest.

### 3. WAF / aplicação

Mostrar:

- aplicação legítima respondendo;
- probe sintético bloqueado pelo ModSecurity/CRS;
- evento correspondente no pipeline de logs/Wazuh, quando disponível.

Teste negativo preferido: XSS/path traversal/SQLi sintético já previsto no
plano de testes, sem payload destrutivo.

### 4. RBAC e MFA da aplicação

Usar `teste@pucparana.com` como identidade funcional de usuário comum.

Demonstrar:

- autenticação/MFA;
- área de usuário permitida;
- área de empresa/admin negada;
- registro de auditoria correspondente.

### 5. OpenBao

Usar a identidade humana técnica `teste`, não AppRole de workload.

Demonstrar:

- WebUI/CLI acessível somente pelo caminho local autorizado;
- leitura do path de laboratório permitida;
- path vizinho/SMTP operacional negado;
- escrita/policies/auth methods negados;
- TTL curto e ausência de default policy.

### 6. Bacularis

Demonstrar:

- WebGUI em loopback;
- autenticação humana `teste`;
- visualização de Director/Storage/Catalog/Jobs;
- ação mutante negada;
- ausência de Docker socket/sudo no runtime Web.

### 7. phpMyAdmin — GUI-01C

Executar somente depois do gate de host correspondente.

Demonstrar:

- login SQL `teste`;
- schema `conectaeduca`;
- SELECT permitido;
- INSERT/UPDATE/DELETE negados pelo próprio MariaDB.

A negação deve vir do banco. Ocultar botão na UI não é evidência suficiente.

### 8. Ferret / DLP

Mostrar:

- serviço healthy;
- relatório/evento sanitizado;
- correlação com Wazuh quando aplicável;
- comportamento detect-only documentado.

### 9. Bacula

Depois do BAC-04 E2E:

- Pool/Jobs/FileSets operacionais;
- produtores MariaDB/OpenBao/Catalog/Recovery State;
- backup concluído;
- perda controlada de artefato descartável;
- restore em destino isolado;
- SHA-256 origem = restore;
- SmokeJobs preservados.

### 10. Wazuh / evidência central

Fechar a narrativa mostrando os eventos correlacionados:

- WAF;
- Suricata;
- Ferret;
- FIM/YARA;
- demais eventos relevantes do pentest.

O objetivo é demonstrar que os controles não são apenas declarativos: há
telemetria consumível e rastreável.

## Regra de tempo

Para uma apresentação de aproximadamente 10 minutos:

- arquitetura/segmentação: 1 min;
- WAF/aplicação/RBAC: 2 min;
- OpenBao/Bacularis/phpMyAdmin: 3 min;
- Ferret/Bacula/Wazuh: 3 min;
- riscos residuais/conclusão: 1 min.

Se o tempo apertar, priorizar provas positivas/negativas e não menus.

## Evidência mínima por controle

Para cada item apresentado, manter:

- objetivo do controle;
- comando/ação de teste;
- esperado;
- observado;
- PASS/FAIL;
- timestamp;
- TXT/checkpoint + SHA-256 quando disponível;
- screenshot apenas como complemento visual.

## Não fazer durante a demonstração

- não revelar senha/token/SecretID/unseal share;
- não usar root token persistente;
- não usar `docker exec` como caminho do usuário `teste`;
- não conceder sudo apenas para facilitar a apresentação;
- não executar payload destrutivo;
- não alterar firewall/ACL/policy sem rollback preparado.
