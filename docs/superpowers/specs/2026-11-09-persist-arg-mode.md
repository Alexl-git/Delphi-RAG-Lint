# 150-RS2 (2): persist the var / out ARGUMENT mode of a member access (2026-11-09)

Origin: 149 RB2 150 row 1 (150-RB2-a). `usages --rw` classifies at READ time whether a stored
`read` is really the whole argument of a `var` (read + write) or `out` (write) parameter of a
RESOLVED call (Query.Callers TArgClassifier: source text + the call's target signature). Nothing
else (cycles, charts, purity, taint, plain SQL) can see that use, and every `usages` call
re-reads source and re-queries targets.

## The fork: where the mode lives (schema stays 23 -- SC/INT own schema)
| option | row shape | effect on the other readers of member_accesses.mode |
|---|---|---|
| A new mode values `var-arg` / `out-arg` | mode replaced | every `mode = 'read'` / `'write'` reader (CyclePlan IsRead, CycleEdge, PurityStage, EffectRules, charts) changes behaviour -- NOT an identity change |
| B mode stays `read`; `accessor_kind` = `var-arg` / `out-arg`, `accessor_symbol_id` NULL | additive meaning of a column that is NULL for every field / value row today | readers of accessor_kind all test `'field'` / `'method'` WITH a non-NULL accessor id: unchanged |
| C new column / table | schema 24 | not in a lane (SCHEMA_VERSION = INT) |

**Chosen: B** (reversible: one UPDATE clears it). A property is never a var / out argument (E2197),
so a row with a real accessor never needs the slot. Inc / Dec stays read-time (text only, no target).

## Write path
Post-pass in Storage ResolveCallTargets after call edges + member accesses are written (same
transaction): every member_accesses row mode 'read', accessor_symbol_id NULL, whose file holds an
in-scope ref (whole pass: all) -> Query.Callers LocateArgument (exported) -> the call ref at the
callee position (refs.symbol_id, else its certain call edge) -> ParamModeAt (exported) on the
target's signature -> accessor_kind var-arg / out-arg / NULL (only rows whose accessor_kind is NULL or
already an argument kind are touched).

## Read path
FindResolvedCallers carries the stored value (TResolvedCaller.ArgUse). TArgClassifier: ArgUse set
-> that; else the read-time path as before (Inc/Dec by text; var/out by target) -- kept as the
fallback because identity-only rows (a local or parameter passed as var) have no member_accesses
row to store in, and a DB resolved before this build has none stored. No marker: the answer is the
same either way, the stored value is read first. Acceptance: `usages --rw` output byte-identical on the fixture between the
1.49 base (read-time) and this build (stored), plus SQL rows showing the stored kinds.