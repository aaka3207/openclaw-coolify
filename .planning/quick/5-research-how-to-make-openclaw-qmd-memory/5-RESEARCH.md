# QMD vs NOVA vs OpenClaw Built-in: Memory System Comparison

**Research date:** 2026-02-21
**Researcher:** Claude (quick task 5)
**Purpose:** Determine whether QMD is worth configuring given existing NOVA + built-in SQLite setup.

---

## 1. What QMD Is

**QMD** (`github.com/tobi/qmd`, npm: `@tobilu/qmd`) is an on-device **search engine** for markdown documents. It is NOT a memory extraction or entity graph system — it is purely a search/retrieval layer.

### Core capabilities
- **BM25 full-text search** (SQLite FTS5) — fast keyword matching
- **Vector semantic search** — embedding-based similarity via local GGUF models
- **Hybrid "query" mode** — BM25 + vector + query expansion + LLM re-ranking
- **Collection management** — index specific directories, add context descriptions
- **MCP server** — exposes search tools to any MCP-compatible client (including OpenClaw)
- **CLI-first** — works standalone via shell, no service required

### How it works
1. You point QMD at directories: `qmd collection add /data/openclaw-workspace --name workspace`
2. QMD indexes all markdown files into SQLite (`~/.cache/qmd/index.sqlite`)
3. Run `qmd embed` to generate vector embeddings via local model
4. Search: `qmd query "user preferences"` → BM25 + vector + reranking
5. Agent uses via MCP tool (`qmd_search`, `qmd_vector_search`, `qmd_query`) or CLI directly

### GGUF model requirements (auto-downloaded on first use)
| Model | Purpose | Size |
|-------|---------|------|
| `embeddinggemma-300M-Q8_0` | Vector embeddings | ~300MB |
| `qwen3-reranker-0.6b-q8_0` | Re-ranking | ~640MB |
| `qmd-query-expansion-1.7B-q4_k_m` | Query expansion | ~1.1GB |
| **Total** | | **~2GB** |

Models cached at `~/.cache/qmd/models/` (which would be `/data/.cache/qmd/models/` in our container given `XDG_CACHE_HOME=/data/.cache`).

### OpenClaw integration
Two options:
1. **CLI** — agent runs `qmd search "..."` as a shell command
2. **MCP server** — add QMD as an MCP server in openclaw.json:

```json
{
  "mcp": {
    "servers": {
      "qmd": {
        "command": "qmd",
        "args": ["mcp"]
      }
    }
  }
}
```

Or install as Claude plugin: `claude marketplace add tobi/qmd`

---

## 2. Live Deployment Status

**Finding: QMD is NOT installed in the current running container.**

Checks performed:
- The main OpenClaw gateway container (`ukwkggw4o8go0wgg804oc4oo`) is **not currently running** — only the sandbox hook container (`openclaw-sbx-agent-main-hook-ingress-1b2c37b7`) is up
- Volume `ukwkggw4o8go0wgg804oc4oo_openclaw-data` shows:
  - `/data/.bun/install/global/bin/` is **empty** — QMD not installed
  - `/data/.cache/` contains only `claude/` and `pip/` — no `qmd/` directory
  - `/data/.openclaw/openclaw.json` has no `mcp` section — QMD MCP not configured
- The current openclaw.json `lastTouchedVersion` is `2026.2.15`, meaning the container predates the `bun install -g https://github.com/tobi/qmd` line added to the Dockerfile

**In other words:** QMD was added to the Dockerfile but has never been deployed. The container that would have QMD installed hasn't been built and deployed yet. The next full redeploy (not just restart) will install QMD.

**No QMD collections or index exist** — even after the next deploy, QMD would need to be configured from scratch (collections added, `qmd embed` run, optionally MCP enabled).

---

## 3. Comparison Matrix

| Dimension | QMD | NOVA (PostgreSQL+pgvector) | OpenClaw Built-in SQLite |
|-----------|-----|---------------------------|--------------------------|
| **What it is** | Search engine over markdown files | Entity/episode extraction + semantic recall | Hybrid search over workspace markdown |
| **Search type** | BM25 + vector + LLM reranking | pgvector semantic search | 70% vector + 30% BM25 |
| **Data scope** | Any indexed markdown collections | Session transcripts → entities/relationships | Workspace markdown (MEMORY.md, daily notes, skills) |
| **Entity extraction** | No — search only | Yes — entities, relationships, episodes | No |
| **Relationship graph** | No | Yes (nova-relationships, 66 PG tables) | No |
| **Temporal recall** | Via file timestamps only | Yes — episodic timeline, "what happened when" | Limited |
| **Runs offline** | Yes (local GGUF models) | Yes (local PostgreSQL) | Yes (SQLite) |
| **MCP integration** | Yes — built-in MCP server with `qmd_search`, `qmd_query` tools | No — hook-based (not MCP) | No — built into OpenClaw directly |
| **Setup complexity** | Low to medium (install OK, but 2GB model download + collection config required) | High — PG, pgvector, hook scripts, cron | Zero — automatic |
| **Storage** | SQLite + ~2GB GGUF models in `/data/.cache/qmd/` | PostgreSQL (66 tables, separate service) | SQLite in `/data/.openclaw/memory/` |
| **Maintenance** | Periodic `qmd update` to re-index; model download once | Cron every 5 min, hook management, PG admin | Automatic (1.5s debounce on workspace changes) |
| **Indexes what** | Any configured directories (you choose) | Session conversation transcripts | Workspace markdown files (auto) |
| **Currently active** | No (not yet deployed) | Yes (deployed, catch-up cron running) | Yes (always active) |
| **Hook/event dependency** | None | Depends on `message:received` (blocked) — catch-up cron workaround | None |
| **RAM pressure on HDD server** | +640MB–1.1GB for GGUF models in memory during query | ~100MB for PG process | Minimal (SQLite) |

---

## 4. Key Questions Answered

### Does QMD replace NOVA's entity extraction?

**No.** QMD is a search engine — it finds documents. NOVA extracts structured entities (people, projects, facts, relationships) from conversations and stores them in a graph. These are fundamentally different operations:
- QMD: "find markdown files containing information about X"
- NOVA: "what do I know about person/project X based on all past conversations?"

QMD cannot replace NOVA's episodic memory or relationship graph.

### Does QMD replace OpenClaw's built-in SQLite search?

**Potentially yes — QMD is strictly more powerful for document search.** OpenClaw's built-in search does 70/30 vector+BM25 over workspace markdown. QMD does the same plus LLM query expansion and re-ranking, and can index directories beyond the workspace (e.g., project repos, docs outside `.openclaw/workspace`).

However, OpenClaw's built-in search requires zero setup and integrates automatically. QMD requires collection setup, a 2GB model download, and MCP configuration.

### Can QMD and NOVA coexist?

**Yes — they operate at different layers:**
- QMD: document retrieval layer (search markdown)
- NOVA: episodic memory layer (extract + store entities)
- OpenClaw built-in: baseline search (automatic, zero-config)

All three can run simultaneously without conflict.

### Is QMD worth configuring given we already have built-in search + NOVA?

**Marginally, with caveats.** The honest analysis:

**Case FOR QMD:**
- LLM re-ranking genuinely improves retrieval quality for ambiguous queries
- Can index directories outside the workspace (e.g., code repos, external docs)
- MCP integration gives agent a clean, structured search interface
- Supports query expansion — the agent asks "how to deploy" and QMD also tries "deployment process", "release procedure", etc.

**Case AGAINST QMD (given our specific situation):**
- OpenClaw's built-in search already covers the workspace markdown adequately
- NOVA already provides semantic entity recall for the main chat
- 2GB of GGUF models adds significant RAM pressure on an HDD server (already slow)
- The first `qmd embed` run will be slow on HDD (scanning all markdown, generating embeddings)
- Model download (2GB) on first use will stall the container startup if not pre-cached
- QMD indexes only markdown files — it cannot search NOVA's PostgreSQL entities
- If the main gateway container isn't reliably running (as seen today), QMD provides no value
- Zero active collections configured → would need manual setup after every fresh deploy

### What's the effort to get QMD working?

After the next redeploy (which installs QMD via the current Dockerfile):
1. Add workspace collection: `qmd collection add /data/openclaw-workspace --name workspace`
2. (Optional) Add daily notes: already covered by workspace
3. Run initial embed: `qmd embed` — slow on HDD, may take 10–30 min depending on content volume
4. Add to openclaw.json `mcp.servers.qmd`
5. Configure in bootstrap.sh to run collection setup on first boot

This is 1–2 hours of work and ongoing maintenance (qmd update on redeploy).

---

## 5. Recommendation

**Skip QMD for now. Revisit only if search quality becomes a pain point.**

**Reasoning:**

The three memory systems in priority order for our deployment:

1. **OpenClaw built-in SQLite (keep, zero effort)** — Automatically indexes workspace markdown. Works for the primary recall use case. Zero configuration.

2. **NOVA PostgreSQL (keep, already deployed)** — The only system doing entity extraction and relationship graphing. Critical for "remember that I prefer X" type queries. Catch-up cron workaround is functional.

3. **QMD (skip for now)** — Marginal improvement over built-in search. The 2GB model download + HDD performance penalty + manual collection setup + RAM pressure is not worth the improvement over what built-in search already provides. The agent rarely hits search quality limits with the current setup.

**If you do want better search quality in the future**, the right intervention is not QMD but fixing the `message:received` hook so NOVA has real-time extraction (rather than 5-minute cron delays). That gives much more value than QMD's re-ranking.

**The one scenario where QMD would be worth it:** If you want the agent to search large external document collections (e.g., entire code repos, PDF/markdown knowledge bases) that live outside the workspace. In that case, QMD's collection management and MCP interface are purpose-built for this and would provide genuine lift.

---

## 6. If You Decide to Configure QMD Later

When the Dockerfile change is deployed (next full redeploy), QMD binary will be at `/data/.bun/install/global/bin/qmd`. To activate:

```bash
# 1. Add workspace as collection
qmd collection add /data/openclaw-workspace --name workspace
qmd context add qmd://workspace "OpenClaw agent workspace: memory, daily logs, skills"

# 2. Generate embeddings (slow on first run)
qmd embed

# 3. Test search
qmd query "user preferences"

# 4. Add to openclaw.json via bootstrap.sh jq patch:
# .mcp.servers.qmd = {"command": "qmd", "args": ["mcp"]}

# 5. For HTTP mode (avoids reload on each request):
# qmd mcp --http --daemon  (in bootstrap.sh after embed)
```

**Storage:** All model files (~2GB) go to `/data/.cache/qmd/models/` — persistent across restarts. Index goes to `/data/.cache/qmd/index.sqlite`. Both on the persistent volume.

**Note:** The `XDG_CACHE_HOME=/data/.cache` env is already set in the Dockerfile (line 46), so QMD will correctly use the persistent volume for its cache/models.

---

## 7. Summary Table: Decision Matrix

| Option | Effort | Value | Verdict |
|--------|--------|-------|---------|
| Keep NOVA as-is | None | High (entity extraction, semantic recall) | **Do this** |
| Keep built-in SQLite | None | Medium (workspace search, automatic) | **Do this** |
| Configure QMD for workspace search | 1–2 hrs + 2GB download | Low marginal (overlaps built-in) | **Skip** |
| Configure QMD for external docs | 1–2 hrs + 2GB download | Medium (if you have external corpora) | **Maybe later** |
| Fix `message:received` hook | Unknown (OpenClaw upstream) | High (real-time NOVA extraction) | **Worth tracking** |
