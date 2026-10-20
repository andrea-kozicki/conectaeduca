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

- [ ] contrato UID materializado e validado em EP125;
- [ ] contrato UID materializado e validado em EP126;
- [ ] readiness pré-corte zero-sudo em EP125;
- [ ] readiness pré-corte zero-sudo em EP126;
- [ ] G1 tooling por origem real do cenário;
- [ ] G2/S10 FIM no path canônico user-writable;
- [ ] G3/S11/S13 Ferret por `submeter_ferret_pentest.py`, sem `mv` direto;
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

## Retomada das VMs antes do freeze

Executar somente quando EP125 e EP126 puderem ser sincronizadas de forma
controlada com o mesmo candidato `<FREEZE_COMMIT>`. Esta seção **não marca
PASS por antecipação**; ela apenas fixa a ordem dos gates já versionados.

1. Em ambas as VMs, registrar HEAD/worktree/`origin/main` e só promover por
   fast-forward quando a relação for segura.
2. Em ambas as VMs, executar o gate de repositório sem sudo/Docker:

   ```bash
   python3 scripts/evidencias/prefreeze_repo_gate.py
   ```

3. Em ambas as VMs, executar o readiness PENTEST-00/zero-sudo:

   ```bash
   python3 scripts/evidencias/pentest_no_sudo_readiness.py
   ```

4. Na EP126, executar o preflight read-only dos gates operacionais:

   ```bash
   python3 scripts/evidencias/ops01_ep126_readonly.py
   ```

5. Na EP126, confirmar o caminho pfSense → Wazuh pós-reboot sem gerar tráfego:

   ```bash
   python3 scripts/evidencias/pfsense_wazuh_postreboot_readonly.py
   ```

   Depois que o marker for gerado externamente com apoio institucional, repetir
   o mesmo helper com o identificador correspondente; não considerar
   `CORRELATED_ALERT_PASS` como prova isolada de
   `SIEM_E2E_COMPLETO`.

6. Consolidar as saídas das duas VMs no **mesmo SHA** e só então registrar o
   inventário read-only final. Qualquer FAIL/BLOCK ou drift de SHA impede
   FREEZE-01 até correção ou aceitação formal de risco.

7. Fixar `<FREEZE_COMMIT>`, executar APPSEC-04/05 Snyk final sobre esse SHA
   exato e somente depois concluir FREEZE-01.

## Freeze

- [ ] `main` limpa e sincronizada;
- [ ] HOST-01 fechado na `main` final
  `<FREEZE_COMMIT>`;
- [ ] BAC-04 v2.4 fechado;
- [ ] BAC-04 v2.5 fechado;
- [ ] GUI-01C fechado;
- [ ] PENTEST-00 fechado;
- [ ] APPSEC-04 fechado com artifact Snyk final sobre o `<FREEZE_COMMIT>`
  e sem CWE-611;
- [ ] APPSEC-05 fechado com o mesmo artifact e sem CWE-23 nos targets Ferret;
- [ ] TXT do artifact contém `EXPECTED_SHA=<FREEZE_COMMIT>`;
- [ ] nome do artifact é `appsec-snyk-final-<FREEZE_COMMIT>`;
- [ ] `appsec-snyk-final.txt.sha256` validado e preservado no pacote;
- [ ] nenhum commit foi mergeado após o scan; se a `main` avançou, o Snyk
  final foi repetido para o novo `<FREEZE_COMMIT>`;
- [ ] OPS-01 fechado ou boundary institucional formalmente registrado;
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
- [ ] backlog sem P0/P1 não aceito;
- [ ] issue #125/OPS-01 fechado por correlação real ou boundary institucional
  explicitamente registrado.


## Artefatos de apoio já preparados

- `docs/release/ESQUELETO-RELATORIO-FINAL.md`;
- `docs/release/ROTEIRO-SLIDES-FINAIS.md`;
- `docs/release/PRESELECAO-EVIDENCIAS-PREFREEZE-20260929.md`;
- `docs/seguranca/PENTEST-COMANDOS-S01-S13.md`;
- `scripts/evidencias/gerar_manifesto_evidencias_finais.py`.

São scaffolds: resultados só entram depois da evidência correspondente.

---

## Controle incremental pós-freeze — 09/10/2026

Os checkboxes históricos deste checklist **não foram marcados
retroativamente**. O snapshot de implantação e a Fase 2 de pentest
possuem marcos e critérios de conclusão diferentes.

| Entregável da Fase 2 | Situação comprovada nesta revisão | Pendência |
|---|---|---|
| Relatório parcial v19 | Existe fora do Git, derivado do v18; PA-02.A–I documentados | Revisão final e novas evidências após testes posteriores |
| PA-01 | Concluído/PASS no escopo avaliado EP125→EP126 | Revalidação complementar opcional e S01–S13 independentes |
| PA-02 | Em teste; PA-02.I = dois diferenciais HTTPS 403 / nginx 200 | `PA-02.I.1` e correlação; não há finding confirmado |
| PA-03 e PA-04 | Consolidados nas superfícies avaliadas | Preservar as limitações de privilégio e legibilidade |
| PA-05 / PA-06 / PA-07 | A executar | Documentar evidências específicas dos eixos |
| Triagem passiva EP125 / EP126 | Concluída em 09/10/2026; relatórios TXT e hashes externos | Não contar indexação como pentest |
| Apresentação, diagrama e ensaios Kali | Não concluídos por este adendo | Produzir após relatório e no escopo acadêmico autorizado |
| Twingate / Pentest B | Posteriores ao Pentest A | Preservar sequência A/B |

**Atenção:** os 13 cenários oficiais S01–S13 não equivalem
automaticamente aos sete eixos PA-01–PA-07. Testes operacionais de
MFA, FIM, DLP e Bacula anteriores ao freeze não fecham cenários
adversariais. Manter arquivos brutos, senhas, tokens e dados sensíveis
fora do repositório; anexar somente evidência revisada e sanitizada.
