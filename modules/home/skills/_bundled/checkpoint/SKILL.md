---
name: checkpoint
description: >-
  Generate a structured handoff (checkpoint) of the current thread before
  context fills up or before starting a focused side-thread. Captures active
  goal, in-flight artifacts, decisions made, open questions, hard rules, and
  first moves on resume — enough state for a fresh-context session to pick up
  cleanly. Use when: (a) the user types `/checkpoint`; (b) the user asks to
  "save state", "checkpoint this", "hand off to a new thread", "wrap up before
  /clear"; (c) context is approaching ~60% AND the thread has non-trivial
  in-flight state across multiple files/PRs/decisions. Output is a markdown
  file the user can paste into a fresh session of their AI assistant
  (e.g., `claude "$(cat <file>)"` for Claude Code).
---

## What this skill does

Writes a structured markdown checkpoint to disk that captures the live state of
the current thread. The checkpoint is a complete handoff: a fresh-context
agent reading it should know what the thread was doing, what's already decided,
what's still open, and exactly what to do next.

This is **v0** — single checkpoint per invocation, manual/explicit user
trigger. It is not auto-fire (memory nudge handles that separately) and it is
not concern-splitting (that lives in v1 as `/fork`).

## When to invoke

| Trigger | Action |
|---------|--------|
| User types `/checkpoint` or `/checkpoint <slug>` | Generate immediately |
| User says "save state", "checkpoint this", "hand off", "before /clear" | Generate, confirm path with user |
| User about to spawn a long-running sub-agent likely to push context near cap | Suggest checkpoint first, ask before generating |
| Context ≥ ~60% AND thread has non-trivial in-flight state (multiple files modified, decisions in flux, open questions) | Suggest checkpoint, ask before generating |

If you would normally be tempted to summarize the thread for the user before a
`/clear`, write a checkpoint instead — the user can re-feed it.

## Where checkpoints live

```
~/.claude/checkpoints/<repo>/<slug>-<YYYY-MM-DD-HHMM>.md
```

- `<repo>` = basename of `git rev-parse --show-toplevel`. Fall back to
  basename of `pwd` if not in a git repo.
- `<slug>` = short kebab-case derived from the active goal of the thread.
  2-4 words. Examples: `checkpoint-skill-design`, `pr-review-batch`,
  `513-grpc-health`, `worktree-tooling`. If the user passed an argument
  (`/checkpoint my-slug`), use that verbatim.
- `<YYYY-MM-DD-HHMM>` = current local time. Avoids collisions within a day.

If the file path collides anyway (same minute, same slug), append `-2`, `-3`.

Storage is **untracked** (lives outside any repo). To preserve a checkpoint
long-term, copy it into `experimental/lupickup/ai/checkpoints/` in the repo
manually.

## Workflow

### Step 1 — Determine the slug

If the user provided one (`/checkpoint <slug>`), normalize to lowercase
kebab-case and use it.

Otherwise infer from the thread's active goal:
- Read the user's most recent goal-defining messages (last 5-10 turns)
- Pick 2-4 words that name the work
- Lowercase, kebab-case, no special characters

Examples:
- Thread about designing this skill → `checkpoint-skill-design`
- Thread reviewing PR #561 → `pr-561-review`
- Thread about the inference app philosophy doc → `inference-app-philosophy`

### Step 2 — Determine the path

```bash
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DATE=$(date +%Y-%m-%d-%H%M)
PATH="$HOME/.claude/checkpoints/$REPO/$SLUG-$DATE.md"
mkdir -p "$(dirname "$PATH")"
```

### Step 3 — Gather context for each section

Run these commands and read the output to fill in sections of the template:

```bash
git status --short                          # uncommitted changes
git log --oneline -20                       # recent commits
git branch --show-current                   # active branch
git worktree list                           # if relevant
gh pr list --author @me --state all --limit 10   # in-flight PRs (if internet/auth available)
```

For non-git context (decisions, open questions, hard rules), look at the
thread itself — recall what was discussed, decided, and surfaced as open.

### Step 4 — Write the checkpoint

Use the template below. Fill every section that applies; **omit sections that
don't apply** rather than leaving them empty. Concrete is better than complete:
two crisp open questions beats six vague ones.

### Step 5 — Print the result

After writing, echo to the user:

```
Checkpoint written:
  ~/.claude/checkpoints/<repo>/<slug>-<date>.md

To resume in a fresh session, paste the file contents into a new conversation
with your AI assistant. For Claude Code:
  claude "$(cat ~/.claude/checkpoints/<repo>/<slug>-<date>.md)"
```

Do **not** suggest `/clear` — that's the user's decision and timing.

## Checkpoint template

```markdown
# Checkpoint — <thread title>

**Date:** <YYYY-MM-DD HH:MM>
**Repo:** <repo name>
**Cwd:** <full path>
**Branch:** <current git branch, or "—" if detached/none>

## Active goal

<One paragraph. What is this thread trying to accomplish? Be specific —
"design and ship a /checkpoint skill" not "improve workflow tooling".>

## In-flight artifacts

| Type | Ref | State | Notes |
|------|-----|-------|-------|
| <PR/Branch/File/Issue/Worktree> | <number, path, or name> | <state> | <one-line note> |

Omit this table if there are no in-flight artifacts.

## Modified files (uncommitted)

- `path/to/file.ext` — what's been changed and why
- `path/to/other.ext` — pending; awaiting decision X

Omit if `git status` shows clean.

## Recent commits (newest first)

- `<SHA>` <message>
- `<SHA>` <message>

3-8 most recent. Omit if no commits in this thread.

## Decisions made / preferences in this thread

- <decision> — short why
- <decision> — short why

These are the locked-in choices the resumed agent should NOT relitigate.

## Open questions / pending discussion

1. <question> — context, what's already been ruled in/out
2. <question> — context

These are the explicit forks the resumed agent should pick up.

## Hard rules in effect

- <rule> — e.g., "no PRs without explicit user authorization"
- <rule> — e.g., "no remote writes from autonomous mode"

Carry over from CLAUDE.md and any rules the user established mid-thread.

## First moves on resume

1. <step>
2. <step>
3. <step>

Concrete. "Read this checkpoint top to bottom" → "Run `git status` to verify
the modified files list" → "Pick up Open Question 1 first because it blocks 2."

## Where things live

\`\`\`
<file/path layout for the artifacts in flight>
\`\`\`

Optional. Include when the thread has a non-trivial layout (worktrees, sibling
threads, output directories) the resumed agent needs to navigate.

## Cross-thread references

- Sibling thread X — see <path or description>
- Parent thread — <one-line summary, link to its checkpoint if any>

Omit if the thread is standalone.

---

*Generated by the `/checkpoint` skill. To resume in a fresh session, paste this*
*file into a new conversation with your AI assistant.*
```

## Style and content guidance

- **Be concrete.** "PR #561 needs splits per the plan in NEXT-STEPS.md" beats
  "PR #561 has some open work."
- **Lead with state, not narrative.** A checkpoint is a snapshot, not a
  story. Skip the recap of how you got here unless it's load-bearing.
- **Quote user language for hard rules.** If the user said "no destructive
  actions in autonomous mode without explicit auth," carry that exact phrase
  forward.
- **Open questions should be answerable.** Not "what do we do about X" but
  "should X use approach A or B? — A handles X, B handles Y; we ruled out C."
- **First moves on resume must be runnable.** A fresh-context agent should be
  able to execute step 1 without further clarification.

## Anti-patterns

- **Don't include the full thread transcript.** A checkpoint is not a backup;
  it's a handoff. If the resumed agent needs the full transcript, the
  checkpoint failed.
- **Don't paste large code blocks.** Reference file paths and line numbers
  instead. The resumed agent will read files itself.
- **Don't write Claude-specific invocations into the checkpoint body** (like
  "now use the /skill skill to do X"). The checkpoint format should stay
  harness-agnostic — Claude, Copilot, Codex, Pi should all be able to consume
  it. Workflow hints belong in the "First moves on resume" section as plain
  English steps, not slash-command names.
- **Don't fabricate decisions or rules** that weren't made in the thread. If
  uncertain whether something was decided, put it in Open Questions instead.
- **Don't checkpoint silently** when context is full and the user hasn't
  asked. Suggest first, write only with confirmation, unless the user
  explicitly invoked `/checkpoint`.

## Output

After writing, print exactly:

```
Checkpoint written:
  <full path>

To resume in a fresh session, paste the file contents into a new conversation
with your AI assistant. For Claude Code:
  claude "$(cat <full path>)"
```

Then stop. Do not summarize the checkpoint contents in chat — the user can
read the file. Do not offer follow-ups unless asked.
