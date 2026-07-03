# v0.83 Item 3 DEFERRED -- object-leak OwnsOracle enhancement (empirical no-op)

**Decision (autonomous, 2026-07-02/03):** DEFER. Do NOT touch the ON-by-default
`object-leak` rule. Rationale below is empirical, not speculative.

## What the plan asked for
Item 3 of `docs/superpowers/plans/2026-07-02-v083-deepen-rules-plan.md` asked to
strengthen the `object-leak` ownership oracle so that "an obvious
`TFileStream`/`TMemoryStream`/`TBitmap` created-and-never-freed" is caught,
because a v0.82 recon claimed the rule "stays SILENT" on those RTL types since the
oracle "can't confirm those RTL types are owned `TObject`s."

## What the current code actually does (verified with the built Win64 exe)
The premise is **incorrect** for the shipped code. `object-leak` does NOT gate on
a type-ownership oracle at all:

- The "created" flag is set by `ExprIsConstructor` (FlowChecks / Flow.Lattices),
  which is purely **syntactic**: it fires for ANY `<Type>.Create` regardless of
  whether `<Type>` resolves to `TObject`, a component, an interface, etc.
- `OwnsOracle`/`OwnCache` is the **interprocedural callee-ownership** predicate
  ("does callee X take ownership of the arg I pass it?"), used only to refine the
  ESCAPE analysis. It is NOT a "is this constructed type an owned TObject?" gate.
- Leak detection = a local assigned from a `.Create` that is still may-open at the
  routine exit (not freed, not transferred). Transfer/escape exclusions
  (returned via Result, stored in a field, passed to a call) keep FP low.

### Probe results (bare `lint --rule object-leak` AND store-bearing `check-ast`)
| Case | Line | object-leak fires? | Correct? |
|------|------|--------------------|----------|
| `s := TFileStream.Create(...)` never freed | yes | yes | leak -> should fire |
| `m := TMemoryStream.Create` never freed | yes | yes | leak -> should fire |
| `b := TBitmap.Create` never freed | yes | yes | leak -> should fire |
| `TFileStream.Create` + `try..finally s.Free` | -- | no (absent) | freed -> correct |
| `Result := TMemoryStream.Create` (returned) | -- | no (absent) | transfer -> correct |
| `FS := TMemoryStream.Create` (field store) | -- | no (absent) | transfer -> correct |
| `s := TMemoryStream.Create; DoSomething(s)` | -- | no (absent) | escape -> correct |

All RTL stream/bitmap leaks the plan wanted are **already caught**, and every
ownership-transfer case is **already excluded** (no false positive).

## Why NOT to implement the "enhancement"
- **Zero benefit:** the target leaks are already detected. There is no silent gap
  to close.
- **Pure risk on an ON rule:** teaching the oracle to force-mark more constructed
  types as "owned" could only widen what is flagged -- i.e. it can only ADD
  findings, and since the real leaks are already found, any additions would be
  the exact FALSE POSITIVES the STRICT guardrail forbids (e.g. components created
  with an `AOwner`, ref-counted/interface types, or ownership that transfers in a
  way the escape analysis already handles).
- The plan's own fallback: "if you cannot get the additions clean, REVERT and
  DEFER; never ship new FPs on an ON rule." Here the additions cannot even be
  net-positive, so deferral is the correct conservative call.

## What a human might reconsider later (optional, not blocking)
If the v0.82 recon meant a *different* narrower gap (it was not reproducible here),
a future pass could look at, with a fresh FP guardrail:
- Constructors with side-argument ownership sinks not modeled (e.g.
  `TReader.Create(SomeStream)` where the reader may or may not own the stream).
- `TStringList.Create` passed to an owning container's `AddObject` (already an
  escape today -> not a leak; correct).
These are refinements to the ESCAPE model, not a "recognize RTL owned bases"
oracle -- and none are needed to catch the leaks Item 3 named.

**Net for v0.83:** Items 1 and 2 shipped (both OFF-by-default, clean src/ FP).
Item 3 deferred as an empirical no-op; the ON `object-leak` rule is UNCHANGED
(no code touched -> no regression possible).
