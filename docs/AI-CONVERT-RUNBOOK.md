# AI Runbook: Converting a Delphi Component with `drag-lint convert-apply`

Audience: an AI coding agent (or a developer driving one) asked to convert a
Delphi component from one type to another on a real form -- for example
`TOvcNumberEdit` -> `TcxCalcEdit`, `TDBEdit` -> `TcxDBTextEdit`, an Orpheus
`TOvc*` edit -> its DevExpress `cx` equivalent, or any `TPersistent`-rooted
class to another.

This is a **procedure**, not a reference. For the DSL grammar, the property-tree
thesis, and per-verb detail, read [`CONVERSION-RULES.md`](CONVERSION-RULES.md).
For the full verb catalog, read [`AI-USAGE.md`](AI-USAGE.md).

`convert-apply` does the **mechanical** part of a conversion -- the retype, the
`uses` add, the `.dfm` re-emit, the property-access rewrite, the creator markers.
It is deterministic (no LLM). It does **not** do semantic fixes that need a human
(cross-type value conversion, split/merge, business logic). Your job is to drive
it, read what it did and didn't do, and finish the human parts it flags.

The conversion verbs (`convert-validate`, `convert-scaffold`, `convert-apply`) have
**no IDE surface** -- they are CLI-only; there is no menu item or dialog for them.

---

## 0. The one hard prerequisite: BOTH types must be indexed

`proptree`, `convert-scaffold`, and `convert-validate` walk the **real property
trees** of the source (`From`) and target (`To`) types. They can only do that if
BOTH types are present in a drag-lint index that you pass with `--db`.
`convert-apply` additionally runs a **freshness guard** on both types before it
will `--apply`.

Before anything else, verify both types resolve:

```
drag-lint query --name TOvcNumberEdit --db <db>     # source
drag-lint query --name TcxCalcEdit    --db <db>     # target
```

Three DBs matter (paths on this machine):

| DB | What it holds | Path |
|----|---------------|------|
| App DB | your project's own source (forms, units) -- has the **instances** | `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` |
| Library Win32 | 3rd-party libraries incl. **DevExpress `cx`** types | `C:\Projects\.drag-lint\library-Win32.sqlite` |
| Library Win64 | 3rd-party libraries (fewer -- `cx` NOT present as of this writing) | `C:\Projects\.drag-lint\library-Win64.sqlite` |

A project's App DB always lives at `<project folder>\_D-RAG\<project file base
name>.sqlite`, a hidden folder beside the `.dproj` -- never guess it, ask
`drag-lint resolve-dbs --project <x.dproj>` (or `--in <x.pas>`).

You can pass **multiple** `--db`; each type is resolved against **all** of them,
first-DB-that-resolves-wins (symbol ids are per-DB). **The From and To types may
live in DIFFERENT DBs.** As of 2026-07-20 `convert-apply` resolves each type
independently across every `--db` for BOTH the freshness guard and the apply plan
(before that fix only the first `--db` was consulted, so a cross-DB pair silently
failed the guard with "not indexed (no skClass symbol found)" and matched no
instances). A typical conversion therefore needs the **app DB** (the form being
edited -- it holds the instances) plus **whichever library DB(s) declare the From
and To types** -- and those can be two different platform libraries.

Real example: an Orpheus source `Abcbtn.TabcToggleBtn` (only in `library-Win64`)
converting to a DevExpress target `cxButtons.TcxButton` (only in `library-Win32`,
since `cx` is Win32-only) needs all three:
`--db <appDB> --db library-Win64 --db library-Win32`. The `#convert` header may use
either bare (`TabcToggleBtn -> TcxButton`) or qualified (`Abcbtn.TabcToggleBtn ->
cxButtons.TcxButton`) type names -- instances are matched by the bare type tail
either way.

### If a type is NOT indexed -- reindex the folder that declares it

This is the most common real-world blocker. Example seen in practice: DevExpress
`cx` types live in `library-Win32.sqlite`, but **Orpheus `TOvc*` source was never
indexed** even though the source is on disk at `C:\Projects\Orpheus\source\`.
`query --name TOvcNumberEdit` returned 0 matches in every DB.

Fix = one **incremental** index of the declaring folder into the right library DB:

```
drag-lint index "C:\Projects\Orpheus\source" --db "C:\Projects\.drag-lint\library-Win32.sqlite"
```

`index` is incremental (it only (re)parses changed/new files), so this is cheap
and does not disturb the rest of the library index. After it finishes, re-run the
two `query --name` checks and confirm both types now resolve. Only then proceed.

> Do NOT full-rescan the whole `C:\Projects` tree to fix one missing type. Index
> the one folder that declares it.

---

## 1. Inspect the source tree (`proptree`)

Confirm the source type's real, deep property tree -- this is what you're
converting FROM, and it tells you which properties actually exist:

```
drag-lint proptree --qname OvcEdClc.TOvcNumberEdit --db <libdb>
```

Use the **qualified** name (`Unit.TType`) when the bare name is ambiguous. The
output is flattened dotted paths (`Font.Color`, `Sub.X`) with the depth shown by
indentation. `--format json` gives schema `proptree/2` if you need to parse it
(additive over the earlier `proptree/1`; adds per-leaf `is_writable`/
`visibility`/`member_kind` and a class-accurate concrete `type` -- see
`docs/CONVERSION-RULES.md`). `--depth N` (default 6) caps recursion;
`truncated:true` means the cap stopped an expansion.

Do the same for the target if you want to see what you're converting TO. This
step is diagnostic -- it does not write anything.

---

## 2. Scaffold a rules file (`convert-scaffold`)

Auto-draft a **valid, pre-filled** conversion-rules file from both trees. The
scaffolder matches target paths to source paths by leaf-name + compatible type
and leaves only genuine ambiguities for you:

```
drag-lint convert-scaffold --from OvcEdClc.TOvcNumberEdit --to cxCalc.TcxCalcEdit \
                           --out convert.rules --db <libdb> [--db <libdb2>]
```

What the draft contains and what you must do with each line:

| Line | Meaning | Your action |
|------|---------|-------------|
| `#convert From -> To[, unit]` | header: the type swap + a best-guess `uses` add | verify the unit is the one that actually declares `To` |
| `#link ToPath <- FromPath` | a concrete, inferred mapping (1 unambiguous match) | usually leave as-is; spot-check a few |
| `#link ToPath <- ???` + `#note candidates:` | AMBIGUOUS -- multiple source paths matched | **you must** replace `???` with the right `FromPath` (or `#ignore` it) |
| `#default ToPath = ???` | target-only property, no source | set a literal default value, or delete the line to leave the T default |
| `#note DROPPED FromPath` | source property with no target | decide: acceptable loss, or handle manually. `#ignore FromPath` silences the later unmapped warning |

The header `, unit` is a **best guess** from the qname prefix -- it is never
fabricated, but confirm it names the unit that truly declares the target type
(the one you'd add to `uses`).

By default (`--surface dfm`, no flag needed) auto-`#link` TARGETS are limited
to the target type's DFM-streamable published properties -- the right bar for
a component conversion. If you're mapping to a public **field** (or a
non-published public property) on the target, pass `--surface pas` to widen
the bar to published+public, including fields; either way a read-only target
is never auto-linked. See `docs/CONVERSION-RULES.md` for the exact rule.

Every `???` is tolerated by the validator; the draft round-trips clean even
unfilled. But an unfilled `???` means that property will NOT be carried -- fill
the ones that matter.

---

## 3. Validate the rules (`convert-validate`)

After you edit the draft, prove every path still exists in the real trees (this
catches typos reFind cannot):

```
drag-lint convert-validate --rules convert.rules \
                           --from OvcEdClc.TOvcNumberEdit --to cxCalc.TcxCalcEdit --db <libdb>
```

Exit **0** = all `#link`/`#default` paths resolve (literal `???` stubs are
tolerated). Exit **1** = a path is wrong -- fix it before applying. Exit **2** =
bad args / no readable DB. Add `--print-parsed` to see how each line parsed.

**Do not run `convert-apply` until `convert-validate` exits 0.**

---

## 4. Dry-run the apply (`convert-apply`, no `--apply`)

This is the crux. **Without `--apply`, `convert-apply` writes nothing** -- it
previews the full 5-surface rewrite so you can read it before committing.

```
drag-lint convert-apply --unit "uSetupDefaultsFrm.pas" --rules convert.rules \
                        --db <appdb> --db <libdb>
```

- `--unit <F.pas>` is the form/unit whose `.dfm` instances you're converting. The
  matching `.dfm` is found beside it.
- Pass the **app DB** (locates the instances + their `.dfm` blocks + access sites)
  AND the **library DB(s)** (resolves From/To types for the freshness guard and
  property trees).
- `--only Name1,Name2` restricts the rewrite to named instances -- use it to
  convert one component at a time on a busy form.

### The 5 surfaces convert-apply rewrites

Read the dry-run output as a report across these five, per instance:

1. **`.pas` declaration retype** -- `Name: FromType;` -> `Name: ToType;` on the
   published field.
2. **`.pas` uses-add** -- adds the unit(s) declaring each `ToType` to `uses`.
3. **`.dfm` object-block re-emit** -- the component's DFM block is re-serialized
   as the target type, including **moved-depth** properties
   (`Font.Size` -> `Style.Active.Font.Size`), events, collections, and binaries.
4. **`.pas` property/event access rewrite** -- instance-scoped: `Edit1.Caption`
   -> `Edit1.Text` (only where the receiver is a converted instance; other
   receivers are left alone).
5. **runtime-creator retype + TODO** -- `TFromType.Create(...)` -> `TToType.Create(...)`
   with a `{ TODO: verify creator }` marker for you to check by hand.

### Reading the dry-run -- what to look for

- **`Converted:`** one line per instance that will be rewritten. If your target
  instance is missing here, the rule didn't match it -- check the `#convert`
  types and the `--only` filter.
- **`Todos:` / `Warnings:`** per-instance problems: unmapped non-default props,
  cross-type binaries that couldn't be copied, creator sites to verify. These are
  the **human parts** convert-apply is flagging -- they don't stop the write, but
  you own them.
- **A skipped instance.** If surface #3 (DFM re-emit) hard-fails for an instance,
  that WHOLE instance is skipped -- none of its 5 surfaces are written (no
  half-conversion). The dry-run says so. Investigate the re-emit failure before
  forcing anything.

### Freshness-guard messages (these BLOCK `--apply`)

If a From/To type's index is out of date, the guard refuses `--apply` (and warns
on dry-run) with one of:

- `<Type>: not indexed (no skClass symbol found) -- reindex the unit declaring this type`
  -> go back to step 0 and index that folder.
- `<Type>: index is stale for <file> (file changed on disk since last index) -- reindex before converting`
  -> the type's source changed since indexing; reindex the file, then retry.

Do not try to bypass these. A stale tree means the re-emit would map to properties
that may no longer exist.

---

## 5. Apply for real (`--apply`)

Once the dry-run looks right and the guard is clean:

```
drag-lint convert-apply --unit "uSetupDefaultsFrm.pas" --rules convert.rules \
                        --db <appdb> --db <libdb> --apply
```

What `--apply` writes (unless `--no-backup`):

- For each touched file, a **`.BCK<n>` backup** (next free number -- never
  overwrites an existing backup).
- A **`recovery.txt`** written **first** (crash-safe: if the write dies mid-way,
  recovery.txt already lists what to restore).
- An in-file `// drag-lint convert-apply` marker comment.

`--no-backup` skips all three -- only use it if the files are already under
version control and you'll rely on that instead.

---

## 6. Verify by compiling (the real proof)

The gold standard: **the converted unit must compile.** If it compiles, the
conversion is at least as correct as a mechanical converter can be.

- **Full project build** (strongest): compile the host project via the
  `delphi-build` skill (rsvars + msbuild). Confirm `BUILD_EXITCODE=0` and no
  `[dcc] Error`. Watch for BPL/exe locks if RAD Studio has the project open.
- **Isolated build** (faster, no lock risk): compile just the converted unit +
  its `uses` in a throwaway project. Proves it parses and type-checks even if you
  can't link the whole app.
- If it does NOT compile: the compiler errors point at exactly the surfaces that
  need a human -- typically a property that has no target equivalent (surface #4
  access on a renamed/removed member) or a creator that needs real argument
  changes (surface #5 TODO). Fix those, rebuild.

After a successful build that changed indexed symbols, **reindex the changed unit
incrementally** so later queries see the new code:

```
drag-lint index "<changed unit's folder>" --db <appdb>
```

---

## Quick reference: the whole flow

```
# 0. ensure both types indexed (reindex the declaring folder if not)
drag-lint query --name <FromType> --db <db>
drag-lint query --name <ToType>   --db <db>
drag-lint index  "<folder declaring the missing type>" --db <libdb>   # only if needed

# 1-3. plan
drag-lint proptree         --qname <Unit.FromType> --db <libdb>
drag-lint convert-scaffold  --from <Unit.FromType> --to <Unit.ToType> --out c.rules --db <libdb>
# ... edit c.rules: fill every ??? that matters ...
drag-lint convert-validate  --rules c.rules --from <Unit.FromType> --to <Unit.ToType> --db <libdb>   # must exit 0

# 4. dry-run (writes nothing) -- READ the output
drag-lint convert-apply     --unit <Form.pas> --rules c.rules --db <appdb> --db <libdb>

# 5. apply (writes .BCK<n> + recovery.txt + marker)
drag-lint convert-apply     --unit <Form.pas> --rules c.rules --db <appdb> --db <libdb> --apply

# 6. verify -> compile the host project (delphi-build skill); reindex the changed unit
```

## What convert-apply does NOT do (leave to a human)

- **Cross-type value conversion.** A binary/complex property is copied only when
  the F and T leaf types are the *same*; otherwise it's flagged, not translated.
- **Split / merge.** One source component -> several targets (or vice versa) is
  deferred.
- **Default-value fidelity in one edge case.** A property ABSENT from the DFM
  equals the source's default; if the source default differs from the target
  default, re-emit currently adopts the target default. convert-apply emits a
  divergence note when F/T types differ. (Full fidelity is the deferred `2a-0`
  parser change.)
- **Semantics behind an access rewrite.** Surface #4 renames `.AsInteger` ->
  `.Value` at the token level per your `#link`; if the *semantics* differ
  (integer vs float), the compiler or your tests must catch it. This is why the
  compile step is the real gate.
