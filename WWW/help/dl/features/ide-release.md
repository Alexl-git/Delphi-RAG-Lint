---
id: ide-release
title: ide-release
summary: Asks a running drag-lint Delphi IDE plugin not to respawn its drag-lint.exe child processes for a while -- and to drop the running one on its next request
product: DL
group: editor-integration
order: 110008
since: 1.13.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# ide-release

Asks a running drag-lint Delphi IDE plugin not to respawn its drag-lint.exe child processes for a while -- and to drop the running one on its next request.

Read this when an engine build fails to copy drag-lint.exe because the Delphi IDE is open. ide-release writes a hold (--seconds N, 1 to 3600; 0, a negative number or no flag gives the default 120 s, and anything above 3600 is cut to 3600) so the plugin stops respawning the engine; --resume clears it and --status reports it. It frees nothing by itself.

## How to run it

Full flag list: [ide-release in the CLI reference](../cli.md#ide-release).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--seconds` | `N` |  |  |
| `--resume` |  |  |  |
| `--status` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Asks a running drag-lint **Delphi IDE plugin** not to respawn its
`drag-lint.exe` child processes for a while -- and to drop the running one on
its next request -- so the engine binary can be rebuilt while the IDE stays
open. The verb frees nothing by itself; see below.

### The problem it solves

A running Windows process holds an **execute lock on its own image**. The
plugin spawns `drag-lint.exe lsp --stdio` as a long-lived child, so an IDE that
is merely *open* blocks the deploy step of an engine build:

```text
  249716 lines, 12.41 seconds, 11077076 bytes code, 991240 bytes data.
ERROR: failed to stage C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe
```

The compile succeeded. Only the copy failed, one line later, naming the file
and not the holder.

**Killing the server alone does not work** -- it is respawned within about a
second and the build loses the race again. So this verb asks for a *window*,
not an event: the plugin stays stopped until the hold expires.

### Running it from the CLI

```text
drag-lint ide-release [--seconds N] [--json]     # hold (default 120s)
drag-lint ide-release --resume                   # clear the hold now
drag-lint ide-release --status [--json]          # report, change nothing
```

Needs no index and no `--db`.

### Writing the hold does not itself free the file

The verb writes a sentinel and returns immediately. The plugin observes it
**lazily** -- on the next call that wants the language server -- because a timer
here would be a second uninvited source of process spawns, and this plugin has
shipped one of those before.

That is also why stopping the running child is the **build's** job:
`build\stage-engine.ps1` writes the hold *and* kills the holder *and* retries.
The hold is what makes the kill stick.

So a caller that needs the lock actually gone must wait and retry. You normally
do not call this by hand at all -- `build_draglint_win64.bat` and
`build\pack-lint-release.ps1` (release packing, since 2026-10-16) stage through
`stage-engine.ps1` and get the recovery automatically.

### Stopping the engine remotely (by hand)

When something else must replace or delete the deployed exe -- a manual deploy,
a release step, a script that copies over `third_party\dll-win64\drag-lint.exe`
-- stop the engine remotely instead of killing processes by name:

```text
drag-lint ide-release --seconds 900      # the IDE plugin stops respawning for 15 min
drag-lint shutdown --all --wait 30       # running lsp engines close every store and exit 0
```

`shutdown` asks running `lsp` engines (over their per-user maintenance pipe) to
stand down: close every store, exit 0. Its flags (`--db`, `--wait`, `--dry-run`,
`--all`, `--force`) are on its `drag-lint --help` line. `ide-release --resume`
lifts the hold early. Measured 2026-10-16: without this, a release pack lost the
copy race twice to short-lived engines started by other sessions.

### Flags

| Flag | Meaning |
|---|---|
| `--seconds N` | hold length; default 120; a value below 1 (or not a number) means 120, a value above 3600 is capped at 3600 |
| `--resume` | clear the hold immediately |
| `--status` | report whether a hold is active; changes nothing |
| `--json` | emit the stable `ide-release/1` document |

Exit codes: `0` on success (including `--resume` when there was no hold to
clear -- that is the desired end state); `1` when the sentinel could not be
written or removed.

### It expires on its own

The sentinel carries a **deadline**, not a duration. A build that crashes
half-way cannot leave the IDE permanently without hovers: the hold lapses and
the next hover starts a fresh server. `--resume` is only for getting it back
sooner.

A missing, empty, unparseable or expired sentinel means **not held**. That
direction is deliberate -- failing open costs a blocked build, which is visible
and retryable, while failing closed would leave the IDE silently mute with no
error anywhere.

### Where the sentinel lives

`%LOCALAPPDATA%\drag-lint\engine-hold`, containing a single UTC epoch second.

Not `%TEMP%`, and that is not arbitrary: `TEMP` is **per-process**. A shell may
have `TEMP=C:\TEMP` while the IDE resolves it to `%LOCALAPPDATA%\Temp`, so a
sentinel written to one is invisible to the other and the hold silently never
arrives. A rendezvous between two processes cannot be built on a variable
either of them may have inherited differently.

### What it does NOT cover

The long-lived language server is gated, and since session 78 so is the
plugin's **job queue**: reindex, lint-all, auto-document, forms-CSV and
refresh-findings jobs are DEFERRED while a hold lasts, then run when it lifts.
They are not dropped, and a job already running when the hold appears is not
interrupted -- the hold's contract is "will not start anything". That matters
beyond tidiness: a queued bare `index` job makes `stage-engine.ps1` refuse to
stage rather than kill, and killing a bat-wrapped job leaves `cmd.exe` running
the next line of the bat.

Hover and lint also spawn short-lived `drag-lint.exe` processes, and one of
those can still hold the file for a moment; the staging recovery retries with a
backoff, which absorbs it.

The VS Code client is unaffected -- since extension v1.4 it runs its own
private copy of the engine and never touches the deployed binary. See
EDITORS.

### The full update sequence (DEC-13, 2026-10-28)

Replacing a running engine -- the installer swapping an old install, or
`build\stage-engine.ps1` deploying a fresh build -- is a CHANNEL stop first and
a kill only as the last resort:

1. `drag-lint ide-release --seconds N` -- the IDE plugin stops respawning.
2. The maintenance verb with `--all --wait 30` (see the shutdown feature page) --
   every engine of this user that listens on the control channel is asked to
   stand down: `lsp`, `cycles --fix`, and (since DEC-13) the long one-shot runs
   `index` (single root, `--project`, `--all` with its `--jobs` pool) and `lint-all`.
   * `index` stops BETWEEN FILES, at the storage layer's file-transaction gate:
     no file row is half written, the WAL is checkpointed and the connection
     closed (no `-wal`/`-shm` sidecar), the resolver stamp is cleared so the
     resume re-derives every edge, and the process exits **4** (stood down, did
     not finish). The same command resumes.
   * `lint-all` stops between files, prints the findings so far marked PARTIAL
     on stderr, exits **4**; project-wide rules did not run.
   * `sql` does not listen: one guarded SELECT, a kill is harmless.
3. Anything still holding the image after the wait: `stage-engine.ps1` refuses
   when an `index` run is still alive (it did not comply), and otherwise kills
   only the processes running the target image, then retries the copy.
4. The installer (`installer\drag-lint.iss`, `PrepareToInstall`) runs steps 1-2
   against the previous install's `drag-lint.exe` before Restart Manager is
   consulted; an old engine without the channel is a no-op.

Guard: `tests\autotest\run_control_channel_guard.ps1` (sections W and ST).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
