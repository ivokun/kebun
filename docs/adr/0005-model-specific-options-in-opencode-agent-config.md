# ADR-0005: Model-Specific Options in opencode Agent Config

## Status

Accepted

## Context

`home/opencode/opencode.json` had drifted from the working config in daily use
(`~/.config/opencode/opencode.json` on a non-NixOS machine, opencode 1.4.7). Three
distinct problems:

1. **An invalid field.** `build` carried `"thinking": {"type": "enabled"}`, which is not
   part of the `AgentConfig` schema.
2. **A silently inert knob.** Several agents set a bare top-level `reasoningEffort`.
   Unknown top-level agent keys are folded into the agent's `options` by
   `ConfigAgentV1.normalize` (`packages/core/src/v1/config/agent.ts`) and passed to the
   provider as model options — but `reasoningEffort` is meaningless on
   `kimi-for-coding/k3`, which talks to an Anthropic-compatible transport
   (`@ai-sdk/anthropic`). The setting validated fine and did nothing.
3. **Missing permissions.** Only `build`/`plan`/`oracle`/`explore` had explicit
   `permission` blocks; every other subagent fell back to defaults.

The correct per-model options are not guesswork; they are enumerated by
`variants()` in `packages/opencode/src/provider/transform.ts`:

- **kimi-for-coding/k3** (`@ai-sdk/anthropic`): adaptive thinking —
  `{thinking: {type: "adaptive", display: "summarized"}, effort}` with
  `effort ∈ low | medium | high | xhigh | max`.
- **opencode-go/deepseek-v4-flash** (`@ai-sdk/openai-compatible`): `reasoningEffort`
  with `low | medium | high | max` (the `max` tier is added specifically for
  `deepseek-v4*`).

## Decision

1. **The local working config is the porting source of truth.** Repo deviations kept
   deliberately: the GitHub MCP token stays as the `YOUR_GITHUB_PAT_HERE` placeholder
   (set manually post-rebuild, per the note in `home/features/opencode.nix`), and the
   `linear` MCP stays removed (dropped in `706a0ac`). The `obsidian` MCP and the
   `@whisperopencode/push` plugin were adopted from the local config.
2. **Model options live in `options`, once.** The redundant top-level
   `reasoningEffort` duplicates are deleted; each agent's model-specific options are set
   explicitly in its `options` object.
3. **Model assignments:**
   - k3 agents (`build`, `explore`, `librarian`, `code-reviewer`, `security-auditor`):
     `options = {thinking: {type: "adaptive", display: "summarized"}, effort: "max"}`.
   - Former GLM-5.2 agents (`plan`, `oracle`, `backend-architect`,
     `frontend-maintainer`, `bug-hunter`, `refactor-specialist`, `test-writer`,
     `docs-writer`, `performance-optimizer`, `ai-engineer`, `devops-engineer`): switched
     to `opencode-go/deepseek-v4-flash` with `options = {reasoningEffort: "max"}`.
   - `git-specialist` (k3) intentionally carries no effort options.
4. **Verification is part of the change.** The config must (a) validate against
   `https://opencode.ai/config.json`, and (b) resolve correctly under
   `XDG_CONFIG_HOME=<isolated> opencode debug config`, which confirms every agent,
   `{file:./prompts/...}` reference, MCP entry, and the merged `options` per agent.

## Consequences

### Positive

- **The effort settings actually take effect.** On k3 the previous `reasoningEffort`
  was accepted and ignored; the adaptive `thinking` + `effort` form is the one the
  Anthropic-compatible transport understands.
- **~10x cheaper subagent fleet.** DeepSeek V4 Flash is $0.14/$0.28 per Mtok
  (input/output) vs GLM-5.2's $1.40/$4.40 on Zen Go, at the same 1M context.
- **One canonical location per setting.** No more top-level/`options` duplication that
  could drift apart.
- **Repo and daily-driver configs are converged** except for the two deliberate
  deviations (token, linear), so future ports are diffs, not archaeology.

### Negative

- **Coupled to opencode internals.** The valid option shapes come from
  `transform.ts`, not a stable public API; a provider or transport change can silently
  invalidate them again. Mitigation: re-run the `opencode debug config` smoke test after
  any opencode bump, and re-check `variants()` when changing models.
- **Repetition.** JSON has no anchors, so the same `options` block is duplicated across
  five k3 agents and eleven DeepSeek agents; a global effort change is an 16-site edit.

### Neutral

- Prompt delivery is unchanged: inline strings for `build`/`plan`/`oracle`,
  `{file:./prompts/*.txt}` for the rest.
- `reasoningEffort: "max"` on DeepSeek and `effort: "max"` on k3 are both the highest
  tier their transports expose; they are not the same mechanism.

## References

- `packages/core/src/v1/config/agent.ts` (`ConfigAgentV1.normalize`) — unknown
  top-level keys are merged into `options`
- `packages/opencode/src/provider/transform.ts` (`variants()`) — per-transport option
  shapes for Kimi (adaptive thinking) and DeepSeek V4 (`reasoningEffort` incl. `max`)
- `packages/opencode/src/agent/agent.ts` — `item.options = mergeDeep(item.options,
  value.options ?? {})`
- [opencode agents docs — Additional](https://opencode.ai/docs/agents/#additional)
- `opencode models --verbose` — per-model capabilities, variants, and cost
- Commit `706a0ac` (linear removal), `home/features/opencode.nix` (token sanitization
  note)

## Notes

- Date proposed: 2026-08-03
- Date accepted: 2026-08-03
- Proposed by: ivokun
- Accepted by: ivokun
