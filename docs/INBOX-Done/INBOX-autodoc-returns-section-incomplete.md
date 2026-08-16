> # CLOSED 2026-08-16 (session 22) -- DOES NOT REPRODUCE. Fixed since filing.
>
> Re-measured against current code on a scratch fixture reproducing
> `PrevSignificantIdx` exactly (seed + `Dec(Result)`), and against the real
> `YADF.Groups.PrevSignificantIdx` in `C:\Projects\YADF\_D-RAG\YADF.sqlite`.
> Today's engine emits the declared-type fallback
> `&lt;returns&gt;&lt;!-- drag-lint:auto type --&gt;Integer&lt;/returns&gt;`, NOT the misleading
> `Observed: AFrom.` this note reported.
>
> * Main defect: fixed by `MineReturnExpressionsEx` bailing on a mutated Result
>   -- `src\cli\DRagLint.Hover.Returns.pas:1024`, `if HasResultMutation(Code) then Exit;`
>   ("absence over wrong": a mutated Result makes every whole-Result assignment
>   a mere seed).
> * Sub-issue 3.2 (a nested anonymous method's `Result` leaking into the
>   enclosing routine) is fixed by `MaskNestedRoutines`, `Hover.Returns.pas:1019`
>   -- verified on a fixture matching `OptionTable`'s shape; no leaked `end,`
>   fragment.
> * Sub-issue 3.1 (truncation at nested `TPath.Combine(`) does not reproduce
>   either; the full nested expression is emitted.
>
> **The stale text still sitting in `C:\Projects\YADF\YADF.Options.pas:364,430`
> is old output from before these fixes and has simply never been regenerated.**
> It is not evidence of a live defect -- regenerating those two blocks clears it.
>
> What remains is a design tradeoff, not a bug: the engine falls back to
> type-only rather than narrating the walk. If that is wanted, it is a feature
> request and needs its own note.

# INBOX: autodoc `<returns>` is incomplete -- only whole-`Result` assignments are seen

- **From:** YADF (Alexander Liberov) -- reported 2026-07-27
- **Affects:** autodoc `<returns>` generation; the same text shows up in Help Insight
  tooltips / LSP hover popups, so a wrong value is read by humans many times per day.
- **Severity:** correctness. The generated sentence is not merely incomplete, it is
  actively misleading -- it names a value the function provably does not return.
- **Evidence base:** `C:\Projects\YADF` (index `C:\Projects\YADF\YADF.sqlite`), which
  the autodoc pass has already run over. Every row below is a verified real case,
  not a constructed one.

---

## 1. The reported case

`C:\Projects\YADF\YADF.Groups.pas:100-105`

```pascal
function PrevSignificantIdx(const ATokens: TTokenList; AFrom: Integer): Integer;
begin
  Result:= AFrom;
  while (Result >= 0) and (ATokens[Result].Kind in [ptSpace, ptCRLF, ptCRLFCo]) do
    Dec(Result);
end;
```

Generated `<returns>` names only `AFrom` -- the **seed** value. But `AFrom` is
precisely the one value this function returns only in the degenerate case where the
loop body never runs. The whole point of the function is `Dec(Result)`: it walks
backwards to the previous significant token, or to -1.

So the doc says "returns AFrom" for a function whose job is to return something
*other than* `AFrom`.

**Root cause (hypothesis):** the extractor collects `Result := <expr>` assignments
and nothing else. Any other way of mutating `Result` is invisible to it.

---

## 2. Generalisation -- every way `Result` can change

The reporter's framing was right: "there might be similar situations where the
result is modified inside a call." There are, and they are already in the corpus.
These three forms all mutate `Result` at object size and must feed `<returns>`.
One further form must be deliberately EXCLUDED -- see immediately below the table.

| # | Form | Verified example | Currently generated | Should be |
|---|------|------------------|---------------------|-----------|
| 1a | `Inc(Result)` / `Dec(Result)` | `YADF.Groups.pas:104`, `YADF.Layout.pas:929`, `:4275`, `:4282` | seed value only | seed + the mutation |
| 1b | `Result` passed as a `var`/`out` argument | (not yet seen in YADF; include for completeness) | presumed missed | mutation via callee |
| 1c | `Result := Result <op> x` accumulator | `YADF.Layout.pas:99` lists a bare `Result + S[i]` | leaks an intermediate | accumulation, not a step |

### Explicitly OUT of scope: member-level assignments

`Result.<Field> := ...` / `Result.<Prop> := ...` must **not** be enumerated in
`<returns>`. Those assignments *form* the result, they are not return values, and
listing them does not scale: `YADF.Options.pas:128` `DefaultOptions` populates 42
fields in a row, so enumerating them would bury the section in noise and drown any
real signal.

The rule the reporter asks for: **only object-sized (whole-`Result`) assignments
belong in `<returns>`.** Where the return type is a complex record/object, report
the whole-object assignments and leave field construction to the body.

Consequence, so it is not "fixed" the wrong way: a function that *only* populates
members -- `DefaultOptions`, `LoadProfiles` -- legitimately has no return
expressions to list, and its currently empty `<returns></returns>` is **not** a bug
under this rule. Whether to emit an empty tag at all, or describe the declared
return type instead, is your call.

---

## 3. Two further `<returns>` defects found while verifying

These are independent of the reported bug -- separate triage, same feature. Both
were found by reading the already-generated output in the same repo.

### 3.1 Expression capture truncates at whitespace inside a call

`YADF.Options.pas` -- `SharedAppDataIniPath`:

```pascal
Result:= TPath.Combine( TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini');
```

Generated: `<returns>Observed: TPath.Combine(.</returns>` -- cut off at the open paren.

The neighbouring `ProfilesIniPath` captures **correctly**:

```pascal
Result:= TPath.Combine(ProfilesDir, 'profiles.ini');
```
-> `<returns>Observed: TPath.Combine(ProfilesDir, 'profiles.ini').</returns>`

The only difference between the two is the **space after `(`**. That strongly
suggests the capture is text/whitespace-delimited rather than balanced-paren aware.

### 3.2 Nested / anonymous routine `Result`s are attributed to the enclosing routine

`YADF.Options.pas` -- `OptionTable: TArray<TOptInfo>` generated:

```
<returns>Observed: O.MaxLen end,; O.Indent end,; O.TabWidth end,; O.ReflowLines end,;
                   O.TrimTrailing end,; O.MaxBlankLines end,.</returns>
```

None of those are `OptionTable`'s return value. They are the `Result`s of **inline
anonymous getters** in the descriptor table:

```pascal
MakeOpt('MaxLen', ..., function(const O: TYadfOptions): Variant begin Result:= O.MaxLen end,
                       procedure(var O: TYadfOptions; const V: Variant) begin O.MaxLen:= V end),
```

Two bugs stacked: (a) an anonymous method's `Result` is credited to its enclosing
function, and (b) the captured text runs past the expression into `end,`, leaking
raw syntax into prose. `YADF.Layout.pas:99` (`FormatSource`) shows the same thing --
its `<returns>` lists `Result + S[i]`, `Child`, `nil`, `True`, all harvested from
nested helpers.

---

## 4. Suggested acceptance criteria

1. `PrevSignificantIdx` -- `<returns>` mentions the backward walk / -1 floor, not
   just `AFrom`.
2. `DefaultOptions` and `LoadProfiles` -- member-level `Result.<Field> :=`
   assignments do **not** appear; 42 field names must never be enumerated.
3. `SharedAppDataIniPath` -- the full nested `TPath.Combine(...)` expression, not
   `TPath.Combine(`.
4. `OptionTable` -- `<returns>` describes the descriptor array; no `end,` fragment
   and no anonymous-method `Result` appears in an enclosing routine's docs.
5. `Result` scope is per-routine: a nested/anonymous routine's `Result` belongs to
   that routine only.

A regression fixture per row would be cheap here -- all five are small, public, and
already in an indexed repo.

## 5. Reproduce

```
drag-lint context --task "modify YADF.Groups.PrevSignificantIdx" \
  --db C:\Projects\YADF\YADF.sqlite --format markdown
```

Or read the already-generated blocks in place:
`YADF.Options.pas` lines 121, 132, 313; `YADF.Layout.pas` line 99;
`YADF.Groups.pas` lines 99-105.

Note: the `<!-- drag-lint:auto BEGIN/END -->` delimiters in `<remarks>` work well --
regenerating in place has not disturbed hand-written prose. This report is only
about the `<returns>` line, which sits **outside** those delimiters.

## 6. No rush

Reported while the drag-lint team is busy on autodoc phase 3. Nothing in YADF is
blocked on it -- the docs are wrong, not the index, and YADF's own builds/tests are
unaffected. File it wherever it fits the phase-3 backlog.
