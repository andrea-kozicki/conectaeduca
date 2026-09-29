# Roteiro de demonstração final — ConectaEduca

## Objetivo

Organizar uma demonstração curta e reproduzível, priorizando **controle + evidência + teste negativo** em vez de navegar longamente por telas.

## Ordem sugerida

1. **Arquitetura e segmentação** — mostrar EP125/DMZ, EP126/interna, pfSense e fluxos mínimos entre zonas.
2. **pfSense + Suricata** — mostrar regras/aliases, sensor ativo e um evento seguro correlacionável. Se o SSH estiver habilitado pelo professor/suporte, ele pode complementar a WebGUI para consultas de shell.
3. **WAF + aplicação** — tráfego legítimo permitido e probe sintético bloqueado, com telemetria quando disponível.
4. **RBAC/MFA** — usar `teste@pucparana.com`: área de usuário permitida; áreas de empresa/admin negadas.
5. **OpenBao** — usar a identidade humana `teste`: path de laboratório permitido; path vizinho, SMTP operacional, escrita e administração negados.
6. **Bacularis** — login `teste`, consulta de Director/Storage/Catalog/Jobs e operação mutante negada.
7. **phpMyAdmin / GUI-01C** — login SQL `teste`, SELECT permitido e INSERT/UPDATE/DELETE negados pelo próprio MariaDB.
8. **Ferret/DLP** — serviço saudável, evento sanitizado e correlação SIEM quando aplicável.
9. **Bacula** — após BAC-04 E2E: Pool/Jobs/FileSets, backup, perda controlada, restore isolado e SHA-256 origem=restore.
10. **Wazuh** — fechar a narrativa mostrando telemetria de WAF, Suricata, Ferret, FIM/YARA e pentest.
11. **AppSec / supply chain** — mostrar os gates finais (Snyk, Semgrep, Gitleaks, PHPUnit e Static Integrity), incluindo APPSEC-04/CWE-611 e APPSEC-05/CWE-23 já revalidados na ref congelada. Para Snyk, usar o artifact sanitizado produzido pelo workflow CI dedicado sem sudo; o status verde isolado do PR não substitui essa evidência.

## Tempo para apresentação de ~10 minutos

- arquitetura/segmentação: 1 min;
- WAF/aplicação/RBAC: 2 min;
- OpenBao/Bacularis/phpMyAdmin: 3 min;
- Ferret/Bacula/Wazuh: 3 min;
- AppSec + riscos residuais/conclusão: 1 min.

Se o tempo apertar, priorizar provas positivas/negativas e não menus.

## Evidência mínima por controle

Registrar objetivo, ação de teste, esperado, observado, PASS/FAIL, timestamp e TXT/checkpoint + SHA-256 quando houver. Screenshot é complemento visual, não substituto da evidência técnica.

## Não fazer durante a demonstração

- não revelar senha, token, SecretID ou unseal share;
- não usar root token persistente;
- não usar `docker exec` como caminho do usuário `teste`;
- não conceder sudo só para facilitar a demonstração;
- não usar payload destrutivo;
- não alterar firewall/ACL/policy sem rollback preparado.

## Gate para usar screenshots

Screenshot é selecionado somente depois da prova técnica equivalente. Não
reexecutar controle fechado apenas para obter imagem melhor.

Para APPSEC-04/05, mostrar `appsec-snyk-final.txt` + hash validado do artifact
da ref congelada. Não exibir token, payload SARIF bruto ou segredos.
