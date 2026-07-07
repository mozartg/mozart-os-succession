---
name: lead-audit-bouncer
description: Pre-ship gate for lead lists and prospect targets. Run before any outreach batch leaves the shop floor.
---

# Lead-Audit Bouncer

Trigger: any lead list, scrape output, or prospect batch is about to be used for outreach.

## Method
1. Sample 10% of rows (min 5). Verify each: URL loads, business exists, contact field plausible.
2. Kill criteria (drop the row): dead site, no contact path, franchise/chain HQ, already a past contact, obviously AI-hallucinated entry.
3. Score fit 1-5 against the current wedge (audit/verification-install clients: has a live listing/site with visible flaws, owner-operated, reachable).
4. Reject the whole batch if >20% of the sample fails — the source is bad; re-scrape, don't patch.

## Quality checklist
- [ ] Sample verified with evidence (URLs pasted, not asserted)
- [ ] Every surviving row has a specific flaw worth auditing
- [ ] Batch size after cull noted vs. before

## Rerunnable prompt
"Act as the lead-audit bouncer. Here is a lead batch: [paste]. Sample-verify 10%, apply kill criteria, score fit for the 48-hr audit offer, and return the culled list plus a verdict: SHIP or RE-SCRAPE, with evidence."
