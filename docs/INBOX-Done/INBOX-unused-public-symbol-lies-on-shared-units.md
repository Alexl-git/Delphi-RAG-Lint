> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16: shared-unit findings now say "not referenced within this project", name the siblings from the dl:shared header, and drop to hint. NOT suppressed -- the one genuine finding lived in the same shared unit. Guarded by run_unused_public_shared_unit.ps1 (11/11, both branches).

# `unused-public-symbol` calls shared-unit API "dead" -- 5 of 6 YADF findings are false

Filed 2026-08-16 (session 21) from a false-positive recheck of the four consumer
projects. **Largest single FP source across all of them.**

Class: **wrong** (the finding is false AND its message asserts something the
tool cannot know).

## Measurement

`lint-all --project` on the three YADF projects reports 6
`unused-public-symbol` findings. Caller refs, counted across the three sibling
project DBs (`YADF`, `YADFOT`, `YADFSetup`):

| symbol | caller refs | verdict |
|---|---|---|
| `SaveOptionsToIni` | **10** | false |
| `EncodingOf` | 2 | false |
| `DetectSourceEncoding` | 2 | false |
| `EmitTokens` | 1 | false |
| `RenderGroupTree` | 1 | false |
| `OptionsHelpText` | 0 | **genuine** |

DataCopy's 3 findings are all genuine (0 callers in any DataCopy DB), so the
rule is not broken everywhere -- it is broken **on shared units**.

## Cause

`DRagLint.Lint.ProjectRules.pas:988` emits

> `Exported routine %s has no references in the index -- possible dead public API`

`IsReferenced(Sym)` asks ONE project's index. YADF, YADFOT and YADFSetup are
three projects over a shared source folder, so a routine defined in a shared unit
and called only from a sibling project has no references *in this DB* and is
reported as dead public API. The message states an index fact but draws a
codebase conclusion, and the two are not the same thing under the authoritative
one-project-plus-library DB scheme (owner ruling 2026-08-13).

## The fix, and why NOT to suppress

**The infrastructure already exists.** Every affected unit carries a `dl:shared`
header naming its owning projects:

```
unit YADF.Groups;   // dl:shared YADF, YADFOT, YADFSetup
unit YADF.Debug;    // dl:shared YADF, YADFSetup
unit YADF.Guard;    // dl:shared YADF, YADFOT, YADFSetup
```

`DRagLint.Lint.SharedUnit.ScanHeader` already parses this and is the "good
example" scrubber cited elsewhere in the backlog.

**Do not simply suppress the rule on shared units.** The one GENUINE finding
(`OptionsHelpText`) lives in `YADF.Options.pas`, which is itself shared -- a
blanket skip would hide it along with the five false ones, trading a false
positive for a false negative in the same file.

Instead **keep the finding and make the message true**, e.g.:

> `Exported routine OptionsHelpText is not referenced within project YADF; this
> unit is shared with YADFOT, YADFSetup -- check there before deleting.`

That is honest, still actionable, and stops the finding reading as "safe to
delete". Optionally drop severity to `hint` on shared units so a true-zero run
is not blocked by a question the single-project index cannot answer.

**Better still, if cheap:** when the `dl:shared` header names sibling projects
whose DBs are resolvable from the manifest, consult them for references before
emitting. That would have answered all six correctly and automatically. It is a
deliberate, bounded exception to the "one project DB" rule -- justified because
the unit itself declares the other projects by name, so nothing is guessed.

## Guard it with the split that exists

`YADF.Options.pas` is the ideal fixture: it contains BOTH a false case
(`SaveOptionsToIni`, 10 sibling refs) and a genuine one (`OptionsHelpText`, 0
refs anywhere) in the same shared unit. A guard that only checks the false one
would pass with the rule switched off.
