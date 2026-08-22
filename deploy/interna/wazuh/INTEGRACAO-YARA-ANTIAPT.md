# ConectaEduca — YARA / anti-APT com Wazuh

## Arquitetura

O agente Wazuh na VM Ubuntu monitora o diretório da aplicação por FIM.
Eventos de criação/modificação classificados pelas regras 110200/110201 podem
acionar uma Active Response local. A Active Response executa YARA no arquivo
alterado. Matches são registrados no `active-responses.log`, decodificados pelo
Manager e elevados pela regra 110203.

## Artefatos entregues

- `yara/rules/conectaeduca_baseline.yar`: ruleset sintética/heurística.
- `agent/yara.sh.example`: Active Response Linux.
- `agent/conectaeduca-fim-yara.xml.example`: fragmento FIM do agente.
- `config/decoders/conectaeduca_yara_decoders.xml`: decoder do Manager.
- `config/rules/conectaeduca_yara_rules.xml`: regras do Manager.
- `config/yara/conectaeduca-yara-manager.xml.example`: command/active-response.

## Para a aula

A ativação no endpoint é propositalmente deixada para a aula:

1. instalar `yara` e `jq` no Ubuntu;
2. cadastrar/enrolar o Wazuh Agent;
3. habilitar o fragmento FIM;
4. copiar o `yara.sh` para `/var/ossec/active-response/bin/yara.sh`;
5. instalar o ruleset em `/etc/conectaeduca/yara/`;
6. aplicar command/active-response no Manager;
7. reiniciar Agent/Manager;
8. criar um arquivo contendo `CONECTAEDUCA_YARA_TEST_MARKER_2026`;
9. demonstrar FIM -> YARA -> alerta.

A ruleset inicial é deliberadamente pequena para uma demonstração segura e
reprodutível. Regras de inteligência de ameaças externas devem ser avaliadas e
versionadas separadamente.
