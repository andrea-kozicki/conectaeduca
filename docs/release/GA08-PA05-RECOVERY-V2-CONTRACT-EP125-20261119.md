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
