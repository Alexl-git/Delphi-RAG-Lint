---
id: cli
title: CLI reference
summary: Every drag-lint command, with its usage and the feature that describes it.
product: DL
---

# CLI reference

Every drag-lint command, with its usage and the features that describe it.

## Commands

### allow

Records a dl:ok review of one finding, so it stops being reported without being fixed.

```text
drag-lint allow <file> --fix-line <L> --fix-rule <id> [--apply] [--rules-dir <dir>] [--config <file>] [--profile <name>] [--enable id,...] [--disable id,...] [--stand-in-for <realpath>] (record a dl:ok review of ONE finding; dry-run without --apply; the lint options decide which findings the line has)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--fix-line` | `<L>` |  |  |
| `--fix-rule` | `<id>` |  |  |
| `--apply` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--config` | `<file>` |  |  |
| `--profile` | `<name>` |  |  |
| `--enable` |  |  |  |
| `--disable` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

Described in:

* [allow](features/allow.md)
* [Allow this message](features/allow-this-message.md)

### ambiguous-calls

Resolver-coverage diagnostic that reports call sites the engine could not pin to exactly one target -- unresolved or ambiguous calls.

```text
drag-lint ambiguous-calls [--qname <Foo.Bar>|--in <file>] --db PATH [--json] (resolver-coverage diagnostic: unresolved/ambiguous call sites)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--in` | `<file>` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

Described in [ambiguous-calls](features/ambiguous-calls.md).

### ask

Ask one report question and print the answer as text.

```text
drag-lint ask <question> --target <T> [--project <P.dproj> | --in <U.pas> | --db <idx>] [--to <B>] [--server-db <idx>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--target` | `<T>` |  |  |
| `--project` | `<P.dproj>` |  |  |
| `--in` | `<U.pas>` |  |  |
| `--db` | `<idx>` |  |  |
| `--to` | `<B>` |  |  |
| `--server-db` | `<idx>` |  |  |
| `--sql-db` | `<idx>` |  |  |
| `--counterpart-db` | `<idx>` |  |  |
| `--depth` | `N` |  |  |
| `--cap` | `N` |  |  |
| `--surface-cap` | `N` |  |  |
| `--control` | `<C>` |  |  |
| `--mode` |  |  |  |
| `--max-rows` | `N` |  |  |
| `--out-root` | `<dir>` |  |  |
| `--pairs-file` | `<f.json>` |  |  |
| `--allow-stale` |  |  |  |
| `--plain` |  |  |  |
| `--open` |  |  |  |
| `--resolve-only` |  |  |  |

Described in:

* [ask](features/ask.md)
* [Chart questions](features/chart-questions.md)

### bench-context

Benchmarks the context command by building context bundles for a sample of symbols against a database.

```text
drag-lint bench-context [--db <file.sqlite>] [--n N]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--n` | `N` |  |  |

Described in [bench-context](features/bench-context.md).

### butterfly

Composes a symbol's callers (upward wing) and callees (downward wing) into one combined chart in a single command.

```text
drag-lint butterfly --qname <X> [--depth N] [--format dot|mermaid|text|json] [--json] [--output F] --db PATH [--db ...] (composes callers (upward wing) + callees (downward wing) of X into one chart; default format dot)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--output` | `F` |  |  |
| `--db` | `PATH` |  |  |

Described in [butterfly](features/butterfly.md).

### call-path

Finds the shortest resolved call path from one symbol to another.

```text
drag-lint call-path --from <A> --to <B> [--max-depth N] --db PATH [--json] (shortest resolved call path A -> ... -> B; exit 1 = no path)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--from` | `<A>` |  |  |
| `--to` | `<B>` |  |  |
| `--max-depth` | `N` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

Described in [call-path](features/call-path.md).

### callgraph

Prints an N-deep resolved call tree for a symbol, in either direction.

```text
drag-lint callgraph --qname <X> [--direction callers|callees] [--depth N] --db PATH [--json] (N-deep resolved call tree; cycle-guarded)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--direction` |  |  |  |
| `--depth` | `N` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

Described in [callgraph](features/callgraph.md).

### check-ast

Runs drag-lint's AST-level checks against a file.

```text
drag-lint check-ast <file> [--profile <name>] [--db PATH] [--rule <id>] [--format text|json] [--json] [--output <file>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |
| `--rule` | `<id>` |  |  |
| `--format` |  |  |  |

Described in [Run AST Checks](features/run-ast-checks.md).

### check-unit

The whole-unit form of the undeclared-identifier quick-fix: resolves every unresolved name in a unit at once and adds the units that declare them.

```text
drag-lint check-unit <unit.pas> [--project <dproj>] [--platform win32|win64] [--shadow <dir>] [--resolve-uses] [--db PATH] [--format json|text]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<dproj>` |  |  |
| `--platform` |  |  |  |
| `--shadow` | `<dir>` |  |  |
| `--resolve-uses` |  |  |  |
| `--db` | `PATH` |  |  |
| `--format` |  |  |  |

Described in [Add Missing Units to uses (whole unit)](features/add-missing-units-to-uses-whole-unit.md).

### compare

Reruns a saved or pasted report and shows before / delta / after.

```text
drag-lint compare --old <report.txt|forms.csv|bundle dir> [--command "<id> -Target T -Project P ...>"] [--project <P.dproj>] [--out-root <dir>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--old` | `<report.txt\|forms.csv\|bundle dir>` |  |  |
| `--command` |  |  |  |
| `--project` | `<P.dproj>` |  |  |
| `--new` | `<same kind>` |  |  |
| `--old-db` | `<old.sqlite>` |  |  |
| `--db` | `<new.sqlite>` |  |  |
| `--auto` |  |  |  |
| `--save` |  |  |  |
| `--snapshot-dir` | `<dir>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |
| `--open` |  |  |  |

Described in [Compare a report with current code](features/compare.md).

### compile-check

Runs a compiler-backed check against a single Delphi project (.dproj) or source file (.pas) and reports the result.

```text
drag-lint compile-check <target.dproj|.pas> [--project <X.dproj>] [--db PATH] [--format json|text] (no --db: caches only into the project's unique manifest owner, else reports uncached; no index is required, the compile and report still run; exit 1 iff an Error finding)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `PATH` |  |  |
| `--format` |  |  |  |

Described in [compile-check](features/compile-check.md).

### context

Returns a compact context bundle for a symbol -- its doc comment, class surface (signatures), the target's own body, and a capped list of callers.

```text
drag-lint context --task "verb qname" [--db <file.sqlite>] [--format md|json|raw] [--no-docs] [--full-surface] [--library-db <library.sqlite>] (AI-ready symbol bundle: doc + class surface + the target body + capped callers. When the task phrase matches a dl:wiki topic ALIAS, up to 2 topics ride along as a "## Wiki" section -- suppressed by --no-docs. A qname that resolves to nothing now exits 1 and SAYS so)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--task` |  |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--no-docs` |  |  |  |
| `--full-surface` |  |  |  |
| `--max-callers` | `N` |  |  |
| `--context` | `N` |  |  |
| `--library-db` | `<library.sqlite>` |  |  |

Described in [context](features/context.md).

### convert-apply

Locates .dfm component instances that match a #convert rule from a conversion-rules file and rewrites all five surfaces: declaration retype, uses-add.

```text
drag-lint convert-apply --unit <F.pas> [--unit <G.pas> ...] --rules <file> --db PATH [--db ...] [--only Name1,Name2,...] [--castlib <file>] [--apply] [--no-backup] [--raise-encoding "<path>=utf8-bom" ...] [--no-warn-unlinked] [--no-reconcile-uses] [--no-reindex] [--progress] [--format json|--json] (locates .dfm component instances matching a #convert rule and rewrites all 5 surfaces: declaration retype + uses-add + .dfm re-emit + property/event access-site rewrite + runtime-creator retype/TODO markers; without --apply this is DRY-RUN ONLY (preview, writes nothing); --apply writes for real with backups + a recovery.txt unless --no-backup; --format json emits schema apply/1 -- the six report surfaces plus a typed items[] carrying a machine-readable kind per line, so the conversion REMAINDER can be dispatched on instead of parsed out of prose, plus resolved_defaults[] (informational receipts, kept OUT of items[] because on a real form they run to thousands and would bury the remainder); --castlib names the .castlib whose enum blocks translate a #link value when the link carries a cast suffix; a source property some converted instance carries that no #link carries and no #ignore acknowledges is warned ONCE per (source type, property) as "dropped on N of M converted instance(s)" -- a minority count is the stronger signal -- and counted in json as unlinked_source_properties / unlinked_source_property_sites / unlinked[]; --no-warn-unlinked drops the warnings and keeps the count; the book's UNIT rules act on the unit too: #unuse Old removes it, #use New adds it to the implementation uses when absent from both clauses, #useswap Old -> New1[, New2] removes Old and adds each New once into the section Old was in (a unit that does not use Old gets no edit from the swap) -- a unit both added and removed is kept, an entry inside a {$IF...} region refuses the unit (exit 1, nothing written); with no sibling .dfm, no #convert block or no matching instance the unit rules run alone (component part skipped; a book with no unit rules still needs the .dfm, exit 1); json adds component_part, uses[] {action,unit,section,line,rule,reason}, uses_removed, uses_added; the To type's unit goes to the INTERFACE uses when the retyped field is declared in the interface, and is MOVED there from an implementation-only use (1.23.0);EVERY #convert block is validated and freshness-checked -- each #link/#default against its own From/To types, each #mapping against the blocks that #apply it -- with each path resolved segment by segment, no depth limit (a published leaf; each hop published, or public and class-typed; private never); a #convert type that resolves in no --db REFUSES the unit, dry run and --apply alike -- an index gap, not a rule error ('<Type> (line N) resolves in no --db -- index gap in the library or project index; reindex, or report it, before converting'); json classes_built counts the classes whose members were resolved; a #link/#default/#mapping path through a member that exists but is inaccessible is SKIPPED, never applied and never an error -- the unit converts the rest -- and reported as a 'line N: warning: ...' line (text: under Warnings; json: warnings[] strings, items[] kind rule-path-unreachable, and unreachable[] {line,path,member,visibility,class,reason,message}); an inherited/inline .dfm object of a From type whose declaring ancestor is not converted is SKIPPED, never converted, while the unit's own instances, code and unit rules convert (1.22.0) -- each reported as a 'line N: warning: ...' line (json: warnings[], items[] kind inherited-instance-skipped, and inherited[] {name,type,line,ancestor_unit,ancestor_state,reason,action}; ancestor_state unconverted|converted|mismatched|outside: the declaring ancestor -- the nearest ancestor class whose .dfm opens it with object -- still has the From type, already has the To type, has a third type, or is not determinable: in no --db, or an ancestor .dfm on the way is missing or binary, which stops the walk; --only filters inherited[] too); one whose declaring ancestor ALREADY has the To type is RETYPED (1.26.0, C8 N2): inherited X: TFrom -> inherited X: TTo, keyword kept, nested and inline-frame children too; the properties its block overrides convert per the book (what it does not stream it inherits: no default resolved, no #default written); its code access sites are rewritten as for an own instance and the To unit is added; every code access to a field a converted ancestor declares (bound by the resolver, any level up) is rewritten too, .dfm block or not (N2a) -- json inherited[].action retyped|code|skipped|unverified (code: line = its first .pas reference), a converted[] line and items[] kind inherited-instance-retyped, not a warning; --only filters both; info capability inherited_retype; a code-only use of an UNCONVERTED ancestor's field is listed as action skipped, ancestor_state unconverted, reason 'ancestor not converted' (1.26.7, capability inherited_code_unconverted); the book's #warn <FromPath> "<text>" fires once per converted instance whose SOURCE .dfm streams FromPath (<value>, <name>, {Prop} expanded) -- 'line N: warning: <inst>: <text>', items[] kind book-warning with value; #check-ref <ToPath> <Class>.<Prop>[, ...] warns when the converted ToPath value contains \ or : (ref-path-like) or no listed Class.Prop of any .dfm in the project index carries it (ref-dangling), and once per run ref-not-checked when the index holds no .dfm property facts; info capabilities book_warn, check_ref (1.26.5); every code rewrite is scoped to the instance's field (receiver bound to it, or unbound / bare / Self. in a routine of the .dfm root class with no same-named local); a site the index cannot vouch for is NOT rewritten and is reported ('access site <file>:<line> ... not verified against the index -- not rewritten', items[] kind access-site-unverified, json access_sites_unverified); a --db resolved before resolver 1.12.0 is REFUSED, dry run too, naming the index ... --resolve-only fix; a #link carrying a cast never rewrites a .pas access site (1.27.0, interim): the cast's pas template is a statement with no correct splice inside an expression, so each bound site is reported -- 'line N: #link To <- From : Cast -- access site <file>:<line> <inst>.<From> not rewritten: ... convert this access site by hand', items[] kind cast-not-applied with instance, file, line and value (the cast); no .pas edit, the .dfm half of the cast unchanged; kind cast-applied is retired; info capability cast_site_refusal; a VALUE cast -- a castlib block with 'value strip-db' (shipped: StripDB, #link TableName <- TableName : StripDB) -- removes one trailing .db, any case, from the linked string: in the .dfm of each converted instance, and in .pas assignments whose right-hand side is ONE string literal; any other assignment and every read get no edit and a warning (items[] value-cast-applied {old_value,value} / value-cast-check; text 'value casts: N value(s) changed ...'); an unknown value keyword fails the run; info capability value_cast_strip_db (1.27.0); json pas_uses[] (1.27.0, dry run and --apply; info capability pas_uses) lists what the .pas still uses that the map does not cover: one row per (instance, member) the code reaches through a converted instance -- the access-site rewrite's own bound sites -- and one per global (routine/const/var/type) from a unit the reconciliation removes: {instance,from_type,to_type,member,kind method|property|field|event|const|var|type|routine|enum-value,visibility,declaring_unit,declared_in,status mapped|cast-refused|same-name|unmapped|global-dangling,lines[],count,resolution resolved|ambiguous|class-not-found|member-not-found|kind-unknown,candidates[]}; the From class is resolved through the unit's scope (the unit itself, then the LAST uses entry declaring it, then the book's qualified #convert From, then a lone declarer) -- several declarers left over is resolution ambiguous with candidates[] units and empty kind/declarer, never a pick (1.28.2, info capability pas_uses_resolution); text prints 'pas uses: N unmapped, M global-dangling, K same-name, J mapped, C cast-refused' and one line per unmapped member; a DESCENDANT unit (a class descending from the unit's root class at any level, or a form hosting it inline) that still streams a converted instance in its .dfm or uses it in code is a WARNING, never a refusal (1.25.0): 'line N: warning: descendant <Unit> still streams <Name> as <TOld> -- convert it next (needs C8 N2)', N = the instance's object line in this .dfm (json: items[] kind descendant-not-converted, descendants[] {unit,name,type,line,reason}; line = the descendant .dfm block, else its first code reference; reason dfm|code|both; --only filters it; only descendants the --db index are seen); a plan the edit applier would refuse in part (overlapping delete ranges -- an engine defect) fails the WHOLE unit before anything is written, dry run too, and a write that fails part-way is ROLLED BACK byte-identical (exit 2, '-- rolled back, unit not changed'; a failed rollback names the files it could not restore) (1.25.1): exit 1, 'ERROR: refused N edit(s) to <file> -- overlapping delete ranges (an engine defect) -- unit not changed, nothing written', json ok=false with that error; a .dfm component nested in another converted one is spliced into its parent's re-emit, and --only naming the parent converts it too (json only_included[] {name,parent}, text '--only: <child> converts too -- nested in <parent>'); a collection property (FieldDefs = < item ... end>) whose item members the book links (#link X.Items.* <- X.Items.*, identity) is carried whole when the To type publishes X with the same collection type, else reported NOT carried with its item count and counted as dropped, #ignore X notwithstanding; a deliberate refusal writes nothing and prints one 'REFUSED: <reason>' line -- a uses entry to change inside a {$IF...} region; an instance whose indexed .dfm span no longer holds it (lines added or removed, a block shrunk onto a sibling's end, or the .dfm cut short: '<Name>: index is stale for this .dfm -- reindex'); a #unuse / #useswap removing the unit that declares the From type of an instance left unconverted (skipped, inherited/inline, or excluded by --only) is refused too ('<rule> would leave <N> unconverted instance(s) of <Type> -- unit not changed') -- EXCEPT that with --only, when every such instance is one --only left out, the removal is SKIPPED (1.23.0: unit kept; json uses[] action skipped with a reason, a 'line N: warning:' line, items[] kind unit-rule-skipped; info capability only_skips_unit_rules); USES RECONCILIATION (1.27.0, C9, default on; --no-reconcile-uses = the 1.26.6 rules above, exactly): the converted .pas/.dfm are RE-INDEXED IN MEMORY (the indexer's own extractor, no DB written, so the dry run shows the --apply plan) and every #unuse / #useswap Old is a WATCH LIST -- the unit is KEPT while a component the converted .dfm still streams has a class declared in it (an unconverted instance, a second component type of that unit, an inherited instance the ancestor has not converted: R26's refusal becomes this, the --only skipped row is unchanged), REMOVED when only .pas code needs it (its dangling references named, the compile errors are the signal), KEPT when no --db indexes it; presence is scope-alias aware (#unuse DBTables matches Bde.DBTables, #use DB is satisfied by Data.DB); a bare name the conversion INTRODUCES into the .pas gets its declaring unit added -- interface uses when referenced above implementation -- and a name (or To type) two units declare is REPORTED, never picked (add #use <unit> to choose); a To-type tie the book's #use (or a uses entry of the unit) settles takes that unit, into the INTERFACE uses when the retyped field is declared there, or MOVED there (C9 A8-1); the C13 move is a row; every unit the #convert surface adds (a To type's unit, a #convert header's trailing unit) is an add row too (rule #convert, source rule, counted by uses_added; none when already present); json: uses[] action remove|add|skipped|kept|moved with source rule|reconcile|convert and needed_by[] {name,line,section}, uses_kept, uses_moved, uses_unresolved[] {name,line,section,reason ambiguous|not-found,candidates[] {unit,db}}, uses_reconcile on|off|degraded, items[] kinds unit-rule-kept, unit-rule-dangling, unit-rule-unverified, uses-unit-ambiguous (all warnings); after --apply the unit's OWN project DB -- the one --db that indexes it, a project index holding one .dproj/.dpr -- is refreshed with 'index --project <it> --db <it>' in a child process (json uses_reindex {status done|skipped|failed|dry-run|off,db,project,ms,reason}; a child still running after 10 minutes is terminated: failed; --no-reindex skips it; no other DB is ever written); info capability uses_reconcile; inside a #convert block '#migrate Old -> New' renames the member at every bound .pas access site of the block's converted instances (methods, events, properties; json items[] migrate-applied) and '#migrate Old -> DL_NONE' wraps each site, inst.Old -> DL_NONE(inst.Old), a deliberate break that does not compile until converted by hand (items[] deliberate-break, field todos); both make pas_uses[] status mapped; a with block, an unverified receiver, a scoped / template form or a member a #link already converts is never rewritten (items[] migrate-check); info capability migrate_members (C18 slice 1); an IDENTIFIER #migrate (file scope, or in a block naming uses units or an enum-value target; 1.38) renames every bare Old token in the .pas code -- var/param/field/result types, casts, is/as, generic arguments, enum literals; never comments or strings -- when New resolves in a --db (else items[] migrate-check per site, no rename), maps an enum type pair member by member on the name after the lowercase prefix (an explicit #migrate member line overrides; an unmatched member in use is a migrate-check), never renames a qualified Unit.Old site (migrate-check), and adds the unit declaring New to uses (interface uses when a site is there); info capability migrate_identifiers; --only names match case-insensitively; a name matching no #convert instance is ignored, never an error, and reported (json only_matched[] / only_unmatched[], always present; text '--only: no #convert instance named X (ignored)'); --unit may repeat (1.23.0): every unit runs in ONE process sharing one rule-book validation and one member cache -- text: one '=== unit i of N: <path> ===' section per unit, then 'batch: N unit(s) -- a ok, b refused, c failed; classes_built K; exit E'; json: ONE apply-batch/1 document {mode,rules_file,units_count,ok,exit_code,ok_count,refused_count,failed_count,classes_built (the run total),units[]: one apply/1 per unit, each equal to that unit's single run -- its classes_built is the unit's own}; under --apply a file a unit cannot write fails that unit before anything is written (exit 2); a unit's refusal or failure never stops the others; exit = the worst unit's; info capability batch_units; 1.33.0: every apply/1 (single or units[]) carries exit_code (that unit's); a --unit no --db indexes is REFUSED, dry run and --apply alike (reason '<unit> is not covered by any supplied --db ...'); --progress writes one STDERR line per finished unit, flushed, stdout unchanged, off by default -- {"progress":{"verb":"convert-apply","unit_done":i,"units":N,"unit":"<path>","ok":b,"refused":b,"exit_code":E}} (info capability batch_progress); json has ok=false, refused=true (a JSON bool) and reason = that text -- every other outcome, success or failure, has refused=false and reason '')
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<F.pas>` |  |  |
| `--rules` | `<file>` |  |  |
| `--db` | `PATH` |  |  |
| `--only` |  |  |  |
| `--castlib` | `<file>` |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--raise-encoding` | `<path>=utf8-bom` |  |  |
| `--no-warn-unlinked` |  |  |  |
| `--no-reconcile-uses` |  |  |  |
| `--no-reindex` |  |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

Described in:

* [convert-apply](features/convert-apply.md)
* [convert-apply #migrate (member, type and enum rename / DL_NONE)](features/convert-apply-migrate.md)

### convert-scaffold

Auto-generates a valid conversion-rules file from the real property trees of a from-type and a to-type.

```text
drag-lint convert-scaffold --from <FromType> --to <ToType> [--output <file>] [--surface dfm|pas] [--depth N] [--rules <file>] [--progress-interval S] --db PATH [--db ...] (auto-generate a VALID conversion-rules file from the real F/T property trees, expanded to --depth N, else the --rules book's #depth N, else 5 (a bad value exits 2): concrete #link where 1 source matches by leaf-name+type, ??? for ambiguities, DROPPED notes for orphaned F props; --surface picks the TO-side target bar, default dfm=published-properties-only, pas=published+public incl. public fields; is_writable=false targets are never auto-linked on either surface; --progress-interval S: see PROGRESS below)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--from` | `<FromType>` |  |  |
| `--to` | `<ToType>` |  |  |
| `--output` | `<file>` |  |  |
| `--surface` |  |  |  |
| `--depth` | `N` |  |  |
| `--rules` | `<file>` |  |  |
| `--progress-interval` | `S` |  |  |
| `--db` | `PATH` |  |  |

Described in [convert-scaffold](features/convert-scaffold.md).

### convert-validate

Parses and validates a conversion-rules file (a reFind-superset DSL), checking its #link/#default paths against the real property trees.

```text
drag-lint convert-validate --rules <file> [--from <FromType>] [--to <ToType>] [--print-parsed] [--db PATH ...] (parse+validate a reFind-superset conversion-rules DSL; checks #link/#default paths against the real --from/--to members, segment by segment with no depth limit (a published leaf; each hop published, or public and class-typed; private never) -- lazily, per class, no tree is built, so --depth and the book's #depth are ignored here (and by the hidden convert-reemit), though a bad #depth (not 1..10, or a second one) is a line N error, and so is a From-only header ('#convert TFoo -> ' or '#convert TFoo': '#convert TFoo has no To type'; '#useswap X -> ': '#useswap X has no replacement unit'); and a #link glyph expression (<FromPath> G[I/N], stitched G[1/6]G[2/6], per-N alternatives split by commas, G[count]) for syntax, I in 1..N and one alternative per N, naming the column; 'line N: warning:' lines (e.g. a straight NumGlyphs carry beside a G-link) never change the exit code; a path whose members all EXIST but one is inaccessible (private anywhere, protected anywhere, a public leaf) is a warning on stdout, not an error: 'line N: warning: <path>: <Member> is <visibility> in <Class>; never applied unless a descendant class changes its visibility' -- only a segment naming no member is "not found" (exit 1); without BOTH --from and --to the book is only PARSED -- no path is checked -- and a 'NOTE:' line on stderr says so; a #warn path or {Prop} placeholder, or a #check-ref ToPath, naming no member is a line N error, and so is a malformed #warn / #check-ref (1.26.5); no JSON mode)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rules` | `<file>` |  |  |
| `--from` | `<FromType>` |  |  |
| `--to` | `<ToType>` |  |  |
| `--print-parsed` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [convert-validate](features/convert-validate.md).

### create-enum-helper

Generates a Byte-family record helper (ToByte/FromByte/ToInteger/ FromInteger/ToString/FromString) for an enum type.

```text
drag-lint create-enum-helper --qname <TEnum> [--apply|--json|--no-backup] [--methods <csv>] [--tostring rtti|case] [--db PATH] - generate a Byte-family record helper for an enum
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<TEnum>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--methods` | `<csv>` |  |  |
| `--tostring` |  |  |  |
| `--db` | `PATH` |  |  |

Described in:

* [create-enum-helper](features/create-enum-helper.md)
* [Create helper class](features/create-helper-class.md)

### cycles

Finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them.

```text
drag-lint cycles --db <file.sqlite> [--edges] [--causes] [--plan [--project <X.dproj>]] [--f2047 [--unit <stem>]] [--fix --project <X.dproj> [--cycle <n> | --unit <stem>] [--part a|b|all] [--apply] [--no-backup] [--no-reindex] [--no-compile] [--shadow-out <dir>] [--rsvars <path>] [--build-timeout <s>]] [--format json|text] [--library-db <lib.sqlite>] [--platform win32|win64] [--rules-dir <dir>] (circular unit deps; --f2047 = only the interface-only cycles dcc rejects with F2047, each edge with its forcing symbols and the next --plan / --fix commands; --plan = mechanical refactoring playbook: moves, uses edits, new-unit text, checklist + predicted output, and a "Fix it" block per group naming the exact --fix dry-run and --apply commands; --fix = the mechanical fix of one group, see the cycles-fix entry)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--edges` |  |  |  |
| `--causes` |  |  |  |
| `--plan` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--f2047` |  |  |  |
| `--unit` | `<stem>` |  |  |
| `--fix` |  |  |  |
| `--cycle` | `<n>` |  |  |
| `--part` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--no-reindex` |  |  |  |
| `--no-compile` |  |  |  |
| `--shadow-out` | `<dir>` |  |  |
| `--rsvars` | `<rsvars.bat>` |  |  |
| `--build-timeout` | `<s>` |  |  |
| `--format` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--platform` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |

Described in:

* [Circular Uses Report (cycles + fix plan)](features/circular-uses-report-cycles-fix-plan.md)
* [Cycles fix (mechanical, compile-gated)](features/cycles-fix.md)

### deps-report

Produces a third-party dependency rollup from an index: which external units/libraries an indexed codebase depends on.

```text
drag-lint deps-report --db <file.sqlite> [--db ...] [--depth N] [--edges] [--all-sources] [--name <pat>] [--format text|json|csv] [--output <file>] (third-party dependency rollup)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--depth` | `N` |  |  |
| `--edges` |  |  |  |
| `--all-sources` |  |  |  |
| `--name` | `<pat>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |

Described in [deps-report](features/deps-report.md).

### diff

Compares two index databases and reports what changed between them -- for example an index snapshot taken before and after a refactor.

```text
drag-lint diff --db <old.sqlite> --db <new.sqlite> [--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<old.sqlite>` |  |  |
| `--json` |  |  |  |

Described in [diff](features/diff.md).

### doc-drift

Diagnostic that computes deterministic doc-vs-code drift findings for one symbol.

```text
drag-lint doc-drift --qname X --db PATH [--json] (diagnostic: deterministic doc-vs-code drift findings for one symbol)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `X` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

Described in [doc-drift](features/doc-drift.md).

### doc-forget

Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply.

```text
drag-lint doc-forget --scope <file.pas|dir> (--project <Tag> [--rename <Tag>=<New>] | --untagged | --list-tags) [--apply|--no-backup] - reap project tags on inbound doc facts
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--scope` | `<file.pas\|dir>` |  |  |
| `--project` | `<Tag>` |  |  |
| `--rename` | `<Tag>` |  |  |
| `--untagged` |  |  |  |
| `--list-tags` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |

Described in [doc-forget](features/doc-forget.md).

### document

Writes DocInsight documentation into every public declaration a project owns.

```text
drag-lint document --qname <Foo.TBar.Baz> [--profile <name>] [--apply|--json|--no-backup|--migrate-pure] [--db PATH] - generate/repair a managed DocInsight comment
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

Described in:

* [Auto-Document Whole Project](features/auto-document-whole-project.md)
* [Document it](features/document-it.md)
* [Document project](features/document-project.md)
* [Document unit](features/document-unit.md)

### document-all

Documents every public declaration in every indexed unit, with no project scope.

```text
drag-lint document-all [--profile <name>] [--stubs|--apply|--json|--no-backup|--include-accessors|--migrate-pure] [--db PATH] - document every public decl in every indexed unit (no project scope)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--stubs` |  |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--include-accessors` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [document-all](features/document-all.md).

### dump-call-edges

Diagnostic that dumps every resolved call edge in the index as refid|targetqname|confidence rows.

```text
drag-lint dump-call-edges --db PATH (diagnostic: resolved call edges: ref_id|target_qname|confidence)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |

Described in [dump-call-edges](features/dump-call-edges.md).

### dump-refs

Diagnostic that dumps every ref in a file together with its enclosingsymbolid attribution.

```text
drag-lint dump-refs <file> --db PATH (diagnostic: refs + enclosing_symbol_id attribution)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |

Described in [dump-refs](features/dump-refs.md).

### exceptions-sync

Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites.

```text
drag-lint exceptions-sync [--profile <name>] [--db <file.sqlite>] [--config <lint.json>] [--apply] [--json] (materialise the project's derived exception classes)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--config` | `<lint.json>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

Described in [exceptions-sync](features/exceptions-sync.md).

### export

Uses export enums with --format delphi-const to dump indexed enum types as Delphi const declarations.

```text
drag-lint export enums --db <file.sqlite> [--format firebird-sql|csv|json|delphi-const] [--output <file>]
drag-lint export obsidian --db <file.sqlite> --output-dir <dir> [--open]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |
| `--output-dir` | `<dir>` |  |  |
| `--open` |  |  |  |

Described in:

* [Export Enums (Delphi const)](features/export-enums-delphi-const.md)
* [Export to Obsidian](features/export-to-obsidian.md)

### extract-method

Pulls a run of statements out of a routine into a new method.

```text
drag-lint extract-method --in <F> --from-line <L1> --to-line <L2> --name <N> [--json|--apply|--no-backup] - pull a statement run into a new method
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<F>` |  |  |
| `--from-line` | `<L1>` |  |  |
| `--to-line` | `<L2>` |  |  |
| `--name` | `<N>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |

Described in [extract-method](features/extract-method.md).

### fb-snapshot

Connects to a Firebird database and captures a snapshot into a sqlite index.

```text
drag-lint fb-snapshot --connection "Database=...;User=...;Password=...;DriverID=FB" --db <sql.sqlite>
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--connection` |  |  |  |
| `--db` | `<sql.sqlite>` |  |  |

Described in [fb-snapshot](features/fb-snapshot.md).

### find-callees

Lists the resolved outgoing calls of one routine, plus the library-bound ones.

```text
drag-lint find-callees --qname <Foo.Bar> --db PATH [--db LIBRARY | --library-db LIBRARY] [--json] (resolved outgoing calls of routine X; library-bound callees are marked library)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `PATH` |  |  |
| `--library-db` | `LIBRARY` | the library index to bind library-bound callees against at read time (a second --db does the same) |  |
| `--json` |  |  |  |

Described in [find-callees](features/find-callees.md).

### find-deadcode

Scans the index for code with no references -- candidates to delete.

```text
drag-lint find-deadcode [--kind method|function|...] [--include-private] [--db PATH]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--kind` |  |  |  |
| `--include-private` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [Find Dead Code](features/find-dead-code.md).

### find-unit

Finds which indexed unit declares a symbol, and adds that unit to a file's uses clause.

```text
drag-lint find-unit --name <Symbol> --in <file> [--json|--apply|--no-backup] --db <db> - add the declaring unit to uses
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<Symbol>` |  |  |
| `--in` | `<file>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

Described in [find-unit](features/find-unit.md).

### format

Runs YADF formatting across a project's files, with indexing involved as part of the same action.

```text
drag-lint format <file> [--yadf-path PATH] [--dry-run] [--diff] (rewrites the file IN PLACE via YADF; --dry-run resolves + version-checks and writes nothing, --diff formats a copy and prints the diff. Refuses YADF older than 1.0.6.6 (exit 4) and restores the file if formatting changes what the unit declares (exit 5))
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--yadf-path` | `PATH` |  |  |
| `--dry-run` |  |  |  |
| `--diff` |  |  |  |

Described in:

* [Format Whole Project with YADF](features/format-whole-project-with-yadf.md)
* [Format with YADF](features/format-with-yadf.md)

### forms-csv

A CSV of a project's forms, one row per form, telling a tester how to reach each one from the main form.

```text
drag-lint forms-csv --project <X.dproj> --db <file.sqlite> [--output <f.csv>] [--root <TfrmMAIN>] (tester CSV, one row per form: menu/ribbon/tab path, control, handler, modal, confidence)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--output` | `<f.csv>` |  |  |
| `--root` | `<TfrmMAIN>` |  |  |

Described in [Forms for testers (CSV)](features/generate-test-helper-csv.md).

### gain

Sums the per-user usage log: tokens returned versus source bytes avoided, per verb and per day.

```text
drag-lint gain [--since yyyy-mm-dd] [--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--since` | `yyyy-mm-dd` |  |  |
| `--json` |  |  |  |

Described in [Gain (counted savings)](features/gain-usage-log.md).

### generate-docs

Uses generate-docs to produce a doc-comment stub for one qualified symbol.

```text
drag-lint generate-docs --qname <Foo.TBar.Baz> [--format xmldoc|pasdoc] [--db PATH]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--format` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [Doc Comment Stub (symbol)](features/doc-comment-stub-symbol.md).

### generate-test

Uses generate-test to produce a unit-test skeleton for one qualified symbol.

```text
drag-lint generate-test --qname <Foo.TBar.Baz> [--framework dunitx|dunit] [--db PATH]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--framework` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [Unit Test Stub (symbol)](features/unit-test-stub-symbol.md).

### ghost-check

Compiles a project with one or more units' content temporarily replaced by their unsaved editor buffers, then restores the original files unchanged.

```text
drag-lint ghost-check <dproj> ( --unit <real.pas> --buffer <buf> | --overlays <manifest> ) [--platform win32|win64] [--in-place] [--format json|text]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<real.pas>` |  |  |
| `--buffer` | `<buf>` |  |  |
| `--overlays` | `<manifest>` |  |  |
| `--platform` |  |  |  |
| `--in-place` |  |  |  |
| `--format` |  |  |  |

Described in [ghost-check](features/ghost-check.md).

### ghost-recover

Scans a project's hidden D-RAG folder for recovery journals left behind when a ghost-check overlay was interrupted by a crash.

```text
drag-lint ghost-recover <dproj> (restore any file left overlaid by an INTERRUPTED ghost-check)
```

Described in [ghost-recover](features/ghost-recover.md).

### glyph-vacuum

Measure every streamed glyph or picture under a tree before writing a glyph rule.

```text
drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...] (measure every streamed graphic under the roots before writing a glyph rule: walks .dfm/.fmx, decodes each Picture.Data/Glyph.Data blob (wrapper class, format, width/height/bpp/palette), pairs it with its count property (NumGlyphs and kin), writes instances.tsv + classes.tsv + skipped.tsv + images\ + gallery.html into --output; --append merges into an existing --output; --db only qualifies class_unit / declared count default / runtime_refs)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--root` | `DIR` |  |  |
| `--output` | `DIR` |  |  |
| `--append` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [glyph-vacuum](features/glyph-vacuum.md).

### graph

Uses graph to export the indexed call/reference graph in DOT format, either whole or rooted at a name substring.

```text
drag-lint graph --db <file.sqlite> [--format dot|mermaid] [--name <root-substr>] [--output <file>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--name` | `<root-substr>` |  |  |
| `--output` | `<file>` |  |  |

Described in [Export Graph (DOT)](features/export-graph-dot.md).

### helpers-of

Lists record/class helper edges targeting a given type, anywhere in the index.

```text
drag-lint helpers-of <T> [--json] --db <db> - list record/class helper edges targeting type T anywhere in the index
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--db` | `<db>` |  |  |

Described in [helpers-of](features/helpers-of.md).

### hover

Shows a hover card for the symbol under the editor caret: signature, documentation, and callers.

```text
drag-lint hover --qname <Foo.Bar> [--db <file.sqlite>] [--format plain|md|json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

Described in [Hover at Cursor](features/hover-at-cursor.md).

### ide-release

Asks a running drag-lint Delphi IDE plugin not to respawn its drag-lint.exe child processes for a while -- and to drop the running one on its next request.

```text
drag-lint ide-release [--seconds N] [--resume] [--status] [--json] (writes a hold sentinel: a running Delphi IDE plugin will not respawn drag-lint.exe while it lasts and stops its LSP child on the next request that wants it, so the engine binary can be rebuilt while the IDE stays open; default 120s, --resume clears it early. Frees nothing by itself -- build\stage-engine.ps1 kills the running holder and retries. The plugin job queue also DEFERS its heavy jobs for the duration rather than starting them)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--seconds` | `N` |  |  |
| `--resume` |  |  |  |
| `--status` |  |  |  |
| `--json` |  |  |  |

Described in [ide-release](features/ide-release.md).

### impact

Reports what would be affected if a chosen symbol changes -- the set of code to retest.

```text
drag-lint impact --qname <Foo.Bar> [--db <file.sqlite>] [--depth N] [--format text|json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |

Described in [Impact / Blast Radius (symbol)](features/impact-blast-radius-symbol.md).

### import-log

Parses an external dcc or msbuild build log and folds its errors and warnings into drag-lint's stored findings.

```text
drag-lint import-log <logfile> --db <file.sqlite> (parse dcc/msbuild log)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |

Described in [Import Build Log](features/import-build-log.md).

### index

Writes DocInsight documentation into every public declaration a project owns.

```text
drag-lint index <path> [--db <file.sqlite>] [--watch [--interval N]] [--library-db <lib.sqlite> ...]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--watch` |  |  |  |
| `--interval` | `N` |  |  |
| `--library-db` | `<lib.sqlite>` | consult another index for calls THIS one cannot resolve (value receivers typed by name bind too; the manifest key libraryResolve opts a section in). |  |
| `--wait-library` | `<min>` | when the platform library of a libraryResolve section is NOT READY, probe every 30 s up to `min` minutes, then continue (marked pending). |  |
| `--require-library` |  | a not-ready platform library is ERROR, exit 2, instead of continuing against the project only. |  |
| `--max-file-kb` | `N` |  |  |
| `--no-use-ignore` |  |  |  |
| `--no-sql-ms` |  |  |  |
| `--deep` |  |  |  |
| `--shallow` |  |  |  |
| `--exclude-under` |  |  |  |
| `--include-only` |  |  |  |
| `--project` | `<file.dproj>` |  |  |
| `--build-config` | `<Release\|Debug\|name>` |  |  |
| `--recompile` |  |  |  |
| `--rebuild` |  |  |  |
| `--dry-run` |  |  |  |

Described in:

* [Auto-Document Whole Project](features/auto-document-whole-project.md)
* [Format Whole Project with YADF](features/format-whole-project-with-yadf.md)
* [Include-file indexing and IF evaluation](features/inc-indexing.md)
* [Index a project against its active build config](features/index-build-config.md)
* [Rebuild Index for This Project](features/rebuild-index-for-this-project.md)
* [Rescan this unit](features/rescan-this-unit.md)

### info

The plugin's status window -- versions, connection health, and which indexes are actually in use.

```text
drag-lint info [--json] [--db <file.sqlite>]... (engine self-info: product/extractor/resolver versions, build date, MIT, tree-sitter + capabilities; read-only)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--db` | `<file.sqlite>` |  |  |

Described in:

* [About and Status](features/about-and-status.md)
* [info](features/info.md)

### init

Registers a project in the manifest, indexes it, finds its index and wires Claude Code, VS Code and Cursor to serve it, in one command.

```text
drag-lint init --project <file.dproj> [--dry-run] [--home-dir <dir>] [--appdata-dir <dir>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<file.dproj>` |  |  |
| `--dry-run` |  |  |  |
| `--home-dir` |  |  |  |
| `--appdata-dir` |  |  |  |

Described in [init: one command from a project to a wired AI client](features/init-wiring.md).

### library-drift

Flags registered library roots that have source on disk but nothing in the index.

```text
drag-lint library-drift [--platform <p>] [--config <path>] [--json] - registry library roots that have source on disk but none in the index (exit 2 if drift; roots the section exclude prunes are listed as excluded, not counted)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--platform` | `<p>` |  |  |
| `--config` | `<path>` |  |  |
| `--json` |  |  |  |

Described in [Library Drift Check](features/library-drift-check.md).

### link-orm

Links a project's code index to a SQL index so ORM-style relationships between Delphi symbols and SQL objects can be resolved across both.

```text
drag-lint link-orm --db <projDb.sqlite> --db <sqlDb.sqlite>
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<projDb.sqlite>` |  |  |

Described in [link-orm](features/link-orm.md).

### lint

lint --fix repairs findings of the 110 fixable rules; --json reports per finding whether it was applied; lint accepts a folder.

```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--project-rules` |  |  |  |
| `--build-config` | `<name>` |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

Described in:

* [Autofix for fixable rules](features/autofix-wave.md)
* [Copy All Diagnostics](features/copy-all-diagnostics.md)
* [Copy Diagnostics (Current File)](features/copy-diagnostics-current-file.md)
* [Fix all in unit](features/fix-all-in-unit.md)
* [Fix all reliability (1.31.3)](features/fix-all-reliability.md)
* [Fix it](features/fix-it.md)
* [Lint Buffer (Unsaved)](features/lint-buffer-unsaved.md)
* [Rename across every project that compiles a shared unit](features/multi-project-rename.md)
* [Target compiler (--target-compiler)](features/target-compiler.md)
* [type-name-prefix: expected letter from the ancestor chain](features/type-name-prefix-origin.md)

### lint-all

Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field.

```text
drag-lint lint-all [--profile <name>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--project` | `<.dproj>` |  |  |
| `--build-config` | `<name>` |  |  |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--output` | `<report.txt>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--quiet` |  | suppress per-file progress lines written to stderr |  |
| `--lint-third-party` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--fix` |  |  |  |
| `--fix-naming` |  |  |  |
| `--apply` |  |  |  |

Described in:

* [Compliance labels (CWE, CERT, MISRA)](features/compliance-labels.md)
* [Fix all in project](features/fix-all-in-project.md)
* [Run Lint All (Full Report)](features/run-lint-all-full-report.md)
* [Taint analysis (SQL, command, path)](features/taint-analysis.md)
* [Target compiler (--target-compiler)](features/target-compiler.md)
* [type-name-prefix: expected letter from the ancestor chain](features/type-name-prefix-origin.md)

### lint-project

Runs project-scoped structural lint rules against an index -- checks such as god-class, unused-public-symbol.

```text
drag-lint lint-project --db <file.sqlite> [--profile <name>] [--rule god-class|unused-public-symbol|interface-reference-cycle|layering-violation|unused-private-member|unused-unit-in-uses|circular-uses|repeated-type-switch|global-only-uses-edge|duplicate-global-decl|uses-global-census|discarded-effect-free-result|query-name-with-effect|assert-with-side-effect|enum-ordinal-persisted|unused-enum-value] [--layers <f.json>] [--json] [--output <f>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--rule` |  |  |  |
| `--layers` | `<f.json>` |  |  |
| `--json` |  |  |  |

Described in [lint-project](features/lint-project.md).

### lint-tree

Answers one question lint-all cannot: does an interface edit to this unit reach any dependent?

```text
drag-lint lint-tree --unit <B.pas> --db <file.sqlite> [--buffer <buf>] [--project <.dproj>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<B.pas>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--buffer` | `<buf>` |  |  |
| `--project` | `<.dproj>` |  |  |
| `--baseline` | `<f.json>` |  |  |
| `--write-baseline` | `<f.json>` |  |  |
| `--platform` |  |  |  |
| `--with-rules` |  |  |  |
| `--compile` |  |  |  |
| `--format` |  |  |  |

Described in [lint-tree](features/lint-tree.md).

### lsp

Starts the LSP (Language Server Protocol) stdio server.

```text
drag-lint lsp --db <file.sqlite> (LSP stdio server) [--stdio] [--parent-pid <n>] [--clientProcessId <n>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--stdio` |  |  |  |
| `--clientProcessId` |  |  |  |
| `--proxy` |  |  |  |
| `--delphi-lsp` | `<path>` |  |  |
| `--trace` | `<file>` |  |  |
| `--merge-diagnostics` |  |  |  |
| `--merge-completion` |  |  |  |
| `--merge-hover` |  |  |  |
| `--merge-definition` |  |  |  |
| `--merge-budget-ms` | `<n>` |  |  |
| `--full-rules` |  |  |  |
| `--delphi-lsp-bits` | `32\|64` |  |  |
| `--no-preprocess` |  |  |  |

Described in:

* [lsp](features/lsp.md)
* [LSP full rule set on save](features/lsp-full-rules.md)
* [LSP proxy merge](features/lsp-proxy-merge.md)

### mcp-config

Adds drag-lint serve to Claude Code, VS Code and Cursor MCP config: merged, backed up, idempotent, removable.

```text
drag-lint mcp-config (--claude-code | --vscode | --cursor | --all) [--remove] [--dry-run] [--name <n>] [--db <index>] [--engine <exe>] [--config-path <file>] [--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--claude-code` |  |  |  |
| `--vscode` |  |  |  |
| `--cursor` |  |  |  |
| `--all` |  |  |  |
| `--remove` |  |  |  |
| `--dry-run` |  |  |  |
| `--name` | `<n>` |  |  |
| `--db` | `<index>` |  |  |
| `--engine` | `<exe>` |  |  |
| `--config-path` | `<file>` |  |  |
| `--json` |  |  |  |
| `--home-dir` |  |  |  |
| `--appdata-dir` |  |  |  |

Described in [Register the MCP server (Claude Code, VS Code, Cursor)](features/mcp-config-writer.md).

### menu-drift

The menu tree a Delphi program builds in code, read statically, and a check that the registered menu paths still match it.

```text
drag-lint menu-drift --project <X.dproj> --db <file.sqlite> --registry <features dir> [--with-dfm] [--format text|json] [--output <f>] (code-built menu tree vs the registry's ide-menu paths and app-menu (form, path) surfaces, which imply --with-dfm; --registry defaults to <project>\_D-RAG\menu-registry: missing / moved / unregistered / notes; exit 0 no drift, 1 drift, 2 usage/setup, 3 stale index)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--registry` | `<features dir>` |  |  |
| `--with-dfm` |  |  |  |
| `--format` | `text\|json` |  |  |
| `--output` | `<f>` |  |  |

Described in [Code-built menu tree and registry drift](features/menu-tree.md).

### menu-tree

The menu tree a Delphi program builds in code, read statically, and a check that the registered menu paths still match it.

```text
drag-lint menu-tree --project <X.dproj> --db <file.sqlite> [--root <QName>] [--with-dfm] [--format text|json|paths] [--output <f>] (the menu tree a program builds in code, read statically; --with-dfm adds the .dfm menus with code links grafted in; exit 0 ran, 2 usage/setup, 3 stale index)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--root` | `<QName>` |  |  |
| `--with-dfm` |  |  |  |
| `--format` | `text\|json\|paths` |  |  |
| `--output` | `<f>` |  |  |

Described in [Code-built menu tree and registry drift](features/menu-tree.md).

### migrate-dbs

Moves project index databases into each project's own D-RAG folder, matching the current index layout.

```text
drag-lint migrate-dbs [--config <drag-lint.json>] [--apply] move project indexes into each project's _D-RAG folder
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<drag-lint.json>` |  |  |
| `--apply` |  |  |  |

Described in [migrate-dbs](features/migrate-dbs.md).

### outline

Prints the file-scoped symbol outline for one Pascal unit.

```text
drag-lint outline --in <path.pas> [--db <path>] [--format text|json] [--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<path.pas>` |  |  |
| `--db` | `<path>` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

Described in [outline](features/outline.md).

### pp-profile

Diagnostic that prints the resolved preprocessor define profile for a project, one symbol per line.

```text
drag-lint pp-profile [--dproj PATH] [--platform win32|win64] [--config Release|Debug] [--in <file.pas> [--db <file.sqlite>]] (diagnostic: print the resolved define profile, one symbol per line; --in prints the profile of the owning project's active build)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--dproj` | `PATH` |  |  |
| `--platform` |  |  |  |
| `--config` |  |  |  |

Described in [pp-profile](features/pp-profile.md).

### preprocess-file

Diagnostic that prints a file's {$IFDEF}-resolved source to stdout under a given define set.

```text
drag-lint preprocess-file --in PATH [--define SYM]... [--numeric K=V]... [--include-mode off|defines-only] [--no-near-search] [--tolerances] [--include-sites] (diagnostic: print {$IFDEF}-resolved source to stdout)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `PATH` |  |  |
| `--define` | `SYM` |  |  |
| `--numeric` | `K` |  |  |
| `--include-mode` |  |  |  |
| `--no-near-search` |  |  |  |
| `--tolerances` |  |  |  |
| `--include-sites` |  |  |  |

Described in [preprocess-file](features/preprocess-file.md).

### project-context

Writes or checks the `.dlcontext.json` file beside a project: platform, config and define set, with the .dproj SHA-1 for staleness.

```text
drag-lint project-context --project <x.dproj|x.dpr> [--platform P] [--config C] [--output <file>] [--json] [--check] (writes <base>.dlcontext.json beside the project: platform, config and the complete effective define set, plus the .dproj SHA-1 for staleness; --check writes nothing and exits 1 saying why when the file is missing or stale; a .dpr with no .dproj exits 2 unless --platform and --config are both given)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<x.dproj\|x.dpr>` |  |  |
| `--platform` | `P` |  |  |
| `--config` | `C` |  |  |
| `--output` | `<file>` |  |  |
| `--json` |  |  |  |
| `--check` |  |  |  |

Described in [project-context](features/project-context.md).

### project-facts

Report what the build does: defines that are on and what sets each, imports, output paths and packages.

```text
drag-lint project-facts --dproj PATH [--platform win32|win64] [--config Release|Debug] [--db PATH] [--json] (what the BUILD does: defines ON and what sets each, <Import>s, output paths, packages; flags a post-processor define with no build step imported)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--dproj` | `PATH` |  |  |
| `--platform` |  |  |  |
| `--config` |  |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

Described in [project-facts](features/project-facts.md).

### proptree

Recursive deep-property enumerator for a class: flattens its own and inherited properties into dotted paths, recursing into class-typed properties.

```text
drag-lint proptree --qname <X> [--depth N] [--rules <file>] [--progress-interval S] [--no-to-persistent] [--refs-as-leaves] [--no-write-back] [--min-visibility published|public] [--format text|json] [--json] --db PATH [--db ...] (recursive deep-property enumerator: flattened dotted paths of a class's own+inherited properties, recursing into class-typed types; depth = --depth N (an integer >= 1), else the --rules book's #depth N (1..10), else 5 -- a K-segment path needs depth >= K-1; a bad --depth or #depth exits 2; --refs-as-leaves leaves TComponent-typed properties unexpanded (references, not owned sub-objects); types recovered by the ancestry-bridge are memoized back into the index automatically -- --no-write-back forces a read-only, non-mutating query; --min-visibility filters emitted leaves by effective visibility, default = all, schema proptree/2; --progress-interval S: see PROGRESS below)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--depth` | `N` |  |  |
| `--rules` | `<file>` |  |  |
| `--progress-interval` | `S` |  |  |
| `--no-to-persistent` |  |  |  |
| `--refs-as-leaves` |  |  |  |
| `--no-write-back` |  |  |  |
| `--min-visibility` |  |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--db` | `PATH` |  |  |

Described in [proptree](features/proptree.md).

### protocol

Registers draglint:// so a chart row opens its line in RAD Studio; a GUI helper exe, no PowerShell.

```text
drag-lint protocol register [--handler <drag-lint-open.exe>] [--dry-run] [--force] (HKCU\Software\Classes\draglint -> the handler; --force accepts a *-wt\ path or replaces a foreign registration)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--handler` | `<drag-lint-open.exe>` |  |  |
| `--dry-run` |  |  |  |
| `--force` |  |  |  |

Described in [Click-to-source: the draglint:// handler](features/protocol-handler.md).

### purge-locals

A size escape hatch for an index database that has grown too large: it drops local-variable and parameter symbols and runs VACUUM to reclaim space.

```text
drag-lint purge-locals --db PATH [--json] (size escape hatch: drop skLocalVar/skParam symbols + VACUUM; call graph unchanged; re-inflated on next index)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

Described in [purge-locals](features/purge-locals.md).

### query

Uses query hints to surface compiler hint/warning findings that have been imported into the index, filtered by code or severity.

```text
drag-lint query --concept "<words>" [--limit N] [--kind k,...] [--json] --db <db>
drag-lint query hints --db <file.sqlite> [--name <code>] [--rule <severity>]
drag-lint query find [--doc-tag X | --doc-contains Y | --decl-contains Z | --no-docs] [--kind K] [--name N] [--unit U] [--public] [--db ...]
drag-lint query ancestors --name <type> [--of <ancestor>] [--db ...] [--json] (transitive class/interface hierarchy)
drag-lint query descendants --of <ancestor> [--db ...] [--json] (the REVERSE of ancestors: every CLASS descending from <ancestor>, across all scanned DBs. Derived INTERFACES are deliberately excluded -- this backs the conversion editor's class pickers. exit 1 = no such ancestor)
drag-lint query find-callers --name <callee-name> [--context N] [--resolved] [--db ...] [--json]
drag-lint query type-usage --in <file.pas> (--names A,B,C | --names-file <f>) [--db ...] [--json]
drag-lint query typecat --name <type> [--db ...] [--json] (resolve type category: float/string/class/interface/...)
drag-lint query unit-usage --unit <UnitName> [--in <file.pas>] [--db ...] [--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--name` | `<code>` |  |  |
| `--rule` | `<severity>` |  |  |
| `--concept` | `<words>` |  |  |
| `--limit` | `N` |  |  |
| `--kind` | `<k,...>` |  |  |
| `--json` |  |  |  |
| `--doc-tag` | `X` |  |  |
| `--doc-contains` | `Y` |  |  |
| `--decl-contains` | `Z` |  |  |
| `--no-docs` |  |  |  |
| `--unit` | `U` |  |  |
| `--public` |  |  |  |
| `--of` | `<ancestor>` |  |  |
| `--context` | `N` |  |  |
| `--resolved` |  | precise callers via resolved call_edges (grouped by target, certain\|ambiguous); a PROPERTY/FIELD name lists its bound accesses [certain, read\|write]; an ENUM VALUE name lists each bound read [certain, read] (resolver 1.6.0-alpha) |  |
| `--case-sensitive` |  |  |  |
| `--exact` |  |  |  |
| `--text` | `"<phrase>"` |  |  |
| `--near` | `<QName>` |  |  |
| `--hops` | `1..3` |  |  |
| `--hops-uses` |  |  |  |
| `--near-boost` |  |  |  |
| `--in` | `<file.pas>` |  |  |
| `--names` | `A` |  |  |
| `--names-file` | `<f>` |  |  |

Described in:

* [Compiler Hints](features/compiler-hints.md)
* [query --concept](features/concept-search.md)
* [Find Undocumented (public)](features/find-undocumented-public.md)
* [query ancestors](features/query-ancestors.md)
* [query descendants](features/query-descendants.md)
* [query find-callers](features/query-find-callers.md)
* [query --kind --all](features/query-kind-all.md)
* [query --name-like](features/query-name-like.md)
* [query --text --near](features/query-text-near.md)
* [query type-usage](features/query-type-usage.md)
* [query typecat](features/query-typecat.md)
* [query unit-usage](features/query-unit-usage.md)
* [Symbol Search](features/symbol-search.md)

### reconcile-project

Lists every unit a project uses that is neither a project member nor in the library, judges each one (project unit or third-party) and fixes it either way.

```text
drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--to project|library] [--only <unit,...>] [--db <db>] [--full] [--json] [--config <path>] - sync project member list; flag stale used units. --only restricts MISSING (and therefore --apply) to a reviewed selection, so a dry run with --only previews exactly what --apply would write. --json carries `applied` (the OUTCOME, false when --apply had nothing to write) plus `backups` and `edited` when --apply is passed. MISSING = used units neither listed nor in the library (registry library path or the manifest library section's include); each is judged by the project's own roots: project unit (fix --apply) or third-party (fix --apply --to library, which adds its folder to that include in --config or the exe-dir drag-lint.json, .bak first). --json items carry owner, suggestedFix and folder
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--apply` |  |  |  |
| `--to` | `project\|library` |  |  |
| `--only` | `<unit,...>` |  |  |
| `--db` | `<db>` |  |  |
| `--full` |  |  |  |
| `--json` |  |  |  |
| `--config` | `<path>` |  |  |

Described in [Reconcile Project Members (.dpr/.dproj)](features/reconcile-project-members-dpr-dproj.md).

### refresh-findings

Recompiles every unit of a project (a forced full build, refresh-findings --full) and refreshes its stored compiler findings.

```text
drag-lint refresh-findings --project <X.dproj> [--db <db>] [--full] [--json] (recompile stale units + refresh compiler_findings; >=2 stale -> full build; no --db = the project's own DB)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `<db>` |  |  |
| `--full` |  |  |  |
| `--json` |  |  |  |

Described in [Full Compile Sweep](features/full-compile-sweep.md).

### register-project

Add a new project to the manifest so index --all and the IDE can see it.

```text
drag-lint register-project <file.dproj> [--name <Section>] [--apply] [--json] (add a NEW project to the manifest so index --all and the IDE can see it; dry-run without --apply)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<Section>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

Described in [register-project](features/register-project.md).

### rename

Renames a symbol across the whole indexed project.

```text
drag-lint rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup] --db <db> - cross-unit rename
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--kind` |  |  |  |
| `--name` | `<QName>` |  |  |
| `--to` | `<New>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

Described in [Rename Symbol](features/rename-symbol.md).

### resolve-dbs

Prints which database(s) drag-lint would actually use for a given project, file, or platform, without running a real query.

```text
drag-lint resolve-dbs [--platform win32|win64] [--config <path>] [--json] (print the consumer DB list query/lsp/serve would use)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--platform` |  |  |  |
| `--config` | `<path>` |  |  |
| `--json` |  |  |  |

Described in [Show Resolved DBs (debug)](features/show-resolved-dbs-debug.md).

### reverse-calltree

Shows callers and callees of one symbol together in a single "butterfly" view.

```text
drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...] (N-deep call tree; callers=who calls X (default), callees=what X calls; cycle-guarded)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--direction` |  |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--db` | `PATH` |  |  |

Described in:

* [Call Graph (Butterfly)](features/call-graph-butterfly.md)
* [Reverse Call Tree (clickable, Messages window)](features/reverse-call-tree-clickable-messages-window.md)
* [Reverse Call Tree (who calls this, N-deep)](features/reverse-call-tree-who-calls-this-n-deep.md)
* [Show in Call Graph](features/show-in-call-graph.md)

### rules

Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field.

```text
drag-lint rules [--json] [--category <name>] [--standard cwe|cert|misra] [--rules-dir <dir>] [--target-compiler <ver|auto> [--project <.dproj>]] - list every lint rule (catalog; each labelled rule shows its CWE/CERT/MISRA ids, --json adds `compliance`; --standard lists only rules labelled under it)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--category` | `<name>` |  |  |
| `--standard` | `cwe\|cert\|misra` |  |  |
| `--rules-dir` | `<dir>` |  |  |

Described in:

* [Compliance labels (CWE, CERT, MISRA)](features/compliance-labels.md)
* [drag-lint: Project Rules](features/drag-lint-project-rules.md)
* [Gap-wave lint rules](features/gap-wave-rules.md)
* [Lint rules](features/lint-rules.md)
* [Target compiler (--target-compiler)](features/target-compiler.md)

### safe-delete

Deletes a symbol if and only if it has zero references in the index.

```text
drag-lint safe-delete --name <QName> [--json|--apply|--no-backup] --db <db> - delete a symbol iff it has zero references
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<QName>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

Described in [safe-delete](features/safe-delete.md).

### schema

Prints the live schema of an index database: schemaversion, every table and column, and row counts.

```text
drag-lint schema --db <file.sqlite> [--format text|json] [--output <file>] (self-documenting LIVE index schema: schema_version + tables + columns + row counts, read-only)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |

Described in [schema](features/schema.md).

### serve

Starts the MCP (Model Context Protocol) stdio server, for AI clients such as Claude or Cursor to query a drag-lint index.

```text
drag-lint serve --db <file.sqlite> [--json] (MCP stdio server)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |

Described in [serve](features/serve.md).

### shared-unit

Reads or extends the dl:shared marker on a unit, recording which projects share it.

```text
drag-lint shared-unit --in <file.pas> [--add-project <name>] [--apply] [--json] (read/extend the dl:shared marker; dry-run without --apply)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<file.pas>` |  |  |
| `--add-project` | `<name>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

Described in [shared-unit](features/shared-unit.md).

### shutdown

Ask running engines (lsp, cycles --fix, index, lint-all) to stand down cleanly, so an index can be rebuilt or an engine replaced.

```text
drag-lint shutdown [--db <file.sqlite>]... [--wait <sec>] [--dry-run] [--all] [--force] (ask running engines to stand down: close every store, exit 0; `index` and `lint-all` runs exit 4)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--wait` | `<sec>` |  |  |
| `--dry-run` |  |  |  |
| `--all` |  |  |  |
| `--force` |  |  |  |

Described in [shutdown](features/shutdown.md).

### slice

Shows the slice of code relevant to one symbol: its declaration, body, and immediate context.

```text
drag-lint slice --qname <Foo.TBar> [--db <file.sqlite>] [--format text|json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

Described in [Symbol Slice](features/symbol-slice.md).

### sql

Chooses the bytes every verb writes to stdout and stderr: 7-bit ASCII with \uXXXX escapes (default), UTF-8 or UTF-16LE, never a BOM; --output files obey it and an ascii run that loses characters warns once on stderr.

```text
drag-lint sql --query "SELECT ..." | --in <q.sql> --db <file.sqlite> [--format text|json] [--json] [--limit N] [--timeout-ms N] [--output <file>] (guarded READ-ONLY SQL over the index: exactly one statement, an sqlite3 authorizer refuses ATTACH/PRAGMA/DDL/writes, row cap 200 and time cap 10000 ms; ask `schema --format json` for the columns)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--query` |  |  |  |
| `--in` | `<q.sql>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--limit` | `N` |  |  |
| `--timeout-ms` | `N` |  |  |
| `--output` | `<file>` |  |  |

Described in:

* [Output encoding (--output-encoding)](features/output-encoding.md)
* [sql](features/sql.md)

### surface

Shows the public surface of a class: its members and signatures, without the method bodies.

```text
drag-lint surface --qname <Foo.TBar> [--db <file.sqlite>] [--include-impl] [--all-visibility] [--format text|json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--include-impl` |  |  |  |
| `--all-visibility` |  |  |  |
| `--format` |  |  |  |

Described in [Class Surface](features/class-surface.md).

### todos

Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers.

```text
drag-lint todos [<path>] (TODO/FIXME/HACK/XXX/REVIEW/NOTE scanner; [--json])
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |

Described in [Scan TODOs / FIXMEs](features/scan-todos-fixmes.md).

### top

Ranks indexed symbols by fan-in -- how many places reference them.

```text
drag-lint top --db <file.sqlite> [--by fanin] [--limit N] [--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--by` |  |  |  |
| `--limit` | `N` |  |  |
| `--json` |  |  |  |

Described in [Top Symbols (fan-in)](features/top-symbols-fan-in.md).

### typeat

Resolves the static type of the expression under the editor caret.

```text
drag-lint typeat <file>:<line>:<col> [--db <file.sqlite>] [--format text|json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

Described in [Type at Cursor](features/type-at-cursor.md).

### usages

Lists references to the symbol represented by a Structure-tree node.

```text
drag-lint usages --name <X> [--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json|--json]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<X>` |  |  |
| `--width` |  |  |  |
| `--db` | `<path>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

Described in:

* [Find Usages](features/find-usages-context.md)
* [usages](features/usages.md)

### uses-audit

For one unit, reports which uses entries could move from the interface section to implementation, and which are unused entirely.

```text
drag-lint uses-audit <unit.pas> --db <file.sqlite> [--format json|text] (interface->impl moves + unused units)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

Described in [Uses Audit -- interface->impl moves + unused (this unit)](features/uses-audit-interface-impl-moves-unused-this-unit.md).

### uses-fix

Applies the fix for the single lint finding on a Structure-tree node; an unused unit is removed or moved to implementation by compiling.

```text
drag-lint uses-fix <unit.pas> --project <dproj> --db <file.sqlite> [--platform win32|win64] [--apply] [--remove-unused] [--only <unit,...>] [--format json|text] (compiler-verified uses cleanup; --format json lists every candidate with a status -- verified | skipped | deselected -- and --only restricts which are compiled and written, so a reviewed partial apply is expressible; a unit --only names that is in the uses clause but in no project index -- an RTL/VCL/library unit -- is decided by compiling too: removed when it has no initialization section (with --remove-unused), else moved to the implementation section, else skipped)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--platform` |  |  |  |
| `--apply` |  |  |  |
| `--remove-unused` |  |  |  |
| `--only` | `<unit,...>` |  |  |
| `--format` |  |  |  |

Described in:

* [Fix it](features/fix-it.md)
* [Uses Cleanup Preview (compiler-verified, this unit)](features/uses-cleanup-preview-compiler-verified-this-unit.md)

### uses-report

Exports the project's unit-dependency data as a CSV file.

```text
drag-lint uses-report --output <out.csv> [--db ...] [--depth N] [--include-external] [--all-sources] [--name <pattern>] (--name is a substring on the unit stem; one that matches NO source unit exits 2 with an ERROR and writes nothing, like outline)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--output` | `<out.csv>` |  |  |
| `--db` |  |  |  |
| `--depth` | `N` |  |  |
| `--include-external` |  |  |  |
| `--all-sources` |  |  |  |
| `--name` | `<pattern>` |  |  |

Described in [Uses Report (CSV)](features/uses-report-csv.md).

### wiki

Looks up the dl:wiki concept topics a team has written into their own doc comments, and routes a human phrase to the code that implements it.

```text
drag-lint wiki --term "<phrase>" | --list | --check [--json] [--db <file.sqlite>] (dl:wiki CONCEPT topics written in doc comments: --term routes a human word or alias ("the scheduler") to the owning symbol, --list prints every topic, --check resolves every SeeCode entry and exits 1 on drift. Authoring format: docs\wiki\Wiki-Blocks-Authoring.md)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--term` |  |  |  |
| `--list` |  |  |  |
| `--check` |  |  |  |
| `--json` |  |  |  |
| `--db` | `<file.sqlite>` |  |  |

Described in:

* [wiki](features/wiki.md)
* [dl:wiki concept blocks](features/wiki-blocks-authoring.md)

### wiring

Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type.

```text
drag-lint wiring --qname <IIntf|TForm> [--db <file.sqlite>] [--format text|json] (Spring4D DI + DFM event edges)
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<IIntf\|TForm>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

Described in [Show Wiring (Spring4D DI + DFM events)](features/show-wiring-spring4d-di-dfm-events.md).

### workspace

Registers a project file into a .drag-lint-workspace.json workspace config, so multi-project workspace commands know about it.

```text
drag-lint workspace index [--config <.drag-lint-workspace.json>]
drag-lint workspace add <projfile> [--config <.drag-lint-workspace.json>]
drag-lint workspace status [--config <.drag-lint-workspace.json>]
```

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<.drag-lint-workspace.json>` |  |  |

Described in:

* [workspace add](features/workspace-add.md)
* [workspace index](features/workspace-index.md)
* [workspace status](features/workspace-status.md)

## Flag aliases

A verb's usage line names the canonical flag only. Each alias is accepted wherever its canonical flag is and means exactly the same, so scripts that use one keep working; write the canonical spelling. `drag-lint --help` lists them in its "Flag aliases:" section. Policy: `docs/CLI-FLAG-ALIASES.md`.

| Canonical | Aliases | Why |
|---|---|---|
| `--force-reparse` | `--no-skip` | back-compat: the first spelling of the index re-parse switch |
| `--help` | `-h`, `-?` | convention: the short help tokens every CLI user tries first |
| `--in` | `--file` | one input-file option (TArgs.InFile); --in is the spelling the ask verb's own parser accepts, so it is the one that works on every verb |
| `--output` | `--out` | back-compat: owner ruling ENG-6 (2026-09-22/23) -- scripts that use --out keep working |
| `--scan-libraries-win` | `--scan-libraries` | back-compat: the spelling before --scan-libraries-all existed |

