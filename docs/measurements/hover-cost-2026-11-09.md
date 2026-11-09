# Hover cost per LSP hover -- 2026-11-09 (wave 150 lane LX2, item 3; D1P-149(iii) / LX-5)

Script: `tests\autotest\tools\hover-cost.ps1` (moved from lanes\149\LX\scratch\ms and fixed).
DB: a copy of `C:\TEMP\claude\lanes\150\_copies\client.sqlite` (ORM3 CLIENT, 171,552,768 B), read-only.
Positions: the first 100 routine names on their declaring lines in `%\CLIENT\%` files (6 files).
Method: per arm, one session with 1 hover and one with 100; ms/hover = (T100 - T1) / 99, min of 2 repeats.
Every hover must return non-empty markdown or the arm is FAIL (exit 1) -- no number is printed as a measurement.

## Why the 149 run printed 0.0 ms
The repeat loop was `for ($r = 0; $r -lt $R; ...)` with `param([int]$R = 2)`. PowerShell variable names are
case-insensitive, so `$r = 0` set R to 0, the loop never ran, no LSP session was started, and the printed result
was [double]::MaxValue - [double]::MaxValue = 0 with empty answer counts. Fixed: `$rep` / `-Repeats`, plus the
answer assertion. Positive control: `-ExeB C:\Windows\System32\hostname.exe` -> `answered=0/3 ... FAIL`, exit 1.

## Results (Win64 Debug builds, shared 9-CPU machine under ~10 agents)

| run | stores | A | A ms/hover | B | B ms/hover | md bytes A / B |
|---|---|---|---|---|---|---|
| 1 | 1 | 1.48.0-alpha (pre-LX) | 170.8 | 1.49.0-alpha base (LX extra stores) | 162.2 | 50490 / 50490 |
| 2 | 1 | 1.49.0-alpha base | 219.7 | lane LX2 build (+ Called from:) | 217.0 | 50490 / 54221 |
| 3 | 2 (--db copy --db copy-b) | 1.48.0-alpha | 189.4 | 1.49.0-alpha base | 171.7 | 50490 / 50490 |
| 4 | 2 | 1.49.0-alpha base | 204.5 | lane LX2 build | 166.1 | 50490 / 54221 |

All arms answered 100/100.

## Reading
- The SAME engine (1.49 base) measured 162-220 ms/hover across the four runs: run-to-run noise on this
  machine is about +-20 percent. Every A/B difference above is inside it.
- LX's extra-stores change (1.48 -> 1.49): no measurable cost (B <= A in both pairs).
- LX2's 'Called from:' line: +3731 md bytes over 100 hovers (the callers are now on the card), no measurable cost
  (TDocFacts.CalledFrom was already computed per hover; only formatting is added).
- Limit: the two-store run uses two copies of the SAME DB, so the extra store adds no new 'Used in:' entries
  (md bytes unchanged); it exercises the extra-store lookup, not a real cross-project fan-out. MS-B re-runs
  this script on the re-parsed real CLIENT DB after the deploy.

Raw: lanes\150\LX2\scratch\ms\hc-148-vs-base.txt, hc-base-vs-lane.txt, hc2-148-vs-base.txt, hc2-base-vs-lane.txt.

Re-run:
```
pwsh -File tests\autotest\tools\hover-cost.ps1 -DbPath <copy.sqlite> -ExeA <old drag-lint.exe> -ExeB <new drag-lint.exe> -PathLike '%\CLIENT\%' -N 100 -Repeats 2 [-SecondDb <copy2.sqlite>] -Out <scratch>\hover-cost.txt
```