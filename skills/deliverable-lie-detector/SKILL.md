---
name: deliverable-lie-detector
description: Proof-before-done gate. Nothing sends, publishes, or lists until every claim in it is verified.
---

# Deliverable Lie-Detector

Trigger: MANDATORY before any last-mile action (send / publish / list / deliver).

## Method
1. Extract every factual claim in the deliverable (names, numbers, URLs, "this works", "ranked #x", "fixed").
2. For each claim, demand evidence: a command output, a loaded URL, a screenshot, a line citation. Mark CONFIRMED or UNVERIFIED.
3. Any UNVERIFIED claim: fix it or cut it. Never soften it into vagueness to dodge the check.
4. For code: run it. "It should work" is a lie until executed. Cite the run output.
5. Final stamp: "LIE-DETECTOR PASS: n claims, n confirmed, 0 unverified" — or it does not ship.

## Quality checklist
- [ ] Claims enumerated, not summarized
- [ ] Evidence is pasted/cited, not described
- [ ] Zero unverified claims at ship time

## Rerunnable prompt
"Run the deliverable lie-detector on this before I send it: [paste]. Enumerate claims, verify each with cited evidence, fix or cut failures, and give the pass/fail stamp."
