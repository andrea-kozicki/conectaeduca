#!/usr/bin/env python3
"""CE-ZT26: reconciliação observacional do tenant Twingate (sem mutações).

Executar pelo Fish: python3 scripts/twingate/ce_twingate_reconcile.py
Somente API Read only. Não imprime nem persiste o token.
"""
import argparse
import getpass
import json
import os
import re
import sys
import urllib.error
import urllib.request

EXPECTED_NETWORKS = ("ConectaEduca - DMZ", "ConectaEduca - Rede Interna")
EXPECTED_CONNECTORS = {
    "conectaeduca-dmz-01": "ConectaEduca - DMZ",
    "conectaeduca-interna-ep126": "ConectaEduca - Rede Interna",
}
EXPECTED_GROUPS = (
    "CE-PORTAL", "CE-SOC-OPERACAO", "CE-INFRA-ADMIN",
    "CE-PENTESTB-LIMITADO",
)
# Estado atual observado em CE-ZT24/25, não uma aprovação para ampliar permissões.
EXPECTED_RESOURCES = {
    "ConectaEducaAPP": {
        "network": "ConectaEduca - DMZ",
        "policy": "CE-PORTAL-MFA-1DIA",
        "groups": {"CE-PORTAL", "CE-PENTESTB-LIMITADO"},
    },
    "ConectaEduca — Wazuh Dashboard": {
        "network": "ConectaEduca - Rede Interna",
        "policy": "CE-SOC-MFA-1DIA",
        "groups": {"CE-SOC-OPERACAO"},
    },
}

QUERY = """
query CEZT26 {
  remoteNetworks(first:100) {
    pageInfo { hasNextPage }
    edges { node { name isActive } }
  }
  connectors(first:100) {
    pageInfo { hasNextPage }
    edges {
      node {
        name state version lastHeartbeatAt
        remoteNetwork { name }
      }
    }
  }
  groups(first:100) {
    pageInfo { hasNextPage }
    edges { node { name isActive users(first:100) { totalCount } } }
  }
  resources(first:100) {
    pageInfo { hasNextPage }
    edges {
      node {
        name isActive
        remoteNetwork { name }
        securityPolicy { name }
        groups(first:100) {
          pageInfo { hasNextPage }
          edges { node { name } }
        }
      }
    }
  }
}
"""

def get_nodes(data, key):
    section = data.get(key) or {}
    if (section.get("pageInfo") or {}).get("hasNextPage"):
        raise ValueError("PAGINACAO_PENDENTE_" + key)
    return {edge["node"]["name"]: edge["node"] for edge in section.get("edges") or []}

def audit(data):
    """Retorna achados determinísticos sem alterar o tenant."""
    networks = get_nodes(data, "remoteNetworks")
    connectors = get_nodes(data, "connectors")
    groups = get_nodes(data, "groups")
    resources = get_nodes(data, "resources")
    findings = []

    def add(kind, name, status, detail):
        findings.append(dict(tipo=kind, nome=name, status=status, detalhe=detail))

    for name in EXPECTED_NETWORKS:
        node = networks.get(name)
        add("REDE", name, "OK" if node and node.get("isActive") else "REVISAR",
            "ativa" if node and node.get("isActive") else "ausente/inativa")

    for name in EXPECTED_GROUPS:
        node = groups.get(name)
        add("GRUPO", name, "OK" if node and node.get("isActive") else "REVISAR",
            "ativo" if node and node.get("isActive") else "ausente/inativo")

    for name, desired_network in EXPECTED_CONNECTORS.items():
        node = connectors.get(name)
        if not node:
            add("CONNECTOR", name, "REVISAR", "registro ausente")
            continue
        network = (node.get("remoteNetwork") or {}).get("name")
        if network != desired_network:
            add("CONNECTOR", name, "REVISAR", "Remote Network divergente")
        elif node.get("state") != "ALIVE":
            add("CONNECTOR", name, "BLOQUEADO",
                "estado=" + str(node.get("state")) +
                " heartbeat=" + str(node.get("lastHeartbeatAt")))
        else:
            add("CONNECTOR", name, "OK", "ALIVE")

    for name, expected in EXPECTED_RESOURCES.items():
        node = resources.get(name)
        if not node:
            add("RECURSO", name, "REVISAR", "ausente")
            continue
        access = node.get("groups") or {}
        if (access.get("pageInfo") or {}).get("hasNextPage"):
            raise ValueError("PAGINACAO_PENDENTE_GRUPOS_RECURSO")
        actual_groups = {e["node"]["name"] for e in access.get("edges") or []}
        actual_network = (node.get("remoteNetwork") or {}).get("name")
        actual_policy = (node.get("securityPolicy") or {}).get("name")
        differences = []
        if not node.get("isActive"):
            differences.append("inativo")
        if actual_network != expected["network"]:
            differences.append("rede divergente")
        if actual_policy != expected["policy"]:
            differences.append("política divergente")
        if actual_groups != expected["groups"]:
            differences.append("grupos divergentes: faltam=" +
                               ",".join(sorted(expected["groups"] - actual_groups)) +
                               " extras=" + ",".join(sorted(actual_groups - expected["groups"])))
        add("RECURSO", name, "REVISAR" if differences else "OK",
            "; ".join(differences) if differences else "vínculos corretos")

    for name in sorted(set(connectors) - set(EXPECTED_CONNECTORS)):
        add("CONNECTOR_EXTRA", name, "INFORMATIVO", "não excluir automaticamente")
    return findings

def fetch(tenant, token):
    req = urllib.request.Request(
        "https://" + tenant + ".twingate.com/api/graphql/",
        data=json.dumps({"query": QUERY}).encode("utf-8"),
        headers={"X-API-KEY": token, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        obj = json.load(response)
    if obj.get("errors"):
        raise ValueError("GRAPHQL_ERROR_" + str(len(obj["errors"])))
    if not isinstance(obj.get("data"), dict):
        raise ValueError("RESPOSTA_INCOMPLETA")
    return obj["data"]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tenant", default="conectaeducalab")
    parser.add_argument("--json", action="store_true", help="imprime JSON sanitizado")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,61}[a-z0-9]", args.tenant):
        parser.error("tenant inválido")
    token = os.environ.get("TWINGATE_API_TOKEN") or getpass.getpass("Token Read only: ")
    if not token.strip():
        print("TOKEN_AUSENTE", file=sys.stderr)
        return 1
    try:
        findings = audit(fetch(args.tenant, token.strip()))
    except (ValueError, urllib.error.URLError, TimeoutError, OSError) as exc:
        # Não imprimir URL, payload HTTP, headers nem o token.
        print("AUDITORIA_FALHOU=" + type(exc).__name__, file=sys.stderr)
        return 1
    finally:
        token = None
    if args.json:
        print(json.dumps({"alteracoes": False, "achados": findings},
                         ensure_ascii=False, indent=2))
    else:
        print("=== CE-ZT26 — RECONCILIACAO READ-ONLY ===")
        for item in findings:
            print(f"{item['tipo']} | {item['nome']} | {item['status']} | {item['detalhe']}")
        print("ALTERACOES=NAO")
    # Não retornar sucesso de conformidade quando há divergência / Connector offline.
    if any(f["status"] == "REVISAR" for f in findings):
        return 2
    if any(f["status"] == "BLOQUEADO" for f in findings):
        return 3
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
