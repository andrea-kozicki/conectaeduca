#!/usr/bin/env python3
"""GA08.33 safety + functional protocol contracts, mock/offline only."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest import mock

FILE=Path(__file__).resolve().parents[2]/"scripts/ga08-33-sockets-persistentes-e2e-ep125.py"
spec=importlib.util.spec_from_file_location("ga08_33",FILE)
assert spec and spec.loader
M=importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)

class Contract(unittest.TestCase):
    def test_default_safe_without_runtime(self):
        out=io.StringIO()
        with mock.patch("sys.argv",["diag"]),redirect_stdout(out),\
             mock.patch.object(M,"run",side_effect=AssertionError("DID_RUN")):
            self.assertEqual(M.main(),0)
        self.assertIn("MODO=PLANO",out.getvalue())

    def test_http_and_fpm_bind_rw_ro_pair(self):
        n=M.mounts(
            "sha256:"+"1"*64,"test-ng",Path("/tmp/public-ng.conf"),
            "/etc/nginx/conf.d/default.conf",101,["82"],
            M.TARGET_HTTP,M.TARGET_FPM,M.HOST_HTTP,M.HOST_FPM,
            "/run/conectaeduca-http/ga08check-abc/http.sock",
            "700","nginx -g 'daemon off;'", "test -S /run/conectaeduca-http/ga08check-abc/http.sock"
        )
        self.assertIn("--network",n)
        self.assertIn("none",n)
        self.assertIn("--read-only",n)
        self.assertIn("--user",n)
        self.assertIn("101:101",n)
        self.assertIn("--group-add",n)
        self.assertIn("82",n)
        self.assertIn("type=bind,src=/var/lib/conectaeduca-ga08/http,dst=/run/conectaeduca-http",n)
        self.assertIn("type=bind,src=/var/lib/conectaeduca-ga08/fpm,dst=/run/conectaeduca-fpm,readonly",n)
        self.assertIn("mkdir -m 700",n[-1])
        self.assertTrue(any("/run:rw," in x and "uid=101" in x for x in n))
        p=M.mounts(
            "sha256:"+"2"*64,"test-php",Path("/tmp/public-fpm.conf"),
            "/usr/local/etc/php-fpm.d/zz-conectaeduca.conf",82,[],
            M.TARGET_FPM,M.TARGET_HTTP,M.HOST_FPM,M.HOST_HTTP,
            "/run/conectaeduca-fpm/ga08check-abc/fpm.sock",
            "750","php-fpm -F","test -S /run/conectaeduca-fpm/ga08check-abc/fpm.sock"
        )
        self.assertIn("type=bind,src=/var/lib/conectaeduca-ga08/fpm,dst=/run/conectaeduca-fpm",p)
        self.assertIn("type=bind,src=/var/lib/conectaeduca-ga08/http,dst=/run/conectaeduca-http,readonly",p)
        self.assertIn("82:82",p)
        self.assertTrue(any("/run:rw," in x and "uid=82" in x for x in p))
        self.assertIn("mkdir -m 750",p[-1])
        self.assertFalse(any("/run/secrets" in v for v in n+p))

    def test_status_contract_and_php_crlf(self):
        with mock.patch.object(M,"run") as call:
            call.return_value=mock.Mock(returncode=0,stdout="HTTP_STATIC=PASS\nFASTCGI_PING=PASS\n")
            with redirect_stdout(io.StringIO()):
                self.assertTrue(M.php_client("sha256:"+"1"*64,"/run/conectaeduca-http/g/http.sock"))
            argv=call.call_args.args[0]
            self.assertIn("--network",argv)
            self.assertIn("--read-only",argv)
            self.assertIn("readonly"," ".join(argv))
            code=argv[argv.index("-r")+1]
            self.assertIn('HTTP/1.1\\r\\nHost:',code)
            self.assertIn('stream_socket_client("unix://"',code)
            self.assertIn('str_starts_with($raw',code)
            self.assertIn('"=FAIL\\n"',code)
            self.assertIn('"\\n"',code)

    def test_exact_temp_config_replaces_only_listener(self):
        with mock.patch.object(M,"run",side_effect=AssertionError("NO_NETWORK")):
            self.assertEqual(M.N_CONF.name,"app-http.dual-socket.candidate.conf")
            self.assertEqual(M.P_CONF.name,"zz-conectaeduca.socket.candidate.conf")
        s=FILE.read_text()
        self.assertIn('nginx_text.count(old_fpm) != 6',s)
        self.assertIn("temp_config(",s)
        self.assertIn("secrets.token_hex(8)",s)

    def test_narrow_cleanup_only_own_subfolder(self):
        with mock.patch.object(M,"run",return_value=mock.Mock(returncode=0)) as call:
            with redirect_stdout(io.StringIO()):
                self.assertTrue(M.cleanup("",M.HOST_HTTP,M.TARGET_HTTP,"ga08check-123456","http.sock",101,"sha256:"+"a"*64,True))
            args=call.call_args.args[0]
            self.assertIn("--network",args)
            self.assertIn("--read-only",args)
            self.assertIn("rmdir",args[-1])
            self.assertIn('rm -f "$file"',args[-1])
            self.assertNotIn("rm -r",args[-1])
            self.assertIn("ga08check-123456",args[-1])

    def test_never_touches_production_compose(self):
        src=FILE.read_text()
        for forbidden in ('"compose", "up"','"compose", "down"',
                          '"docker", "stop"','"docker", "prune"',
                          'chmod(', 'chown('):
            self.assertNotIn(forbidden,src)
        self.assertIn("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT",src)
        self.assertIn("PA02_FECHADO=NAO",src)

if __name__=="__main__":
    unittest.main()
