# Three remaining raw-text scans that read comment content as code

Filed 2026-08-15 from a systematic audit of the whole `src\` tree for ONE bug
family. **The family is now NINE instances, SEVEN fixed** (#1 below closed
2026-08-16). The two that remain are #2 (transient, user-invoked) and #3 (left
alone on purpose), so this note is effectively discharged.

The three below are listed in the original priority order, with the reason.

## The family, for context

A scanner reads raw source text and mistakes comment or string content for code.
Fixed so far:

0. **`DRagLint.FormsMap`** -- fixed 2026-08-16, see the banner under #1 below.
   Adds one lesson the other six did not: **a scrub that fails open is
   indistinguishable from no scrub at all in a green suite.** Whatever replaces
   a raw read must be tested against the UNFIXED build, or the fail-open branch
   can swallow the entire fix without a single red check.
1. `DRagLint.Lint.SharedUnit.ScanHeader` -- the `dl:shared` reader. **This is the
   good example**: its unit header argues the case at length and ships a correct
   4-state machine.
2. `TReviewMarkers.MarkerBearingLines` -- `review-marker-unused` fired on prose.
3. `CollectCallIdents` / `CollectRaiseClass` (`Doc.Facts`) -- brace depth was a
   per-line LOCAL; prose became callees, and prose "we raise EFoo" fabricated an
   `<exception cref>`.
4. `MaskCommentsAndStrings` + `CheckUndeclared` (`AstChecks`) -- a raw regex over
   the whole file with no stripping at all.
5. **`ParseDprUses`** (`Index.Closure`) -- fixed 2026-08-15. Anchored `\buses\b`
   on UNSCRUBBED text, and its ad-hoc stripper handled braces only. A `.dpr`
   header comment containing the word "uses" anchored the search, and a
   commented-out member inside a real clause was harvested as a live unit --
   PHANTOM UNITS IN THE COMPILE CLOSURE, i.e. in project index membership.
6. **`ReadDeclLine`** (`Doc.Facts`) -- fixed 2026-08-15, at the choke point all
   directive detectors read through. `procedure Foo; // override in subclasses`
   documented Foo as an override; `// deprecated;` fabricated a `<deprecated>`
   tag.

All six now scrub with **one** implementation, `StripPasCommentsKeepLayout`
(`DRagLint.Lint.ProjectChecks.Parse`), except #1-#4 which carry their own
purpose-built state machines for reasons stated in place. Note that function
blanks comments and **preserves string-literal content** -- load-bearing, because
`deprecated 'use Bar instead'` needs its message.

---

## 1. `DRagLint.FormsMap.pas` -- forms-map launch/show detection  **[FIXED 2026-08-16]**

> **FIXED.** `ReadPasLinesScrubbed` is now the single `.pas` read behind all four
> scan sites; guarded by `tests\autotest\run_formsmap_comment_scrub.ps1` (20/20),
> which was **run red against the unfixed build first**. `FORMS_CSV_ALGORITHM`
> bumped 4 -> 5. `run_formsmap` and `run_formsmap_multidb` still green.
>
> **Two corrections to what is written below -- the harm was MISDIAGNOSED, and
> the fix was nearly a silent no-op.**
>
> **(a) A comment cannot invent a form edge.** The claim "wrong rows in the
> forms-map CSV" is false. The primary launch edges come from the AST-exact
> `refs` index, which never sees comment text, so a commented-out
> `TfrmX.Create` produces no ref and no edge -- the form stays `DEAD FORM`. The
> first fixture built for this note asserted exactly that and passed against
> the unfixed build, which is how the misdiagnosis surfaced.
>
> The reachable harm is one step later and narrower: **`CaptionForHandler` step
> (3)** (`:583`). When no control is bound directly to the launching routine, it
> text-scans the form's own `.pas` for callers of that routine and takes the
> FIRST match. A commented-out call therefore wins, and a **real** navigation
> edge is captioned with the **wrong button**. `IsLaunchLine`/`IsShowLine` at
> `ProcessSite` only ever *confirm* a line the index already pointed at, so they
> can suppress a real edge but not fabricate one. `BuildHookMap` Pass A can mark
> a routine a launcher off a comment, but that is inert unless a proc-var hook
> also names it.
>
> **(b) The re-split is where this gets silently disabled.** The first
> implementation split the scrubbed text with
> `Split([#10, #13], TStringSplitOptions.ExcludeEmpty)`. That treats a CRLF pair
> as two separators AND deletes every genuine blank line, so the scrubbed count
> can never reach `ReadAllLines`' count on any file containing a blank line --
> i.e. every real file. The fail-open branch fired every single time and the
> scrubbing was never once applied, **while the whole suite stayed green**,
> because falling open returns exactly the raw text the callers used to read.
> Split on `#10` only, keep empties, strip the `CR`, then truncate. The fixture
> keeps deliberate blank lines for this reason and says so in place.
>
> The design below is otherwise sound and was followed as written.

### Original note (kept for the record)

`IsLaunchLine` (:323) and `IsShowLine` (:330) are bare `Pos` over raw lines, and
the `.pas` reads that feed them (`TFile.ReadAllLines`, :537, :670, :769) do no
masking at all. So:

* `// FrmMain.ShowModal;` confirms a show site (used at :990/:994);
* a comment naming `TFrmFoo.Create` makes the enclosing routine a launcher (:931).

**Harm:** wrong rows in the forms-map CSV and wrong hook edges.

**Why not fixed here:** it needs a change at the READ sites, not a one-line
substitution, and the line COUNT must stay byte-identical to `ReadAllLines`
because FormsMap emits line numbers -- `StripPasCommentsKeepLayout` preserves
line breaks, but re-splitting the scrubbed text risks an off-by-one at EOF that
would silently shift every reported line. Worth doing carefully, not quickly.

**Fix:** one `ReadPasLinesScrubbed(APath)` helper used by every `.pas` read in the
unit; assert in a test that its line count equals `ReadAllLines`' for a file with
and without a trailing newline.

> **Design worked out 2026-08-16 (not implemented -- recorded so it is not
> re-derived).** The four `.pas` reads that feed launch/show/hook detection are
> **:537, :670, :769 and :822**; :822 is inside the cached `FileLines` closure,
> which is the natural choke point. Leave the others alone and say why:
> **:304 is a LINE COUNT and must stay raw**, :349/:435 are `.dfm`, :1261 is the
> `.dpr`, and :143 is the class-declaration scan (a separate question -- a
> commented-out class decl would mislead it too, but that is not this note).
>
> The off-by-one risk has a cheap structural answer rather than a careful one.
> Do NOT split the scrubbed text and hope the count matches:
>
> ```pascal
> Raw     := TFile.ReadAllLines(APath, TEncoding.ANSI);   // authoritative count
> Scrub   := StripPasCommentsKeepLayout(TFile.ReadAllText(APath, TEncoding.ANSI));
> // layout-preserving, so line i of Scrub IS line i of Raw
> if Length(ScrubLines) >= Length(Raw) then SetLength(ScrubLines, Length(Raw))
> else Exit(Raw);   // fail OPEN to raw text rather than shift every line number
> ```
>
> `ReadAllLines` drops the empty final element that a trailing newline produces
> and a naive `Split` does not -- that is the entire off-by-one. Taking
> `ReadAllLines`' count as authoritative and truncating to it makes the two
> indexings identical by construction, and the fallback guarantees that a
> surprise can only lose the scrubbing, never move a reported line.
>
> The test the note asks for still stands, and should assert the count parity on
> a file WITH and WITHOUT a trailing newline plus one whose last line is inside
> an unterminated `{` comment.

## 2. `DRagLint.Resolver.TypeAt.pas` -- hover type inference

`InferLocalVarType` (:221) with `ExtractDeclType` (:200) walks lines upward from
the cursor matching `Name: Type`, and matches inside comments too. A commented-out
declaration -- `// AButton: TSpeedButton` -- shadows the real one.

**Harm:** a wrong type in a hover. User-invoked and transient, which is why it
ranks below the two fixed today.

**Fix:** skip comment content while walking up. The upward walk makes a whole-file
mask the natural approach.

## 3. `DRagLint.CLI.pas` -- the `todos` verb (:4820-4847)

Has a same-line quote-parity guard (:4846) but no brace or star-paren state.

**Harm:** marginal -- a TODO inside a block comment is arguably still a TODO. Left
alone on purpose; listed so the audit is complete rather than because it needs
doing.

---

## Checked and CLEARED by the same audit

Recorded so nobody re-audits them: `Hover.Returns.TokenizeBody` (state declared
OUTSIDE the line loop, star-paren and doubled quotes handled),
`Doc.Harvest.ClassifyLine` (threaded `var AState: TLexState`),
`Preprocess.Tolerance.StripCodeLine` (threaded `TScanState`),
`Parser.DocComments.TDocCommentScanner.Scan` (5-state machine),
`Parser.Sql` (`StripCommentsAndStrings` applied before the CREATE regexes),
`Lint.ProjectChecks.Parse.ParseUsesFromContent` (scrubs first -- the template).
Also cleared as not-source-input: `Project.Resolver:621`, `Preprocess.Profile:130`,
`CompileCheck:429-477`, `Hover.Renderer:339`, `Index.Reconcile:246`,
`GitSince:212`, `Plugin.Editor:500` (JSON), `Plugin.StructureForm:547` (DB names),
`QueryRules:362` (AST capture text).

## The standing rule this produces

A new scanner over raw Delphi text must either scrub with
`StripPasCommentsKeepLayout` first, or thread comment state ACROSS lines -- never
declare it as a per-line local, which was the shared root cause of instances 3
and 5. Better still, use the tree-sitter AST, which is already available on every
one of these paths.
