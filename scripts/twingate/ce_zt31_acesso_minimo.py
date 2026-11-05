#!/usr/bin/env python3
"""CE-ZT31 — auditoria dirigida de identidade e menor privilégio (sem mutações).

Uso (Fish/Bash): python3 scripts/twingate/ce_zt31_acesso_minimo.py
Consulta apenas usuários, recursos e portas do tenant. Token Read only.
Nunca envia ou grava credenciais ou dados de sessão em arquivos.
"""
import getpass
import hashlib
import json
import urllib.error
import urllib.request

URL = "https://conectaeducalab.twingate.com/api/graphql/"
QUERY = """
query CEZT31 {
  users(first:100) {
    totalCount
    pageInfo { hasNextPage }
    edges {
      node {
        email
        role
        state
        groups(first:100) {
          pageInfo { hasNextPage }
          edges { node { name } }
        }
      }
    }
  }
  resources(first:100) {
    pageInfo { hasNextPage }
    edges {
      node {
        name
        __typename
        isActive
        remoteNetwork { name }
        securityPolicy { name }
        protocols {
          allowIcmp
          tcp { policy ports { start end } }
          udp { policy ports { start end } }
        }
        groups(first:100) {
          pageInfo { hasNextPage }
          edges { node { name } }
        }
      }
    }
  }
}
"""

EXPECT = {
    "ConectaEducaAPP": "CE-PORTAL-MFA-1DIA",
    "ConectaEduca — Wazuh Dashboard": "CE-SOC-MFA-1DIA",
}


def private_identity(email):
    """Não divulga o endereço completo ao colar saída em tickets."""
    if not email or "@" not in email:
        return "SEM_EMAIL"
    local, domain = email.rsplit("@", 1)
    digest = hashlib.sha256(email.lower().encode()).hexdigest()[:8]
    return local[:1] + "***@" + domain + " #" + digest


def ports(protocol):
    if not protocol:
        return "NAO_INFORMADO"
    policy = protocol.get("policy", "INDETERMINADO")
    if policy != "RESTRICTED":
        return policy
    pairs = protocol.get("ports") or []
    return "RESTRICTED:" + ",".join(
        str(x["start"]) if x["start"] == x["end"]
        else str(x["start"]) + "-" + str(x["end"])
        for x in pairs
    )


def port443only(node):
    p = node.get("protocols") or {}
    tcp = p.get("tcp") or {}
    udp = p.get("udp") or {}
    return (
        tcp.get("policy") == "RESTRICTED"
        and tcp.get("ports") == [{"start": 443, "end": 443}]
        and udp.get("policy") == "RESTRICTED"
        and not udp.get("ports")
        and not p.get("allowIcmp")
    )


def report(data):
    lines = ["=== CE-ZT31 — IDENTIDADES / PORTAS / MENOR PRIVILEGIO ==="]
    users = data.get("users") or {}
    resources = data.get("resources") or {}
    if any((s.get("pageInfo") or {}).get("hasNextPage") for s in (users, resources)):
        raise ValueError("PAGINACAO_PENDENTE")
    lines.append("TOTAL_IDENTIDADES=" + str(users.get("totalCount")))
    for edge in users.get("edges") or []:
        u = edge["node"]
        g = u.get("groups") or {}
        if (g.get("pageInfo") or {}).get("hasNextPage"):
            raise ValueError("PAGINACAO_GRUPO")
        names = sorted(e["node"]["name"] for e in g.get("edges") or [])
        lines += [
            "IDENTIDADE=" + private_identity(u.get("email")),
            "ESTADO=" + str(u.get("state")) + " ROLE=" + str(u.get("role")),
            "GRUPOS=" + (",".join(names) or "NENHUM"),
        ]
    for edge in resources.get("edges") or []:
        node = edge["node"]
        name = node["name"]
        p = node.get("protocols") or {}
        g = node.get("groups") or {}
        if (g.get("pageInfo") or {}).get("hasNextPage"):
            raise ValueError("PAGINACAO_RECURSO")
        names = sorted(e["node"]["name"] for e in g.get("edges") or [])
        policy = (node.get("securityPolicy") or {}).get("name")
        lines += [
            "---",
            "RECURSO=" + name,
            "REDE=" + str((node.get("remoteNetwork") or {}).get("name")),
            "GRUPOS=" + (",".join(names) or "NENHUM"),
            "POLITICA=" + str(policy),
            "TCP=" + ports(p.get("tcp")),
            "UDP=" + ports(p.get("udp")),
            "ICMP_PERMITIDO=" + str(p.get("allowIcmp")),
            "PORTAS_MINIMAS_443=" + ("SIM" if port443only(node) else "REVISAR"),
        ]
        if name in EXPECT and policy != EXPECT[name]:
            lines.append("POLITICA_ESPERADA_DIVERGENTE=SIM")
    lines += [
        "ALTERACOES=NAO",
        "TOKENS_EXIBIDOS=NAO",
        "CE-ZT31_CONCLUIDO",
    ]
    return "\n".join(lines)


def main():
    token = getpass.getpass("Token Twingate Read Only: ").strip()
    if not token:
        print("TOKEN_AUSENTE")
        return 1
    req = urllib.request.Request(
        URL,
        method="POST",
        headers={"X-API-KEY": token, "Content-Type": "application/json"},
        data=json.dumps({"query": QUERY}).encode(),
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as stream:
            payload = json.load(stream)
    except (urllib.error.URLError, TimeoutError, OSError):
        print("ERRO_REDE_OU_API_SEM_DETALHES_SENSIVEIS")
        return 1
    finally:
        token = None
    if payload.get("errors"):
        print("GRAPHQL_ERRORS=" + str(len(payload["errors"])))
        # A mensagem do servidor não é copiada; ela pode conter detalhes do tenant.
        return 1
    try:
        print(report(payload["data"]))
    except (KeyError, ValueError, TypeError):
        print("RESPOSTA_INCOMPLETA_OU_PAGINACAO")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
