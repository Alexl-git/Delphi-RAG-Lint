# Group C -- the plan

Written 2026-08-16 (session 22), at the owner's request, after Groups A and B
were worked. Group C was classified *"not defects, leave"*; this turns each of
the five into a decision with a next action, so nothing here needs re-deriving.

Four of the five were measured this session. **Two are now unblocked and ready
to build, two are cheap, one is genuinely blocked.** Ordered by value per unit of
work.

---

## 1. `rule-hardening-plan-2026-08-13` -- DO THIS FIRST

Not a defect report: it is the owner's own question (*"Can we harden our rules to
get rid of these false positives?"*) already answered with a 10-row table
ordered by findings-removed per unit of work. The analysis is done; what is
missing is execution.

**Why it leads:** it is the only Group C item that directly serves the standing
rule that *a finding count in the thousands IS the defect*. Its top rows are the
cheapest false-positive removals available anywhere in the backlog.

| do | rule | findings | cost | why now |
|---|---|---|---|---|
| 1 | `sql-injection-concat` | 1+ | **XS** | regex only -- require TWO distinct SQL tokens, or a leading SQL verb. Today the word `" from "` in an English sentence trips it. |
| 2 | `used-before-assignment` | 7 | **S** | an `out` argument is being counted as a READ; the signature is already indexed. Also closes the remaining half of Group A's `used-before-assignment` note. |
| 3 | `object-leak` (A) | ~15 | **S** | the guard is the NEXT statement; needs an AST sibling check, which the checker already walks. |
| 4 | `field-name-prefix` | 6 | **S** | a DFM heuristic firing on a hand-written class; policy call. |

Stop after row 4 and re-measure before committing to rows 5-10 (`try-except-swallowed`
at 38 is the biggest prize but needs a policy decision about what "handled"
means, and that is an owner question, not an engineering one).

**Each row needs a positive control.** Every one of these narrows a rule, and a
narrowed rule that fires on nothing looks identical to a fixed one.

---

## 2. `exception-class-unit-and-generated-exception-types` -- BUILD STAGE 1

**Measured this session, and the objection did not survive.** The note's own
design question 5 said *"measure the distinct-message count on ORM3 before
committing -- if it is 400, the feature is wrong as stated."*

| | count |
|---|---|
| LIVE `raise Exception.Create` sites in ORM3 | **89** |
| distinct messages | **64** |
| after normalization | **63** |

64, not 400. And design question 1 (near-duplicate churn) collapses to a single
pair, `'LookupAccountName failed: '` vs `'...: %s'`.

**Action: build Stage 1 only** -- a config key naming the project's exceptions
unit, and `raise-bare-exception` reporting which existing class fits (or that
none does). It is read-only and cannot damage anything, and the note estimates
it converts most of the 19 `raise-bare-exception` findings from un-actionable to
actionable.

**Do NOT start Stage 3** (generating classes from message text). Design
questions 2, 3 and 4 -- where the static prefix ends, hierarchy, and who owns
the file -- are untouched and still gate it.

**One hard constraint the measurement exposed:** the implementation must read the
AST, not the text. A naive text scan reports 98 sites; **9 are commented out**,
and Pascal doubled-quote escapes (`'Can''t ...'`) truncate a naive literal
extraction mid-message.

---

## 3. `converter-editor-phase-g-engine-findings` -- TAKE 2.11 NEXT

Its one concrete engine ask (`convert-validate` rejecting `#mapping`/`#apply`) is
**done this session**. What remains is findings 2.4-2.11, which the note itself
asked to be re-triaged rather than taken as filed.

**Next: 2.11, strong type aliases (`T = type string`) are never indexed.** It is
marked HIGH, it is *the same defect class as 2.1* which has already been fixed
(the grammar parses the declaration, no emitter claims it, no symbol row is
written), so the fix is likely near-identical and in the same place. Its cost is
concrete: `TFileName`, `TCaption`, `TDate`, `TTime` have no declaration row, so
every type-aware consumer must decline matches that are legal Delphi.

Then 2.4/2.5/2.10 together -- they are one theme, *"the query API invites a
caller bug"*: `--name` is substring, case-sensitive, and resolves ties by
non-contractual row order. An `--exact` flag plus a documented ordering closes
all three.

2.6/2.7/2.8 are convenience and documentation; batch them last.

**Not a defect and must not be filed as one:** `convert-apply` cannot evaluate
`#mapping`/`#apply`. That is spec G6.1 and deliberate.

---

## 4. `yadf-share-review-marker-hash` -- FREEZE, THEN SHIP VERIFY-ONLY

**Re-counted this session and the economics inverted.** At filing there were 27
markers in drag-lint and 0 in YADF. Now:

| repo | markers |
|---|---|
| Delphi-RAG-lint | 43 |
| YADF | 147 |
| DataCopy | 59 |
| **total** | **249** |

The note's "changing the normaliser is nearly free right now" window has
**closed**. Treat `NormalizeLine` as frozen unless there is a correctness
reason, and budget a 249-marker re-stamp if it ever changes.

**Action, in order:**

1. **Decide the sharing mechanism.** Prefer the search path (YADF adds
   `src\lint` to its unit path) if YADF's build can reach across repos --
   single source of truth, zero drift. Otherwise a vendored copy PLUS a battery
   test asserting the two files are byte-identical. Do not vendor without that
   test; drift in a hash function is invisible until it produces false staleness.
2. **Ship `HashWindow` with it.** The hash changed after this note was filed:
   lone-keyword anchors now hash a bounded WINDOW, not a single line. A copy
   missing `HashWindow`/`NormalizedIsLoneKeyword` will disagree on exactly the
   anchors that motivated the change, and the disagreement will look like stale
   reviews rather than a version skew.
3. **VERIFY and WARN, never rewrite** -- unchanged, and the note argues it well:
   a correct normalisation-invariant hash gives YADF nothing to refresh, so a
   refresh feature would fire only where refreshing is wrong.

YADF has no copy yet, so nothing can disagree today. Note however that YADF
already holds 147 markers written INTO it by drag-lint -- it is a consumer of
the hash without owning the function, which is the situation this closes.

---

## 5. `ide-lsp-ram-and-shim-todo` -- GENUINELY BLOCKED, TOOLING IS READY

§1.1's ask is **done this session**: folded into the union design, where it
corrected a real error -- section 4.4 listed `references` as an *overlapping*
request kind to arbitrate, when DelphiLSP does not advertise `referencesProvider`
at all. drag-lint is the sole provider for `textDocument/references` and
`workspace/symbol`; there is nothing to merge.

TODOs 3 and 4 cannot be advanced here by construction:

* **TODO 3** (design-time package RAM audit) needs a running IDE to enumerate
  loaded modules. This is the real RAM lever -- 305 BPLs, DevExpress design-time
  dwarfing anything LSP-related -- and it is ordinary supported configuration.
* **TODO 4** (superset shim) is gated on TODO 2b's error text, which needs an
  IDE start.

**What was done instead:** all four `tools\lsp-diag\*.ps1` scripts were verified
to parse cleanly (parse-only -- deliberately not executed, since `arm` mutates
the registry and User environment). This matters because 2b gets exactly ONE
shot at the next IDE start, and a capture script that fails then wastes the whole
opportunity.

**Action: none until an IDE session is available.** When one is, run
`arm` -> reproduce -> `collect` -> `disarm` FIRST, before anything else, because
everything downstream depends on that error text. Do not design the shim before
reading it: if the failure is a config/handshake mismatch, a relay reproduces it
exactly, because it forwards the same bytes.

---

## What this plan deliberately does not do

Nothing here proposes work on `loader2019-formcreate-inifile-leak` (a correct
finding about an EXTERNAL project -- fixing it is the owner's call, not engine
debt) or on the Group B items that need a 1.4 GB corpus or an hours-long
rebuild. Those are tracked in their own notes and in `INBOX-INDEX.md`.
