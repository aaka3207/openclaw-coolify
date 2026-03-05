---
summary: "Ideal Customer Profile for lead screening"
read_when:
  - Screening leads from email newsletters
  - Classifying whether a company is a qualified prospect
---

# Lead Screening ICP

This document defines the Ideal Customer Profile (ICP) for outbound targeting. Use it when classifying leads from newsletters, job boards, LinkedIn, and other sources.

## Primary ICP: Series A / Series B Engineering-Led SaaS

**Company stage:** Seed (post-revenue) to Series B
**Headcount:** 15-150 employees
**Industry:** B2B SaaS, developer tools, AI/ML infrastructure, data platforms
**Business model:** Product-led growth (PLG) or sales-assisted PLG

## Strong Fit Signals

- Engineering team of 5-30 actively hiring (signals scaling pressure)
- CTO, VP Engineering, or Head of Engineering actively posting or hiring
- Pain signals in job descriptions: "scaling," "technical debt," "platform reliability," "developer experience"
- PLG motion evident: self-serve signup, usage-based pricing, or developer community
- Recently raised (Series A in last 12 months) — budget exists, growth pressure exists
- Building on modern stack (Next.js, TypeScript, Postgres, Supabase, Vercel, AWS)

## Weak Fit Signals (Deprioritize)

- Enterprise-only GTM with no self-serve component
- Non-technical founders with no in-house engineering
- Consulting/agency model (not a product company)
- Pre-revenue or pre-product (too early)
- Series C+ with 500+ employees (too big, long sales cycle)
- Government, healthcare, finance with heavy compliance requirements (slow)

## Disqualify If

- Competitor in the AI agent orchestration space
- Direct outreach already in progress (deduplicate against `leads/active.md`)
- Domain is obvious spam or lead gen farm

## Scoring Guide

When classifying a lead, output a score 1-5:

| Score | Meaning |
|-------|---------|
| 5 | Perfect fit — all strong signals, no weak signals |
| 4 | Good fit — most strong signals present |
| 3 | Possible fit — mixed signals, worth a second look |
| 2 | Weak fit — mostly weak signals |
| 1 | Disqualify — fails ICP or meets disqualify criteria |

Write qualified leads (score >= 3) to `leads/today.jsonl` using this format:
```json
{"company": "...", "url": "...", "signal": "...", "score": 4, "date": "YYYY-MM-DD"}
```

Review `leads/today.jsonl` at end of day. Anything score 4-5 gets surfaced to Ameer.
