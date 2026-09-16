# Compatibilidade Python e triagem Semgrep

## Escopo

Os scripts Python operacionais do ConectaEduca suportam **Python 3.10 ou superior**.

Essa decisão é explícita porque o código já utiliza sintaxe e recursos modernos,
como unions com `|` em type hints, por exemplo:

```python
def sanitize(event: dict) -> dict | None:
    ...
```

Portanto, achados de regras cujo objetivo é preservar compatibilidade com
Python 3.5/3.6/3.7 não representam, por si só, vulnerabilidades nem regressões
para o runtime suportado pelo projeto.

## Achados triados no sanitizador OpenBao

Um scan amplo do registry do Semgrep sinalizou no arquivo
`scripts/observabilidade/sanitizar_openbao_audit.py` as regras:

- `python36-compatibility-Popen1` — uso de `errors=` em
  `subprocess.Popen`;
- `python36-compatibility-Popen2` — uso de `encoding=` em
  `subprocess.Popen`.

Essas regras informam que os argumentos correspondentes dependem de Python
3.6+. Como o baseline do ConectaEduca é Python >= 3.10, os dois achados são
classificados como **N/A por versão mínima suportada**, e não como falhas de
segurança.

Os argumentos permanecem no código porque tornam explícito o tratamento de
texto UTF-8 e de bytes inválidos na leitura contínua dos logs do OpenBao.

## Estratégia de supressão

A supressão foi aplicada somente na chamada `subprocess.Popen` afetada e
somente para os dois IDs de compatibilidade conhecidos:

```text
python36-compatibility-Popen1
python36-compatibility-Popen2
```

Não foi usado `.semgrepignore` para excluir o arquivo e não foram
desabilitadas regras de segurança relacionadas a `subprocess`.

O gate local continua detectando, entre outras classes:

- `eval/exec` inseguro em Python;
- `subprocess` com `shell=True`;
- `eval` em PHP;
- exposição direta de mensagem interna de exceção em PHP.

As fixtures positivas permanecem obrigatórias para provar que o SAST continua
detectando padrões vulneráveis.

## Gate de runtime

O checkpoint `scripts/evidencias/checkpoint_semgrep_sast.sh` valida também a
versão do interpretador:

```text
PYTHON_RUNTIME_MIN=3.10
```

O gate falha antes do scan se `python3` for inferior a 3.10. Assim, a
classificação dos achados de compatibilidade não depende apenas de
documentação: o requisito mínimo é verificável no CI.

## Política de triagem

Para findings futuros:

1. achados de segurança continuam sujeitos a correção, controle compensatório
   ou risco residual documentado;
2. achados de compatibilidade só podem ser marcados N/A quando a versão mínima
   suportada estiver documentada e verificada;
3. suppressions devem citar IDs específicos de regras;
4. não usar exclusão ampla de arquivo para esconder findings;
5. uma supressão de compatibilidade não deve encobrir regra de segurança no
   mesmo sink.

Essa distinção preserva o Semgrep como controle de segurança sem obrigar o
projeto a suportar versões de Python fora do baseline técnico.
