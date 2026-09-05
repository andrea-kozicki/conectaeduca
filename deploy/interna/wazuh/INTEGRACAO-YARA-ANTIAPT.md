# ConectaEduca — YARA / anti-APT com Wazuh

## Estado

**Validado operacionalmente nas VMs.**

O conteúdo deste documento começou como readiness para demonstração. Após a implantação, o fluxo passou por teste real com marcador sintético e foi promovido de "preparado" para "validado".

## Arquitetura

```text
arquivo sintético criado/modificado na EP125
        |
        v
Wazuh Agent / FIM
        |
        | regras 110200 / 110201
        v
Active Response local
        |
        v
yara.sh + ruleset ConectaEduca
        |
        v
active-responses.log
        |
        v
decoder conectaeduca_yara_decoder*
        |
        v
regra 110211 — nível 12
        |
        v
Wazuh Manager / alerta
```

## Artefatos

- `yara/rules/conectaeduca_baseline.yar`;
- `agent/yara.sh.example`;
- `agent/conectaeduca-fim-yara.xml.example`;
- `config/decoders/conectaeduca_yara_decoders.xml`;
- `config/rules/conectaeduca_yara_rules.xml`;
- configuração de command/Active Response no Manager.

## Evolução do teste

### Fase de preparação

O plano original reservava a ativação para a implantação/aula:

1. instalar YARA/JQ;
2. enrolar o Agent;
3. habilitar FIM;
4. instalar Active Response;
5. instalar ruleset;
6. configurar Manager;
7. gerar marcador sintético.

### Fase validada

Na implantação:

- EP125 e EP126 permaneceram Active no Manager;
- FIM foi direcionado a diretório sintético controlado na EP125;
- criação/modificação acionou as regras 110200/110201;
- Active Response executou YARA localmente;
- o resultado foi decodificado;
- match positivo chegou à regra `110211`, nível 12;
- `configtest` foi aprovado;
- TCP/1515 deixou de ser publicado depois do enrollment.

## Por que o teste é sintético

O objetivo é provar detecção e resposta sem introduzir malware funcional.

O marcador do projeto permite exercitar:

- monitoramento de filesystem;
- encadeamento de regras;
- execução de resposta;
- parser/decoder;
- classificação do evento;
- chegada ao Manager.

Isso é suficiente para validar o mecanismo sem criar risco desnecessário no laboratório.

## Escopo do ruleset

A ruleset inicial é deliberadamente pequena e reproduzível.

Regras externas de inteligência de ameaças devem ser:

1. avaliadas quanto a origem/licença;
2. revisadas para falso positivo;
3. versionadas;
4. testadas;
5. promovidas em PR separado.

Não transformar a demonstração em execução automática de rulesets não auditadas.
