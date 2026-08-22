rule ConectaEduca_Synthetic_Test_Marker
{
    meta:
        description = "Marcador sintetico para demonstracao academica ConectaEduca"
        scope = "laboratorio"

    strings:
        $marker = "CONECTAEDUCA_YARA_TEST_MARKER_2026" ascii

    condition:
        $marker
}

rule ConectaEduca_PHP_Encoded_Eval_Heuristic
{
    meta:
        description = "Heuristica defensiva para PHP com eval e base64_decode"
        scope = "servidor-web"

    strings:
        $eval = "eval(" ascii nocase
        $b64 = "base64_decode(" ascii nocase

    condition:
        filesize < 2MB and all of them
}
