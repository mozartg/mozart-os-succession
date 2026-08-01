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

## Current deployment state

- Cloud source: complete.
- Manifest and hashes: complete.
- One-time bridge installer: complete.
- Local v3 deployment: pending the one-time desktop bridge.
- Current local v2 bootstrap: still working and remotely callable.

## Operating boundary

No secrets belong in this public repository. Runtime credentials remain local. Workspace reads redact common secret assignments and block selected sensitive or binary file types.
