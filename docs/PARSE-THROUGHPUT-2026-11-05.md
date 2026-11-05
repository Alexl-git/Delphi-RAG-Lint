# Parse throughput, 1.43 full re-parse (2026-11-05)

Source: `C:\TEMP\claude\lanes\143\reparse\SUMMARY.txt` (written 15:49, engine
`third_party\dll-win64\drag-lint.exe`, 1.43.0-alpha). Numbers are copied from
that file; nothing was re-measured.

| phase | exit | wall-clock | volume | logged rate |
|---|---|---|---|---|
| library-win32 | 0 | 2h53m | 6966 / 6966 files parsed | 0.90 s/file |
| library-win64 | 0 | 3h02m | 7162 / 7162 files parsed | 0.94 s/file |
| projects | 0 | 9m01s | 37 / 37 sections | -- |
| catchup | 0 | 2m00s | -- | -- |

Run started 12:35:31, phase=done at 15:49:02: **3h13m elapsed** end to end.
The two libraries ran in parallel, so the elapsed figure is the longer
library (3h02m) plus the projects pass (9m) plus catch-up (2m), with start-up
overhead.

## Against the target

- Plan target for a full re-parse: 5-5.5 h. Measured 3h13m, i.e. about
  1h47m-2h17m (35-42 %) under the target.
- The 1.43 plan estimated ~4.2 h (12:35 -> ETA 16:50); the run finished
  about 1h01m before that ETA.
- Cost for comparison (1.42, resolve-only, from PLAN section 3): Win32 53 min,
  Win64 58 min in parallel.

## Caveats

- The `s/file` figures are the engine's own log values; the wall-clock per
  file (library-win32: 2h53m / 6966 = about 1.5 s) is higher than the logged
  0.90 s, so the log rate is most likely the parse stage only, not the whole
  checkpoint cycle. Not verified against the engine source.
- Machine load during the run (parallel lanes, battery) was not recorded
  here, so the figures are not a clean benchmark.
