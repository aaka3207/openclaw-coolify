---
phase: quick-10
plan: 01
subsystem: bootstrap/memory
tags: [audit, gap-analysis, bootstrap, memory, agents]
dependency_graph:
  requires: [quick-9, 06-02-PLAN.md]
  provides: [gap-analysis-report]
  affects: [06-02 execution readiness]
tech_stack:
  added: []
  patterns: []
key_files:
  created: [.planning/quick/10-did-we-follow-the-plan-on-file-path-fixe/10-SUMMARY.md]
  modified: []
decisions: []
metrics:
  duration: ~5 min
  completed: 2026-02-22
  tasks_completed: 1
  tasks_total: 1
---

# Quick Task 10 — Audit: Did We Follow the File Path Fix Plans?

**Purpose**: Compare planned fixes from 06-02-PLAN.md and quick-9-PLAN.md against what was actually implemented in bootstrap.sh and the repo.

**Verdict**: Quick-9 fixes are fully implemented. 06-02 planned items are NOT implemented.

---

## Audit Results

### From quick-9-PLAN.md

#### Item 1: Workspace Symlink — IMPLEMENTED

**Plan**: Add `ln -s /data/openclaw-workspace /data/.openclaw/workspace` block after `mkdir -p` in bootstrap.sh.

**Evidence** (bootstrap.sh lines 28-34):
```bash
# Fix: OpenClaw resolves ~/.openclaw/workspace → /data/.openclaw/workspace (via root symlink)
# but config workspace is /data/openclaw-workspace — unify them
if [ ! -L "$OPENCLAW_STATE/workspace" ]; then
  rm -rf "$OPENCLAW_STATE/workspace"
  ln -s "$WORKSPACE_DIR" "$OPENCLAW_STATE/workspace"
  echo "[fix] Symlinked .openclaw/workspace → $WORKSPACE_DIR"
fi
```

**Status**: Fully implemented. Committed in `c35dbe2`.

---

#### Item 2: Sub-agent Announce-back (`dangerouslyDisableDeviceAuth`) — SUPERSEDED

**Plan**: Add `gateway.dangerouslyDisableDeviceAuth = true` patch to bootstrap.sh.

**What quick-9 did**: Added the patch in `c35dbe2`.

**What happened next**: Commits `d4b2c0d` and `0d1583c` REMOVED this key because it is NOT a valid gateway key in OpenClaw 2026.2.19+ — its presence crashes the gateway with "Unrecognized key".

**Current bootstrap.sh state** (lines 16-22 and 334-336): Actively DELETES the key from config if present:
```bash
# gateway.dangerouslyDisableDeviceAuth is NOT a valid key in 2026.2.19+ — crashes gateway
if jq -e '.gateway.dangerouslyDisableDeviceAuth != null' "$CONFIG_FILE" &>/dev/null; then
  jq 'del(.gateway.dangerouslyDisableDeviceAuth)' "$CONFIG_FILE" > ...
  echo "[config] Removed invalid gateway.dangerouslyDisableDeviceAuth key"
fi
```

**Alternative fix in place**: Sub-agent announce-back is handled instead via:
- `gateway.mode = "remote"` + `gateway.remote.url = "ws://127.0.0.1:18789"` (loopback bypass)
- `gateway.remote.token` (auth for mode=remote)
- `commands.useAccessGroups = false` (scope fix)
- `--allow-unconfigured` flag on exec line

**Status**: Plan superseded — `dangerouslyDisableDeviceAuth` was invalid and removed. Equivalent fix achieved via mode=remote loopback approach from quick-8.

---

#### Item 3: QMD Path Unification — IMPLEMENTED (via Item 1)

**Plan**: Symlink unifies `/data/.openclaw/workspace/memory/` and `/data/openclaw-workspace/memory/`.

**Evidence**: Symlink from Item 1 directly achieves this. Both paths now resolve to the same directory.

**Status**: Fully implemented as a side-effect of the workspace symlink.

---

### From 06-02-PLAN.md

#### Item 4: AGENTS.md Added to seed_agent Loop — MISSING

**Plan**: Change `for doc in SOUL.md BOOTSTRAP.md; do` to `for doc in SOUL.md BOOTSTRAP.md AGENTS.md; do`.

**Evidence** (bootstrap.sh line 76):
```bash
for doc in SOUL.md BOOTSTRAP.md; do
```

AGENTS.md is NOT in this loop. `grep -n "AGENTS.md" scripts/bootstrap.sh` returns no results.

**Status**: NOT IMPLEMENTED. AGENTS.md will not be seeded to workspace on deploy.

---

#### Item 5: memory/patterns/ Seeding Block — MISSING

**Plan**: Add a block after the SOUL/BOOTSTRAP/AGENTS loop to:
```bash
if [ -d "/app/memory/patterns" ]; then
  mkdir -p "$dir/memory/patterns"
  for pattern in /app/memory/patterns/*.md; do
    ...
  done
fi
```

**Evidence**: `grep -n "memory/patterns" scripts/bootstrap.sh` returns no results.

**Status**: NOT IMPLEMENTED. No pattern file seeding exists in bootstrap.sh.

---

#### Item 6: AGENTS.md File Exists in Repo Root — EXISTS BUT UNTRACKED

**Plan**: Create `AGENTS.md` in repo root with memory discipline protocol.

**Evidence**:
```
$ test -f AGENTS.md && echo EXISTS
EXISTS
$ git status AGENTS.md
Untracked files: AGENTS.md
$ wc -l AGENTS.md
64 AGENTS.md
```

**Content check**: File contains `memory_search` instruction (passes 06-02 must_have check). File has 64 lines with the correct memory discipline protocol format.

**However**: File is UNTRACKED — it was never committed to git. It will NOT be included in the Docker image build and will NOT be available at `/app/AGENTS.md` for bootstrap.sh to seed.

**Status**: PARTIAL — file exists locally but is not committed. Cannot be seeded to workspace until committed.

---

#### Item 7: memory/patterns/ Directory with Seed Files — MISSING

**Plan**: Create `memory/patterns/preferences.md`, `memory/patterns/sandbox-creation.md`, `memory/patterns/n8n-workflows.md`.

**Evidence**:
```
$ ls memory/patterns/ 2>/dev/null || echo "DIR MISSING"
DIR MISSING
$ ls memory/ 2>/dev/null || echo "memory/ dir missing"
memory/ dir missing
```

**Status**: NOT IMPLEMENTED. Neither the `memory/` directory nor any seed files exist in the repo.

---

## Bonus Items Implemented (Not in Original Plans)

These were implemented beyond the original plans, primarily from quick-8 onwards:

| Item | Commit | Description |
|------|--------|-------------|
| `hash -r` before exec | `c35dbe2` | Prevents stale PATH hash table on restart |
| Config lock/unlock pattern | Various | chmod 644 before patches, chmod 444 after |
| Early `dangerouslyDisableDeviceAuth` cleanup | `0d1583c` | Runs before all other patches to prevent crash |
| `gateway.mode = "remote"` patch | `8d7f5e0` | TEMP: activates loopback for sub-agents |
| `gateway.remote.token` patch | `8d7f5e0` | TEMP: auth for mode=remote |
| `commands.useAccessGroups = false` | `83491f3` | Sub-agent scope access fix |
| `--allow-unconfigured` exec flag | `8d7f5e0` | TEMP: required for mode=remote without full config |
| `gateway.dangerouslyDisableDeviceAuth` del | `d4b2c0d` | Active deletion of invalid key |
| `del(.commands.gateway)` etc | Various | Remove invalid commands keys agent might add |

---

## Gap Analysis Summary

| # | Planned Fix | Status | Action Required |
|---|-------------|--------|-----------------|
| 1 | Workspace symlink | IMPLEMENTED | None |
| 2 | dangerouslyDisableDeviceAuth | SUPERSEDED | None — replaced by better fix |
| 3 | QMD path unification | IMPLEMENTED | None |
| 4 | AGENTS.md in seed_agent loop | MISSING | Add to for loop in bootstrap.sh |
| 5 | memory/patterns/ seeding block | MISSING | Add block to bootstrap.sh after seed loop |
| 6 | AGENTS.md file in repo | PARTIAL | Commit AGENTS.md to git (already exists locally) |
| 7 | memory/patterns/ seed files | MISSING | Create directory and 3 seed files |

---

## What 06-02 Still Needs to Do

The 06-02-PLAN.md tasks are almost entirely NOT done. To execute 06-02, the plan must:

1. **Commit AGENTS.md** — file exists at repo root but is untracked. `git add AGENTS.md && git commit`
2. **Create memory/patterns/** — directory and 3 seed files (preferences.md, sandbox-creation.md, n8n-workflows.md) need to be created
3. **Update bootstrap.sh seed_agent loop** — add `AGENTS.md` to `for doc in SOUL.md BOOTSTRAP.md; do`
4. **Add memory/patterns/ seeding block** — add mkdir + cp loop to bootstrap.sh after seed loop
5. **Deploy and verify** — push commit, wait for Coolify deploy, SSH verify files in workspace

Task 3 (memory_search end-to-end verify) from 06-02-PLAN.md may already be partially satisfied since the memorySearch config is in place from 06-01.

---

## Self-Check: PASSED

- Audit covers all 7 planned items from both source plans
- Each status is backed by grep/ls/git evidence from actual codebase
- Gap analysis identifies exactly what 06-02 needs to do
- No guessing — all statuses verified against bootstrap.sh and filesystem
