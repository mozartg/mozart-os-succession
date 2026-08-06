# Mozart OS — Fable Succession Pack

**Status:** IMPLEMENTED-UNVERIFIED REFERENCE PACK — as of 2026-08-06

A collection of operating doctrine, verification-skill templates, an audit-offer template, and an Android application specification inspired by a prior working style.

## What this repository is

- `doctrine/FABLE-DOCTRINE.md` — proposed model-routing and verification rules
- `skills/` — five zero-dependency Claude skill packages
- `offers/` — fixed-scope audit offer and gig-copy templates
- `apps/` — Vocal Warm-Up Coach specification
- `HANDOFF.md` — instructions for reproducing parts of the documented workflow
- `.github/workflows/reusable-micro-test.yml` — shared repository checks used by multiple repositories

## What is verified

The reusable micro-test v2 branch passed:

- strict workflow syntax validation;
- verified `actionlint` checksum installation;
- exact SHA-pinned official GitHub Actions;
- a live reusable-workflow invocation;
- evidence-artifact generation and upload.

Verification run: https://github.com/mozartg/mozart-os-succession/actions/runs/31102378882

Artifact inventory: https://api.github.com/repos/mozartg/mozart-os-succession/actions/runs/31102378882/artifacts

## What is not verified

This repository does **not** prove:

- equivalence to Fable, Claude, Opus, or any other model;
- a complete or production-ready operating system;
- that every doctrine rule improves outcomes;
- that the application specification has been implemented;
- that every skill works across current model or tool versions;
- deterministic results in real-world execution.

The latest prior repository validation failure reported a missing `services/receipt-monitor/index.mjs` file and an unmet minimum-size contract. That run remains part of the evidence history:

https://github.com/mozartg/mozart-os-succession/actions/runs/30755311718

## Current limitations

- The repository is primarily documentation, templates, and specifications.
- No root `AGENTS.md` currently grants operational authority.
- Claims in doctrine or handoff documents are proposals until tested and linked to receipts.
- The shared micro-test reports landing-page defects by default; strict enforcement is opt-in so existing repositories are not silently converted into false green or mass red states.

## Authority boundary

This README describes repository state. It does not authorize an LLM or agent to execute commands, alter systems, publish content, or treat aspirational language as runtime fact. Agent authority must be stated separately and explicitly.
