# Ref-gap G -- Member-Access Indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **THIS PLAN HAS A SUPERVISED PAUSE (Task 2): the parser diff MUST be shown to the user and approved BEFORE it is applied.**

**Goal:** Index property/field member-access on typed receivers (`Edit1.Caption`) under a new `member-access` ref kind, tightly gated to avoid ref-flooding, so the component-conversion applier (sub-project B) can find instance-scoped property-access sites to rewrite.

**Architecture:** A single new gated emission in `DRagLint.Parser.Delphi13.pas`'s `Walk` `exprDot` case, right beside the existing ref-gap D (`Self.`-member) emission. Ref-gap D emits the rhs member ONLY when lhs=`Self`; ref-gap G is the complement -- emit a `member-access` ref for the rhs member when lhs is a plain identifier that is NOT `Self`. No new ref kind changes existing `read`/`write`/`type_use`/`call` emissions. The kind-agnostic-but-not-auto-consuming rename path means existing consumers are untouched.

**Tech Stack:** Delphi 13 (RAD Studio 37), tree-sitter-delphi13 via `TreeSitter`; the ref index (SQLite store); PowerShell autotest driving `src/cli/Win64/Debug/drag-lint.exe`.

## Global Constraints

- **Encoding:** all new/edited `.pas` and `.ps1` files strict 7-bit ASCII, NO BOM, CRLF. No Unicode/em-dashes -- use `--`.
- **SUPERVISED parser change:** the RED test is written and run FIRST (Task 1). The parser edit (Task 2) requires an AST-recon step then a **STOP: hand the user the exact `DRagLint.Parser.Delphi13.pas` diff and wait for explicit approval BEFORE applying it.** Do NOT edit the parser without the user's go. This mirrors ref-gap E.
- **The tight gate (load-bearing):** emit `member-access` ONLY when the `exprDot` lhs is a plain `identifier` node AND lhs is NOT `Self` (case-insensitive; Self is ref-gap D's) AND the rhs is a plain `identifier`. So `Edit1.Caption` is captured; `Self.FField` (D's), `GetX().Caption` (exprCall lhs), `a.b.Caption` (chained -- each level with an identifier lhs handles its own rhs via the recursion), `arr[i].Caption` are NOT flooded.
- **New kind is additive:** `member-access` is a NEW `kind` string value. It MUST NOT change any existing `read`/`write`/`type_use`/`call`/`event-binding` emission. The ref-gap D test (`run_self_field_refs.ps1`) and ref-gap E test (`run_type_ref_gap_e.ps1`) are the regression net and MUST stay green.
- **No schema migration:** the new kind rides the existing `kind` column. No new `TReference` field, no DB migration.
- **Build recipe:** CLI Win64 Debug via rsvars + msbuild through PowerShell `Start-Process -Wait`, read log for `BUILD_EXITCODE=0` and no `[dcc] Error`. Build project: `src/cli/drag-lint.dproj`. Exe: `src/cli/Win64/Debug/drag-lint.exe`. Do NOT use the MCP build tool; do NOT run `cmd.exe /c build.bat` from Bash (hangs).
- **DocInsight/CDD:** the new emission carries a clear code comment mirroring the ref-gap D comment beside it (explaining the gate).

---

## File Structure

- **Modify** `src/parser/DRagLint.Parser.Delphi13.pas` -- ONE new gated emission in `Walk`'s `if NodeType = 'exprDot'` branch (~lines 1396-1410), immediately after the ref-gap D block. SUPERVISED (Task 2).
- **Create** `tests/autotest/run_member_access_refs.ps1` -- the RED->GREEN autotest: positive captures, negative (over-capture) controls, and the D/E regression re-runs.
- **Modify** docs: `CHANGELOG.md` (ref-gap G line) + a line in `docs/CONVERSION-RULES.md` noting the enabling capability.

---

## Task 1: Write the RED test for member-access indexing

**Files:**
- Create: `tests/autotest/run_member_access_refs.ps1`
- Reference (read-only, the pattern): `tests/autotest/run_self_field_refs.ps1`

**Interfaces:**
- Consumes: the shipped `drag-lint.exe` `index` + `find-callers`/`dump-refs --json` verbs (whichever exposes ref `kind`; check `run_self_field_refs.ps1` for which it uses).
- Produces: a test that FAILS on the current exe (no `member-access` kind exists) and will PASS after Task 2.

- [ ] **Step 1: Determine which verb exposes ref kind + name for assertions**

Read `tests/autotest/run_self_field_refs.ps1` to see how it queries refs and asserts on kind/name.

Run: `grep -n "find-callers\|dump-refs\|--json\|kind\|member" tests/autotest/run_self_field_refs.ps1`
Note the exact query verb + JSON shape it asserts against (e.g. `find-callers --name Caption --json` returning refs with a `kind` field). Use the SAME mechanism in the new test.

- [ ] **Step 2: Write the RED test**

Create `tests/autotest/run_member_access_refs.ps1`. Mirror `run_self_field_refs.ps1`'s harness (Check function, Write-Ascii ASCII/CRLF writer, fresh temp workdir, whole-tree index). Fixture unit:

```pascal
unit u;

interface

type
  TOther = class
    Prop: Integer;
    procedure Method;
  end;
  TThing = class
    client: TOther;
    Edit1: TOther;
    procedure Run(other: TOther; obj: TOther);
  end;

implementation

procedure TOther.Method; begin end;

procedure TThing.Run(other: TOther; obj: TOther);
var Y: TOther;
begin
  Edit1.Prop := 5;          // member-access WRITE-side on Edit1.Prop
  Y := Edit1;               // plain read of Edit1 (no member) -- NOT member-access
  obj.Prop := Edit1.Prop;   // member-access on obj.Prop (write) AND Edit1.Prop (read)
  Self.client := other;     // ref-gap D territory (Self.) -- NOT a NEW member-access
  other.Method;             // member-access on other.Method? (a method member) -- see note
end;

end.
```

Query refs (use the mechanism from Step 1). Assert (the exact matchers depend on the query verb; write them to be specific to `kind=member-access` + `name_text`):

POSITIVE:
- `Prop` has `member-access` refs at the `Edit1.Prop` sites (write and read) and the `obj.Prop` site.

NEGATIVE (over-capture control -- these MUST have NO `member-access` ref):
- `Self.client` -> NO new `member-access` on `client` (ref-gap D already emits a `read`; assert NO `member-access` kind for it -- Self is excluded).
- the bare `Edit1` in `Y := Edit1;` -> NO `member-access` (it is a plain read, no member).
- `GetX().Caption`-shape is not in this fixture; add a line `Y := TOther(other).Prop;` OR keep it simple -- the exprCall-lhs exclusion is asserted by the absence of any member-access whose site is not a plain-identifier receiver. (Keep the fixture minimal + assert what the gate produces; document the method-member `other.Method` decision below.)

METHOD-MEMBER NOTE: `other.Method` is a member access whose rhs is a method. The gate as specified (lhs plain identifier, not Self, rhs plain identifier) WOULD emit a `member-access` for `Method`. That is acceptable (a method rename could use it too) but is NOT needed for the property-rename use case. DECISION for the test: assert whichever the gate produces and DOCUMENT it -- do NOT add extra gating to exclude methods (that would need member-kind resolution the parser lacks at this point; property-vs-method disambiguation is a query-time concern for B). If the user prefers methods excluded, that is a follow-up, not this gate.

Write the assertions so they FAIL on the current exe (no `member-access` kind emitted at all -> every positive assertion fails).

- [ ] **Step 3: Run the RED test against the CURRENT exe**

Run: `pwsh -File tests/autotest/run_member_access_refs.ps1`
Expected: FAIL -- the positive `member-access` assertions fail (the kind does not exist yet). The negative assertions may pass trivially (nothing emits member-access). Capture the output as RED evidence.

- [ ] **Step 4: Commit the RED test**

```bash
git add tests/autotest/run_member_access_refs.ps1
git commit -m "test(refgap-g): RED -- member-access on typed receivers not yet indexed

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: SUPERVISED parser change -- emit member-access

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (the `exprDot` branch in `Walk`, ~lines 1396-1410, immediately after the ref-gap D block)

**Interfaces:**
- Consumes: the `exprDot` node's `lhs`/`rhs` fields (confirmed by AST recon in Step 1).
- Produces: a `member-access` ref (kind string) with `NameText` = the rhs member identifier, positioned at the rhs identifier's span, emitted under the tight gate.

- [ ] **Step 1: AST recon (throwaway, reverted) -- confirm the node shape**

Confirm the exact field names + node types for `Edit1.Prop` and `obj.Prop := ...`. The existing ref-gap D code already uses `ANode.ChildByField('lhs')` and `ANode.ChildByField('rhs')` on the `exprDot` node and checks `L.NodeType = 'identifier'` -- so the shape is ALREADY KNOWN from the D code. A full S-expr dump is optional; if any doubt about the assignment-lhs-is-exprDot shape, do a quick throwaway dump on the Task-1 fixture and REVERT it. Record what you confirmed in the report.

Note: the spec DECIDED a SINGLE kind `member-access` (no read/write split) -- a property rename rewrites the same bytes regardless. So you do NOT need to detect assignment-lhs context in the parser; emit `member-access` for the rhs member in the `exprDot` case uniformly (both `x := Edit1.Prop` and `Edit1.Prop := x` produce a `member-access` on `Prop`, because both contain an `exprDot` with lhs=`Edit1`, rhs=`Prop`).

- [ ] **Step 2: Prepare the EXACT diff and STOP for user approval**

Write the intended change (do NOT apply yet). The change adds, immediately AFTER the ref-gap D block inside `if NodeType = 'exprDot'`:

```pascal
      // Ref-gap G: capture the MEMBER of a NON-Self dotted access (obj.Member)
      // as a 'member-access' ref, so the component-conversion applier can find
      // instance-scoped property/event access sites to rewrite. Gated tightly
      // (mirrors ref-gap D's Self. gate, of which this is the complement): lhs
      // must be a plain identifier and NOT Self (Self is ref-gap D's 'read'),
      // and rhs must be a plain identifier. Chained (a.b.Member), call
      // (f().Member), and indexed (arr[i].Member) receivers are excluded -- each
      // exprDot LEVEL with a plain-identifier lhs emits its own member-access via
      // the recursion below; complex receivers are the future expression stage's
      // problem. A distinct kind ('member-access') keeps existing read/write/
      // type_use consumers untouched.
      if (not L.IsNull) and (L.NodeType = 'identifier')
         and (not SameText(Trim(NodeText(L, AState.Source)), 'Self')) then
      begin
        var RG:= ANode.ChildByField('rhs');
        if (not RG.IsNull) and (RG.NodeType = 'identifier') then
          AState.EmitRef('member-access', NodeText(RG, AState.Source), RG);
      end;
```

Placement: INSIDE the `if NodeType = 'exprDot'` block, AFTER the existing ref-gap D `if ... Self ... EmitRef('read', R ...)` block and BEFORE the `for i:= 0 to ANode.NamedChildCount - 1 do Walk(...)` recursion line. (Do not disturb the base-identifier `read` emission or the recursion.)

**STOP HERE. Present this exact diff to the user (the controller must relay it and get an explicit go).** Do NOT apply until approved. If the user requests changes to the gate, revise and re-present.

- [ ] **Step 3: After approval -- apply the diff**

Apply exactly the approved change. Verify the working-tree file stays ASCII/CRLF (python byte-check: CRLF pairs, 0 bare LF, 0 non-ASCII).

- [ ] **Step 4: Build Win64 Debug**

Build via the recipe (rsvars + msbuild `src/cli/drag-lint.dproj` `/p:Config=Debug /p:Platform=Win64`).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 5: Run the test for GREEN**

Run: `pwsh -File tests/autotest/run_member_access_refs.ps1`
Expected: PASS -- positive `member-access` assertions now pass; negatives still hold (Self excluded, bare reads not captured).

- [ ] **Step 6: Commit (only after GREEN + approval)**

```bash
git add src/parser/DRagLint.Parser.Delphi13.pas
git commit -m "feat(refgap-g): index member-access on typed receivers (SUPERVISED, user-approved)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Over-capture flood check + D/E regression

**Files:**
- Modify: `tests/autotest/run_member_access_refs.ps1` (add the flood-check section)

**Interfaces:**
- Consumes: the built exe with the Task-2 change; a real sizable unit to index (e.g. a CLIENT form, or reuse an existing fixture the D/E tests use).
- Produces: evidence the change is additive (existing kinds unchanged) and not exploding.

- [ ] **Step 1: Add the flood-check to the test**

Extend `run_member_access_refs.ps1`: index a sizable real unit (or a larger fixture) and capture (a) the total ref count, (b) the per-kind counts for `read`/`write`/`type_use`/`call`, and (c) the `member-access` count. The check: `member-access` count is > 0 and proportionate (spot-check a handful against the source -- each `ident.Member` should yield one). The existing-kind counts are for the report (Step 3 confirms they did not change vs a pre-change baseline -- if a baseline is impractical, at least assert they are non-zero and the test documents the member-access/total ratio).

- [ ] **Step 2: Re-run the D and E regression tests**

Run: `pwsh -File tests/autotest/run_self_field_refs.ps1`  (ref-gap D -- Self. handling)
Expected: PASS (unchanged -- G's gate excludes Self, so D's emissions are untouched).

Run: `pwsh -File tests/autotest/run_type_ref_gap_e.ps1`  (ref-gap E -- type_use)
Expected: PASS (unchanged -- G touches only the exprDot member, not type_use).

- [ ] **Step 3: Run the full member-access test**

Run: `pwsh -File tests/autotest/run_member_access_refs.ps1`
Expected: PASS (positives + negatives + flood-check all green). Capture the counts in the commit/report.

- [ ] **Step 4: Commit**

```bash
git add tests/autotest/run_member_access_refs.ps1
git commit -m "test(refgap-g): over-capture flood check + D/E regression green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Docs + ledger

**Files:**
- Modify: `CHANGELOG.md`, `docs/CONVERSION-RULES.md`
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a durable record that ref-gap G shipped + enables the applier's #4 surface.

- [ ] **Step 1: Update CHANGELOG + CONVERSION-RULES**

Add a CHANGELOG entry: ref-gap G indexes `member-access` on typed receivers (new kind, gated to non-Self plain-identifier receivers), enabling the component-conversion applier's property/event-access rewrite. In `docs/CONVERSION-RULES.md`, add a line under the apply/Batch-2 section noting the `member-access` capability is the basis for surface #4.

- [ ] **Step 2: Update the SDD ledger**

Append a "REF-GAP G" section to `.superpowers/sdd/progress.md`: the supervised parser change (user-approved diff), the new `member-access` kind + gate, the flood-check numbers, D/E regression green, per-task commits, and that sub-project B's #4 query is finalized against these rows next.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md docs/CONVERSION-RULES.md .superpowers/sdd/progress.md
git commit -m "docs(refgap-g): CHANGELOG + CONVERSION-RULES + SDD ledger

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:** the spec's fix (member-access emission in exprDot, gated to non-Self plain-identifier lhs) -> Task 2; the schema decision (new kind, no column/migration) -> Task 2's EmitRef('member-access',...); the testing plan (positive/negative/over-capture/D-E-regression) -> Tasks 1+3; the SUPERVISED pause -> Task 2 Steps 2-3; the single-kind (no read/write split) decision -> Task 2 Step 1 note; the "what G does NOT do" (receiver-type join, chained receivers, any rewrite) -> excluded by the gate + noted. All covered.

**2. Placeholder scan:** no TBD/placeholder. The method-member (`other.Method`) behavior is explicitly DECIDED (assert-what-the-gate-produces, document it, no extra gating) rather than left open. The flood-check baseline is given a pragmatic fallback if a strict before/after baseline is impractical.

**3. Type consistency:** the new kind string is `member-access` everywhere (Task 1 assertions, Task 2 EmitRef, Task 3 flood-check, Task 4 docs). The gate condition (lhs plain identifier AND not Self AND rhs plain identifier) is stated identically in the constraints, Task 1 negative controls, and Task 2's diff. The emission site (after ref-gap D block, before the recursion, inside the exprDot case) is consistent.

**4. Supervision:** Task 2 is unambiguous -- prepare the diff, STOP, get approval, THEN apply. The controller (running subagent-driven-development) must relay the diff to the user and not let the implementer apply it unreviewed.
