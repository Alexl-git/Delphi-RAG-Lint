# heartbeat

The engine reports what it is doing; the IDE plugin reads it to tell a busy
engine from a stuck one. Before 1.40 the plugin judged only by output and CPU,
so a long index that printed nothing could be killed, and a spinning frozen
engine could survive.

## Status record

A process-wide record, updated by the engine as it works:

| field | meaning |
|---|---|
| seq | +1 on every report; the plugin's only change test |
| action | verb or LSP method (`index`, `lint-all`, `lint`, `context`, `textDocument/hover`) |
| step | phase inside the action (`parse`, `per-file scan`, `resolve`); empty = none |
| n / total | counter inside the step; total 0 = unknown |
| age | milliseconds since the last report (display only) |

Text form: `beat=<seq>|<action>|<step>|<n>|<total>|<age-ms>`.

## Which verbs report

`index` (single, `--project`, `--all`: one tick per parsed file), `lint-all`
(phase steps and a tick per file), `lint` and `context` (at dispatch), and the
LSP server for every request. Every other verb has no beat; the plugin then
falls back to the old output-or-CPU rule.

## The pipe

A status-only listener on `\\.\pipe\drag-lint-beat-<sid>-s<session>-p<pid>`
(same user and session rules as the control pipe). It answers `status` and
refuses `shutdown`. The prefix differs on purpose: `shutdown --all` and the
engine stager enumerate `drag-lint-ctl-*`, so their behaviour is unchanged.

## What the plugin does with it

* `ProcRun`: polls every 2 s. Once one beat answered, progress means output was
  read or the sequence changed; CPU no longer counts. No progress for the
  caller's stall budget means stuck. No beat ever: the old rule.
* `LspClient.IsStuck`: samples the beat every 2 s; once one answered, the CPU
  mark is ignored. A beat that stops answering is frozen. The stuck limit is
  unchanged (180 s).
* The status bar shows the last beat, e.g. `index parse 120/400`.

## Verified by

`tests\autotest\run_engine_heartbeat_guard.ps1` (engine side),
`tests\plugin\run_procrun_heartbeat.ps1` and the HB1-HB3 checks of
`tests\plugin\run_lsp_nonblocking.ps1` (plugin side).