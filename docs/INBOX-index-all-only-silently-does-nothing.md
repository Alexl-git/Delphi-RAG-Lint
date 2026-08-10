# INBOX -- `index --all --only <Section>` SILENTLY SUCCEEDS while indexing nothing

Filed 2026-08-10. Cost: one full invalid pipeline measurement (a reported lint
regression of +163 findings and a failed convergence gate that were both
artifacts, not results).

## Symptom

    C:\TEMP> drag-lint.exe index --all --only DragLint-Cli --recompile
    C:\TEMP>

Zero output. **Exit code 0.** The target `.sqlite` is not touched -- byte-identical
mtime before and after. Nothing anywhere says the section was not found, that the
manifest was empty, or that no work was done.

## Root cause

`--all` reads the manifest **relative to the EXE's OWN DIRECTORY**
(`RootDir: <dir of drag-lint.exe>\`). The deployed engine dir
`third_party\dll-win64\` holds `drag-lint.json`, so `--all` resolves 30 sections
there. A freshly BUILT exe in `src\cli\Win64\Debug\` has no `drag-lint.json`
beside it, so the same command resolves **0 sections** -- and reports success.

    # fresh build, no manifest beside it
    > drag-lint.exe index --all --dry-run
    Index manifest (dry-run):
      RootDir: C:\Projects\Delphi-RAG-lint\src\cli\Win64\Debug\
      OutDir:
      Sections to build: 0          <-- the only hint, and only with --dry-run

`--dry-run` DOES show `Sections to build: 0`. The real run prints nothing at all,
so the one diagnostic that exists is on the path a person takes when they already
suspect a problem.

## Why it is worth fixing rather than remembering

This is the ordered pipeline's load-bearing step. The documented order is
reindex -> autodoc -> reindex -> lint-all, and the ordering exists *specifically*
because running autodoc against a stale DB computes facts from stale data -- the
cause of the 514-finding regression recorded in
`docs\RESUME-2026-08-10-schema-v20-v21-and-doc-drift.md`.

A no-op reindex does not fail the pipeline. It degrades it into exactly the
broken order the pipeline was built to prevent, while every step still reports
success. Observed downstream effects, all of which looked like real regressions:

* `PASS-B PENDING EDITS: 641 across 45 file(s)` (the convergence gate; 0 expected)
* `doc-drift 13 -> 169`, of which 161 `managed facts block is out of date`
* `lint-all 2773 -> 2936`
* a constructor's caller list growing from 1 entry to 97, most marked ` ?` --
  i.e. the FABRICATED-CALLER shape that a previous session already fixed once,
  reappearing purely because the doc pass read a stale index

Every one of those numbers was an artifact. Confirmed by an A/B on identical
inputs (same file, same DB, both binaries): the real diff was **2 lines**.

## Suggested fix

1. `index --all` should print what it resolved (`N section(s) from <manifest>`)
   on the NORMAL path, not only under `--dry-run`.
2. **`--only <X>` matching no section must be an ERROR** (non-zero exit). A filter
   that selects nothing is a typo or a missing manifest, never an intent.
3. Resolving **0 sections** should warn loudly and exit non-zero -- "no manifest
   found beside <exe dir> and none in the CWD chain".

(3) alone would have turned a silently invalid 20-minute pipeline into an
immediate one-line failure.

## Workaround until then

Copy the engine dir's sidecars next to any freshly built exe before using `--all`:

    copy third_party\dll-win64\drag-lint.json  src\cli\Win64\Debug\
    xcopy /E /I third_party\dll-win64\rules    src\cli\Win64\Debug\rules
    copy third_party\dll-win64\*.dll           src\cli\Win64\Debug\

Then verify with `index --all --dry-run` that `Sections to build:` is non-zero
BEFORE trusting any pipeline run. Verbs that take an explicit `--db`
(`document`, `lint-all`, `doc-drift`) are unaffected -- only manifest-driven
`--all` resolution breaks.
