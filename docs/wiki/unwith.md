# unwith

Removes a `with E do S` by writing `E.` before every bare identifier of `S` that `E`'s members declare. Reach for it when
you want a `with` gone and cannot afford a name silently changing meaning: an unprefixed member that an outer symbol also
names still compiles, and then reads the wrong thing.

## Running it from the CLI

```
drag-lint unwith --db <db> [--in <F> [--line <N>]] (--plan | --apply --project <X.dproj>)
                 [--platform <p>] [--rsvars <bat>] [--build-timeout <s>] [--library-db <L>|none] [--no-backup] [--json]
```

`--plan` writes nothing: for every `with` in the file (or, without `--in`, the project) it prints `candidate` or
`refused <kind>: <why>`; with `--in` also what each identifier becomes and what it binds to today. `--apply` writes the
candidates. Exit codes: 0 plan printed or applied; 1 the `--line` with refused, nothing to apply, or the gate or the proof
refused and rolled back; 2 a usage error or a failed rollback.

Nested `with`: the innermost goes first; the outer refuses `inner-with-first`. Reindex and run again.

## What `--apply` proves

1. **Closure.** The target's type, its ancestors (through the platform library) and the helpers in scope decide prefix or keep.
2. **Index, before.** The ref the resolver bound at that position must agree, else `binding-conflict`.
3. **Compile gate.** Baseline build, write under backups, build again; any failure restores every file byte-identically.
4. **Index, after.** The rewritten project is re-indexed into a COPY of the DB, and every ref of every rewritten body must
   bind to what it bound before, else `rebind-after` and a rollback. The build cannot see this: the text compiles.

Reindex the real DB after a good apply; only the copy was written.

## What refuses

| kind | why |
|---|---|
| `null-type`, `no-type-row` | the index cannot name the target's type (ambiguous, or a type outside this index) |
| `unsupported-target-kind` | an interface, alias or pointer |
| `unresolved-ancestor` | an ancestor outside the project and the library may declare anything |
| `closure-conditional` | a conditional directive inside a project type of the chain: another configuration has other members |
| `multiple-targets` | `with A, B do` |
| `target-call`, `target-constructor`, `target-indexer`, `target-property-getter` | evaluated once by `with`, N times after |
| `target-cast`, `target-not-chain`, `target-unbound`, `target-not-variable`, `target-header` | not a plain, bound, one-line chain (`X as T` on a stable `X` IS accepted) |
| `cast-after-side-effect` | a call stands before the first use: a failing `as` would raise after it instead of before |
| `target-used-bare` | the body assigns or passes the target: `with` read it once, the rewrite would follow it |
| `target-field-reassigned`, `target-var-param` | a class-typed slot something else can rebind: a writer outside a constructor, destructor or unit section, an argument, an `@` |
| `conditional-in-body` | a conditional or include directive inside the statement |
| `inner-with-first`, `anonymous-method`, `asm-in-body`, `inline-decl` | a scope in the body that changes the answer |
| `invisible-member`, `nested-type-member`, `type-name-member`, `helper-ambiguous` | the name's binding, or `E.Name` being a rewrite of it, is not proved |
| `binding-conflict` | closure and resolver disagree |
| `stale-file`, `encoding-roundtrip`, `parse-error`, `no-facts` | reindex, or the file cannot be rewritten byte-faithfully |

## Limits

One build configuration is proved (the project's active one). The timing of a nil dereference in a target chain moves from
the `with` to the first use; a failing `as` is covered by `cast-after-side-effect`, a nil is not.

## From `lint --fix`

`drag-lint lint --fix --fix-rule with-statement --db <db> [--in <f.pas> [--fix-line <L>]] [--apply --project <X.dproj>]`
is the same run as `unwith`: without `--apply` it prints the plan, with it the gate builds and rolls back as above.
`--apply` without `--project` exits 2.
