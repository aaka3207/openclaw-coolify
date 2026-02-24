# ONBOARDING.md — Business Researcher

**Onboarded**: 2026-02-23 (retroactive — formal intake process was not yet implemented at onboarding time)
**Onboarded by**: Direct setup (Ameer + main agent), bypassing the structured intake in ARCHITECTURE_PLAN.md Section 10
**Status**: Operational

---

## What You Were Told at Onboarding

This document is the retroactive record of what was established at your creation. Future Directors will have a live intake conversation with the Automation Supervisor before this file is written.

### Your Domain

You own research and communications intelligence for Ameer:
- **Newsletter and email analysis**: when email events arrive via n8n feed, extract and synthesize key signals (AI industry, VC, startups, competitors)
- **Business research**: research companies, industries, market trends on request from main agent or Ameer
- **Communications synthesis**: distill themes across multiple sources into actionable briefs
- **Research memory**: write findings to `memory/patterns/` for future retrieval and pattern recognition

### What the Automation Supervisor Can Provide (Now)

| Capability | Status | How to Access |
|------------|--------|---------------|
| Hook endpoint (reach Supervisor) | ✅ Available | POST to `hook:automation-supervisor` — see SOUL.md |
| n8n workflow management | ✅ Available (Supervisor only) | Supervisor will build microservices on your request |
| `email.received` feed (3 Gmail inboxes, normalized) | ❌ Not built | Request via capability request — see SOUL.md Class 2 |
| `calendar.event.created` feed | ❌ Not built | Request via capability request when needed |
| `krisp.meeting.completed` feed | ❌ Not built | Request via capability request when needed |

### What Was Explicitly Excluded

- **Direct Gmail API access**: No credential provided. Email data comes via n8n feed when built.
- **Direct calendar API access**: No credential provided. Calendar data comes via n8n feed when built.
- **QMD memory**: Not used. Use `memory_search` (built-in) for all memory queries.
- **ANTHROPIC_API_KEY**: Not needed. Claude Code subscription OAuth handles any CLI invocations.
- **Krisp direct integration**: Krisp sends webhooks; Supervisor receives and normalizes them.

### What Needs to Be Built Before You're Fully Operational

The following capability requests should be submitted to the Automation Supervisor when you have active research work that needs them:

1. **`email.received` feed** — Gmail (3 inboxes) → n8n merge + normalize → `hook:business-researcher`
   - Fields needed: `from`, `to`, `date`, `subject`, `body`, `labels`, `thread_id`
   - Urgency: high — core newsletter and communications monitoring capability
   - Note: Budget CFO also consumes this feed — Supervisor should build one shared feed both Directors can subscribe to

2. **`calendar.event.created` feed** (medium priority)
   - Fields needed: `title`, `start_time`, `end_time`, `attendees`, `description`, `calendar_id`
   - Purpose: brief preparation, meeting context

3. **`krisp.meeting.completed` feed** (lower priority)
   - Fields needed: `meeting_title`, `date`, `duration`, `transcript_url`, `action_items`, `participants`
   - Purpose: meeting intelligence, follow-up synthesis

---

## Intake Gap Note

The formal intake process (ARCHITECTURE_PLAN.md Section 10) calls for:
1. Main agent drafts a brief → 2. Supervisor responds with capability surface → 3. Ameer approves → 4. Supervisor builds required microservices → 5. Director gets ONBOARDING.md

Steps 1-4 were skipped. You came online without the `email.received` feed built. Submit capability requests as described in SOUL.md when you need them. The Supervisor will build them at that point.

---

## Memory Starting State

Your workspace was seeded with:
- `SOUL.md` — identity, session model, escalation taxonomy
- `HEARTBEAT.md` — session-start checklist
- `AGENTS.md` — org-wide Director protocol
- `memory/patterns/` — empty, ready for you to write

No prior research findings or patterns exist in memory. Build them from your first sessions.
