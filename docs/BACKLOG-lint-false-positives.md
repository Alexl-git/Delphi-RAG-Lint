# BACKLOG: lint false positives -- doc-drift on type decls, object-leak on VCL-owned components

Status: **BOTH FIXED 2026-07-08.**
- FP #1 (doc-drift on class/interface type decls) fixed in commit `4ec233b`: `Analyze`'s
  param/return findings (1-6) are now gated on `ASym.Kind in [skProcedure, skFunction,
  skMethod, skConstructor, skDestructor]`, so a type/const/var symbol skips param drift
  entirely. Regression test `tests/autotest/run_doc_drift_typedecl.ps1` (RED->GREEN).
- FP #2 (object-leak on owner-parented components) fixed in commit `6e46a13`: a new
  `ConstructorTransfersOwnership` guard treats `X := TSomething.Create(Owner)` as an
  ownership transfer when the type is a `TComponent` descendant (`IsDescendantOf`) and the
  first arg (`AOwner`) is non-nil; `Create(nil)`, non-TComponent, and the no-store path stay
  leak-checked. Regression test `tests/autotest/run_object_leak_owned.ps1` (owner-parented
  not flagged; genuine no-owner leak + `Create(nil)` still flagged).

Original report below (captured 2026-07-08 from a real dogfooding run):
drag-lint 0.94.0-alpha `lint-all` over the YADF repo, on a freshly-written unit
(`C:\Projects\YADF\YADFOT.Options.pas`) whose code is correct and compiles clean
(Win32 Debug BPL, `BUILD_EXITCODE=0`, 0 errors). Both findings below are false
positives -- the code is right and the rule is wrong. Neither is high-severity
(one `warning`, the rest `info`), but both misfire on very common, idiomatic
Delphi patterns, so they add recurring noise on every VCL/OTA unit.

Two independent rules are involved. They are unrelated fixes; do them separately.

---

## FP #1 -- `doc-drift` (`ddParamMissing`) fires on a CLASS TYPE declaration

### Symptom

On a documented `class` type declaration, `doc-drift` emits, per ancestor class
and per implemented interface, a spurious "signature param has no <param> tag":

```
warning doc-drift  YADFOT.Options.pas:54  signature param "TFrame" has no <param> tag
warning doc-drift  YADFOT.Options.pas:82  signature param "TInterfacedObject" has no <param> tag
warning doc-drift  YADFOT.Options.pas:82  signature param "INTAAddInOptions" has no <param> tag
```

### Reproducing code (all correct, all compile)

```pascal
  /// <summary>The generic Tools > Options frame. ...</summary>
  /// <remarks>Not thread-safe; ...</remarks>
  TYadfOptionsFrame = class(TFrame)          // <- L54: "TFrame" flagged as a param
    ...
  end;

  /// <summary>INTAAddInOptions page carrying one YADF frame class. ...</summary>
  TYadfOptionsPage = class(TInterfacedObject, INTAAddInOptions)  // <- L82: both flagged
    ...
  end;
```

A class type has **no parameters**; `<param>` tags are meaningless on a type
declaration. The ancestor class `TFrame` and the implemented interface
`INTAAddInOptions` are being mis-parsed as a routine's parameter list.

### Root cause

`src/doc/DRagLint.Doc.Drift.pas`, `Analyze` (the `ddParamMissing` loop, ~L423-431):

```pascal
    // --- 2. ddParamMissing: a sig param with no <param> tag. FIXABLE. ----------
    for N in SigNames do
    begin
      var Documented: Boolean := False;
      for DP in ADoc.Params do
        if SameText(DP.Name, N) then begin Documented := True; Break; end;
      if not Documented then
        Findings.Add(MakeFinding(ddParamMissing,
          Format('signature param "%s" has no <param> tag', [N]), True, DocLine));
    end;
```

`SigNames := ParseParamNames(ExtractParamList(EffectiveSignature(AStore, ASym)))`
runs regardless of `ASym.Kind`. When `ASym` is a class/type symbol, its
"signature" is the ancestor-list heading -- `(TFrame)` or
`(TInterfacedObject, INTAAddInOptions)` -- and `ExtractParamList` + `ParseParamNames`
treat those comma/`;`-separated names as param names. The unit's own header
comment (L49) already says this analyzer is for a routine ("Analyzes ADoc against
ASym's **live signature and body facts**"), so the guard is just missing.

`ddParamRenamedOrRemoved` (L417-421) is safe here only because a correctly
documented class has no `<param>` tags to mismatch; but `ddParamVolatileMode`
would also be nonsensical on a type. The whole param/return block should be
routine-only.

### Suggested fix

Gate the param analysis (at minimum `ddParamMissing`, ideally the whole
param/return section) on the symbol being a routine, e.g.:

```pascal
  if ASym.Kind in [skFunction, skProcedure, skMethod, skConstructor, skDestructor] then
  begin
    // ... existing ExtractParamList / ddParamRenamedOrRemoved / ddParamMissing /
    //     ddParamVolatileMode / return-type checks ...
  end;
```

(Adjust the kind set to the actual `TSymbolKind` enum values.) A type/const/var
symbol has no params -- skip param drift entirely for it.

### Note

`doc-drift` on a class decl mis-parsing the ancestor list also means the
`--fixable`/autofix path (this finding is marked `Fixable=True`) would try to add
`<param name="TFrame">` stub tags to a class comment, which would be actively
wrong output -- another reason to gate it.

---

## FP #2 -- `object-leak` fires on a VCL component created with an owner

### Symptom

```
info object-leak  YADFOT.Options.pas:204  Object "lbl" may be leaked: created but not freed or transferred on some path.
```

### Reproducing code (correct -- no leak)

```pascal
      okEnum:
        begin
          lbl := TLabel.Create(Self);      // <- L204: "Self" (the TFrame) is the OWNER
          lbl.Parent := parent;
          lbl.Caption := T[i].Caption;
          cmb := TComboBox.Create(Self);
          ...
          FControls[i] := cmb;             // cmb stored; lbl deliberately not stored
        end;
```

`lbl` is created with `AOwner = Self` (a `TYadfOptionsFrame`, i.e. a `TComponent`
descendant). In the VCL, a component constructed with a **non-nil owner** is
inserted into that owner's `Components` list and freed automatically by
`TComponent.Destroy` when the owner dies. So `lbl`'s lifetime IS transferred at
construction -- there is no leak, and an explicit `lbl.Free` would be wrong
(double-free risk on owner teardown). This is the single most common VCL
allocation idiom.

Note the rule did NOT fire on the sibling `cmb`/`cb`/`se`/`ed` in the same
routine, because those are stored in `FControls[i]` and the escape analysis sees
them escape. The differentiator is purely "stored in a field/array vs not" -- the
owner argument is ignored.

### Root cause

`src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas`, the object-leak block
(~L791-816): it records each local's constructor-assignment site via
`ExprIsConstructor(...)` and then flags any created local still "may-open" at the
routine exit (`EIn2[Cfg.ExitIdx][I]`). The `TEscape` analysis is given an
`OwnsOracle`, but that oracle does not treat "`TComponent`-descendant constructed
with a non-nil first argument (`AOwner`)" as an ownership transfer / escape. So an
owner-parented component that is never explicitly stored or freed reaches exit
still "open" and is reported.

### Suggested fix

Teach the ownership oracle (or the `ExprIsConstructor` classification feeding the
escape lattice) that a constructor call on a `TComponent` descendant with a
**non-nil `AOwner` argument** transfers ownership -- treat it like an escape /
"transferred", so it is not a leak. Concretely:

- If the constructed type is (transitively) a `TComponent` and the call site
  passes a first argument that is not the `nil` literal, mark the local as
  transferred at that site.
- `Create(nil)` (explicit nil owner) should still be subject to the normal
  leak check -- that genuinely has no owner.

Type ancestry is already indexed (`query ancestors --name <T> --of TComponent`
resolves it), so the "is a TComponent descendant" test is available to the
analyzer.

### Lower-confidence variant worth considering

Even without full type resolution, a cheaper heuristic: a constructor local
whose `.Parent := X` is set (as `lbl.Parent := parent` here) is a VCL control
placed into the visual tree and is owner-managed -- but the owner-argument test
above is the principled fix and should be preferred.

---

## Impact / priority

- Both are low severity (`warning`/`info`) but high frequency: FP #1 hits every
  documented class/interface with an ancestor or implemented interface; FP #2
  hits every `X := TSomething.Create(Self/Owner)` that isn't separately stored.
  On a typical VCL/OTA unit that is a lot of recurring noise, and it undermines
  trust in the two rules.
- FP #1 additionally risks emitting incorrect autofix output (`<param>` stubs on
  a class comment), so it is the higher-value fix.
- Neither blocked the YADF work (the code is correct); filing so the reporting
  can be tightened.

Reporter context: found while porting the YADFOT Tools>Options page (YADF repo,
commit 5f1346a). Index used: `C:\Projects\YADF\.private\yadf-index.sqlite`
(reindexed to schema v15 for this run).
