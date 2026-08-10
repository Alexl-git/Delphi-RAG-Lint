---
name: relint
description: "Use when re-measuring a Delphi project's lint health end-to-end, hardening drag-lint's rules against false positives, or checking code quality after a batch of changes. Runs the full reindex -> autodoc -> reindex -> lint-all loop from scratch, keeps a timestamped result file, and classifies findings by count so the biggest noise sources and the biggest real debts are both visible. Triggers on: /relint, relint, re-lint, remeasure lint, lint health, lint baseline, false-positive sweep."
---

# relint -- measure, classify, and harden

Runs the whole loop and produces **one classified report**. Two audiences, one
run:

- **The code** -- which real defects to fix, ranked by count.
- **The rules** -- which findings are the LINTER being wrong. A rule that is
  wrong at scale is a bug in drag-lint, not a chore for the user.

Both matter. A finding count in the thousands is itself a defect: if people
cannot trust the list, they stop reading it, including the day it is right.

## The order is load-bearing

```
reindex  ->  autodoc  ->  reindex  ->  lint-all
```

**Never reorder, never skip a reindex.** autodoc computes facts (callers,
complexity, return cases) FROM THE INDEX. Run it against a stale index and it
writes stale facts into your source, then lint reports the damage as drift.
That mistake produced a 514-finding phantom regression once, and a 641-pending-edit
"convergence failure" another time. Both were the ordering, not the code.

The same applies after *any* edit to the target source, including your own: a
doc block graded against shifted line numbers reports params that are in the
signature as missing.

## Preflight -- three checks that prevent a wasted run

A full run is 20+ minutes. These take seconds and each one has silently
invalidated a real run before.

### 1. The manifest must resolve (THE SILENT KILLER)

`index --all` reads its manifest **relative to the exe's own directory**. An exe
with no `drag-lint.json` beside it resolves **0 sections, indexes nothing,
prints nothing, and exits 0.**

```
drag-lint index --all --dry-run          # "Sections to build:" MUST be > 0
```

If it says 0 and you are running a freshly built exe, copy the sidecars next to
it (`drag-lint.json`, `rules\`, `*.dll`) or use the deployed one. **Do not
proceed on 0** -- every reindex below becomes a no-op and the whole run measures
a stale database while reporting success.

### 2. Nothing is holding a lock

```
tasklist | findstr /i "drag-lint drag_lint_graph"
```

A running indexer holds a Windows lock on the exe AND on the `.sqlite`. A `cp`
over a locked exe **fails silently**, so you test the old binary.

### 3. Source is committed

`autodoc --apply` REWRITES SOURCE. Commit first; then a bad pass is one
`git checkout` away instead of lost work.

## Run it

```bash
STAMP=$(date -u +%Y%m%d-%H%M%S)
EXE="C:/Projects/Delphi-RAG-lint/third_party/dll-win64/drag-lint.exe"
DB="C:/Projects/.drag-lint/<Repo>-<Project>.sqlite"    # ask: drag-lint resolve-dbs
SRC="C:/Projects/<Repo>/src"
CFG="C:/Projects/<Repo>/drag-lint-lint.json"           # optional; carries exclude_paths
OUT="C:/TEMP/claude/relint-$STAMP.txt"

cd /c/TEMP     # neutral CWD

# 1. REINDEX FIRST
"$EXE" index --all --only <Section> --rebuild

# 2. AUTODOC (only for a repo that has opted into managed doc blocks)
for f in $(find "$SRC" -name "*.pas"); do
  "$EXE" document --unit "$f" --db "$DB" --apply >/dev/null
done
find "$SRC" -name "*.bak" -delete

# 3. REINDEX AGAIN  (facts changed; the DB must match disk again)
"$EXE" index --all --only <Section> --rebuild

# 4. CONVERGENCE GATE -- a second dry pass must want ZERO edits
#    Non-zero here means the writer disagrees with itself: STOP and diagnose,
#    do not trust the lint numbers that follow.

# 5. LINT
"$EXE" lint-all --db "$DB" ${CFG:+--config $CFG} > "$OUT" 2>&1
```

`--rebuild` (from scratch), not `--recompile`, when the point is a trustworthy
baseline. `--recompile` is for the fast inner loop.

## Classify

```bash
# by rule, descending -- the ranking that decides what to do next
grep -oE "\[(error|warning|info|hint)\] [a-z0-9-]+:" "$OUT" \
  | sed 's/:$//' | sort | uniq -c | sort -rn

# vendored vs. ours -- vendored code is NOT your quality signal
grep -c 'third_party' "$OUT"
```

Then sort every rule above ~20 findings into:

| Bucket | Meaning | Action |
|---|---|---|
| **Vendored** | in `third_party/` or another upstream drop | `exclude_paths` -- never restyle upstream |
| **Rule wrong** | the finding is not a defect | fix the RULE, add a fixture, record in `docs/BACKLOG-lint-false-positives.md` |
| **Threshold wrong** | "this function is big", hundreds of times | retune the threshold; do not restructure working code to satisfy a number |
| **Mechanical** | naming/casing with a deterministic fix | `--fix` on a branch, then build + battery |
| **Real debt** | leaks, swallowed exceptions, dataflow | fix per site, with judgement |

### Reading it honestly

- **Sample before you believe a big number.** Read 5 findings of any rule over
  100 before acting. `local-var-casing` looked like 212 real issues; 116 were
  the loop counter `i`, and its autofix wanted to rename `fi` to `Fi` -- which
  invents an `F` field prefix and makes the code worse.
- **One rule, one complaint.** If a message says "should be X **and not** Y", it
  is two rules wearing one id, and the noisy half will bury the useful half.
- **A security rule that is always wrong is worse than no rule.** Check every
  hit in that category by hand before reporting it. All four `hardcoded-credential`
  hits in this repo were a const named `AUTO_TOKEN` and the CLI's own help text.
- **Count vendored code separately, always.** It flatters or damns your number
  for work you will never do.

## Report

Give the deltas per rule against the previous run, not just a total -- a total
that moves 8 can hide +150/-158. Keep every `relint-<stamp>.txt`; the previous
file is the only baseline a delta can be computed against.

State explicitly which bucket each big mover landed in, and **whether the
convergence gate passed**. If it did not, say the lint numbers are provisional.

## Then

- Feed confirmed false positives back as rule fixes + fixtures. That is the
  point of the loop -- each pass should leave the linter sharper, not just the
  code cleaner.
- Keep `docs/AI-CODING-CONVENTIONS.md` in step with any naming-rule change, in
  the same commit, so generated code keeps matching the rules.
