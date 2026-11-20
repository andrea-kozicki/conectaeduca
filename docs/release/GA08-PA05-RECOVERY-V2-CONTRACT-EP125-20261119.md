# GA08 / PA05 — contrato de recuperacao v2 (EP125)

**Estado em 19/11/2026:** desenho e simulacao somente offline. Nenhum
manifesto v2 real foi gerado, nenhum rollback foi executado, nenhum
container foi recriado e nao existe aprovacao operacional para mutacao.

## Por que o contrato v2 e necessario

A EP125 em producao usa 14 Compose: dez camadas da DMZ, a camada
`compose.pa05-10328ab6.yml` e tres overlays GA08. Um retorno seguro
**nao pode remover o 11o arquivo**: sem os tres overlays GA08, o baseline
aprovavel para estudo e de **11 arquivos**, preservando o PHP PA-05.

Os contextos privados de 03 e 04/11 foram classificados como `LEGADO_9_10`.
O antigo `scripts/ga08-change-control.py` continua protegido contra
mutacao na topologia PA-05 e nao e um driver de recuperacao aplicavel.

## Evidencias tecnicas ja recebidas na EP125

- Tres containers DMZ healthy; 14 arquivos na mesma ordem nos labels.
- Três overlays GA08 SHA-256 identicos aos candidatos revisados na PR #217.
- Diferencas nas duas referencias FPM/Nginx foram de caminho, nao de bytes:
  quatro comparacoes SHA-256 `IGUAL`.
- Interpolacao limitada dos conjuntos 11 e 14 usando os dois contextos
  privados: quatro verificacoes `PASS`.
- Docker Compose 5.7.0: configuracao ativa 14 contra os tres labels de
  hash de servico, em cada contexto: **6/6 `IGUAL`**. Estes hashes nao
  constituem ensaio de recuperacao nem teste funcional.
- **Custodia parcial v2 executada na EP125:** dois contextos privados
  validados; seis hashes de servico `MATCH`; 14 fontes Compose com SHA-256
  recolhido somente em memoria; tres IDs locais de imagens conferidos.
  Resultado `PASS_CUSTODIA_PARCIAL_SOMENTE_LEITURA`, sem exibir hashes,
  caminhos ou valores e sem criar manifesto. Os digests completos de
  config 11/14, snapshot atual e recuperabilidade de segredos continuam
  pendentes.
- CI do commit anterior ao contrato v2: oito workflows aprovados.

## Contrato do manifesto privado v2

O modulo `scripts/ga08-pa05-recovery-v2-contract.py` implementa apenas
validacao de esquema e simulacao pura (sem Docker, escrita em disco,
`compose up` ou rollback). Ele aceita, quando existir e for autorizado
um manifesto v2 com owner do operador, permissao `0600`, sem symlink e
mantido **somente na EP125 ou em custodia privada**, nunca no GitHub.

Campos obrigatorios:

| Campo | Conteudo permitido |
|---|---|
| `format` e identidade | formato `2`, `change_id`, projeto e host EP125 |
| `restore_target` | somente `PA05_BASE_11` |
| `private_context_id` | identificador do contexto 0600, sem valores de segredos |
| `compose.baseline11` | sequencia exata dos 11 arquivos ate PA-05 |
| `compose.active14` | sequencia exata dos 14 arquivos em uso |
| `source_sha256` | 14 fingerprints por **posicao** `01` a `14`; nao caminhos no repo |
| `config_sha256` | digests canonicos privados de 11 e 14 Compose interpolados |
| `images` | tags aprovadas e IDs imutaveis das imagens PHP, Nginx e WAF |
| `snapshot` | referencia, cobertura atestada e restaurabilidade confirmada |
| `verification` | flags booleanas de proveniencia, testes e ensaio funcional |
| `approval` | flags booleanas de janela, segredos recuperaveis e EP126 |
| `state` | somente `CANDIDATE_ONLY` nesta fase |

O validador rejeita campos extras, hashes invalidos, substituicao da
imagem PHP PA-05, baseline de 9/10 arquivos e flags de atestacao que nao
sejam booleanas. As flags sao declaracoes de evidencias externas, **nao**
verificacoes autonomas do validador; ainda deverao ser corroboradas pelo
operador e por testes independentes no futuro.

**Nao preencher esse esquema com hashes fabricados, dados de teste ou
valores copiados de logs.** A geracao real, os caminhos e a guarda do
manifesto dependem de um coletor v2 adicional, sujeito a revisao e
autorizacao especifica para criar arquivos privados. Nenhum arquivo da
EP125 sera criado por este contrato.

## Inventario de custodia v2 somente leitura (executado na EP125)

Foi preparado o script `scripts/ga08-pa05-v2-custody-inventory-ep125.py`
com atestacao SHA-256 fixa dos tres verificadores privados anteriores
que a operadora ja executou em `~/Downloads`. Antes de aceitar qualquer
material para um manifesto, o novo inventario exige:

1. Docker Compose 5.7.0 e **6/6** hashes do runtime identicos nos dois
   registros privados, sem ler/mostrar valores de ambiente.
2. Sequencia das 14 fontes igual entre PHP, Nginx e WAF; integridade e
   proveniencia previamente aprovadas, com `env_file`/inclusoes externas
   inesperadas rejeitadas.
3. SHA-256 em memoria das **14 fontes Compose** (`01` a `14`) com
   permissoes e propriedades seguras, sem apresentar caminhos/digests.
4. IDs locais das tres imagens confirmados contra os IDs reais dos
   containers. O PHP deve permanecer na imagem PA-05 aprovada.

Executar somente apos disponibilizar na EP125 uma copia SHA-256 validada
do arquivo versionado; **sem sudo**:

```bash
python3 ~/Downloads/ga08-pa05-v2-custody-inventory-ep125.py
```

Este inventario reune informacoes **somente em memoria**, produzindo
contagens publicas; nao faz `docker compose config --format json`, nao
captura digests canonicos de configuracao interpolada e **nao cria o
manifesto v2**. As referencias a secrets/TLS permanecem privadas. O
snapshot atualizado, a restaurabilidade e a aprovacao do operador
continuam gates manuais independentes. O teste local inicial dessa
ferramenta integra a suite GA08, agora com **78 testes offline PASS**.

**Saida real em 19/11:** `CONTEXTOS_PRIVADOS=2_VALIDADOS`,
`HASHES_SERVICO=6_MATCH`, `FONTES_COMPOSE=14_SHA256_EM_MEMORIA`,
`IMAGENS=3_IDS_LOCAIS_CONFERIDOS` e
`COLETOR_V2=PASS_CUSTODIA_PARCIAL_SOMENTE_LEITURA`.

## Digests canonicos 11/14, somente leitura (executado na EP125)

O novo `scripts/ga08-pa05-v2-config-digest-ep125.py` exige uma copia
com SHA-256 aprovado do coletor v2 em `~/Downloads` e repete todas as
atestacoes anteriores. Para cada contexto protegido de 03 e 04/11,
compara os modelos interpolados **inteiros**, em memoria, gerados por
`docker compose config --format json` para os 11 arquivos de baseline
PA-05 e os 14 ativos. A configuracao JSON **pode conter valores de
ambiente e referencias privadas**, mas nunca e exibida, gravada nem
devolvida; o script nao le conteudos de arquivos de segredo. Recusa
`env_file`, inclusoes ou `extends` nao aprovados e reforca a imagem
PHP PA-05 em ambos os modelos. O digest canonico SHA-256 tambem
permanece privado em memoria: publica apenas `IGUAL`/`DIFERENTE`.

Executar **somente apos validar o SHA-256 da copia do script** e com
autorizacao da operadora para processamento de referencias privadas em
memoria; nenhum `sudo`:

```bash
python3 ~/Downloads/ga08-pa05-v2-config-digest-ep125.py
```

**Saida real EP125 em 19/11:** `CONFIG_MODELOS_INTERPOLADOS=4`,
`BASELINE11_ENTRE_CONTEXTOS=IGUAL`, `ATIVO14_ENTRE_CONTEXTOS=IGUAL`,
`PHP_PA05_PRESERVADO=SIM` e `DIGEST_V2=PASS_EM_MEMORIA`.
Nenhum JSON, valor, digest ou caminho foi exibido; nenhum arquivo ou
servico foi modificado. O manifesto v2 **nao foi criado** e o rollback
permanece bloqueado. Isto comprova consistencia dos modelos entre os
contextos, mas **nao** prova restauracao funcional, disponibilidade
atual de segredos ou validade do snapshot. A suite GA08 local soma
**86 testes offline PASS**; o commit que incorporou o preflight fechou
com **8/8 verificacoes de CI aprovadas**.

## Gates que continuam abertos apos a paridade 11/14

1. **Snapshot atual dos dois hosts:** o ultimo snapshot informado pelo
   suporte e de 09/11/2026 (EP125 `ubuntu.33`; EP126 `ubuntu.49`).
   Antes de recuperar ou mudar serviços, solicitar comprovacao de
   snapshot **atual**, identificador, data/hora, cobertura e mecanismo
   de retorno. A VM nao consegue atestar sozinha o estado do hipervisor.
2. **Recuperabilidade real de segredos e TLS:** atestar por quem os
   custodia que chaves, certificados, credenciais e materiais OpenBao
   necessarios podem ser restaurados com o procedimento autorizado;
   nao publicar valores, chaves, shares nem conteudo de `.env` no GitHub
   ou no chat. Checagens de referencia e hash nao provam backup.
3. **Ensaio isolado e E2E:** testar restauracao fora dos hosts ativos e
   exercitar HTTPS/WAF, PHP-MariaDB EP126, autenticacao/MFA/RBAC e
   isolamento, sem mudar servicos ativos ate haver plano e aprovacao.
4. **Manifesto v2 privado:** somente apos gates anteriores e uma nova
   autorizacao expressa para criacao de arquivo na EP125; sem commit
   de hashes, caminhos nem identificadores privados no repositorio.

## Sequencia proposta (apenas simulação de estados)

1. Validar snapshot atual, custodia de secrets/TLS, dependencias EP126,
   janela e aprovacao especifica da operadora.
2. Revalidar hashes das 14 fontes, modelo interpolado 11/14, integridade
   dos containers, `config-hash` de runtime e IDs das imagens.
3. Adquirir **lock unico por host/projeto**; nenhuma concorrencia entre
   cutover, operacao de recuperacao e diferentes `change_id`.
4. Em futura implementacao autorizada, avaliar restauracao isolada de PHP
   com os **11 arquivos**, exigir health; depois Nginx e WAF, sempre com
   abortagem fechada antes do proximo servico se uma etapa falhar.
5. Executar testes HTTPS, WAF/CRS, PHP→MariaDB EP126, login/MFA/RBAC,
   TLS e isolamento de backends. Sem este ensaio, declarar apenas
   `RECUPERACAO_FUNCIONAL_NAO_COMPROVADA`.
6. Registrar resultado com criterio de retorno ao snapshot se a aplicacao
   nao recuperar. Nunca marcar rollback como concluido apenas por
   `healthy` de containers.

O contrato expõe esses estados somente em simulacao Python: falhas
injetadas em qualquer passo abortam a sequencia antes de prosseguir.
**Nao contem comandos Docker de mutacao.**

## Testes offline e limites de uso

Sem precisar de VM:

```bash
python3 scripts/ga08-pa05-recovery-v2-contract.py
python3 scripts/ga08-pa05-recovery-v2-contract.py --simulate-failure WAIT_PHP_HEALTH
python3 tests/python/test_ga08_pa05_recovery_v2_contract_offline.py -q
```

Mesmo que um manifesto v2 privado seja disponibilizado no futuro,
`--check-manifest /caminho/privado/manifest.json` verificara so esquema,
permissoes e flags. O sinal de prontidao nunca e autorizacao de `up`.

**`--execute` sempre retorna `FAIL_CLOSED` nesta versao.** Nao invocar
o driver legado para recuperar esta pilha. Antes de qualquer habilitacao
de mutacao, sao necessarios: coletor privado revisado; digest de base
11 comparado com contexto autorizado; snapshots atuais, teste de retorno,
CI e revisao humana da PR; plano de contingencia e autorizacao expressa.

## Decisao para merge

A validacao da configuracao ativa ja possui evidencias fortes. Este contrato
v2 adiciona somente o **modelo de seguranca da recuperacao**; nao retira
automaticamente a PR #217 de Draft. Um merge preparatorio de codigo sem
deploy exige revisao de escopo e confirmacao de que a `main` nao aciona
implantacoes automaticas; um merge descrito como recuperacao funcional
requer antes evidencia de retorno efetivo e testes E2E.
