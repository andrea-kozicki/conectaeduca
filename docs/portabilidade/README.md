# ConectaEduca — trilha de reconstrução portátil

> **Estado:** plano de implementação, não instrução de implantação. Esta
> documentação não altera o laboratório EP125/EP126 e não declara que uma
> instalação limpa já foi testada.

## Objetivo

Permitir que uma pessoa clone o repositório em uma máquina própria e execute
uma parte **funcional, verificável e independente** do ConectaEduca. A
infraestrutura, os snapshots, os endereços, as identidades e os certificados
do laboratório acadêmico não serão pré-requisitos.

O arquivo acadêmico permanece preservado: o estado observado nas VMs em
2026, os testes registrados e os scripts de mudança históricos não devem ser
reescritos como se fossem o resultado de uma reinstalação nova.

## Perfis propostos

| Perfil | Componentes | Evidência exigida antes de dizer que funciona |
| --- | --- | --- |
| `lite` (primeiro) | PHP, Nginx, WAF e MariaDB, dados sintéticos e redes Docker locais | Build em clone limpo, bootstrap idempotente, HTTPS de desenvolvimento, endpoint da aplicação, consulta à base, teste de bypass e casos negativos |
| `duas-zonas` | DMZ e interna em duas VMs, roteamento/firewall próprios | Matriz de portas permitidas/negadas e fluxos fim a fim entre as VMs |
| `observabilidade` (opcional) | Wazuh, Ferret, OpenBao e Bacula, cada um com pré-requisitos e dados de laboratório | Inicialização, healthcheck, teste funcional e, no caso de backup, restauração de dados fictícios |
| `k8s` (posterior) | Adaptadores Kubernetes dos componentes já comprovados no `lite` | Cluster de teste, políticas, limites, persistência, testes positivos/negativos e desinstalação segura |

Esses perfis são **metas**, não serviços atualmente habilitados. A primeira
versão deverá caber em um ambiente pessoal com 32 GB de RAM mediante testes
de consumo; a pilha completa de SIEM e backup não pode ser considerada
obrigatória para o perfil `lite`.

## Política para não quebrar a `main`

1. Não editar ou substituir os Dockerfiles, Compose, SQL, drivers de
   cutover/rollback ou configs GA08 históricos para fazer o novo perfil
   funcionar. Construir a implementação portátil em diretório separado,
   inicialmente `deploy/portable/`, com nomes de projeto e volumes isolados.
2. Não mesclar PRs históricas de implantação por atacado. Verificar sobreposição
   com a `main`, extrair apenas o que for reproduzível, testar e revisar cada
   mudança. Documentar quando a PR antiga foi superada por outra.
3. Nunca reutilizar segredos, chaves, certificados, contas, IPs, imagens TAR,
   dumps, snapshots ou dados reais da PUCPR. Usar arquivos de exemplo,
   geração local e dados sintéticos, sem publicar segredos criados.
4. Manter o status **DRAFT** de PRs operacionais não homologadas, incluindo a
   #217, enquanto a semântica de recuperação permanecer dependente das VMs.
   A validação GA08 11/14 da EP125 é uma evidência histórica válida, mas
   não é um teste de reconstrução portátil.
5. Uma PR documental só deve ser integrada após revisão de links, privacidade,
   possíveis conflitos e checks aplicáveis. Uma PR de runtime requer ainda
   build, smoke test, caminhos de falha, limpeza segura e revisão humana.

## Fases com critérios verificáveis

### 0 — Inventário e classificação (`docs/` apenas)

- [ ] Confrontar fontes atuais com [`INVENTARIO-INICIAL.md`](INVENTARIO-INICIAL.md).
- [ ] Classificar dependências como **versionada**, **recriável**, **opcional**
  ou **dependente do ambiente acadêmico**.
- [ ] Conferir licenças e permissão de redistribuição de componentes e dados;
  o `composer.json` declara `proprietary`, portanto não assumir uma licença
  pública para o código autoral sem decisão expressa da autora.
- [ ] Congelar SHA, resultado de testes e limitações no registro acadêmico.

**Aceite:** nenhuma dependência da EP125/EP126 fica escondida num comando
de instalação supostamente universal.

### 1 — Perfil Lite declarativo (PR separada)

- [ ] Criar `deploy/portable/` sem alterar a composição histórica.
- [ ] Fixar versões e proveniência das imagens e fornecer um comando de
  build que injete o SHA real do checkout, não `UNSET`.
- [ ] Usar as configurações de exemplo **existentes** em `.env.example` como
  referência; criar só as novas variáveis necessárias, com validação e sem
  valores sensíveis reais.
- [ ] Gerar segredos e certificados de desenvolvimento **fora do Git**;
  nenhum teste imprime seus valores.
- [ ] Criar base MariaDB vazia + dados sintéticos e privilégios mínimos
  sem fixar o IP institucional.
- [ ] Isolar volumes, nome do projeto, bindings e portas do perfil Lite.

**Aceite:** build e inicialização em clone limpo, sem scripts de EP125/EP126
nem arquivos privados originais.

### 2 — Segurança e CI de integração (PR separada)

- [ ] Validar o modelo Compose resolvido sem imprimir variáveis sensíveis.
- [ ] Testar HTTPS no WAF, Nginx/PHP, conexão ao banco, autenticação com
  usuários fictícios e negação de bypass externo aos backends.
- [ ] Registrar testes negativos de autorização e MFA separadamente dos
  resultados de testes apenas sintáticos.
- [ ] Ensaiar backup e restore **de dados sintéticos** em destino isolado.
- [ ] Garantir que a desmontagem normal não apaga volumes persistentes;
  limpeza destrutiva exige um comando e confirmação separados.

**Aceite:** um segundo computador/runner consegue repetir o cenário com
resultados esperados. CI estática e E2E são evidências distintas.

### 3 — Duas redes e serviços opcionais (PRs pequenas)

- [ ] Reproduzir a separação DMZ/interna em duas VMs ou redes controladas,
  sem alegar equivalência com o pfSense institucional.
- [ ] Se usar pfSense, implantar uma **VM/appliance separada**; se não,
  documentar explicitamente o firewall Linux alternativo e as diferenças.
- [ ] Adicionar OpenBao, Wazuh, Ferret, Bacula e Twingate um por vez,
  respeitando licença, consumo de RAM, segredos e testes próprios.
- [ ] Deixar o perfil básico utilizável quando serviços opcionais faltarem.

**Aceite:** inventário por serviço com resultados verificáveis, e não apenas
containers `Up`.

### 4 — Kubernetes opcional (depois do Lite)

- [ ] Adaptar o core testado para K3s/Kustomize sem migrar drivers de
  rollback criados para Docker Compose e as VMs originais.
- [ ] Validar health probes, NetworkPolicy, requests/limits, volumes,
  armazenamento de segredos e restauração de dados sintéticos.

**Aceite:** mesmas verificações funcionais e de isolamento do Lite, em
cluster de teste descartável. O Kubernetes não substitui o pfSense.

## Ordem das PRs existentes

Revisar primeiro as cadeias sobrepostas, sem mudar sua ordem por conveniência:

| Conjunto | PRs abertas no inventário de 19/11 | Decisão preliminar |
| --- | --- | --- |
| GA08/PA05 | #217, #230 | Preservar evidência 11/14; extrair somente fontes e testes portáteis, sem promover rollback antigo |
| Ferret | #207, #226, #227 | Comparar com V5 já versionado; nunca exigir a imagem privada/TAR anterior |
| Segurança e acesso | #205, #203, #225, #228, #213 | Revalidar auth/MFA, logging, OpenBao/Twingate no novo ambiente sintético |
| Operação/reconciliação | #219, #221, #215, #224 | Reaproveitar testes neutros; arquivar scripts feitos para operar checkouts institucionais |
| Histórico e documentos | #235, #232, #218, #214, #200 | Editar narrativa, privacidade e datas; a #200 requer separação de Dockerfile e documentação |

**Não executar nem mesclar nada automaticamente** com base nesta tabela.
O inventário de PRs é uma fotografia e deve ser renovado antes de cada lote.

## Primeiro marco público de sucesso

> `git clone` → requisitos explícitos → build das imagens → inicialização
> isolada com banco fictício → HTTPS via WAF → testes de aplicação,
> autorização e bypass → parada segura.

Esse marco não exige snapshots da PUCPR, nem a execução simultânea de Wazuh,
Bacula e todo o legado. Será a primeira afirmação de **laboratório
reproduzível** que poderá ser defendida com evidência nova.

## Documentos existentes que continuam válidos

- [`docs/encerramento/CONTINUIDADE-OFFLINE.md`](../encerramento/CONTINUIDADE-OFFLINE.md) — preservação sem VMs.
- [`docs/portfolio/PR_AUDITORIA_INDIVIDUAL_20261118.md`](../portfolio/PR_AUDITORIA_INDIVIDUAL_20261118.md) — auditoria histórica de PRs.
- [`docs/portfolio/PRIVACIDADE-E-PUBLICACAO.md`](../portfolio/PRIVACIDADE-E-PUBLICACAO.md) — limites de divulgação.
- [`deploy/pfsense/README.md`](../../deploy/pfsense/README.md) — topologia e evidências históricas.

