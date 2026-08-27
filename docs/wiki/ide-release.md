# ide-release

Asks a running drag-lint **Delphi IDE plugin** to stop its `drag-lint.exe`
child processes and not respawn them for a while, so the engine binary can be
rebuilt while the IDE stays open.

## The problem it solves

A running Windows process holds an **execute lock on its own image**. The
plugin spawns `drag-lint.exe lsp --stdio` as a long-lived child, so an IDE that
is merely *open* blocks the deploy step of an engine build:

```
  249716 lines, 12.41 seconds, 11077076 bytes code, 991240 bytes data.
ERROR: failed to stage C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe
```

The compile succeeded. Only the copy failed, one line later, naming the file
and not the holder.

**Killing the server alone does not work** -- it is respawned within about a
second and the build loses the race again. So this verb asks for a *window*,
not an event: the plugin stays stopped until the hold expires.

## Running it from the CLI

```
drag-lint ide-release [--seconds N] [--json]     # hold (default 120s)
drag-lint ide-release --resume                   # clear the hold now
drag-lint ide-release --status [--json]          # report, change nothing
```

Needs no index and no `--db`.

## Reaching it in the IDE

No IDE surface. It is a message *to* the IDE, not an action in it. While a hold
is active the plugin shows `drag-lint: engine released for a rebuild (Ns left)`
on its status strip, so a temporarily quiet IDE is never a mystery.

## Writing the hold does not itself free the file

The verb writes a sentinel and returns immediately. The plugin observes it
**lazily** -- on the next call that wants the language server -- because a timer
here would be a second uninvited source of process spawns, and this plugin has
shipped one of those before.

That is also why stopping the running child is the **build's** job:
`build\stage-engine.ps1` writes the hold *and* kills the holder *and* retries.
The hold is what makes the kill stick.

So a caller that needs the lock actually gone must wait and retry. You normally
do not call this by hand at all -- `build_draglint_win64.bat` invokes the
recovery automatically when staging fails.

## Flags

| Flag | Meaning |
|---|---|
| `--seconds N` | hold length; default 120, clamped to 1..3600 |
| `--resume` | clear the hold immediately |
| `--status` | report whether a hold is active; changes nothing |
| `--json` | emit the stable `ide-release/1` document |

Exit codes: `0` on success (including `--resume` when there was no hold to
clear -- that is the desired end state); `1` when the sentinel could not be
written or removed.

## It expires on its own

The sentinel carries a **deadline**, not a duration. A build that crashes
half-way cannot leave the IDE permanently without hovers: the hold lapses and
the next hover starts a fresh server. `--resume` is only for getting it back
sooner.

A missing, empty, unparseable or expired sentinel means **not held**. That
direction is deliberate -- failing open costs a blocked build, which is visible
and retryable, while failing closed would leave the IDE silently mute with no
error anywhere.

## Where the sentinel lives

`%LOCALAPPDATA%\drag-lint\engine-hold`, containing a single UTC epoch second.

Not `%TEMP%`, and that is not arbitrary: `TEMP` is **per-process**. A shell may
have `TEMP=C:\TEMP` while the IDE resolves it to `%LOCALAPPDATA%\Temp`, so a
sentinel written to one is invisible to the other and the hold silently never
arrives. A rendezvous between two processes cannot be built on a variable
either of them may have inherited differently.

## What it does NOT cover

Only the long-lived language server is gated. Hover and lint also spawn
short-lived `drag-lint.exe` processes, and one of those can still hold the file
for a moment; the staging recovery retries with a backoff, which absorbs it.

The VS Code client is unaffected -- since extension v1.4 it runs its own
private copy of the engine and never touches the deployed binary. See
[EDITORS](https://github.com/Alexl-git/Delphi-RAG-Lint/blob/main/docs/EDITORS.md).
