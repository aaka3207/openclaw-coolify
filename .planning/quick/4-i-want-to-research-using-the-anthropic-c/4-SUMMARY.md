---
phase: quick-4
plan: "01"
subsystem: research
tags: [anthropic, claude-max, api, cost-analysis, openclaw]
dependency_graph:
  requires: []
  provides: ["research/claude-max-api-compatibility"]
  affects: ["ANTHROPIC_API_KEY configuration in OpenClaw"]
tech_stack:
  added: []
  patterns: []
key_files:
  created:
    - .planning/quick/4-i-want-to-research-using-the-anthropic-c/RESEARCH.md
  modified: []
decisions:
  - "Claude Max is NOT compatible with OpenClaw — it provides no API key"
  - "Continue using Anthropic API Console pay-as-you-go for ANTHROPIC_API_KEY"
  - "Recommended models: Claude 3.5 Sonnet (quality) or Haiku (cost) for agent tasks"
metrics:
  duration: "~8 min"
  completed: "2026-02-21"
  tasks_completed: 1
  files_created: 1
---

# Phase quick-4 Plan 01: Claude Max vs Anthropic API Research Summary

## One-liner

Claude Max is a claude.ai consumer subscription with no API access — OpenClaw requires Anthropic API Console pay-as-you-go credits via ANTHROPIC_API_KEY, costing ~$15-35/month for moderate use vs $100-200/month for Max.

## What Was Done

**Task 1: Research Claude Max subscription and API access compatibility**

Researched Anthropic's subscription tiers, API access model, and pricing to answer whether Claude Max can power OpenClaw. Produced a comprehensive research document at `RESEARCH.md`.

## Key Findings

1. **Claude Max = NO API access.** It covers claude.ai web interface + Claude Code (Anthropic's own CLI). No ANTHROPIC_API_KEY is generated.

2. **OpenClaw needs the Anthropic API**, which is a completely separate product managed at console.anthropic.com with per-token billing.

3. **No workarounds exist** — proxying claude.ai sessions violates Anthropic's Terms of Service and is unreliable.

4. **Cost comparison for single-user OpenClaw agent:**
   - Claude Max: $100-200/month (no API access)
   - API pay-as-you-go (Sonnet): ~$15-35/month
   - API pay-as-you-go (Haiku): ~$4-8/month

5. **Recommendation:** Use existing ANTHROPIC_API_KEY from console.anthropic.com with Claude 3.5 Sonnet or Haiku for cost-effective agent operation.

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | `a167a44` | RESEARCH.md: Claude Max vs API compatibility research |

## Self-Check: PASSED

- [x] RESEARCH.md created at expected path
- [x] All 5 research sections present (Max details, API compatibility, Claude Code bridge, cost comparison, recommendation)
- [x] TL;DR section at top
- [x] Actionable recommendation at bottom
- [x] Sources/links included
- [x] Commit `a167a44` exists in git history
