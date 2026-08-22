# Wazuh — ConectaEduca

Stack Wazuh single-node usada como núcleo de SIEM/observabilidade de segurança do ConectaEduca.

## Baseline atual

- Wazuh Manager, Indexer e Dashboard em containers;
- imagens validadas e versionadas;
- certificados, chaves e credenciais somente em `.runtime/`, fora do Git;
- arquivos sensíveis de runtime com permissões restritivas;
- Dashboard publicado somente em loopback no laboratório;
- Indexer e API do Manager sem publicação ampla no host;
- retenção de alertas tratada por política própria;
- regras customizadas para eventos DLP/Ferret e YARA;
- overlay de host preparado para implantação na VM Ubuntu interna.

## Integrações

### Ferret / DLP

O Ferret produz eventos minimizados e sanitizados. O Wazuh não deve ingerir `inbox/` nem `reports/raw/`.

Consulte `INTEGRACAO-FERRET-DLP.md`.

### YARA / anti-APT

O fluxo preparado é:

```text
Wazuh Agent/FIM
    -> arquivo criado ou modificado
    -> Active Response local
    -> YARA
    -> active-responses.log
    -> decoder/rule do Manager
    -> alerta
```

A ativação real de Agent + FIM + YARA permanece reservada para demonstração em aula.

Consulte `INTEGRACAO-YARA-ANTIAPT.md`.

## Laboratório x VM final

No laboratório, o bloco containerizado permite validar o Manager/Indexer/Dashboard e as regras.

Na VM final:

- o Wazuh Agent será instalado nativamente nos endpoints que precisam observar filesystem/host;
- bindings administrativos serão definidos após endereçamento e pfSense;
- `.runtime/` não entra no handoff;
- certificados e credenciais serão rematerializados no destino.

## Preparação e testes

A partir da `main`:

```bash
bash scripts/evidencias/preparar_wazuh_fase4g_c.sh
bash scripts/evidencias/testar_wazuh_fase4g_c.sh
```

Readiness YARA/anti-APT:

```bash
bash scripts/evidencias/checkpoint_yara_antiapt_readiness.sh
```

Não envie, versione ou compartilhe `deploy/interna/wazuh/.runtime/`.
