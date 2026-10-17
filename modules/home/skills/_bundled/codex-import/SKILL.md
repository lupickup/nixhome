---
name: codex-import
description: >-
  Import OpenAI Codex threads into GitHub Copilot app sessions so the work can
  continue in Copilot with any model. Lists local Codex threads with
  `codex-export`, writes a Markdown transcript of each chosen thread, and starts
  a Copilot session in the matching project that reads the transcript and
  reports where things stand. Use when the user types `/codex-import`, or asks
  to import, move, migrate, continue, or resume Codex sessions or threads in
  Copilot.
---

# Import Codex threads into GitHub Copilot

Copilot can't load Codex history as native chat turns. Instead, each imported
thread becomes a new Copilot session that reads a transcript of the Codex
conversation and picks up from there. Codex data is only read, never changed.

Requires `codex-export` on `PATH` (nixhome:
`modules.home.dev.codex.exporter.enable = true`) and the GitHub Copilot app's
session tools (`list_projects`, `create_session`, `list_sessions_and_chats`).

## 1. Pick threads

If the user named threads (ids, titles, or a repository), use those. Otherwise
run:

```sh
codex-export list --limit 15
```

Add `--cwd <dir>` when the user means a specific repository and
`--search <text>` for a named topic. Show a short numbered list (title,
directory, last active, turns) and ask which threads to import with
`ask_user`. Skip threads whose `history` is `none` in `codex-export list
--json`; there is nothing to import.

## 2. Export each transcript

For each chosen thread:

```sh
codex-export show <id> --json
codex-export export <id> -o ~/.copilot/imports/codex/<id>.md
```

`show` provides the title, directory (`cwd`), branch, and last-active time used
below. The transcript is written with mode 0600 because it contains whatever
the user pasted into Codex; keep it local.

## 3. Choose where the session lives

Call `list_projects` and pick the project whose `main_repo_path` is the
thread's directory or contains it. When the directory still exists, compare
against `git -C <cwd> rev-parse --show-toplevel`.

- **Matching project:** create a project session with
  `workspace_type: "branch"`, so it continues in the checkout Codex used,
  including uncommitted changes.
- **Linked worktree** (for example under Codex's `worktrees/` directory): use
  the main repository's project with `workspace_type: "worktree"` and
  `base_branch` set to the branch checked out in that worktree.
- **Git repository without a project:** ask the user before calling
  `create_project` with the repository root.
- **Not a repository** (scratch or deleted directory): create a chat session
  with `session_kind: "chat"`.

## 4. Create the session

Call `create_session` with:

- `project_id` from step 3 (omit it for chat sessions).
- `name`: the Codex title in sentence case, at most 40 characters.
- `detached: true`, so the session is top-level in its project and outlives the
  importing session. Nest it under the current session only if the user asks.
- `kickoff.mode: "interactive"`. Set `kickoff.model` only when the user asks for
  a specific model.
- `kickoff.prompt` from this template:

```text
Continue the OpenAI Codex thread "<title>", imported into GitHub Copilot.

Transcript: <transcript path>
Codex thread <id> · last active <last active> · directory <cwd> · branch <branch>

1. Read the transcript's header and turn index, then the last two or three
   turns in full. Use the index's line numbers to read earlier turns only when
   needed; transcripts of long threads can exceed 1 MB.
2. Check the working tree read-only (git status, recent log) for changes made
   since the thread's last activity.
3. Reply with a brief status: the original goal, what got done, the current
   state, open items, and the suggested next step.

Don't edit files or run mutating commands until I say what to do next.
```

Drop the branch from the second line when the thread has none.

## 5. Report

Call `list_sessions_and_chats` and link each new session's name to its
`app_url`. Mention any threads you skipped and why.

Without the Copilot app session tools (for example in a terminal agent), stop
after step 2 and print the kickoff prompt so the user can paste it into a new
session.
