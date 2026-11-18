# Continuidade do ConectaEduca sem EP125/EP126

**Atualização:** 18/11/2026. Este roteiro não precisa das VMs institucionais.
Seu propósito é preservar um portfólio tecnicamente auditável **sem simular
testes de infraestrutura que não podem mais ser executados**.

## O que permanece reproduzível

| Recurso | Disponível a partir do Git? | Limite |
| --- | --- | --- |
| Aplicação PHP e testes PHPUnit | **Sim**, com dependências locais compatíveis | Não comprova configuração nem bancos efetivos das VMs |
| Workflows de CI, Gitleaks, Semgrep e Snyk | **Sim**, conforme permissões e integrações habilitadas | Alertas estáticos não substituem pentest ou inspeção live |
| Regras Wazuh V6 / PA-06 | **Sim**, arquivo, SHA-256 e verificador offline | Não carrega regras num manager nem garante novos alertas |
| Composições declarativas de serviços | **Parcial**, leitura e análise estática | Arquivos `.env`, volumes e configurações institucionais não são distribuídos |
| Ferret V5 / GA-06 | **Parcial**, manifestos e política do override | TAR privado e imagem efetiva não podem ser conferidos sem custódia apropriada |
| Diagramas e relatórios sanitizados | **Sim**, conforme revisão de publicação | Não equivalem a captura de tráfego atual ou serviços ativos |
| Twingate, pfSense, WAF, OpenBao e Bacula | **Não**, para homologação funcional integral | Dependem de rede, identidades, certificados, serviços e autorização |

## Verificações úteis num clone autorizado

Execute os comandos apenas em sua estação de desenvolvimento ou CI. Eles não
realizam deploy nas VMs. Não cole saídas contendo identificadores, segredos ou
detalhes da rede institucional em issues públicas.

```bash
git status --short --branch
git rev-parse HEAD
git log -1 --format='%h %cs %s'

# Regras Wazuh V6 já versionadas na main
python3 scripts/evidencias/pa06_validar_80710_v6.py

# Autotestes de controles já versionados
python3 scripts/evidencias/checkpoint_compose_security_invariants.py --self-test
python3 scripts/evidencias/pfsense_wazuh_decoder_regression.py --self-test
```

Em ambiente PHP com Composer instalado, os testes de aplicação podem ser
realizados **conforme as instruções do README e do workflow PHPUnit**:

```bash
composer validate --strict --no-check-publish
composer audit --locked --no-interaction
```

O validador YAML/XML da [PR #244](https://github.com/andrea-kozicki/conectaeduca/pull/244)
passou na própria PR, mas **só existirá na `main` após merge aprovado**.
Depois da integração, consulte
`docs/qualidade/VALIDACAO-CONFIGURACOES-OFFLINE.md` para os comandos e as
limitações. Não usar a PR em aberto como evidência de código já publicado na
branch principal.

## Sequência recomendada para o fechamento público

1. **Revisar privacidade:** usar os guias em `docs/portfolio/`; verificar
   commits, diffs, imagens, metadados, URLs e descrições de PRs, não apenas o
   texto atual do README. Não publicar evidência bruta ou credenciais.
2. **Decidir as PRs documentais:** revisar #243, #244 e esta proposta.
   Merges devem ocorrer individualmente e com checks aprovados. Não promover
   PRs de deploy antigas por conveniência.
3. **Fixar a referência final:** após os merges autorizados, registrar o SHA
   exato de `main`, data, conjunto de testes e riscos residuais. Caso haja
   novo commit, repetir a verificação aplicável antes de chamá-lo de baseline.
4. **Registrar o encerramento acadêmico:** distinguir conclusão da entrega da
   universidade de encerramento físico das VMs; documentar `NÃO VERIFICÁVEL`
   para qualquer estado que não puder ser reinspecionado.
5. **Preservar a narrativa de portfólio:** arquitetura, decisões técnicas,
   pentest A/B, melhorias e limitações. Não divulgar snapshots ou endpoints
   operacionais institucionais.

## Convenção para a declaração final

Usar uma frase que não transforme CI em homologação da infraestrutura:

> O código-fonte e os controles estáticos do ConectaEduca foram preservados e
> são auditáveis no commit identificado. Os testes operacionais das VMs
> refletem as evidências e datas documentadas; funcionalidades que exigiam o
> ambiente acadêmico permanecem com os limites explicitados no relatório.

## Arquivamento seguro do trabalho individual

- Manter repositório, relatórios finais e apresentações em armazenamento sob
  seu controle, com cópias redundantes e hashes quando apropriado.
- Guardar documentos e evidências de terceiros **somente** quando houver
  direito de cópia e divulgação. Uma cópia pessoal de snapshot ou volume
  institucional não é automaticamente permitida.
- Separar o material **publicável** dos registros restritos de execução. O
  segundo grupo não deve ser enviado ao GitHub nem a serviços públicos.
- Verificar se links e imagens do README continuam funcionando após o
  encerramento das VMs; priorizar recursos versionados e sem dependência de IP.

Este roteiro complementa o
[estado consolidado](README.md), o [plano EP125](../portfolio/EP125-PRE-ENCERRAMENTO.md)
e o [plano EP126](EP126-ULTIMA-JANELA.md).
