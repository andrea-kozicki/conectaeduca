# Inventário inicial das dependências — futura instalação Lite

**Corte de código:** `main` em
`0d9c0ad35b2ff79c7f39590516f2ada8b3533c4e`, consultada em
19/11/2026. Este é um **diagnóstico estático de arquivos versionados**;
nenhum clone limpo, imagem, container, VM ou rede foi executado aqui.

Os caminhos abaixo foram consultados nessa referência do GitHub. As lacunas
são **requisitos para a nova implementação**, não prova de que o ambiente
acadêmico esteja defeituoso.

| Componente | Fonte versionada | O que já existe | Lacuna para reconstrução portátil |
| --- | --- | --- | --- |
| Aplicação PHP | `composer.json`, `composer.lock`, `src/`, `public/`, `deploy/dmz/php/Dockerfile` | PHP `^8.5`, dependências Composer, Dockerfile multi-stage com imagem-base por digest | Build exige `CONECTAEDUCA_SOURCE_COMMIT` diferente de `UNSET`; `deploy/dmz/compose.yml` usa `UNSET` por padrão. O novo fluxo deve fornecer o SHA real do checkout e testar build limpo. |
| Nginx | `deploy/dmz/nginx/Dockerfile`, `deploy/dmz/nginx/app-http.conf` | Imagem-base fixada por digest, healthcheck local e upstream FastCGI `php:9000` | Adaptar binding, rotas e TLS ao perfil de laboratório sem publicar o backend externamente. |
| WAF/CRS | `deploy/dmz/waf/Dockerfile`, `deploy/dmz/compose.waf.yml`, `deploy/dmz/compose.waf-tls.yml` | Imagem CRS fixada por digest, overlay de WAF e secrets TLS por arquivo | Overlay atual ajusta logging para `journald`, publica portas de teste só em loopback e exige arquivos de certificado/chave fora do Git. Precisa de modo portátil e certificado dev gerado localmente. |
| MariaDB | `deploy/interna/mariadb/compose.yml`, `sql/conectaeduca.sql`, `deploy/interna/mariadb/20-minimos-privilegios.sql` | MariaDB por digest; schema estrutural SQL sem dados; secrets por arquivo | SQL de privilégios fixa o IP da antiga DMZ. Uma instalação nova deve parametrizar/recriar a política de acesso sem alterar esse registro histórico. Requer fixtures sintéticas. |
| Segredos | `.env.example`, `deploy/dmz/compose.database.yml`, `deploy/dmz/compose.app-secrets.yml` | Exemplo de variáveis, chaves assimétricas e senha do banco referenciadas por caminhos de secrets | A `.env.example` já existe: reutilizar como referência. O perfil portátil precisa de gerador local, política de `gitignore`, validação de permissões e saída sem segredo. Não copiar material das VMs. |
| Duas VMs | `deploy/dmz/compose.host.yml`, `deploy/dmz/compose.vm.yml`, `deploy/pfsense/README.md` | Arquitetura histórica DMZ/interna, host bind e parâmetros de implantação | Compose e firewall pertencem a hosts distintos; o modo Lite deve substituir endereços e redes institucionais por uma rede local documentada. O modo duas-zonas será posterior. |
| GA08/PA05 | PR #217 e #230, scripts e overlays candidatos | Paridade 11/14 e PHP PA05 observadas na EP125; scripts de controle fail-closed | Não depender de contextos privados 0600, snapshots, caminhos da EP125 nem drivers antigos para iniciar o perfil Lite. Revisar sobreposições antes de extrair código. |
| Ferret | `deploy/interna/ferret/` e PRs #207/#226/#227 | Artefatos versionados e execução histórica V5 | Verificar fonte do build e licença; TAR/imagem local institucional não pode ser pré-requisito. Serviço opcional. |
| Telemetria/segredos/backup | `deploy/interna/` e documentação de Wazuh/OpenBao/Bacula | Desenho e evidências de operação acadêmica | Recursos e dados de restore não comprovados fora das VMs; perfis opcionais com fixtures e testes isolados. |
| Zero Trust/perímetro | `deploy/pfsense/`, PR #213 | Topologia, regras e documentação de Twingate | Credenciais e recursos de identidade não são portáveis automaticamente. Isolar pfSense como VM opcional e Twingate como integração externa opt-in. |

## Três pontos que não podem ser ignorados

1. **Build PHP:** passar explicitamente o SHA em `CONECTAEDUCA_SOURCE_COMMIT`;
   não remover silenciosamente o gate de proveniência do Dockerfile.
2. **Banco de dados:** o arquivo SQL que restringe a origem do usuário de
   aplicação é específico da antiga DMZ. O novo perfil deve usar um mecanismo
   próprio de privilégio mínimo, adequado à topologia de teste.
3. **Secrets/TLS:** arquivos e valores necessários ao Compose histórico
   nunca podem ser copiados indiscriminadamente para o Git. Criar apenas
   credenciais fictícias locais e atestar sua exclusão dos commits/logs.

## Verificações que abrirão a próxima PR de código

- [ ] Determinar versão mínima de Docker Engine e Docker Compose (os overlays
  históricos usam `!reset` e `!override`).
- [ ] Especificar `deploy/portable/` sem mexer nos Dockerfiles históricos
  ou nas regras que dependem da EP125.
- [ ] Validar licenças de imagens e pacotes, e verificar se todos os builds
  são possíveis a partir de fontes publicamente acessíveis e pinadas.
- [ ] Criar comandos idempotentes de setup e desmontagem com nomes de
  projeto/volumes próprios.
- [ ] Gerar apenas segredos/certificados de desenvolvimento e dados de
  aplicação totalmente sintéticos.
- [ ] Automatizar `compose config`, build, health, HTTPS, conexão PHP→DB,
  bloqueio de acesso direto aos backends e testes PHP de segurança.
- [ ] Ensaiar reconstrução em clone limpo; registrar versões, RAM e tempo
  de build sem alegar comportamento não observado.

## Critério para promover um componente na matriz

- **DECLARADO:** fonte presente e dependências mapeadas.
- **BUILD_TESTADO:** imagem construída a partir de clone limpo com SHA e
  dependências verificadas.
- **BOOT_TESTADO:** serviço iniciado, healthy e com persistência apropriada.
- **E2E_TESTADO:** fluxo funcional e negativos executados com dados sintéticos.
- **NÃO_REPRODUZIDO:** não executado ou dependente de acesso/arquivo externo.

O estado de um componente só avança com evidência da **nova instalação**,
sem reclassificar retrospectivamente os testes da EP125 ou EP126.
