#!/usr/bin/env bash
# ConectaEduca - biblioteca comum para implantação das VMs Ubuntu.
# Bash deliberado: os hosts finais são Ubuntu e os orquestradores usam Bash.

CE_FAILURES=0
CE_WARNINGS=0
CE_REPORT=""

ce_set_report() {
    CE_REPORT="$1"
}

ce_emit() {
    local line="$*"
    printf '%s\n' "$line"
    if [[ -n "$CE_REPORT" ]]; then
        printf '%s\n' "$line" >>"$CE_REPORT" || {
            printf 'ERRO: não foi possível gravar o relatório: %s\n' "$CE_REPORT" >&2
            exit 1
        }
    fi
}

ce_section() {
    ce_emit ""
    ce_emit "============================================================"
    ce_emit "$*"
    ce_emit "============================================================"
}

ce_ok() {
    ce_emit "OK|$*"
}

ce_warn() {
    CE_WARNINGS=$((CE_WARNINGS + 1))
    ce_emit "AVISO|$*"
}

ce_fail() {
    CE_FAILURES=$((CE_FAILURES + 1))
    ce_emit "FALHA|$*"
}

ce_have() {
    command -v "$1" >/dev/null 2>&1
}

ce_trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

ce_valid_ipv4() {
    local ip="$1" IFS=. octets=() oct
    read -r -a octets <<<"$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for oct in "${octets[@]}"; do
        [[ "$oct" =~ ^[0-9]+$ ]] || return 1
        (( 10#$oct >= 0 && 10#$oct <= 255 )) || return 1
    done
}

ce_valid_iface() {
    local value="$1"
    [[ -n "$value" ]] || return 1
    [[ "$value" != -* ]] || return 1
    [[ "$value" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

ce_valid_role() {
    [[ "$1" == "dmz" || "$1" == "interna" ]]
}

ce_valid_stage() {
    [[ "$1" == "base" || "$1" == "network" || "$1" == "deploy" ]]
}

ce_semver_triplet() {
    local v="${1#v}"
    if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    fi
    return 1
}

ce_version_ge() {
    local current="$1" required="$2"
    local -a c=() r=()
    mapfile -t c < <(ce_semver_triplet "$current" | tr ' ' '\n') || return 1
    mapfile -t r < <(ce_semver_triplet "$required" | tr ' ' '\n') || return 1
    [[ ${#c[@]} -eq 3 && ${#r[@]} -eq 3 ]] || return 1

    local i
    for i in 0 1 2; do
        if (( 10#${c[$i]} > 10#${r[$i]} )); then return 0; fi
        if (( 10#${c[$i]} < 10#${r[$i]} )); then return 1; fi
    done
    return 0
}

ce_cfg_get() {
    local key="$1" file="$2"
    awk -v wanted="$key" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            line=$0
            pos=index(line, "=")
            if (pos == 0) next
            k=trim(substr(line, 1, pos-1))
            if (k != wanted) next
            count++
            v=trim(substr(line, pos+1))
            if ((v ~ /^".*"$/) || (v ~ /^\047.*\047$/)) {
                v=substr(v, 2, length(v)-2)
            }
            value=v
        }
        END {
            if (count > 1) exit 3
            if (count == 1) print value
        }
    ' "$file"
}

ce_cfg_validate_keys() {
    local file="$1"
    shift
    local allowed=" $* "
    local key bad=0

    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        if [[ "$allowed" != *" $key "* ]]; then
            printf 'UNKNOWN=%s\n' "$key"
            bad=1
        fi
    done < <(
        awk '
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            {
                pos=index($0, "=")
                if (pos == 0) {
                    print "__LINHA_SEM_IGUAL__"
                    next
                }
                key=substr($0, 1, pos-1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                print key
            }
        ' "$file"
    )

    return "$bad"
}

ce_file_mode_private() {
    local file="$1" mode
    mode="$(stat -c '%a' "$file" 2>/dev/null)" || return 1
    case "$mode" in
        400|440|600|640) return 0 ;;
        *) return 1 ;;
    esac
}

ce_is_tracked() {
    local root="$1" file="$2" rel
    [[ "$file" == "$root/"* ]] || return 1
    rel="${file#"$root/"}"
    git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1
}


ce_require_project_root() {
    local root="${PROJECT_ROOT:-}"
    if [[ -z "$root" ]]; then
        root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    fi
    [[ -n "$root" && -d "$root/.git" ]] || return 1
    printf '%s' "$root"
}

ce_cfg_required() {
    local key="$1" file="$2" value rc=0
    value="$(ce_cfg_get "$key" "$file")" || rc=$?
    (( rc == 0 )) || return "$rc"
    [[ -n "$value" ]] || return 4
    printf '%s' "$value"
}

ce_port_valid() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

ce_wait_container_health() {
    local cid="$1" timeout="${2:-180}" elapsed=0 state health
    while (( elapsed <= timeout )); do
        state="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || true)"
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || true)"
        if [[ "$state" == "running" && ( "$health" == "healthy" || "$health" == "none" ) ]]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed+5))
    done
    return 1
}

ce_valid_git_oid() {
    [[ "$1" =~ ^[0-9a-fA-F]{40}$ || "$1" =~ ^[0-9a-fA-F]{64}$ ]]
}

ce_valid_git_tag_name() {
    local tag="$1"
    [[ -n "$tag" && "$tag" != -* ]] || return 1
    git check-ref-format "refs/tags/$tag" >/dev/null 2>&1
}

ce_git_exact_tags() {
    local root="$1"
    git -C "$root" tag --points-at HEAD 2>/dev/null | sort | paste -sd, -
}

ce_git_baseline_matches() {
    local root="$1" expected_commit="$2" expected_tag="$3"
    local head tag_commit
    ce_valid_git_oid "$expected_commit" || return 2
    ce_valid_git_tag_name "$expected_tag" || return 3
    head="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || return 4
    tag_commit="$(git -C "$root" rev-parse "$expected_tag^{commit}" 2>/dev/null)" || return 5
    [[ "${head,,}" == "${expected_commit,,}" ]] || return 6
    [[ "${tag_commit,,}" == "${head,,}" ]] || return 7
}
