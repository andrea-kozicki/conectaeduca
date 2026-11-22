#!/usr/bin/env python3
"""Offline contract for read-only protected GA08 context comparison."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-private-context-compare-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_context_compare", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class GA08PrivateContextCompareTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.tmp = Path(work.name)
        self.root = self.tmp / "GA08"
        self.root.mkdir(mode=0o700)
        self.root.chmod(0o700)
        self.change_id = "GA08-20261104-TESTA"
        self.record = self.root / self.change_id
        self.record.mkdir(mode=0o700)
        self.record.chmod(0o700)
        self.refs = {key: "/safe/fixture/SECRET_DO_NOT_PRINT"
                     for key in mod.REFERENCE_KEYS}
        self.refs["CONECTAEDUCA_APP_URL"] = "https://SECRET_DO_NOT_PRINT"
        self.refs["CONECTAEDUCA_DB_HOST"] = "database.internal"
        self.refs["CONECTAEDUCA_DB_PORT"] = "3306"
        self.refs["CONECTAEDUCA_STACK_SECRET_GID"] = "82"
        self.refs["CONECTAEDUCA_HTTP_PORT"] = "80"
        self.refs["CONECTAEDUCA_HTTPS_PORT"] = "443"
        self.refs["CONECTAEDUCA_WAF_BIND_ADDRESS"] = "0.0.0.0"
        self.context = {
            "format": 1, "change_id": self.change_id, "host": "ep125-pucpr",
            "references": self.refs,
        }
        self.manifest = {
            "change_id": self.change_id, "project": mod.PROJECT,
            "rollback_config_sha256": {"9": "a" * 64, "10": "b" * 64},
        }
        self.write("runtime-refs.json", self.context)
        self.write("manifest.json", self.manifest)

    def write(self, name, obj):
        path = self.record / name
        path.write_text(json.dumps(obj), encoding="utf-8")
        path.chmod(0o600)
        return path

    def test_protected_context_parses_but_values_not_printed(self):
        self.assertEqual(mod.records(self.root), [self.record])
        data = mod.read_private_json(self.record / "runtime-refs.json")
        refs = mod.context_references(data, self.change_id)
        self.assertEqual(refs, self.refs)
        self.assertEqual(mod.manifest_class(self.manifest, self.change_id),
                         "LEGADO_9_10")
        self.assertEqual(mod.compare_references(refs, {k: refs[k] for k in
                         mod.REFERENCE_KEYS if k != "CONECTAEDUCA_GA08_NGINX_CONF"}),
                         (17, 0, 0))

    def test_one_mismatch_and_one_unknown_are_counted_without_values(self):
        live = {k: value for k, value in self.refs.items()
                if k != "CONECTAEDUCA_GA08_NGINX_CONF"}
        live["CONECTAEDUCA_DB_HOST"] = "unapproved-other"
        live["CONECTAEDUCA_PRIVATE_KEY_FILE"] = None
        self.assertEqual(mod.compare_references(self.refs, live), (15, 1, 1))

    def test_context_requires_exact_18_keys_and_identity(self):
        obj = dict(self.context)
        obj["references"] = dict(self.refs)
        obj["references"].pop("CONECTAEDUCA_DB_HOST")
        with self.assertRaisesRegex(mod.GateError, "contexto_chaves_divergentes"):
            mod.context_references(obj, self.change_id)
        with self.assertRaisesRegex(mod.GateError, "contexto_identidade_divergente"):
            mod.context_references(self.context, "GA08-20261103-OTHER")

    def test_read_rejects_unsafe_mode_and_symlink(self):
        path = self.record / "runtime-refs.json"
        path.chmod(0o644)
        with self.assertRaisesRegex(mod.GateError, "arquivo_permissao_insegura"):
            mod.read_private_json(path)
        path.chmod(0o600)
        alias = self.record / "symlink.json"
        alias.symlink_to(path)
        with self.assertRaisesRegex(mod.GateError, "json_privado_indisponivel"):
            mod.read_private_json(alias)

    def test_private_json_sanitizes_parse_failures(self):
        path = self.record / "runtime-refs.json"
        path.write_text("PASSWORD_SECRET_UNEXPECTED_JSON", encoding="utf-8")
        path.chmod(0o600)
        with self.assertRaises(mod.GateError) as error:
            mod.read_private_json(path)
        self.assertNotIn("PASSWORD_SECRET", str(error.exception))

    def test_legacy_manifest_never_proves_pa05_rollback(self):
        self.assertEqual(mod.manifest_class(self.manifest, self.change_id),
                         "LEGADO_9_10")
        newer = dict(self.manifest)
        newer["rollback_config_sha256"] = {"11": "c" * 64}
        self.assertEqual(mod.manifest_class(newer, self.change_id),
                         "11_PRESENTE_NAO_ATESTADO")
        newer["rollback_config_sha256"] = {"9": "NOT_SHA256", "10": "b" * 64}
        self.assertEqual(mod.manifest_class(newer, self.change_id),
                         "DIGESTS_INVALIDOS")

    def test_runtime_recovery_from_synthetic_mounts(self):
        def mount(dest, source):
            return {"Destination": dest, "Source": source, "Type": "bind"}

        php = {
            "Config": {"Env": ["DB_HOST=db.internal", "DB_PORT=3306",
                               "APP_URL=https://example.test"]},
            "HostConfig": {"GroupAdd": ["82"]},
            "Mounts": [
                mount("/run/secrets/" + name, "/secure/" + name)
                for name in ("conectaeduca_db_password", "conectaeduca_private_key",
                             "conectaeduca_public_key", "conectaeduca_db_tls_ca")
            ] + [mount("/run/conectaeduca-fpm", "/run/ce-fpm"),
                 mount("/usr/local/etc/php-fpm.d/zz-conectaeduca.conf", "/cfg/fpm")],
        }
        nginx = {"Mounts": [
            mount("/run/conectaeduca-fpm", "/run/ce-fpm"),
            mount("/run/conectaeduca-http", "/run/ce-http"),
            mount("/etc/nginx/conf.d/default.conf", "/cfg/http-unix"),
        ]}
        waf = {
            "HostConfig": {"GroupAdd": ["82"], "PortBindings": {
                "8080/tcp": [{"HostIp": "0.0.0.0", "HostPort": "80"}],
                "8443/tcp": [{"HostIp": "0.0.0.0", "HostPort": "443"}],
            }},
            "Mounts": [
                mount("/run/conectaeduca-http", "/run/ce-http"),
                mount("/run/secrets/waf_tls_cert", "/secure/tls-cert"),
                mount("/run/secrets/waf_tls_key", "/secure/tls-key"),
            ],
        }
        found = mod.runtime_references({"php": php, "nginx": nginx, "waf": waf})
        self.assertEqual(len(found), 17)
        self.assertEqual(found["CONECTAEDUCA_GA08_SOCKET_DIR"], "/run/ce-fpm")
        self.assertEqual(found["CONECTAEDUCA_GA08_HTTP_SOCKET_DIR"], "/run/ce-http")
        self.assertEqual(found["CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF"],
                         "/cfg/http-unix")
        self.assertEqual(found["CONECTAEDUCA_STACK_SECRET_GID"], "82")

    def test_main_only_prints_classified_counts_not_private_values(self):
        current = {key: val for key, val in self.refs.items()
                   if key != "CONECTAEDUCA_GA08_NGINX_CONF"}
        with (
            mock.patch.object(mod.socket, "gethostname", return_value="ep125-pucpr"),
            mock.patch.object(mod.os, "geteuid", return_value=1000),
            mock.patch.object(mod, "REPO", self.tmp),
            mock.patch.object(mod, "private_root", return_value=self.root),
            mock.patch.object(mod, "inspect_runtime", return_value={}),
            mock.patch.object(mod, "runtime_references", return_value=current),
            mock.patch("builtins.print") as printed,
        ):
            self.assertEqual(mod.main(), 0)
        output = "\n".join(str(call.args[0]) for call in printed.call_args_list)
        self.assertIn("REFERENCIAS_MATCH=17", output)
        self.assertIn("MANIFESTO_MODELO=LEGADO_9_10", output)
        self.assertIn("ROLLBACK_PA05_APROVADO=NAO", output)
        self.assertNotIn("SECRET_DO_NOT_PRINT", output)
        self.assertNotIn("/safe/fixture", output)

    def test_source_has_no_mutation_or_raw_logging(self):
        script = SCRIPT.read_text(encoding="utf-8")
        for forbidden in (
            "docker compose", "subprocess.check_output", "print(proc.stdout)",
            "print(proc.stderr)", "print(refs)", "print(manifest)",
            "os.environ.update", ".write_text(", ".write_bytes(",
        ):
            self.assertNotIn(forbidden, script)


if __name__ == "__main__":
    unittest.main()
