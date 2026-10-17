"""Exercise codex-export against a synthetic Codex home."""

import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/codex-export"

PARENT = "01a00000-0000-7000-8000-000000000001"
CHILD = "01a00000-0000-7000-8000-000000000002"
ARCHIVED = "01a00000-0000-7000-8000-000000000003"
ROLLOUT = "01a00000-0000-7000-8000-000000000004"
LEGACY = "01a00000-0000-7000-8000-000000000005"
EMPTY = "01a00000-0000-7000-8000-000000000006"
OTHER = "01b00000-0000-7000-8000-000000000007"

THREADS_SCHEMA = """
create table threads (
    id text primary key, rollout_path text not null default '',
    created_at integer not null, updated_at integer not null,
    source text not null, cwd text not null, title text not null default '',
    archived integer not null default 0, git_branch text, git_sha text,
    git_origin_url text, model text, reasoning_effort text,
    first_user_message text not null default '', name text, thread_source text,
    agent_nickname text, agent_path text)
"""


def user(text):
    return {"type": "userMessage", "content": [{"type": "text", "text": text}]}


def agent(text, phase=None):
    return {"type": "agentMessage", "text": text, "phase": phase}


class CodexExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(os.path.realpath(self.temporary.name))
        self.home = self.root / "codex"
        self.repo = self.root / "work" / "repo"
        self.elsewhere = self.root / "elsewhere"
        for path in (self.home / "sessions", self.repo, self.elsewhere):
            path.mkdir(parents=True)
        self.env = {key: value for key, value in os.environ.items() if key != "CODEX_HOME"}
        self.env.update(HOME=str(self.root), CODEX_HOME=str(self.home),
                        PYTHONDONTWRITEBYTECODE="1")
        self.build_home()

    def build_home(self):
        now = int(time.time())
        decoy = sqlite3.connect(self.home / "state_9.sqlite")
        decoy.execute(THREADS_SCHEMA)
        decoy.commit()
        decoy.close()

        state = sqlite3.connect(self.home / "state_10.sqlite")
        state.execute(THREADS_SCHEMA)
        state.execute("create table thread_spawn_edges (parent_thread_id text not null, "
                      "child_thread_id text not null primary key, status text not null)")
        child_source = json.dumps({"subagent": {"thread_spawn": {"parent_thread_id": PARENT}}})
        rollout = self.write_rollout("rollout.jsonl", self.rollout_records())
        legacy = self.write_rollout("legacy.jsonl", self.legacy_records())
        rows = [
            (PARENT, "", now - 3600, now - 60, "vscode", str(self.repo), "Fix the login bug",
             0, "main", "0123456789abcdef", "git@example.test:me/repo.git", "gpt-test", "high",
             "Fix the login bug", "Fix login bug", "user", None, None),
            (CHILD, "", now - 3000, now - 120, child_source, str(self.repo),
             "Investigate the session cookie", 0, None, None, None, None, None,
             "Investigate the session cookie", None, "subagent", "Euler", None),
            (ARCHIVED, "", now - 7200, now, "cli", str(self.repo), "Old work", 1,
             None, None, None, None, None, "", None, None, None, None),
            (ROLLOUT, str(rollout), now - 7200, now - 300, "cli", str(self.repo),
             "Rollout thread", 0, None, None, None, None, None, "", None, None, None, None),
            (LEGACY, str(legacy), now - 7200, now - 400, "exec", str(self.repo),
             "Legacy thread", 0, None, None, None, None, None, "", None, None, None, None),
            (EMPTY, str(self.home / "missing.jsonl"), now - 7200, now - 500, "cli",
             str(self.repo), "Empty thread", 0, None, None, None, None, None, "", None, None,
             None, None),
            (OTHER, "", now - 90 * 86400, now - 40 * 86400, "cli", str(self.elsewhere),
             "Other project work", 0, None, None, None, None, None, "", None, None, None, None),
        ]
        state.executemany(f"insert into threads values ({','.join('?' * 18)})", rows)
        state.execute("insert into thread_spawn_edges values (?, ?, 'open')", (PARENT, CHILD))
        state.commit()
        state.close()

        long_output = "M src/app.py\n" + "x" * 1000
        parent_items = [
            ("t1", user('<in-app-browser-context source="ambient-ui-state">\nignore me\n'
                        "</in-app-browser-context>\n\nFix the login bug | quickly")),
            ("t1", agent("Looking at the login handler.", "commentary")),
            ("t1", {"type": "commandExecution", "command": "/bin/zsh -lc 'git status --short'",
                    "aggregatedOutput": long_output, "exitCode": 0, "status": "completed"}),
            ("t1", {"type": "fileChange", "status": "completed", "changes": [
                {"path": str(self.repo / "src/app.py"), "kind": {"type": "update", "move_path": None},
                 "diff": "@@ -1 +1 @@\n-old\n+new\n"},
                {"path": str(self.repo / "src/new.py"), "kind": {"type": "add"}, "diff": "a\nb\n"}]}),
            ("t1", {"type": "subAgentActivity", "kind": "started", "agentThreadId": CHILD}),
            ("t1", {"type": "subAgentActivity", "kind": "interacted", "agentThreadId": CHILD}),
            ("t1", {"type": "mcpToolCall", "server": "docs", "tool": "search",
                    "arguments": {"q": "login"}, "status": "completed",
                    "result": {"content": [{"type": "text", "text": "found it"}]}}),
            ("t1", {"type": "webSearch", "query": "login bug", "action": {"type": "search"}}),
            ("t1", {"type": "reasoning", "summary": ["HIDDEN-REASONING"], "content": []}),
            ("t1", agent("Fixed the login bug.", "final_answer")),
            ("t2", user("Thanks, now add tests")),
            ("t2", agent("Added tests.")),
        ]
        history = sqlite3.connect(self.home / "thread_history_1.sqlite")
        history.execute("create table thread_items (thread_id text not null, turn_id text not null, "
                        "item_id text not null, rollout_ordinal integer not null, "
                        "created_at_ms integer not null, item_json text not null, "
                        "item_type text not null default '', "
                        "primary key (thread_id, turn_id, item_id))")
        batches = {
            PARENT: parent_items,
            CHILD: [("c1", user("Investigate the session cookie")),
                    ("c1", agent("Cookie expiry was wrong.", "final_answer"))],
            ARCHIVED: [("a1", user("old"))],
            OTHER: [("o1", user("Other work")), ("o1", agent("Done elsewhere."))],
        }
        for thread_id, items in batches.items():
            for ordinal, (turn_id, item) in enumerate(items):
                history.execute("insert into thread_items values (?, ?, ?, ?, ?, ?, ?)",
                                (thread_id, turn_id, f"item-{ordinal}", ordinal,
                                 (now - 3600) * 1000 + ordinal, json.dumps(item), item["type"]))
        history.commit()
        history.close()

    def write_rollout(self, name, records):
        path = self.home / "sessions" / name
        path.write_text("".join(json.dumps(record) + "\n" for record in records))
        return path

    def rollout_records(self):
        def completed(item):
            return {"timestamp": "2026-01-02T03:04:05.000Z", "type": "event_msg",
                    "payload": {"type": "item_completed", "turn_id": "r1", "item": item}}
        return [
            {"timestamp": "2026-01-02T03:04:05.000Z", "type": "session_meta",
             "payload": {"id": ROLLOUT}},
            completed({"type": "UserMessage", "content": [{"type": "text", "text": "Rollout prompt"}]}),
            completed({"type": "CommandExecution", "command": ["/bin/zsh", "-lc", "ls -la"],
                       "aggregated_output": "total 0", "exit_code": 0}),
            completed({"type": "FileChange", "changes": {str(self.repo / "a.txt"): {
                "type": "update", "unified_diff": "@@\n-a\n+b\n", "move_path": None}}}),
            completed({"type": "AgentMessage", "phase": "final_answer",
                       "content": [{"type": "text", "text": "Rollout answer"}]}),
        ]

    def legacy_records(self):
        return [
            {"timestamp": "2025-01-02T03:04:05.000Z", "type": "event_msg",
             "payload": {"type": "user_message", "message": "Legacy prompt"}},
            {"timestamp": "2025-01-02T03:04:06.000Z", "type": "response_item",
             "payload": {"type": "function_call", "name": "shell",
                         "arguments": json.dumps({"command": ["ls"]})}},
            {"timestamp": "2025-01-02T03:04:07.000Z", "type": "event_msg",
             "payload": {"type": "agent_message", "message": "Legacy answer"}},
        ]

    def run_tool(self, *args, check=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *args], env=self.env, text=True,
                                capture_output=True, stdin=subprocess.DEVNULL, timeout=30)
        if check and result.returncode != 0:
            self.fail(f"codex-export {' '.join(args)} failed:\n{result.stderr}")
        return result

    def listing(self, *args):
        return json.loads(self.run_tool("list", "--json", *args).stdout)

    def test_list_shows_top_level_threads_newest_first(self):
        rows = self.listing()
        self.assertEqual([row["id"] for row in rows], [PARENT, ROLLOUT, LEGACY, EMPTY, OTHER])
        parent = rows[0]
        self.assertEqual((parent["turns"], parent["user_messages"]), (2, 2))
        self.assertEqual((parent["history"], parent["children"]), ("sqlite", 1))
        self.assertEqual(parent["title"], "Fix login bug")
        self.assertEqual(rows[1]["history"], "rollout")
        self.assertIsNone(rows[1]["turns"])
        self.assertEqual(rows[3]["history"], "none")

    def test_list_filters(self):
        everything = {row["id"] for row in self.listing("--all", "--limit", "0")}
        self.assertTrue({CHILD, ARCHIVED} <= everything)
        self.assertEqual([row["id"] for row in self.listing("--cwd", str(self.elsewhere))], [OTHER])
        self.assertEqual([row["id"] for row in self.listing("--search", "OTHER project")], [OTHER])
        self.assertNotIn(OTHER, {row["id"] for row in self.listing("--days", "30")})
        self.assertEqual(len(self.listing("--limit", "2")), 2)

    def test_list_table_abbreviates_home(self):
        output = self.run_tool("list").stdout
        self.assertTrue(output.startswith("UPDATED"))
        self.assertIn(f"{PARENT}  ~/work/repo", output)

    def test_show_reports_relationships(self):
        parent = json.loads(self.run_tool("show", PARENT, "--json").stdout)
        self.assertEqual([child["id"] for child in parent["children"]], [CHILD])
        self.assertEqual(parent["git_branch"], "main")
        child = json.loads(self.run_tool("show", CHILD, "--json").stdout)
        self.assertEqual(child["parent_id"], PARENT)
        self.assertTrue(child["subagent"])
        self.assertEqual(json.loads(self.run_tool("show", "01b0", "--json").stdout)["id"], OTHER)

    def test_export_renders_condensed_transcript(self):
        text = self.run_tool("export", PARENT).stdout
        self.assertTrue(text.startswith("# Fix login bug\n"))
        self.assertNotIn("ignore me", text)
        self.assertIn("**User:**\n\nFix the login bug | quickly", text)
        self.assertIn("> Looking at the login handler.", text)
        self.assertIn("- Ran `git status --short` (exit 0)", text)
        self.assertIn("characters omitted", text)
        self.assertIn("- Edited `src/app.py` (+1 −1)\n- Added `src/new.py` (+2 −0)", text)
        self.assertIn(f"- Started subagent Euler (`{CHILD}`)", text)
        self.assertEqual(text.count("subagent Euler"), 1)
        self.assertIn('- MCP `docs.search` `{"q": "login"}`', text)
        self.assertIn("found it", text)
        self.assertIn("- Web search: `login bug`", text)
        self.assertNotIn("HIDDEN-REASONING", text)
        self.assertIn("**Codex:**\n\nFixed the login bug.", text)
        self.assertIn("**Codex:**\n\nAdded tests.", text)
        self.assertIn("- Git: `main` @ `0123456789ab` (git@example.test:me/repo.git)", text)
        self.assertIn("## Subagents\n\n### Subagent: Euler", text)
        self.assertIn("Investigate the session cookie", text)
        self.assertIn("Cookie expiry was wrong.", text)
        self.assertIn("Fix the login bug \\| quickly", text)

    def test_turn_index_points_at_turn_headings(self):
        lines = self.run_tool("export", PARENT).stdout.split("\n")
        rows = [re.match(r"\| (\d+) \| (\d+) \|", line) for line in lines]
        rows = [(int(m.group(1)), int(m.group(2))) for m in rows if m]
        self.assertEqual([turn for turn, _ in rows], [1, 2])
        for turn, line in rows:
            self.assertTrue(lines[line - 1].startswith(f"## Turn {turn}"), lines[line - 1])

    def test_export_options(self):
        quiet = self.run_tool("export", PARENT, "--output-chars", "0", "--subagents", "none").stdout
        self.assertNotIn("```text", quiet)
        self.assertNotIn("## Subagents", quiet)
        self.assertIn("```diff\n  @@ -1 +1 @@", self.run_tool("export", PARENT, "--diffs").stdout)
        full = self.run_tool("export", PARENT, "--subagents", "full").stdout
        self.assertIn("### Subagent: Euler", full)
        self.assertIn("#### Turn 1", full)

    def test_export_writes_private_file(self):
        target = self.root / "out" / "nested" / "parent.md"
        result = self.run_tool("export", PARENT, "-o", str(target))
        self.assertIn("wrote", result.stderr)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        self.assertTrue(target.read_text().startswith("# Fix login bug"))

    def test_rollout_items_are_normalized(self):
        text = self.run_tool("export", ROLLOUT).stdout
        self.assertIn("- History source: rollout", text)
        self.assertIn("**User:**\n\nRollout prompt", text)
        self.assertIn("- Ran `ls -la` (exit 0)", text)
        self.assertIn("- Edited `a.txt` (+1 −1)", text)
        self.assertIn("**Codex:**\n\nRollout answer", text)

    def test_legacy_rollout_events(self):
        text = self.run_tool("export", LEGACY).stdout
        self.assertIn("**User:**\n\nLegacy prompt", text)
        self.assertIn('- Tool `shell` `{"command": ["ls"]}`', text)
        self.assertIn("**Codex:**\n\nLegacy answer", text)

    def test_errors(self):
        cases = [
            (("export", EMPTY), "no readable history"),
            (("export", "01a00000"), "matches 6 threads"),
            (("show", "zzzz"), "no Codex thread matches"),
            (("--codex-home", str(self.root / "absent"), "list"), "does not exist"),
            (("--codex-home", str(self.repo), "list"), "no Codex state database"),
        ]
        for args, message in cases:
            with self.subTest(args=args):
                result = self.run_tool(*args, check=False)
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
