# ConectaEduca — Guia de privacidade e publicação responsável

**Contexto:** projeto acadêmico individual de Andréa Kozicki, executado em infraestrutura institucional e apresentado como portfólio público de Segurança da Informação.  
**Data de referência:** 18/11/2026.  
**Escopo:** documentação, código, descrições de PRs, imagens e evidências publicadas. Não autoriza alteração de VMs, reescrita de histórico nem cópia de material institucional.

## 1. Quatro níveis de evidência

| Nível | O que se pode afirmar | O que não se pode presumir |
| --- | --- | --- |
| Fonte versionada | Arquivo presente no repositório em determinado commit | Que tenha sido implantado na VM |
| Configuração observada | Arquivo/serviço verificado na VM na data indicada | Que a `main` reproduza o estado integral |
| Comportamento testado | Resultado limitado à origem, identidade e janela do teste | Que toda a superfície esteja protegida |
| Homologação | Cobertura repetível, com testes positivos, negativos e critérios explícitos | Que exista sem as evidências requeridas |

Os dois ciclos de pentest tiveram condições diferentes. Não atribuir melhorias exclusivamente ao Twingate; não tratar alertas, healthchecks, hashes ou respostas HTTP isoladas como prova de homologação global.

## 2. O que revisar antes de publicar

- **Identidade e ambiente:** nomes de usuários institucionais, diretórios pessoais, e-mails identificáveis, nomes de hosts internos e endereços privados que não sejam indispensáveis ao entendimento.
- **Credenciais e criptografia:** senhas, tokens, chaves privadas, dados de AppRole, seeds de MFA, material de CA privada e arquivos `.env` reais. Arquivos de exemplo devem conter placeholders claramente sintéticos.
- **Dados e telemetria:** dumps, bancos, logs com pessoas identificáveis, relatórios DLP, eventos brutos, registros de inscrição, backups e snapshots.
- **Custódia:** imagens TAR ou artefatos produzidos/fornecidos pela instituição não devem ser redistribuídos por presumir que o projeto é acadêmico.
- **Metadados e screenshots:** verificar texto visível, propriedades do arquivo, nomes de pastas, abas abertas, identificadores de sessão e elementos de interface.
- **Diffs e PRs antigas:** verificar arquivos adicionados, linhas removidas, comentários, edições de descrição e commits históricos; uma PR em draft também pode ser pública.

Use nomes genéricos e caminhos portáveis em exemplos. Quando o identificador concreto for necessário para um teste, mantenha-o em evidência privada autorizada, fora do portfólio.

## 3. Tratamento de achados

1. Registrar **apenas o tipo de exposição, a localização e o responsável pela revisão**, sem colar o valor em issue ou comentário público.
2. Determinar se o conteúdo é dado real, fixture sintética, placeholder ou falso positivo. Padrões textuais isolados não bastam para confirmar vazamento.
3. Quando houver **segredo efetivo**, solicitar revogação/rotação pelo canal institucional competente antes de discutir medidas de limpeza do Git. Não divulgar o segredo para reproduzir o problema.
4. Para descrições de PR, anonimizar somente o que é dispensável, preservando o contexto. **Isso não apaga os blobs dos commits nem garantidamente o histórico de edições.**
5. Para commits, branches ou artefatos históricos, elaborar um plano específico de preservação, impacto e autorização antes de qualquer reescrita. Não executar operações destrutivas em massa.
6. Após correção, repetir a busca de padrões e registrar exatamente qual superfície foi verificada — descrição atual, branch, `main`, patch ou histórico completo.

## 4. Gates de uma PR destinada ao portfólio

- [ ] Conteúdo e autoria revisados pela responsável pelo projeto.
- [ ] Nenhum segredo, conta institucional ou evidência identificável foi incluído no diff.
- [ ] Datas, versões, resultados e limitações têm referência verificável.
- [ ] Código e documentação distinguem **proposto**, **versionado**, **executado** e **homologado**.
- [ ] Testes estáticos/CI disponíveis passaram, e a ausência de teste em VM está declarada.
- [ ] Links, imagens e texto alternativo foram conferidos.
- [ ] Existe plano de rollback quando uma PR pretende mudar comportamento operacional; sem autorização, a mudança fica em rascunho.
- [ ] A decisão de licença e de publicação é compatível com direitos da autora, de terceiros e da instituição.

## 5. Limites no encerramento das VMs

O GitHub continuará sendo fonte para código e documentação, mas não substituirá os estados locais da EP125/EP126, certificados, snapshots ou logs que não tenham sido preservados com autorização. O [inventário pré-encerramento da EP125](EP125-PRE-ENCERRAMENTO.md) prevê coleta **somente leitura**; a EP126 exige reconciliação específica dos scripts e artefatos locais.

Quando uma evidência não puder ser recuperada, registrar **não preservada** ou **não verificável**. Não fabricar resultado ou alegar um último reteste que não ocorreu.

## Documentação associada

- [Triagem das PRs históricas](PR_TRIAGE.md)
- [Matriz pública de evidências](EVIDENCIAS-PUBLICAS.md)
- [Lições aprendidas](LESSONS_LEARNED.md)
- [Política de reporte responsável](../../SECURITY.md)

**Este guia é uma política de publicação do portfólio, não uma autorização para disponibilizar artefatos institucionais ou alterar a infraestrutura.**
