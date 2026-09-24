# Checklist de fechamento acadêmico — ConectaEduca

## Regra

Este checklist só marca como concluído aquilo que pode ser sustentado por documentação ou evidência. Não transformar item planejado em implementado e não transformar implementação em validação sem teste.

## Relatório

- [ ] arquitetura final coerente com o runtime entregue;
- [ ] fluxos permitidos/bloqueados da segmentação descritos;
- [ ] decisões de menor privilégio documentadas;
- [ ] OpenBao, Wazuh, Bacula, Ferret e WAF descritos com função clara;
- [ ] risco residual do backup no mesmo domínio físico registrado;
- [ ] negativa institucional de segundo disco/partição registrada;
- [ ] TIME-01/NTP tratado como resolvido ou risco aceito;
- [ ] quatro objetivos do pentest explicitados: movimento lateral, escalação, evasão e vazamento;
- [ ] S01–S13 referenciados;
- [ ] MITRE ATT&CK reconciliado aos testes efetivamente executados;
- [ ] LGPD/privacidade tratada transversalmente;
- [ ] resultados distinguem esperado, observado e conclusão;
- [ ] limitações institucionais não são apresentadas como falhas de implementação.

## Pentest

- [ ] readiness pré-corte zero-sudo em EP125;
- [ ] readiness pré-corte zero-sudo em EP126;
- [ ] runtime check pós-corte como `teste`;
- [ ] S01 Perímetro;
- [ ] S02 WAF;
- [ ] S03 Segmentação;
- [ ] S04 Login/MFA;
- [ ] S05 RBAC/ownership;
- [ ] S06 MariaDB;
- [ ] S07 Segredos;
- [ ] S08 Containers;
- [ ] S09 SIEM;
- [ ] S10 FIM;
- [ ] S11 DLP/Egress;
- [ ] S12 Backup/restore;
- [ ] S13 Privacidade/LGPD;
- [ ] testes críticos repetidos após correção de achado, quando houver;
- [ ] evidência contém data/hora, origem, destino, ferramenta, esperado e observado.

## Freeze

- [ ] `main` limpa e sincronizada;
- [ ] HOST-01 fechado;
- [ ] BAC-04 v2.4 fechado;
- [ ] BAC-04 v2.5 fechado;
- [ ] GUI-01C fechado;
- [ ] PENTEST-00 fechado;
- [ ] riscos P1 encerrados ou aceitos formalmente;
- [ ] nenhuma credencial no Git;
- [ ] hashes consolidados;
- [ ] tag/commit de freeze identificado;
- [ ] Twingate ainda inativo no Pentest A.

## Depois do freeze

- [ ] OWASP ZAP/DAST;
- [ ] Pentest A sem Twingate;
- [ ] registrar baseline A;
- [ ] ativar Twingate com token fora do Git;
- [ ] validar Connector/recursos;
- [ ] Pentest B com os vetores comparáveis;
- [ ] tabela comparativa A × B sem extrapolar resultados.

## Demonstração ao professor

- [ ] diagrama final disponível;
- [ ] pfSense/Suricata;
- [ ] WAF;
- [ ] aplicação/RBAC/MFA;
- [ ] OpenBao;
- [ ] Bacularis;
- [ ] phpMyAdmin;
- [ ] Ferret;
- [ ] Bacula;
- [ ] Wazuh;
- [ ] teste negativo visível em pelo menos um controle de autorização;
- [ ] nenhuma tela/comando revela segredo.

## Apresentação

- [ ] slides coerentes com o relatório;
- [ ] nenhuma arquitetura antiga/Cognito;
- [ ] screenshots legíveis;
- [ ] MITRE usado para explicar comportamento, não apenas como lista;
- [ ] resultados dos pentests aparecem com evidência;
- [ ] riscos residuais aparecem explicitamente;
- [ ] fala de ~10 minutos ensaiada;
- [ ] plano B preparado caso uma WebGUI esteja indisponível: screenshot + TXT/checkpoint.

## Entrega final

- [ ] PDF/relatório final;
- [ ] PPTX final;
- [ ] diagrama final;
- [ ] evidências sanitizadas;
- [ ] SHA256SUMS;
- [ ] commit/tag de freeze anotado no relatório;
- [ ] repositório sem arquivos runtime/secrets;
- [ ] backlog sem P0/P1 não aceito.
