# Custódia Shamir do OpenBao

## Objetivo

O OpenBao do ConectaEduca utiliza Shamir Secret Sharing com 3 shares e threshold 2. A custódia inicial mantinha as três shares no mesmo domínio de falha da EP126. A estratégia adotada para o laboratório separa a custódia do estado live sem exigir hardware adicional.

## Modelo 2-de-3

- Share 1 permanece local na EP126, protegida por diretório 0700 e arquivo 0600.
- Share 2 é criptografada localmente antes de ser armazenada no Google Drive.
- Share 3 é criptografada localmente antes de ser armazenada no OneDrive.
- As duas cópias externas usam frases secretas diferentes.
- Frases secretas não são armazenadas nos respectivos serviços de nuvem.

O OpenBao não acessa Google Drive ou OneDrive diretamente. Em um unseal normal, um operador/helper usa a Share 1 local e uma das shares externas, descriptografada somente em memória. Em cenário de perda da EP126, após restauração dos dados do mesmo OpenBao, as Shares 2 e 3 externas ainda permitem atingir o quorum 2-de-3.

## Procedimento de custódia

O helper `scripts/recuperacao/custodiar_shamir_cloud.py` possui duas fases:

1. `prepare`: criptografa Share 2 e Share 3 separadamente, produz manifestos de integridade e valida descriptografia em memória sem remover as originais.
2. `finalize`: recebe cópias baixadas novamente do Google Drive e OneDrive, revalida hash e conteúdo contra as originais e, somente após confirmação explícita, remove Share 2 e Share 3 do estado live da EP126.

O arquivo de estado gerado após a finalização não contém shares, tokens ou frases secretas.

## Recovery

O helper `scripts/recuperacao/unseal_shamir_cloud.py` suporta:

- modo normal: Share 1 local + Share 2 ou Share 3 externa;
- modo disaster: Share 2 do Google Drive + Share 3 do OneDrive.

As shares externas são descriptografadas apenas em memória e enviadas ao endpoint local de unseal do OpenBao. O helper não grava plaintext externo na EP126.

## Controles

- execução como usuário normal, sem root shell;
- sem alteração de pfSense, Twingate, rede ou políticas OpenBao;
- sem exibição de shares ou passphrases;
- sem persistência de passphrases;
- pacotes externos criptografados com AES-256-CBC + PBKDF2;
- verificação SHA-256 de ciphertext por manifesto;
- separação lógica entre Google Drive e OneDrive.

## Evidência de 05/09/2026

O fluxo de custódia foi validado no laboratório:

- cópias baixadas do Google Drive e OneDrive foram revalidadas;
- Share 1 permaneceu local;
- Shares 2 e 3 foram removidas do estado live somente após a revalidação;
- risco de domínio único do estado live foi mitigado;
- rekey não foi executado.

## Risco residual

A exclusão das Shares 2 e 3 do estado live não equivale a secure erase. Snapshots ou backups anteriores da EP126 podem conter cópias históricas das shares. Como não houve rekey, esse risco deve permanecer documentado como residual.

O teste de recovery 2-de-3 deve ser executado em janela controlada. Não é necessário reiniciar ou selar o OpenBao apenas para produzir evidência quando o ambiente está estável.
