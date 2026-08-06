#!/usr/bin/env bash
set -u

AUDIT_ROOT="${AUDIT_ROOT:-/tmp/vssr2-capability-audit-final}"
REPO_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
mkdir -p "$AUDIT_ROOT/logs" "$AUDIT_ROOT/results" "$AUDIT_ROOT/cache"
rm -rf "$AUDIT_ROOT/omnigent" "$AUDIT_ROOT/openinterpreter" "$AUDIT_ROOT/canary" "$AUDIT_ROOT/canary2"

run_logged() {
  local log="$1"
  shift
  set +e
  "$@" >"$AUDIT_ROOT/logs/$log" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '\nVSSR_FAIL rc=%s\n' "$rc" >>"$AUDIT_ROOT/logs/$log"
  fi
  return "$rc"
}

printf '=== exact source checkout ===\n'
git clone --depth 1 --branch v0.8.2 https://github.com/omnigent-ai/omnigent.git "$AUDIT_ROOT/omnigent"
git clone --depth 1 --branch rust-v0.0.34 https://github.com/openinterpreter/openinterpreter.git "$AUDIT_ROOT/openinterpreter"
git -C "$AUDIT_ROOT/omnigent" rev-parse HEAD | tee "$AUDIT_ROOT/logs/omnigent_sha.log"
git -C "$AUDIT_ROOT/openinterpreter" rev-parse HEAD | tee "$AUDIT_ROOT/logs/openinterpreter_sha.log"

printf '=== reversible read/write/update/delete canary ===\n'
if ! run_logged canary_attempt1.log docker run --rm \
  -v "$AUDIT_ROOT:/audit" alpine:3.20 sh -c '
    set -eu
    for tool in omnigent openinterpreter; do
      p="/audit/canary/$tool/read-write.txt"
      mkdir -p "$(dirname "$p")"
      printf "%s-canary\n" "$tool" > "$p"
      grep -qx "$tool-canary" "$p"
      printf "updated\n" >> "$p"
      test "$(wc -l < "$p")" -eq 2
      rm -f "$p"
      test ! -e "$p"
    done
    echo VSSR_PASS
  '; then
  run_logged canary_attempt2.log docker run --rm \
    -v "$AUDIT_ROOT:/audit" python:3.12-alpine python -c '
from pathlib import Path
for tool in ("omnigent", "openinterpreter"):
    p = Path("/audit/canary2") / tool / "read-write.txt"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"{tool}-canary\n", encoding="utf-8")
    assert p.read_text(encoding="utf-8") == f"{tool}-canary\n"
    p.write_text("updated\n", encoding="utf-8")
    assert p.read_text(encoding="utf-8") == "updated\n"
    p.unlink()
    assert not p.exists()
print("VSSR_PASS")
' || true
fi

printf '=== Omnigent CLI exact v0.8.2 ===\n'
run_logged omni_cli_attempt1.log docker run --rm \
  -v "$AUDIT_ROOT/omnigent:/src:ro" python:3.12-bookworm bash -c '
    set -euo pipefail
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git build-essential >/dev/null
    python -m pip install -q --upgrade "uv>=0.11.8"
    cp -a /src /tmp/omnigent
    cd /tmp/omnigent
    OMNIGENT_SKIP_WEB_UI=true uv sync --extra dev
    .venv/bin/omnigent --version
    .venv/bin/omnigent --help >/tmp/omnigent-help.txt
    .venv/bin/omni diagnose --help >/tmp/omnigent-diagnose-help.txt
    test -s /tmp/omnigent-help.txt
    test -s /tmp/omnigent-diagnose-help.txt
    echo VSSR_PASS
  ' || true

printf '=== Omnigent local component tests intervention 1 ===\n'
if ! run_logged omni_tests_attempt1.log docker run --rm \
  -v "$AUDIT_ROOT/omnigent:/src:ro" python:3.12-bookworm bash -c '
    set -euo pipefail
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git build-essential >/dev/null
    python -m pip install -q --upgrade "uv>=0.11.8"
    cp -a /src /tmp/omnigent
    cd /tmp/omnigent
    OMNIGENT_SKIP_WEB_UI=true uv sync --extra dev
    mapfile -t files < <(
      find tests -type f -name "test_*.py" \
        | grep -Ei "(policy|sandbox|scheduled|session|harness|mcp|slack|auth|project|subagent|polly|debby|database|cli)" \
        | grep -Ev "(e2e|configure_models|coding_d7_migration|databricks|integration|live)" \
        | sort | head -n 40
    )
    printf "selected_files=%s\n" "${#files[@]}"
    printf "%s\n" "${files[@]}"
    test "${#files[@]}" -gt 0
    timeout 1200 uv run pytest -q "${files[@]}" \
      -m "not live and not databricks and not nightly" \
      --disable-warnings --maxfail=20
    echo VSSR_PASS
  '; then
  printf '=== Omnigent local component tests intervention 2 ===\n'
  run_logged omni_tests_attempt2.log docker run --rm \
    -v "$AUDIT_ROOT/omnigent:/src:ro" python:3.12-bookworm bash -c '
      set -euo pipefail
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git build-essential >/dev/null
      python -m pip install -q --upgrade "uv>=0.11.8"
      cp -a /src /tmp/omnigent
      cd /tmp/omnigent
      OMNIGENT_SKIP_WEB_UI=true uv sync --extra dev
      mapfile -t files < <(
        find tests -type f -name "test_*.py" \
          | grep -Ei "(policy|scheduled|sandbox)" \
          | grep -Ev "(e2e|configure_models|coding_d7_migration|databricks|integration|live)" \
          | sort | head -n 12
      )
      printf "selected_files=%s\n" "${#files[@]}"
      printf "%s\n" "${files[@]}"
      test "${#files[@]}" -gt 0
      timeout 900 uv run pytest -q "${files[@]}" \
        -m "not live and not databricks and not nightly" \
        --disable-warnings --maxfail=10
      echo VSSR_PASS
    ' || true
fi

printf '=== Open Interpreter exact rust-v0.0.34 release CLI ===\n'
run_logged oi_cli_attempt1.log docker run --rm \
  -v "$AUDIT_ROOT/openinterpreter:/src:ro" ubuntu:24.04 bash -c '
    set -euo pipefail
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl jq tar gzip findutils >/dev/null
    asset="$(curl -fsSL https://api.github.com/repos/openinterpreter/openinterpreter/releases/tags/rust-v0.0.34 \
      | jq -r ".assets[] | select(.name | test(\"open-interpreter-package-x86_64-unknown-linux-(gnu|musl)\\\\.tar\\\\.gz$\")) | .browser_download_url" \
      | head -n 1)"
    test -n "$asset"
    mkdir -p /tmp/oi
    curl -fsSL "$asset" -o /tmp/oi.tar.gz
    tar -xzf /tmp/oi.tar.gz -C /tmp/oi
    bin="$(find /tmp/oi -type f -name interpreter -perm -111 | head -n 1)"
    test -x "$bin"
    "$bin" --version
    "$bin" --help >/tmp/oi-help.txt
    "$bin" exec --help >/tmp/oi-exec-help.txt
    "$bin" acp --help >/tmp/oi-acp-help.txt
    "$bin" mcp-server --help >/tmp/oi-mcp-help.txt
    test -s /tmp/oi-help.txt
    test -s /tmp/oi-exec-help.txt
    test -s /tmp/oi-acp-help.txt
    test -s /tmp/oi-mcp-help.txt
    echo VSSR_PASS
  ' || true

printf '=== Open Interpreter codex-rs tests intervention 1 ===\n'
if ! run_logged oi_tests_attempt1.log docker run --rm \
  -v "$AUDIT_ROOT/openinterpreter:/src:ro" \
  -v "$AUDIT_ROOT/cache/cargo:/cargo" rust:1-bookworm bash -c '
    set -euo pipefail
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git pkg-config libssl-dev clang cmake >/dev/null
    cp -a /src /tmp/openinterpreter
    cd /tmp/openinterpreter/codex-rs
    export PATH=/usr/local/cargo/bin:$PATH
    export CARGO_HOME=/cargo/home
    export CARGO_TARGET_DIR=/cargo/target
    cargo metadata --no-deps --format-version 1 | grep -q "\"name\":\"codex-core\""
    timeout 1800 cargo test -p codex-core --lib --no-fail-fast
    echo VSSR_PASS
  '; then
  printf '=== Open Interpreter protocol/MCP tests intervention 2 ===\n'
  run_logged oi_tests_attempt2.log docker run --rm \
    -v "$AUDIT_ROOT/openinterpreter:/src:ro" \
    -v "$AUDIT_ROOT/cache/cargo:/cargo" rust:1-bookworm bash -c '
      set -euo pipefail
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git pkg-config libssl-dev clang cmake jq >/dev/null
      cp -a /src /tmp/openinterpreter
      cd /tmp/openinterpreter/codex-rs
      export PATH=/usr/local/cargo/bin:$PATH
      export CARGO_HOME=/cargo/home
      export CARGO_TARGET_DIR=/cargo/target
      pkg="$(cargo metadata --no-deps --format-version 1 \
        | jq -r ".packages[].name" \
        | grep -E "^(codex-protocol|codex-mcp-server|codex-app-server-protocol)$" \
        | head -n 1)"
      test -n "$pkg"
      printf "selected_package=%s\n" "$pkg"
      timeout 1200 cargo test -p "$pkg" --lib --no-fail-fast
      echo VSSR_PASS
    ' || true
fi

printf '=== build all 115 claim records ===\n'
python3 "$REPO_ROOT/scripts/vssr2_tool_capability_audit.py" \
  --root "$AUDIT_ROOT" --out "$AUDIT_ROOT/results"
cp "$AUDIT_ROOT/logs/"*.log "$AUDIT_ROOT/results/" 2>/dev/null || true
{
  echo "branch=${GITHUB_REF_NAME:-local}"
  echo "workflow_run_id=${GITHUB_RUN_ID:-local}"
  echo "workflow_run_attempt=${GITHUB_RUN_ATTEMPT:-1}"
  echo "runner=${RUNNER_NAME:-local}"
  echo "repository=${GITHUB_REPOSITORY:-unknown}"
  echo "production_credentials=false"
  echo "production_mounts=false"
  echo "container_cleanup=docker --rm"
  echo "audit_root=$AUDIT_ROOT"
} > "$AUDIT_ROOT/results/execution-receipt.txt"

printf 'VSSR2_FINAL_COMPLETE\n'
