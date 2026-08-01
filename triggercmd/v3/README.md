# TRIGGERcmd Control Plane v3

## Purpose

This is the durable bridge between ChatGPT's TRIGGERcmd connector and the Windows computer at `C:\Users\mozar`.

The design replaces repeated PowerShell dumps with a self-updating bootstrap and a job-based command fleet.

## Architecture

1. `bootstrap.ps1` downloads and verifies `manifest.json`.
2. Every managed file is checked against its SHA-256 hash before installation.
3. Existing files and `commands.json` are backed up before replacement.
4. `commands.json` is regenerated atomically from the manifest.
5. The TRIGGERcmd agent is restarted asynchronously after the result is returned.
6. Long-running commands immediately return a job ID, then complete in the background.
7. `job_status` and `job_result` retrieve durable execution evidence.

## One-time bridge

The current local v2 bootstrap does not know how to pull v3. One final desktop bridge is required:

```powershell
$u='https://raw.githubusercontent.com/mozartg/mozart-os-succession/main/triggercmd/v3/install-once.ps1';$p="$env:TEMP\triggercmd-v3.ps1";Invoke-WebRequest $u -OutFile $p -UseBasicParsing;powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

After this one-time bridge, future cloud-side changes require only invoking the existing `bootstrap` TRIGGERcmd command.

## Commands installed by v3

- `bootstrap` — fetch, validate, back up, install, and restart.
- `control_status` — immediate control-plane status.
- `result_probe` — fresh trigger alias for `control_status`, used to distinguish stale trigger definitions from result-callback defects.
- `job_status <job-id>` — immediate durable job metadata.
- `job_result <job-id>` — immediate durable job output.
- `workspace_list <path>` — queued directory inventory under `C:\Users\mozar`.
- `workspace_read <path>` — queued redacted text preview under `C:\Users\mozar`.
- `system_health` — queued OS, memory, disk, and uptime check.
- `process_find <fragment>` — queued process inspection.
- `port_check <port>` — queued TCP-port inspection.
- `command_find <name>` — queued executable/command lookup.
- `catdesk_status` — queued CatDesk process and port status.
- `playwright_status` — queued Node/npm/npx and browser-package status.
- `browser_status` — queued Edge/Chrome and debugging-port status.
- `approved_inventory` — queued inventory of Approved scripts.
- `trigger_reload` — immediate asynchronous agent restart.

## Result protocol

TRIGGERcmd allows roughly four to five seconds for `sendresult.bat`. Therefore, diagnostic work is not performed before acknowledging the request.

Queued commands immediately return:

```text
QUEUED <task> :: Job=<job-id>
```

The worker writes its final status and output to:

```text
C:\Users\mozar\TriggerCMD-Scripts\Control\Jobs\<job-id>.json
```

This avoids the recurring `Trigger sent. No result.` failure caused by trying to finish local diagnostics inside the reply window.

## Callback diagnosis protocol

When an existing trigger returns `[object Object]`, deploy a new trigger name mapped to the same immediate task. Then compare:

1. `bootstrap` returns the installed manifest version and managed-command count.
2. `list_commands` confirms the new trigger is visible.
3. `result_probe` must return the same compact string as `control_status`.
4. If the fresh trigger works but the old trigger fails, the provider-side trigger definition is stale.
5. If both fail, inspect the MCP result serialization and `SendResult` callback independently.
6. A passing result requires three repeated successful calls and one negative-path test.

Legacy unmanaged commands may remain in `commands.json`; therefore the provider's total command count can exceed the bootstrap managed-command count. That difference is not itself a contradiction.

## Current deployment state

- Cloud source: complete.
- Manifest and hashes: complete.
- One-time bridge installer: complete.
- Local control plane reported version `3.1.5` and CatDesk online through a returned bootstrap result on 2026-08-01.
- Most non-bootstrap command callbacks still returned `[object Object]` or no result during the same session.
- Version `3.1.6` adds `result_probe` to isolate stale-trigger behavior after deployment.

## Operating boundary

No secrets belong in this public repository. Runtime credentials remain local. Workspace reads redact common secret assignments and block selected sensitive or binary file types.
