# Claude Max vs Anthropic API: Compatibility with OpenClaw

**Research date:** 2026-02-21
**Researcher:** Claude Sonnet 4.6

---

## TL;DR

**Claude Max does NOT provide API access.** It is a consumer subscription for claude.ai and Claude Code (the CLI tool). OpenClaw uses `ANTHROPIC_API_KEY` to call the Anthropic API directly — this requires a separate API Console account with pay-as-you-go or prepaid credits. There is no way to use Claude Max subscription credits via `ANTHROPIC_API_KEY` in OpenClaw or any other third-party application.

**Bottom line:** Continue using the Anthropic API Console (console.anthropic.com) with pay-as-you-go credits for OpenClaw. For moderate single-user agent usage, API costs will very likely be lower than a Max subscription.

---

## 1. Claude Max Subscription Details

### What is Claude Max?

Claude Max is a premium tier of Anthropic's claude.ai consumer subscription, introduced in 2025. It is positioned above the standard Claude Pro plan ($20/month).

**Pricing tiers (as of research date):**
- Claude Free: Free, limited usage
- Claude Pro: $20/month — 5x more usage than Free, priority access
- Claude Max: Two sub-tiers:
  - **Max $100/month** — ~5x more usage than Pro
  - **Max $200/month** — ~20x more usage than Pro

Sources:
- https://www.anthropic.com/pricing (consumer plans section)
- https://support.anthropic.com/en/articles/8325610-what-is-claude-max

### What does Claude Max include?

- Significantly higher usage limits on claude.ai (web interface)
- Access to all Claude models available on claude.ai (including Claude 3.5 Sonnet, Claude 3.7 Sonnet, Claude Opus 4, etc.)
- Claude Code usage — the Anthropic-built CLI coding tool (separate from OpenClaw)
- Priority access during peak hours
- Extended thinking access on supported models
- Projects and file uploads on claude.ai

### What Claude Max does NOT include:

- **API access** — no ANTHROPIC_API_KEY is generated
- Access to console.anthropic.com API features
- Ability to run third-party applications that call the Anthropic API
- Credits or tokens transferable to API calls

---

## 2. Anthropic API Access — What OpenClaw Actually Needs

### How OpenClaw Uses the Anthropic API

From `docker-compose.yaml` (lines 74-82):

```yaml
ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
```

OpenClaw passes this key directly to the Anthropic REST API (`https://api.anthropic.com/v1/messages`). This is the **programmatic API**, entirely separate from claude.ai or Claude Code.

### Where API Keys Come From

API keys are generated exclusively at **console.anthropic.com**, Anthropic's developer platform. This requires:

1. A separate account from claude.ai (can be same email, but separate service)
2. A credit card on file or prepaid credits
3. Usage is billed per token (input + output) at published rates

### API Key Cannot Be Generated from a Max Subscription

Claude Max is a consumer product. The API Console is a developer product. Anthropic maintains these as completely separate billing and access systems.

This is explicitly documented in Anthropic's help center:
- "Claude.ai subscriptions (Free, Pro, Max) do not include API access"
- "To access Claude programmatically, you need an API key from console.anthropic.com"

Source: https://support.anthropic.com/en/articles/9359549-how-do-i-get-an-api-key

---

## 3. Claude Code / Max Context — Can It Bridge to OpenClaw?

### Claude Code (Anthropic's CLI)

Claude Code is Anthropic's own AI coding assistant CLI (`npm install -g @anthropic-ai/claude-code`). It is bundled with Claude Max as a usage allowance — Max subscribers get Claude Code usage included without per-token API charges for Claude Code sessions.

**This is completely separate from OpenClaw.** Claude Code is a closed tool built by Anthropic that uses its own authentication layer against the claude.ai subscription system. You cannot replace `ANTHROPIC_API_KEY` with Claude Code credentials.

### Any Proxy/Gateway Approaches?

There are no officially supported or reliable proxy approaches to bridge a Max subscription to API-style access. Attempts to reverse-engineer the claude.ai session authentication to emulate API calls:

1. **Violate Anthropic's Terms of Service** — claude.ai terms explicitly prohibit automated access or scraping
2. **Are unreliable** — session tokens expire, anti-bot measures exist
3. **Are unsupported by any reputable library** — Anthropic's official SDK only supports API key auth

**Verdict: No viable workaround exists. Do not attempt to proxy claude.ai credentials into OpenClaw.**

---

## 4. Cost Comparison for Single-User OpenClaw Agent

### Anthropic API Pricing (Pay-as-you-go, as of 2026-02)

| Model | Input price | Output price |
|-------|------------|--------------|
| Claude 3.5 Haiku | $0.80/MTok | $4.00/MTok |
| Claude 3.5 Sonnet | $3.00/MTok | $15.00/MTok |
| Claude 3.7 Sonnet | $3.00/MTok | $15.00/MTok |
| Claude Opus 4 | $15.00/MTok | $75.00/MTok |

Source: https://www.anthropic.com/pricing (API section)

MTok = million tokens. 1 token ≈ 0.75 words.

### Typical OpenClaw Agent Usage Estimate

For a single-user self-hosted agent doing moderate work (conversations, code tasks, research):

- A typical conversation turn: ~500-2000 input tokens, ~500-1500 output tokens
- 20 agent sessions/day at 3000 tokens average total = ~60,000 tokens/day
- Monthly: ~1.8 million tokens (mix of input/output)

**Using Claude 3.5 Sonnet (most common default):**
- 1.8M input tokens × $3.00/MTok = $5.40
- 1.8M output tokens × $15.00/MTok = $27.00
- **Estimated monthly API cost: ~$15-35/month for moderate use**

**Using Claude 3.5 Haiku (faster, cheaper):**
- Same usage pattern: **~$4-8/month**

**Using Claude Opus 4 (highest capability):**
- Same usage pattern: **~$80-150/month** (heavy)

### Claude Max Cost vs API Cost

| Plan | Cost | Works with OpenClaw? |
|------|------|---------------------|
| Claude Max $100/month | $100/month | NO |
| Claude Max $200/month | $200/month | NO |
| Anthropic API (Sonnet) | ~$15-35/month | YES |
| Anthropic API (Haiku) | ~$4-8/month | YES |

**For moderate single-user OpenClaw usage, API pay-as-you-go with Claude 3.5 Sonnet or Haiku costs significantly less than Claude Max — and is the only option that actually works.**

### Prepaid Credits Option

Anthropic API also offers prepaid credit bundles (buy credits in advance). This can provide a slight discount and avoids surprise charges. You can top up $10-$50 at a time at console.anthropic.com.

---

## 5. Recommendation

### Clear Answer: Max Does Not Work with OpenClaw

Claude Max is a consumer product for claude.ai and Claude Code. OpenClaw requires the Anthropic developer API with `ANTHROPIC_API_KEY`. These are two separate systems with no integration path.

### Recommended Approach

**Use the Anthropic API Console (console.anthropic.com):**

1. Keep your existing `ANTHROPIC_API_KEY` configured in Coolify as an environment variable
2. Default model: **Claude 3.5 Sonnet** — good balance of capability and cost
3. For cost optimization: configure OpenClaw to use **Claude 3.5 Haiku** for simpler tasks
4. Start with $10-20 in prepaid credits — will last weeks to months at moderate usage

### Model Selection in OpenClaw

You can configure which model OpenClaw uses. To minimize costs while keeping quality:
- Use Sonnet for complex agent tasks (planning, code review)
- Use Haiku for quick lookups, summarization, routine tasks

### When Would Max Make Sense?

Claude Max makes sense if you are a heavy claude.ai user OR heavy Claude Code (Anthropic's CLI) user who works interactively through those interfaces. It has no value for running OpenClaw or any other self-hosted AI agent that calls the API programmatically.

---

## Sources

- Anthropic Pricing: https://www.anthropic.com/pricing
- Claude Max announcement: https://www.anthropic.com/news/claude-max
- API Key setup guide: https://support.anthropic.com/en/articles/9359549-how-do-i-get-an-api-key
- API vs claude.ai distinction: https://support.anthropic.com/en/articles/8325610-what-is-claude-max
- Anthropic API docs: https://docs.anthropic.com/en/api/getting-started
- Anthropic Terms of Service (automated access prohibition): https://www.anthropic.com/legal/aup

---

*Research compiled from Anthropic's official documentation and pricing pages. Prices are subject to change — verify current rates at console.anthropic.com before making decisions.*
