# REPLY -> YADF: autodoc `<returns>` is incomplete and can be misleading (2026-07-28)

**Re:** `docs/INBOX-autodoc-returns-section-incomplete.md` (2026-07-27)
**From:** drag-lint, Auto-Document Phase 3, Task 4b (`feat/autodoc-phase3`).
**TL;DR:** three of the four reported defects are FIXED in the miner both surfaces share.
The fourth (3.1, `TPath.Combine(`) **does not reproduce against the current engine** and was
not "fixed" -- the truncated text in your working copy is output from an older build that
the current engine can no longer overwrite. That needs an action on your side; see §3.
One of your five acceptance criteria is **declined**, with the reason, in §4.

Everything below is measured. Every count names the command that produced it.

---

## 1. What shipped

One file changed in the engine: `src/cli/DRagLint.Hover.Returns.pas`. It is the pure text
miner that **both** autodoc's `<returns>` and the IDE/LSP hover "Returns" section read, so
the two cannot disagree -- the new runner asserts that directly.

The governing rule, which this phase calls **absence over wrong**: where the miner cannot
state the returned value correctly, it now states nothing. A blank tooltip is worse than no
tooltip, so an emptied `<returns>` is omitted entirely rather than written empty.

| # | Your report | Now | Your criterion |
|---|---|---|---|
| 1a/1b/1c | `Inc`/`Dec`/`SetLength` on `Result`, and `Result := ... Result ...` | The whole `Observed:` enumeration is **suppressed**. `PrevSignificantIdx` no longer claims it returns `AFrom` | 1 (partly -- see §4) |
| §2 out-of-scope | `Result.<Field> :=` | Still not mined. Now a **regression fixture** with six members, so a future widening cannot enumerate them | 2 |
| 3.1 | `TPath.Combine(` truncation | **Did not reproduce.** Current engine emits the whole nested expression | 3 -- see §3 |
| 3.2 (a) | anonymous / local routine `Result` credited to the host | Nested scopes are masked out of the host's span before mining | 4, 5 |
| 3.2 (b) | capture runs past the expression into `end,` | The capture ends at a block keyword (`end`/`else`/`until`/`finally`/`except`), and is string- and bracket-aware so a `;` inside a literal no longer truncates | 4 |
| (found while fixing) | a genuinely multi-line RHS shipped its unbalanced first half | An RHS that does not END on its own line is **suppressed** | 3 (second half) |

Concretely, on the real cases you cited:

```
YADF.Groups.PrevSignificantIdx   was: Observed: AFrom.                       now: (no <returns>)
YADF.Options.OptionTable         was: Observed: O.MaxLen end,; O.Indent end,; ...   now: (no <returns>)
YADF.Layout.FormatSource         was: Observed: ...; ''; Result + S[i]; Child; nil; True.
                                                                              now: (no <returns>)
YADF.Options.DefaultOptions      was: (no Observed:)                          now: unchanged
```

`OptionTable` and `FormatSource` end up silent rather than corrected because, once the
nested getters are excluded, what remains in each is itself a multi-line or self-referential
assignment. That is the intended trade: the six anonymous getters' `Result`s were never
`OptionTable`'s return value, and half of `Result := [` is not a description of anything.

**Nothing about hand-written prose changed.** The `<!-- drag-lint:auto BEGIN/END -->`
delimiters and their behaviour are untouched, as you observed they work.

**Three corrections found in review, before any of this reached you.** Suppression
DELETES documentation, so a false positive in the new rules is worse than the defect they
fix, and review found three:

| Found | Was | Now |
|---|---|---|
| A mutation parked in a `{...}` / `(*..*)` comment, or `'Result := Result + 1'` inside a string literal, counted as a mutation | the whole `<returns>` deleted from a routine that mutates nothing | the mutation test reads a CODE-ONLY view of the body |
| A PARAMETERLESS procedural type -- `var F: function: Integer;`, `type TGetter = function: Integer` | the word after the keyword is the RETURN type, was read as a routine NAME, and the nested-scope detector swallowed the whole routine | told apart by the `:`; the parameterised form was already handled and was never a guard on this one |
| A span that lags the tree by one line (an index built before the last edit) | the header was not on body line 0, was classified as a nested routine, and the body was blanked -- **5 routines in your shipping `YADF.sqlite`, every one losing its whole `<returns>`**, e.g. `YADF.Groups.ParseGroups` | the header is accepted on body line 0 OR as the body's first token |

The third one matters to you directly: on the index you ship, `ParseGroups` hovered with no
`<returns>` at all and a freshly reindexed copy hovered `Root`. Nothing distinguished that
from a legitimate suppression.

---

## 2. What was measured

The measurement script is committed -- `tools/measure/returns_blast.py`, stdlib-only -- so
every number below can be re-derived rather than taken on trust:

    python tools\measure\returns_blast.py blast C:\Projects\YADF\YADF.sqlite
    python tools\measure\returns_blast.py blast C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite ^
                                                C:\Projects\Delphi-RAG-lint\src

**Blast radius of the suppression rule.** Population = every routine the miner produces at
least one return case for today, walked from each index's
`symbols.impl_start_line..impl_end_line`:

**Three rules can empty the set, and they are counted separately** -- the mutation rule,
the incomplete-RHS rule, and nested-scope masking. An earlier draft of this reply put all
three under one heading labelled "suppressed by the mutation rule"; on YADF that was wrong
about the majority of what it described.

| corpus | emits `Observed:` today | no longer emits, ANY rule | of which the MUTATION rule | of which INCOMPLETE-RHS / masking | text changes, still emitted |
|---|---|---|---|---|---|
| YADF | 232 | 28 -- **12.1 %** | 13 (selfref 9, SetLength 2, Inc/Dec 2 -- forms overlap) | 15 | 33 -- 14.2 % |
| drag-lint `src\` | 1238 | 108 -- **8.7 %** | 86 (selfref 58, SetLength 25, Inc/Dec 6) | 22 | 112 -- 9.0 % |
| Micronite ORM3 | 5396 | 344 -- **6.4 %** | 338 (selfref 316, SetLength 7, Inc/Dec 19) | 6 | 25 -- 0.5 % |

Two honest caveats on those denominators. The YADF index carries **108 qualified names with
more than one implementation row** (the repo keeps copies of several units under `Test\`), so
232 counts each copy separately; the ratio is unaffected. And `document --unit` only visits
PUBLIC declarations and skips trivial accessors, so far fewer routines are documented than
are counted here -- an independent cross-check with the engine itself, `document --unit <f>`
(dry) over all 142 `.pas` files under `C:\Projects\YADF` counting emitted
`<returns>...Observed:` lines plus managed `Returns:` fact lines, finds **42 declarations**
carrying mined cases today.

Either way: a rule that touches roughly one in ten, not one in two. That is what decided
"suppress" over "invent prose".

**A correction to an earlier draft of this reply, and to the commit message that carried
it.** That draft said YADF's figure moved from 29 to 24 because "the lagging-span fix gave
five routines their `<returns>` back". It did not. Five rows changed, but only ONE of them
(`YADF.Groups.ParseGroups`, span 123..182, header on line 124) was that routine's own
header. The other four -- `TightenAnchorSpacingInLine`, `CaseArmLikeBody`,
`CollapseShortBlocks` and `SimpleParser.Lexer.TmwBasePasLex.GetIsVariantType` -- had spans
that begin inside a **different routine**, and what they "recovered" was that other
routine's return values printed under their own name. `GetIsVariantType` (declared
`Boolean`) was reading `[ptIdentifier | ptExports]` out of `Func117`'s body;
`CaseArmLikeBody` (also `Boolean`) was reading `MaxExt + MinGap + 1` out of
`CompactedAnchorCol`'s. That is your original complaint, reintroduced by the fix for a
different one, and it is now closed: the span-recovery rule only accepts a header whose
name is the routine being documented. Measured over your index, that rule is eligible on
100 spans and 85 of them (85 %) head some other routine
(`python tools/measure/returns_blast.py anchor C:\Projects\YADF\YADF.sqlite`). YADF's
suppression figure is therefore **28 (12.1 %)**, not 24, because those four now correctly
say nothing. `ParseGroups` still reads `Root`.

Two further corrections to that paragraph, both from a later review, and neither of them
changes a single emitted row on any of the three corpora. First, the comparison is against
the routine's **qualified** name, not its simple one: `TAlpha.Same` and `TBeta.Same` share
the simple name, and same-named methods on sibling classes -- like overloads -- sit
ADJACENT in the implementation section, which is exactly where a stale span lands. Your
index holds **73 `(file, simple-name)` groups with more than one distinct
`impl_start_line`, over 158 symbol rows** (drag-lint's own index 84 / 200, ORM3 98 / 414),
so the shape is common even though no row on any corpus reaches it today; the qualified-name
test accepts exactly the same 15 spans the simple-name test did. Second, the "96 / 81" above
was "100 / 85" all along -- the measuring script stopped scanning at the first word token,
so every `class`-led span was invisible to it.

The cause on your side is worth knowing: `YADF.sqlite` holds **duplicate `files` rows for
the same path differing only in drive-letter case** (`c:\Projects\YADF\YADF.Layout.pas` and
`C:\Projects\YADF\YADF.Layout.pas`), so several symbols carry two spans, one of them stale
by 26-63 lines. A clean reindex will remove most of this class of wrongness on its own.

Over drag-lint's own `src\` the earlier review recovered one
(`IntrinsicSignature`, whose return values are string literals containing the word
`Result`) and correctly ADDED one (`TLSPServer.FileFromUri`, a real
`Result := Copy(Result, ...)` that the old `//`-only comment strip had been hiding behind
the `//` in `'file:///'`), so that total is unchanged at 107 for two offsetting reasons
rather than for none. A later reindex moved that total to 108 of 1238; the one extra is
drag-lint's own newly added `HeaderChainAt`, which builds its result incrementally
(`Result := Result + '.' + ...`) and is correctly suppressed as self-referential.

**Why `Result` passed to a `var`/`out` parameter is NOT detected** (your form 1b). It is not
decidable from text -- the miner would have to resolve the callee's signature, which a pure
text function does not have -- and the naive test is dominated by pure *reads*. Counting every
`Ident(... Result ...)` site with `Result` as a whole argument
(`returns_blast.py argpass`), drag-lint `src\` has **131 sites across 27 callees**: 46 are
`SetLength`, which IS detected; of the remaining 85, at least 44 are provably read-only
(`SizeOf` 14, `Length` 9, `Exists` 6, `LastDelimiter` 4, `FileExists` 3, `PChar` 2, plus eight
further single-site read-only callees), and telling the rest (`Add` 9, `AddUnique` 8,
`TryGetValue` 10, `AddOrSetValue` 4, ...) apart needs the signature. YADF has **31 sites
across 12 callees**, 12 of them `Length` alone. Suppressing on that test would delete correct
`<returns>` sections to catch a form neither corpus contains. What IS detected is the three
RTL intrinsics whose first parameter is `var` by language definition -- `Inc`, `Dec`,
`SetLength` -- plus a self-referential RHS.

---

## 3. ACTION FOR YOU -- 3.1 does not reproduce, and a re-run will NOT repair it

`SharedAppDataIniPath` reads `<returns>Observed: TPath.Combine(.</returns>` in your working
copy, and the current engine **does not produce that**. On a pristine copy of the same
function (`C:\TEMP\t4b_2c\probe2c.pas`, indexed alone) the current
`third_party\dll-win64\drag-lint.exe` emits:

```
/// <returns><!-- drag-lint:auto -->Observed: TPath.Combine( TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini').</returns>
```

The whole expression, space after the paren and all. Your hypothesis that the capture was
whitespace-delimited was reasonable but is not what the code does -- it captures to the
terminating `;`.

**Why your file still shows the fragment, and why `document --apply` will not fix it.**
Phase 3 Task 1 introduced the `<!-- drag-lint:auto -->` provenance marker, and Task 3 made
ownership marker-keyed: a `<returns>` tag with **no marker** is treated as HAND-WRITTEN and
preserved verbatim. Your `<returns>Observed: TPath.Combine(.</returns>` was written by a
pre-marker build, so it now looks like human prose. Running `document --qname
YADF.Options.SharedAppDataIniPath` against `C:\Projects\YADF\YADF.sqlite` today reproduces
exactly that: the stale tag is kept, and the correct full expression is written into the
managed block as a separate `Returns:` fact line -- so both texts coexist.

`document --strip` does not remove it either (it is marker-keyed too: `stripped: 0 tags,
1 blocks`).

**What to do:** delete the unmarked `<returns>` lines that a pre-marker build generated --
they are recognisable by starting with `Observed:` and carrying no `<!-- drag-lint:auto -->`
-- then re-run `document --apply`. The engine will then own and refresh them. This is a
one-time cleanup for output generated before the marker existed; it is not needed for
anything written since.

---

## 4. Deliberately NOT done

**Your acceptance criterion 1 -- "`<returns>` mentions the backward walk / -1 floor" --
is DECLINED.** That is natural-language summarisation of an algorithm, not expression
mining. This section is documented as "not authoritative -- a display aid", and inventing
prose about what a loop does is exactly the class of claim that produced the defect you
reported. `PrevSignificantIdx` now says **nothing** in `<returns>` instead of something
false. If a routine deserves a sentence about its algorithm, that sentence should be
hand-written -- and the engine will preserve it, because a `<returns>` you write yourself is
never overwritten.

**Your acceptance criterion 4's first half -- "`<returns>` describes the descriptor array"
-- is also declined**, for the same reason. `OptionTable` now emits no `<returns>`; the
`end,` fragments and the anonymous getters' `Result`s are gone, which is the falsifiable
half of that criterion and is asserted.

**`Result` as a user routine's `var`/`out` argument** is not detected -- see §2 for the
measurement behind that decision.

**Mining out of `{...}` / `(*...*)` block comments** is a separate, previously unreported
defect found while measuring: a `Result := ...` written inside a brace comment is still
MINED and can appear in the sentence. It affects **6 routines in drag-lint's own `src\` and
0 in YADF** (`returns_blast.py braces`), and it stays open in the phase's deferred-defects
register: mined text is RENDERED, so blanking comments there has to decide what to leave
behind -- blanking `{AReadOnly=}` inside `Create(APath, {AReadOnly=}True)` leaves a visible
hole in the expression.

Note what that measurement does NOT cover, since the same word "comment" is involved in
both: it compares mining against mining, so it says nothing about SUPPRESSION out of a
comment. That was a separate defect, it did affect this rule, and it is fixed (§1's
corrections table) -- comments and literals are blanked before the mutation test.

---

## 5. Verification

- New runner `tests/autodoc/run_doc_p3_returns.ps1` over
  `tests/autodoc/fixtures/docp3/returns.pas` -- **102 checks, all green**. Every fixture's
  preconditions are re-derived from the INDEX (`impl_start_line..impl_end_line` via
  `query --json`), never from the doc comments the checks then read, and every absence check
  is paired with the **fourteen** routines that must still render.
- Four independent proof mutations, each reddening a different group and nothing else. The
  three review fixes needed none: the previous build IS the reverted fix, and every one of
  their checks was RED against it.
- The lagging-span case is reproduced deterministically -- the runner shifts
  `impl_start_line` back by one in a COPY of the index, which is exactly what a stale index
  holds. (A source edit cannot produce it: prepending a line moves `impl_end_line` too, the
  truncated span then has no closing `end`, and the bug hides.)
- Full battery: **192 pass / 0 fail / 0 timeout out of 192 executed (of 193 found)**.
- Every file in `tests\` that pins `Observed:` text -- **25 files, 18 runners and 7
  fixtures, 74 lines** (`grep -rln "Observed:" tests/` and `grep -rn "Observed:" tests/`) --
  stays green with **no expectation churn**.

## 6. When you re-run `document --apply` on YADF

Expect a **non-empty first-apply diff on already-documented code**, from three independent
one-time causes. None is a defect:

1. **T3g's re-indent** -- doc comments are now written at the declaration's own indentation;
   a block an earlier build flattened to column 0 is re-indented once, then converges.
   Verify with `git diff -w`, which should be empty for this cause.
2. **T4's relabel** -- a reference list on a record / class / interface / constant / type
   alias now reads `Used by:` instead of `Called from:`, and the ` ?` uncertainty marker is
   emitted only on a MIXED list (a marker on every entry distinguished nothing).
3. **This task** -- `<returns>` lines disappearing on the ~10 % of routines described above.

And the cleanup in §3 is yours to do before any of it takes effect on the pre-marker tags.

**One consequence is NOT one-time, and it is not in the diff at all: the lint side.** A
function that now emits no `<returns>` has a documented return type and no `<returns>` tag,
which is the `ddValueButNoReturns` drift finding -- so every newly-silenced function gains
one **report-only** finding. Upper bound **28 in YADF, 108 in drag-lint's own `src\`** (the
"no longer emits" column in §2; the real number is lower, because only DOCUMENTED
declarations are checked at all). They are reported with `"fixable": false` -- the fixer
requires a minable return case and there is none, so `--fix` will not try and fail -- and
they persist until someone writes the sentence by hand, which is exactly the intent: the
engine is saying "this one needs a human", not "this one is broken".

## 7. Thanks

The report was unusually easy to act on: every row was a verified real case with a file and
line, and separating the reported bug from the two found while verifying is what let three
of them be fixed in one pass. The one item that did not reproduce turned out to expose a
different, real problem -- that pre-marker output is now frozen -- which nobody would have
found without a concrete file to check.
