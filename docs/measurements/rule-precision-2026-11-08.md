# Rule precision on ORM3 CLIENT, 2026-11-08 (wave 148 T3)

Engine 1.46.0-alpha, copy of Micronite2027.sqlite (indexed 2026-11-07 22:46). One `lint-all --json` run with the OFF rules enabled (14 min, 23169 findings). Counts: T2/wt docs/measurements/orm3-client-lintall-1.46.0-alpha.json. Method: up to 20 findings per rule sampled evenly, ONE source line read each (plus the surrounding case/function for used-before-assignment). Shares are line-level judgements, not full triage.

| rule | state | findings | sample | verdict |
|---|---|---|---|---|
| string-equality-comparison | OFF | 43 | 19 | pattern is true (plain `=` on strings); not a defect by itself (case-sensitive compare is usually intended). Stays OFF |
| exhaustive-enum-case | OFF | 34 | 20 (18 in uPLANLIST.PAS) | the enum coverage was not checked per case (only the `case` head read); clustered in one unit. Stays OFF; needs a per-finding missing-member list in the message |
| mutable-global-variable | OFF | 375 | 8 read | all true globals (frmMAIN, BASICS state); legacy-wide. Stays OFF (floods) |
| query-name-with-effect | OFF | 1 | 1 | Blueprint4.ViewModel.pas:335 GetOperationNames; effect not verified. Stays OFF (n=1, unproved) |
| interface-object-mixing, is-never-true | OFF | 0 | - | no data on CLIENT; is-never-true needs Loader2025 copy (149) |
| float-equality-comparison | ON | 49 | 20 | ~all true comparisons on Double/TDateTime (`zd <> 0`, `TRange = 0`, complex-number `=` in ap.pas); `= 0` sentinels are the usual benign share (~half). Keep ON |
| length-zero-compare | ON | 13 | 13 | all true (style hint). Keep ON |
| used-before-assignment | ON | 29 | 20 | uPLANLIST: `acc_QI` etc. assigned only through var-param calls inside `case` branches with no `else`, other enum values fall through: plausible TRUE; likely 1 pattern repeated (medium confidence) |
| read-never-assigned | ON | 19 | 19 | globals read but never assigned in CLIENT (QuitMicronite verified: read in uMain.pas:1096, no write). Some (ComputerName/UserName) may be set outside the project: medium |
| dataset-open-without-close | ON | 7 | 7 | mixed: 2 `.Active := True` on memtables, 1 TdxActivityIndicator `Active := True` (FALSE POSITIVE: not a dataset), 3 `TBL.Open`. About 2/7 FP-suspect. Tune: type must be TDataSet descendant |
| discarded-effect-free-result | ON | 3 | 3 | `Describe;` statement calls (uPLANLIST 2360/2377/2385): result discarded, effect-free per analysis; unverified |
| lossy-cast | ON | 2 | 2 | Utf8ToAnsi(RawByteString(S)): intentional, true finding |
| taint-command-injection | ON | 1 | 1 | uOcrProcessRunner.pas:102 CreateProcess(PChar(CmdLine)): plausible true; CmdLine origin not traced |
| parameter-type-too-wide | ON | 7 | 7 | BASICSF.pas signatures (TStringList, TsgDX*, cx grid views) : plausible, not verified |
| criticalsection-not-released, init-order-hazard, finalization-after-dependency, global-set-in-initialization-never-freed | ON | 0 each | - | zero on CLIENT; E-LA-ROW16 baseline = 0 findings on 1.46 (1.44.1 comparison not run: 149) |
| unused-unit-in-uses | ON | 3871 | not sampled | RF before-count |
| for-bound-modified-in-body 1 / loop-condition-invariant 0 / concat-in-loop 76 | ON | | | RF before-counts (the 1 is uStyles.pas:506 FP RF fixed) |

Not done (149): doc-drift cost timing (171 findings in this run; separate timing run), is-never-true on Loader2025, freeonterminate-then-wait ctor refs, C3 unused-public-symbol enum-binding 1.46 vs 1.44.1 (135 findings now).
