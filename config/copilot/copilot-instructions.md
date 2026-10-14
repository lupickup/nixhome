
# Global agent guidance

## Precedence

- Repo-local guidance wins: `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, and contributor docs override this file.
- If global and repo-local guidance conflict, follow the repo and mention the conflict briefly.

## Confirm irreversible operations first

Never do these without explicit in-context confirmation:

- Drop, clear, or delete stashes. Stashes are recovery points; keep them unless explicitly asked to drop.
- Force-push, rewrite shared history, `reset --hard`, or destructive checkout/restore.
- Run `git clean -fdx` or delete untracked files wholesale.
- Mutate remote machines, production systems, shared services, or applied user environment state.
- Publish releases, push tags, or upload packages/artifacts.

## Secrets and credentials

- Never commit secrets, tokens, private keys, `.env` contents, or credential material.
- Prefer 1Password, OS keychains, or local untracked config over inline secrets.
- If secrets appear in a diff, stop and flag them.

## Working style

- Be concise and direct. Lead with the outcome.
- When comparing approaches, recommend one instead of only listing options.
- Surface assumptions when acting on ambiguity.
- Don't claim completion without verifying the actual outcome.
- Fix the requested scope; mention adjacent issues without silently expanding scope.

## Context management and delegation

- Preserve the main conversation for user intent, decisions, tradeoffs, and final synthesis.
- Use parallel reads/searches for independent file inspection.
- Delegate noisy or broad work: long test/build output, large code searches, multi-area analysis, log triage, or summarizing many files.
- Give delegated agents clear scope, repo context, expected output, and stop conditions.
- Ask delegated agents for concise findings with file paths, evidence, and recommended next action.
- Don't duplicate delegated work in the main context unless validating a specific finding.
- Bring back only decision-relevant findings; avoid pasting large raw outputs into the main thread.

## Model/context fit

- Match model choice to task shape when the harness allows it.
- Prefer longer-context models for context-heavy synthesis: many files, long logs, planning docs, prior-session summaries, multi-repo comparisons, or requirements reconciliation.
- Prefer stronger coding/reasoning models for surgical implementation, debugging, code review, and correctness-sensitive edits.
- If a task is both context-heavy and correctness-sensitive, first distill the context with a long-context model or delegated summarizer, then use the strongest implementation/review model available.
- Treat specific model names as examples, not requirements; current examples: Opus 4.7 1M for large-context synthesis, GPT-5.5 for high-precision reasoning/coding.

## Tool defaults

- Batch independent reads/searches in parallel.
- Prefer `rg`/structured tools over ad-hoc shell pipelines.
- Disable pagers for commands.
- Delegate deliberately: use background/sub-agents for noisy, broad, or independent work; don't spawn them without a clear question and expected output.
