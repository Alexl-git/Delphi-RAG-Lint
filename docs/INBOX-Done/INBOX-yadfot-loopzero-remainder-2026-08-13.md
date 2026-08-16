> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** RETIRED 2026-08-16 as STALE. Its itemised remainder predates two rule fixes and the bare-except marker restamp; YADFOT now measures 6 findings, 0 errors. Re-derive from a fresh run rather than reading this list.

# YADFOT LoopZero remainder -- what is left, and why none of it may be `allow`ed

Session of 2026-08-13. YADFOT went **35 -> 10**. This note accounts for the 10.

The standard (owner ruling 2026-08-12) is fix-the-rule > fix-the-source >
`allow`, and **never `allow` something in class 1**. Everything below is class 1
(a rule defect) or blocked on a ruling, which is exactly why it is filed here
instead of being marked reviewed. Marking these `dl:ok` would record something
untrue about the code, permanently, with a hash attached.

## Resolved this session, for context

| Rule | n | Outcome |
|---|---|---|
| `local-var-casing` | 7 | source fixed by hand (YADF `91d1f21`) -- NOT autofixable, see INBOX-field-name-prefix-fixable-flag-lies.md |
| `try-except-swallowed` | 5 | **rule fixed** -- a call carrying the exception's text is reporting |
| `try-except-swallowed` | 10 | `allow`ed -- genuine deliberate swallows on IDE shutdown/registration paths |
| `doc-drift` | 2 | autofixed, but see the oscillation warning below |

## 1. `used-before-assignment` x2 -- an out-buffer counted as a read

    YADFOT.Wizard.pas:243  Got:= Reader.GetText(Pos, @Chunk[0], ChunkSize);
    YADFOT.Wizard.pas:247  Move(Chunk[0], Utf8Bytes[CurLen], Got);

`Chunk: array[0..ChunkSize-1] of AnsiChar` is an OUTPUT buffer. Line 243 takes
its ADDRESS and hands it to a callee that fills it; 247 reads it only after that
call. Neither is a read of an unassigned value.

**This should already work.** `CollectReadsAndCallDefs`'s own doc-comment
(`DRagLint.Analysis.Flow.Lattices.pas:784`) says it "treats call arguments / `@x`
as POSSIBLE defs (FP-safe), not reads". So the intent is correct and something
downstream is not honouring it -- candidate causes: the address-of is applied to
an ARRAY ELEMENT (`@Chunk[0]`) rather than a plain var, so `LeftmostBaseVar` may
not resolve it; or the `repeat..until` back-edge replays the read before the def.
Not chased -- it is in the CFG lattice, and destabilising definite-assignment
late in a session to clear 2 findings is a bad trade.

Related, already filed: `INBOX-group-E-dataflow-rules-are-majority-false.md`.

## 2. `object-leak` x2 -- both provably wrong

    YADF.Tokens.pas:282   Lex:= TmwPasLex.Create;   -> freed at :322 `finally Lex.Free`
    YADF.Groups.pas:200   Cur:= TGroup.Create(..., Cur)

Tokens: the guard is the NEXT statement (`try` immediately follows), which is the
already-catalogued cause -- rule-hardening plan item 2, "~15 findings, AST
sibling, cost S".

Groups: ownership is TRANSFERRED. `TGroup.Create` ends with
`if Assigned(AParent) then AParent.Children.Add(Self)` (`:124`), and
`TGroup.Destroy` frees `Children` (`:130`). The tree owns it. This is plan item 6
(transfer detection) in a non-VCL form -- the transfer is a constructor argument,
not an `Owner:` property, so a VCL-shaped check will not catch it.

## 3. `length-zero-compare` x1 -- a dynamic array read as a string

    YADF.Layout.pas:2535   if (Length(W) = 0) or (W[0] <> 'then') then

`W` is indexed and compared against a string, so it is an ARRAY OF string, not a
string. The advice ("prefer `X = ''`") would not compile. Plan item 7; needs the
declared type, cost M.

## 4. `compiler-magic-comments` x1 -- prose about TODOs is not a TODO

    YADF.Guard.pas:19   comments (block labels, --d10 TODO flags) but

The word TODO appears inside a sentence DESCRIBING what the guard preserves.
There is no TODO item here. A narrow fix: require the marker to open the comment
or be followed by `:`/`(`, rather than matching the bare word anywhere in prose.
Note `tests\autotest\run_magic_comment_boundaries.ps1` exists and passes, so the
boundary definition is deliberate -- check it before changing.

## 5. `unit-too-large` x1 -- genuine, and CANNOT be acknowledged

    YADF.Layout.pas -- 5620 lines, threshold 2000

The finding is TRUE. Splitting the formatter engine is a real refactor, out of
scope for a lint sweep. But it also cannot be `allow`ed:

    > drag-lint allow YADF.Layout.pas --fix-line 1 --fix-rule unit-too-large
    Refusing to write: a dl:ok marker on ...:1 would not parse back (the line is
    inside a block comment or a string literal ...)

The refusal is CORRECT behaviour -- a marker there would be invisible and the
finding would keep firing. But it leaves a file-level finding with no way to
record a review. **This is the real gap: `allow` has no anchor for file-level
rules.** The suggested alternative (raise `threshold` in config) is not a review,
it is hiding the number, and it would silence every other unit too.

## 6. `unused-public-symbol` x2 -- BLOCKED on the DB-role ruling

    YADF.Tokens.pas:90    EmitTokens
    YADF.Options.pas:382  OptionsHelpText

Both are reachable from `YadfMain.pas`, which is a member of YADF.dproj and
YADFSetup.dproj but NOT of YADFOT.dproj. So within YADFOT's compile closure they
genuinely have no caller, and the finding is a true statement answering the wrong
question. Plan item 9 (multi-DB reachability); the resume doc's standing
instruction is explicit: **do NOT `allow` these.**

## 7. Standing warning -- `doc-drift` OSCILLATES between the three projects

Measured this session, not theorised. Autofixing YADFOT's 2 doc-drift findings
took YADFOT 12 -> 10 and pushed **YADFSetup 12 -> 14**: the regenerated
`Used by:` line dropped `declaration (YADF.Debug.pas)`, because YADF.Debug is a
member of YADF/YADFSetup but not of YADFOT.

Every affected line carries `(+N more)`. The shared-unit merge refuses truncated
lists (a window onto a list is not the list), so these cannot converge while the
lists truncate. LoopZero's step-2 guard applies: autodoc is OUT of the loop.

The recorded remedy needs an owner decision: raise `docs.max_callers` (manifest,
currently 5) above the shared units' real caller counts so nothing truncates, OR
teach the merge to reconcile truncated lists by count.
