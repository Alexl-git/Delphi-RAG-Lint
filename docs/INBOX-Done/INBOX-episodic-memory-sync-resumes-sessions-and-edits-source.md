> **RETIRED to INBOX-Done/ on 2026-08-15.** NOT A DRAG-LINT DEFECT and no longer actionable here: it is the episodic-memory plugin's --resume agents editing the working tree. Now a standing fact in auto-memory (kill the sync-cli.js node PARENTS at session start).
>
> Original note follows unchanged.

# INBOX -- episodic-memory background sync resumes old sessions and edits source

**Filed:** 2026-08-12. **Severity:** high (unattended LLM writes to the working tree).
**Component:** `superpowers-marketplace/episodic-memory` plugin v1.4.1 -- NOT drag-lint.

## Symptom

`src/doc/DRagLint.Doc.Facts.pas` was unmodified at session start (confirmed against the
SessionStart git snapshot and `main` = `e1b473f`) and was rewritten twice, at 09:38:08
and 09:38:19, by no session the user was aware of. The content was precisely the task
recorded as the next action in
`docs/RESUME-2026-08-12b-lint-perf-release-and-yadf-cycle.md` -- new `GBAncestry`,
`GBCoveredBy`, `GBWiring` accumulators plus the matching `TB0` bookkeeping and a third
line in `DocFactsBuildProfile`.

## Root cause

The SessionStart hook launches episodic-memory's background sync
(`dist/sync-cli.js`). Its summariser is broken -- the log repeats:

```
Summary generation failed: Cannot read properties of undefined (reading 'match')
All 3 summarization attempts failed.
```

To summarise a conversation it spawns a full agent:

```
claude.exe --model haiku --resume 4023b50b-27b5-4a0a-8194-83f571a83c05 \
           --permission-mode default --no-session-persistence
```

`--resume` **continues** the conversation; it does not merely read the transcript. The
resumed session (`4023b50b-...`, the previous working session -- same GUID as the
scratchpad path cited in the resume doc) had ended **mid-request**, with the pending
instruction being "instrument the ancestry/CoveredBy/Wiring tail". The Haiku agent
inherited that as its live task and executed it against the real repo.

Two sync invocations resumed the same id, which is why there were two writes seconds
apart.

## Reproduction

1. End a session mid-request in a repo covered by episodic-memory.
2. Start a new session; the SessionStart hook fires the sync.
3. `Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Select CommandLine`
   -- observe `--resume <prior-session-guid>` under the plugin's bundled
   `claude-agent-sdk-win32-x64\claude.exe`.
4. Watch the working tree change with no user session responsible.

## Notes

- Killing the `claude.exe` children does not help: they respawn within seconds as the
  sync walks its queue of failed summaries, resuming a *different* archived
  conversation each time (observed next: `782a192b-...`, a `C--Windows-System32`
  conversation). Kill the `sync-cli.js` **node parents** instead. Do not kill the
  `mcp-server.js` node whose parent is the live session pid.
- Any archived conversation is eligible, so the blast radius is every repo the user
  has ever run a session in, not just this one.
- `--permission-mode default` did not prevent the edit.

## Suggested fixes (upstream)

1. Summarisation must read the transcript, never `--resume` it. If an agent is needed,
   give it a read-only tool set.
2. Fix the `reading 'match'` crash so the resume path is not reached at all.
3. Failing both, run the summariser with `--permission-mode plan` or an explicit deny
   list covering Edit/Write/Bash.

## Disposition this session

Processes killed; the edit they produced was reviewed, judged correct but incomplete,
and kept. It leaves the `SeeAlso` / `Since` / `GetSymbolFacts` span (~lines 2107-2258)
untimed, so `build total` minus the parts will still show a remainder.
