---
phase: quick-5
plan: 01
subsystem: memory
tags: [qmd, nova, memory, search, research]
dependency_graph:
  requires: []
  provides: [qmd-vs-nova-decision]
  affects: [phase-6-agent-orchestration]
tech_stack:
  added: []
  patterns: []
key_files:
  created:
    - .planning/quick/5-research-how-to-make-openclaw-qmd-memory/5-RESEARCH.md
  modified: []
decisions:
  - skip-qmd-for-now
metrics:
  duration: ~25 min
  completed: 2026-02-21
---

# Quick Task 5: QMD Memory Research Summary

**One-liner:** QMD is a document search engine (BM25 + vector + LLM reranking), not an entity extractor — skip it for now, OpenClaw's built-in SQLite search already covers the same ground without 2GB model overhead.

---

## What Was Researched

- QMD (`github.com/tobi/qmd`, v1.0.8) capabilities via GitHub README and CHANGELOG
- Live deployment status: checked Docker volumes for QMD install state
- Three-way comparison: QMD vs NOVA (PostgreSQL+pgvector) vs OpenClaw built-in SQLite

---

## Key Findings

1. **QMD is not installed in the live deployment.** The `bun install -g https://github.com/tobi/qmd` line exists in the Dockerfile but the current running container predates that change. The main OpenClaw gateway container was not running at research time (only sandbox hook container was up). No QMD binary, no cache directory, no MCP config exists on the data volume.

2. **QMD is a search engine, not a memory system.** It indexes markdown files and provides BM25 + vector + LLM re-ranking search. It does NOT extract entities, relationships, or episodes from conversations. It cannot replace NOVA's episodic memory or the relationship graph.

3. **QMD overlaps significantly with OpenClaw's built-in SQLite search.** OpenClaw already does 70/30 vector+BM25 over workspace markdown automatically with zero config. QMD adds LLM re-ranking and query expansion on top, but indexes the same files. The marginal improvement does not justify 2GB of GGUF model downloads + HDD performance pressure.

4. **Resource cost is non-trivial on this server.** Three GGUF models total ~2GB (embedding: 300MB, reranker: 640MB, query-expansion: 1.1GB). On an HDD server that already has chown-stall issues and slow npm installs, first-boot model download would be a significant problem without pre-caching.

5. **NOVA remains the only system doing entity extraction.** The right investment for memory quality is fixing real-time NOVA extraction (the `message:received` hook blocker), not adding a search layer that duplicates what's already there.

---

## Recommendation

**Skip QMD. Keep NOVA + built-in SQLite as-is.**

The two-layer memory architecture (built-in SQLite for workspace search, NOVA for episodic entity extraction) already covers all key recall patterns. QMD would add a third layer with marginal search quality improvement at significant resource cost.

**Revisit QMD only if:** you want the agent to search large external document collections (code repos, knowledge bases) that live outside the OpenClaw workspace — QMD's collection management is purpose-built for this use case.

---

## Follow-Up Actions

- None required (decision: skip QMD)
- Optional future: if external doc search becomes a need, QMD collections + HTTP MCP daemon would be the approach
- Phase 6 execution remains the priority (task router, sub-agent memory isolation, NOVA filter)

---

## Deviations from Plan

None — plan executed exactly as written.

---

## Self-Check: PASSED

- `5-RESEARCH.md` exists with QMD feature summary, live deployment check, comparison matrix, and recommendation
- Task 1 committed: `fc2c3a9`
