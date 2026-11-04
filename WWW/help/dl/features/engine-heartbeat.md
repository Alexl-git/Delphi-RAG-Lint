---
id: engine-heartbeat
title: "Engine heartbeat: the IDE tells a busy engine from a stuck one"
summary: A running engine reports what it is doing, so the IDE kills only an engine whose status stopped moving
product: DL
group: editor-integration
order: 110006
since: 1.40.0-alpha
status: shipped
updated: 1.42.0-alpha
---

# Engine heartbeat: the IDE tells a busy engine from a stuck one

A running engine reports what it is doing, so the IDE kills only an engine whose status stopped moving.

Read this to understand why a long index or lint-all no longer gets killed while it works, and why a frozen engine still is. The engine keeps a status record (action, step, n of total) and answers it on a status-only pipe, drag-lint-beat-*, next to the control pipe. The IDE plugin polls it every two seconds: a changing record counts as progress, a frozen record on a spinning process counts as stuck. The status bar shows it, e.g. 'index parse 120/400'. An old engine or a verb without a beat falls back to the earlier output-or-CPU rule.

## Details

The engine reports what it is doing; the IDE plugin reads it to tell a busy
engine from a stuck one. Before 1.40 the plugin judged only by output and CPU,
so a long index that printed nothing could be killed, and a spinning frozen
engine could survive.

### Status record

A process-wide record, updated by the engine as it works:

| field | meaning |
|---|---|
| seq | +1 on every report; the plugin's only change test |
| action | verb or LSP method (`index`, `lint-all`, `lint`, `context`, `textDocument/hover`) |
| step | phase inside the action (`parse`, `per-file scan`, `resolve`); empty = none |
| n / total | counter inside the step; total 0 = unknown |
| age | milliseconds since the last report (display only) |

Text form: `beat=<seq>|<action>|<step>|<n>|<total>|<age-ms>`.

### Which verbs report

`index` (single, `--project`, `--all`: one tick per parsed file), `lint-all`
(phase steps and a tick per file), `lint` and `context` (at dispatch), and the
LSP server for every request. Every other verb has no beat; the plugin then
falls back to the old output-or-CPU rule.

### The pipe

A status-only listener on `\\.\pipe\drag-lint-beat-<sid>-s<session>-p<pid>`
(same user and session rules as the control pipe). It answers `status` and
refuses `shutdown`. The prefix differs on purpose: `shutdown --all` and the
engine stager enumerate `drag-lint-ctl-*`, so their behaviour is unchanged.

### What the plugin does with it

* `ProcRun`: polls every 2 s. Once one beat answered, progress means output was
  read or the sequence changed; CPU no longer counts. No progress for the
  caller's stall budget means stuck. No beat ever: the old rule.
* `LspClient.IsStuck`: samples the beat every 2 s; once one answered, the CPU
  mark is ignored. A beat that stops answering is frozen. The stuck limit is
  unchanged (180 s).
* The status bar shows the last beat, e.g. `index parse 120/400`.

### Reading it from outside (1.42)

`drag-lint shutdown --all --dry-run` lists every engine of this user and session and adds, per engine, the
beat line: `pid 1234 beat: index: resolve calls 512000/1100203 (seq 8048, last report 3 s ago)`. It asks
nothing and changes nothing. Compare two readings: the seq and N are the progress test.

The stage's own `still running` line carries the same counter and a rate:
`stage: calls -- still running, 12m00s elapsed, resolve calls 512000 of 1100203, 710/s`. A stage with no
counter prints the time only.

### Slow or stuck? (1.42)

A heartbeat proves only that its own timer thread is alive, so a long stage compares the status record's seq.
A counter standing still for 15 minutes prints `stage: calls -- NO PROGRESS for 900 s at <step> N of M`, and free
RAM under 512 MB prints `LOW MEMORY`. Neither stops anything.

`index --stall-exit-min <min>` arms an exit: a counter standing still that long ends the run with exit 8 and a
`STALLED` line (exit 9, at a quarter of the limit, when RAM is critical). A moving counter is never stopped,
however slow and however short memory is. Some steps have no counter (purity fixpoint, facts-inherited, COMMIT),
so set the limit above the longest of them: 60 on a library index.

The open transaction rolls back, as after a kill. **Re-run a library killed after its walk with `--resolve-only`:**
a plain re-run re-parses every file, because the indexer fingerprint is stamped only at the end of a run.
To stop a run from outside, use the existing `shutdown --force`; there is no separate nudge.

### A second writer waits on it (1.41)

Asked `status<TAB>beat<TAB>writing`, the pipe adds `writing=<db>|<db>...`: the
databases this engine has a writer store open on (lower-cased full paths). A
request without `writing` gets the old reply.

A writer that finds the database locked (SQLITE_BUSY) asks the other engines'
heartbeat pipes once a second which of them write that database. It keeps
waiting while one of them advances its beat seq, and gives up ("database is
locked") once no holder's seq has moved for the writer timeout (120 s, or
`DRAGLINT_BUSY_TIMEOUT_MS`). A holder with no heartbeat (an older engine, a
verb without a beat pipe, a non-drag-lint writer) therefore keeps the fixed
120 s. After 5 s of a wait that saw progress, the waiter prints one NOTE to stderr.
The waiter does not advance its own beat while it waits. Guard:
`tests\autotest\run_busy_beat_guard.ps1`.

### Verified by

`tests\autotest\run_engine_heartbeat_guard.ps1` (engine side),
`tests\plugin\run_procrun_heartbeat.ps1` and the HB1-HB3 checks of
`tests\plugin\run_lsp_nonblocking.ps1` (plugin side).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
