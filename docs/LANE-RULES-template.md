# Lane rules template (copy to `C:\TEMP\claude\lanes\<wave>\LANE-RULES.md`, fill the <...>)

Why this exists (LANE-CWD, 2026-11-03): a lane agent's process cwd is the MAIN tree
`C:\Projects\Delphi-RAG-lint`, not its worktree. Relative paths wrote four stray edits into main
in one night, and one reached the first 1.40.0 build. Every lane brief must carry the block below.

## Where you work
- ONLY in your worktree `C:\TEMP\claude\lanes\<wave>\<lane>\wt` (branch `lane/<wave>-<lane>`, base `<sha>`).
  Scratch (private): `C:\TEMP\claude\lanes\<wave>\<lane>\scratch`.
- Your process cwd is the MAIN tree. Therefore:
  - Every path you hand to Read, Edit, Write, Glob, Grep, `[IO.File]`, `Get-Content`, `Set-Content`
    is an ABSOLUTE path under your worktree. A relative path lands in main.
  - Every git call is `git -C <wt> ...`. A bare `git` acts on main.
  - Every build is `cd <wt> && <build bat>` in the SAME command; a bat run without the `cd`
    builds the main tree.
  - Every script you run is addressed by its absolute worktree path; when it resolves its repo from
    `$PSScriptRoot` that is enough, when it resolves from the cwd pass `-Repo <wt>`.
- Never edit, build in, stash in, or deploy to the main tree. Reading its docs is fine.
- Before your first edit and before each commit, run `git -C C:\Projects\Delphi-RAG-lint status --short`
  and `git -C <wt> status --short`; a path of yours showing in the main tree is a leak: stop and report it.
- Commit on your branch with a pathspec: `git -C <wt> commit -m "..." -- <paths>`. Never `commit -a`,
  `add -A`, `reset --hard`, `clean`, `checkout -- <paths>`, bare `stash`, `push`.

## Private engine and databases
- Use your PRIVATE engine copy `C:\TEMP\claude\lanes\<wave>\<lane>\engine\drag-lint.exe`, never
  `third_party\dll-win64`. Always pass `--db` explicitly.
- Real project/library DBs are read-only for you; work on copies in your scratch folder.

## Finish
- Append one line to the wave LEDGER: `<ISO time> <lane> DONE|PARTIAL|BLOCKED <head sha> <state>`.
- Report: per item DONE / FIXED-already / BLOCKED plus commit SHAs; guards run with counts.

## Optional enforcement (not implemented)
A PreToolUse hook that refuses Edit/Write/Bash whose target path is inside the main tree while the
session is a lane session would make the rule mechanical. It needs a lane marker (an env var such as
`DL_LANE_WT` set at dispatch) and was deliberately skipped in 1.42 wave 2 (owner brief: optional).
