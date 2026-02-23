---
phase: quick-13
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/restore-config.sh
autonomous: false
must_haves:
  truths:
    - "openclaw.json is regenerated with full Phase 8 config"
    - "Gateway starts and responds to requests"
    - "memorySearch, subagents, hooks, cron, tailscale all configured"
  artifacts:
    - path: "scripts/restore-config.sh"
      provides: "One-shot config restoration script for server execution"
  key_links:
    - from: "scripts/restore-config.sh"
      to: "scripts/bootstrap.sh"
      via: "Deletes corrupted config so bootstrap.sh regenerates on restart"
      pattern: "rm.*openclaw.json"
---

<objective>
Restore openclaw.json to full Phase 8 working state after corruption.

Purpose: The config was emptied/corrupted during a debugging session. `openclaw doctor` shows gateway.mode unset, session dirs missing, no embedding provider. The fix leverages bootstrap.sh's existing regeneration logic.

Output: A server-side script that deletes the corrupted config and restarts the container, letting bootstrap.sh regenerate everything from scratch with all jq patches applied.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@scripts/bootstrap.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create restore-config.sh server script</name>
  <files>scripts/restore-config.sh</files>
  <action>
Create a bash script `scripts/restore-config.sh` that the user runs on the server (192.168.1.100) via SSH. The script must:

1. Require sudo (check at start, exit if not root)
2. Define the volume config path: `/var/lib/docker/volumes/ukwkggw4o8go0wgg804oc4oo_openclaw-data/_data/.openclaw/openclaw.json`
3. Back up the corrupted config to `openclaw.json.corrupted.bak` (if it exists and is non-empty)
4. DELETE the config file entirely (`rm -f`). This is the key action -- bootstrap.sh line 211 checks `[ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]` and regenerates from the full template when the file is missing.
5. Print what will happen: "Config deleted. On next container start, bootstrap.sh will regenerate the full Phase 8 config including: gateway (loopback+tailscale), memorySearch (gemini), subagents (haiku), hooks, cron, automation-supervisor, model aliases, COMPANY_MEMORY.md extraPaths, and all jq patches."
6. Find the openclaw container: `docker ps --filter "name=openclaw-ukwkggw4o8go0wgg804oc4oo" --format '{{.Names}}' | head -1`
7. If container found, restart it with `docker restart <container>` and tail logs for 30 seconds to confirm startup: `timeout 30 docker logs -f --since 1s <container> 2>&1 | head -80`
8. If no container found, print instructions to redeploy from Coolify

The script should be defensive (set -e), print each step clearly, and confirm the config was deleted before restarting.

Do NOT attempt to write a config file manually -- bootstrap.sh already has the complete template (lines 216-301) plus 50+ jq patches (lines 304-553) that bring it to Phase 8 state. Deleting and letting it regenerate is the correct approach.
  </action>
  <verify>
    - `bash -n scripts/restore-config.sh` passes (syntax check)
    - Script contains `rm -f` of the config path
    - Script contains `docker restart` logic
    - Script does NOT contain any `jq` or manual JSON writing (bootstrap.sh handles that)
  </verify>
  <done>Script exists, is syntactically valid, and implements delete-and-restart strategy</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 2: Verify config restoration on server</name>
  <files>scripts/restore-config.sh</files>
  <action>User runs the restore script on the server and verifies gateway comes up healthy.</action>
  <verify>Gateway responds and openclaw doctor passes</verify>
  <done>Gateway running with full Phase 8 config</done>
  <what-built>restore-config.sh script that deletes corrupted openclaw.json and restarts the container so bootstrap.sh regenerates the full Phase 8 config</what-built>
  <how-to-verify>
    1. Copy script to server: `scp scripts/restore-config.sh ameer@192.168.1.100:/home/ameer/`
    2. SSH to server: `sshpass -p '@pack86N5891' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ameer@192.168.1.100`
    3. Run: `sudo bash /home/ameer/restore-config.sh`
    4. Watch logs for "[config]" lines showing each patch applied
    5. Verify gateway starts: look for "OpenClaw is ready!" in output
    6. Test gateway: `curl -s http://192.168.1.100:18789/health` or access Control UI
    7. Run `openclaw doctor` inside container to confirm all checks pass
  </how-to-verify>
  <resume-signal>Type "approved" if gateway is running with full config, or describe issues</resume-signal>
</task>

</tasks>

<verification>
- Script deletes corrupted config and lets bootstrap.sh regenerate
- Gateway starts successfully after restart
- `openclaw doctor` shows gateway.mode set, session dirs present, embedding provider configured
</verification>

<success_criteria>
- openclaw.json restored to Phase 8 state with all patches applied
- Gateway accessible at http://192.168.1.100:18789
- memorySearch, subagents, hooks, cron, tailscale all properly configured
</success_criteria>

<output>
After completion, create `.planning/quick/13-restore-openclaw-config-to-phase-8-state/13-SUMMARY.md`
</output>
