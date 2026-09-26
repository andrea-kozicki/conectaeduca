# WAZ-02 — bases Rootcheck do grupo conectaeduca-dmz

## Objetivo

Fechar o WAZ-02 sem introduzir conteúdo arbitrário no grupo central do Wazuh.

A policy `agent.conf` deste grupo referencia:

- `etc/shared/rootkit_files.txt`;
- `etc/shared/rootkit_trojans.txt`.

Esses arquivos são materializados no Wazuh Manager a partir do payload exato do
pacote `wazuh-agent 4.14.7-1 amd64`, correspondente à versão operacional do
laboratório.

## Procedência validada

Pacote:

`wazuh-agent_4.14.7-1_amd64.deb`

URL de origem utilizada no staging:

`https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.7-1_amd64.deb`

A EP126 confirmou, via metadados locais do dpkg, os hashes MD5 esperados:

| Arquivo | MD5 esperado pelo dpkg | SHA-256 do payload validado |
|---|---|---|
| `rootkit_files.txt` | `6943964a87d768d8434fffbaceda89f2` | `a823bf4677d27a5e0d88afebc31b059460010db6645aa95ab7137d8445501789` |
| `rootkit_trojans.txt` | `53b6740f2d2cff27f2889103ed8439fd` | `6c9f84ad9b4a334b82302c138914df823b50341de49d15cc752c9115cab7139f` |

O staging em 26/09/2026 extraiu os dois arquivos sem instalação do pacote e
comprovou igualdade byte a byte com os MD5 esperados pelo dpkg.

O conteúdo upstream não é duplicado no Git do ConectaEduca. A versão do
artefato fica fixada por pacote, URL e hashes. A cópia live só pode ser feita a
partir de arquivos que coincidam com os SHA-256 acima.

## check_ports

O grupo DMZ não usa mais `<check_ports>yes</check_ports>`.

Motivo: no EP125 o Rootcheck 4.14.7 registrou que `netstat` não está
disponível e pulou a verificação de portas. Instalar `net-tools` apenas para
satisfazer esse subcheck ampliaria o software do host sem necessidade.

Controles compensatórios já existentes:

- Syscollector com inventário de portas;
- Suricata;
- pfSense;
- Wazuh;
- pentest com `nmap -sT`.

Assim, `check_ports=no` elimina o warning conhecido sem fingir cobertura
inexistente. Os demais checks Rootcheck permanecem habilitados.

## Aplicação live

A sequência de mudança é:

1. validar o `agent.conf` candidato com `verify-agent-conf`;
2. preservar backup do estado live;
3. materializar as duas bases no grupo `conectaeduca-dmz`;
4. ativar o novo `agent.conf` por último;
5. confirmar Agent 001 `Active`;
6. confirmar `agent_groups -S -i 001` como sincronizado;
7. executar `wazuh-syscheckd -t` e `wazuh-logcollector -t` no EP125;
8. comprovar ausência dos warnings antigos de bases Rootcheck e de
   `netstat not available`;
9. preservar TXT + SHA-256.

Não é necessário reiniciar o Manager para distribuição de configuração
central. Restart do agente só deve ocorrer se a validação pós-sync demonstrar
necessidade explícita.

## Rollback

O rollback restaura o `agent.conf` anterior e remove/restaura as bases de
acordo com o snapshot pré-mudança. Depois, a sincronização do Agent 001 deve ser
confirmada novamente.
