# GA-08 — Marco de validação do socket Unix — 28/10/2026

## Resultado confirmado
O ensaio isolado `GA08_NGINX_FPM_INTEGRADO_V4_20261028T215119.txt` registrou:
- `VOLUME_PREPARADO=SIM`;
- PHP-FPM `RUNNING=true EXIT=0`, pronto para conexões;
- socket `UID=82 GID=82 MODO=660`;
- Nginx `RUNNING=true EXIT=0`;
- `RESPOSTA_FPM=pong`;
- `NETWORK_MODE=NONE_EM_AMBOS`, nenhuma porta publicada;
- `PRODUCAO=NAO_ALTERADA`, `STATUS=INTEGRACAO_OK`.

## Interpretação e limites
A comunicação FastCGI Nginx→PHP-FPM por socket Unix foi comprovada em contêineres efêmeros, sem rede. A solução candidata utiliza Nginx UID101/GID101 com grupo suplementar 82 e PHP-FPM UID82/GID82, sem `listen.owner` ou `listen.group` na configuração FPM não-root. Isso elimina a necessidade de comunicação TCP Nginx→PHP-FPM no desenho proposto.

**Ainda não comprovado:** implantação do overlay Compose completo; isolamento efetivo PHP→Nginx no ambiente de aplicação; acesso do PHP ao banco EP126; persistência e saúde de todos os serviços após eventual implantação; rollback testado. Não executar merge ou implantação antes desses gates.

## Histórico relevante
- Teste com `listen.owner/group`: FPM encerrava com `failed to chown() ... Operation not permitted` (exit 78).
- Ensaio `GA08_SOCKET_GRUPO82_20261028T214034.txt`: `SOCKET_CONNECT_OK` para UID101 com grupo suplementar 82.
- Ensaio v3 e primeira execução v4: configuração FPM local desatualizada.
- Segunda execução v4: configuração sincronizada e integração `pong` confirmada.

## Evidência e diário da EP125
`/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP125/GA08/GA08_NGINX_FPM_INTEGRADO_V4_20261028T215119.txt`

O script v4 contém rotina de append no `~/ConectaEduca_Fase2_Evidencias/EP125/diario.md`. A presença efetiva da última entrada deverá ser confirmada em leitura posterior, sem presumir acesso direto ao arquivo da VM.

## Próximos gates
1. Validar sintaxe e resolução do Compose com todos os overlays efetivos, sem aplicar alterações.
2. Verificar redes, mounts, grupo suplementar e permissões resultantes.
3. Ensaiar isolamento PHP→Nginx e manutenção do fluxo WAF→Nginx→FPM.
4. Validar conectividade PHP→EP126 e planejar rollback antes de implantação autorizada.
