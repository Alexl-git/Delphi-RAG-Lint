unit DRagLint.CLI.Convert;

// ---------------------------------------------------------------------------
// The component-conversion verb family (lane v1511 SPLIT, T07): proptree, convert-validate, convert-reemit,
// convert-scaffold, convert-apply and glyph-vacuum, with their tree-depth / progress helpers and the
// apply/1 JSON writer. Moved verbatim out of DRagLint.CLI; the analysis lives in DRagLint.Convert.*.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint proptree --qname X [--depth N] [--rules FILE] [--no-to-persistent]
/// [--refs-as-leaves] [--min-visibility published|public] [--format text|json] [--json] --db PATH
/// [--db ...] -- Track 3 Batch 1: the index-driven RECURSIVE deep-property
/// enumerator. Resolves class X, walks its own + inherited kind='property'
/// children, parses each property's type from its Signature, and recurses into
/// class-typed property types (depth-capped + a visited-TYPE-name cycle guard) to
/// produce flattened dotted paths (Font.Color, Inner.Shade). Depth is --depth N,
/// else the --rules book's '#depth N', else 5 (ResolveTreeDepth; a bad --depth,
/// --depth &lt; 1 or a bad '#depth' is exit 2). ToPersistent (default ON) stops the ancestor
/// climb at TPersistent/TObject; --no-to-persistent climbs past. --refs-as-leaves
/// (TreatRefsAsLeaves, default OFF) emits a property whose type descends from
/// TComponent as a REFERENCE LEAF instead of recursing into it -- a referenced
/// component is not an owned sub-object -- while owned TPersistent sub-objects
/// (TFont, ...) still expand. text = an
/// indented tree (indent = the path's dot-depth); json = schema proptree/2 (v2:
/// adds per-leaf visibility/is_writable/member_kind; additive over proptree/1).
/// --min-visibility published|public filters the EMITTED leaves by EFFECTIVE
/// (most-derived) visibility: unset (default) emits ALL leaves exactly as
/// proptree/1 did (back-compat); 'published' emits only published leaves;
/// 'public' emits published+public leaves. Applies to both text and json output.
/// With multiple --db, the first DB that resolves the qname to a class is used
/// (ids are per-DB). Write-back is AUTOMATIC: the resolving index is opened
/// WRITABLE so a property type recovered by the lazy ancestry-bridge (across an
/// unresolved/type-alias ancestor edge) is memoized back onto the property row
/// (next query is a plain hit; self-limiting). A writable open that fails falls
/// back to read-only (resolution still works; memoization skipped). --no-write-back
/// forces a read-only (query_only) open that never mutates the DB; killing the
/// process mid-run is safe (each memoized type is its own SQLite statement).
/// --progress-interval S (default 0 = off) writes one JSON progress line to
/// STDERR at most every S seconds while the tree is built (MakeProgressWriter);
/// stdout is unchanged.</summary>
/// <param name="AArgs">QName=class, DepthGiven/DepthRaw=--depth and
/// RulesFile=--rules (recursion cap, see ResolveTreeDepth; default 5),
/// ToPersistent=ancestor-stop, RefsAsLeaves=--refs-as-leaves (TComponent-typed
/// properties are reference leaves, not expanded), NoWriteBack=force read-only
/// (no memoization),
/// MinVisibility=--min-visibility filter ('' = all), Format/AsJson=output,
/// DbPath/DbPaths=index(es).</param>
/// <returns>0 ok; 1 qname not resolved to a class in any DB; 2 usage error / no
/// readable db / invalid --min-visibility value / invalid --depth or --rules
/// book depth / invalid --progress-interval.</returns>
function DoPropTree(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-validate --rules FILE [--from FromType] [--to ToType]
/// [--print-parsed] [--db PATH ...] -- Track 3 Batch 1: parse a reFind-superset
/// conversion-rules DSL file and (when --from/--to types are supplied) validate its
/// #link / #default target/source paths against the REAL members of those types,
/// each path resolved segment by segment (1.20.6, T2b: TPropMemberCache -- no property
/// tree is built, so --depth no longer applies and no path is too deep; a published
/// leaf, each hop published or public-and-class-typed, never private). --rules is required (missing -&gt; usage + exit 2;
/// unreadable -&gt; exit 2). Without --from/--to it is parse-only: only unknown-
/// directive parse errors are reported, path checks are skipped. --print-parsed
/// dumps 'parsed N rule(s)' plus one 'line L: kind ...' summary per rule (so a test
/// can assert the parse result with no trees). A literal '???' path is an explicit
/// STUB marker (the scaffolder emits these) and is NOT a path error. A #link
/// glyph expression (G[I/N] grammar) is checked in either mode, and a problem
/// names the column inside the expression. Prints 'line N: message' per error,
/// then 'line N: warning: message' per warning -- first each UNREACHABLE path
/// (T2h, owner ruling R12: every segment exists but one fails the .dfm surface,
/// 'line N: warning: &lt;path&gt;: &lt;Member&gt; is &lt;visibility&gt; in
/// &lt;Class&gt;; never applied unless a descendant class changes its
/// visibility'), then ConversionRuleWarnings -- all on stdout, then 'OK' when
/// there were no errors; warnings never change the exit code. No JSON mode.</summary>
/// <param name="AArgs">RulesFile=--rules; CallFrom=--from (FromType qname),
/// RenameTo=--to (ToType qname); PrintParsed=--print-parsed; ToPersistent=--no-to-persistent;
/// DbPath/DbPaths=index(es) the from/to classes are resolved in.</param>
/// <returns>0 valid / parse-ok; 1 errors found (parse or validation); 2 bad args
/// (no --rules) or unreadable rules file.</returns>
function DoConvertValidate(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-reemit --from-block FILE --rules FILE --from FromType
/// --to ToType --db PATH -- HIDDEN test verb driving the pure ReemitComponent
/// engine. Prints the emitted T DFM block + report as JSON. Not in help/README;
/// superseded by convert-apply (2a-iii).</summary>
/// <param name="AArgs">FromBlockFile=--from-block (one F DFM object block file);
/// RulesFile=--rules; CallFrom=--from (FromType qname), RenameTo=--to (ToType
/// qname); DbPath/DbPaths=index(es) the from/to classes are resolved in.</param>
/// <returns>0 when Ok; 1 on a hard re-emit failure; 2 on bad args.</returns>
/// <remarks>Resolves the F/T classes from the index (like convert-validate,
/// same first-DB-that-resolves-wins loop, ConvertClassIn -- 1.20.6: no property
/// tree is built, each dotted path is resolved lazily), parses the rules DSL, calls
/// ReemitComponent, and serializes the result. Read-only against the store.</remarks>
function DoConvertReemit(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-scaffold --from FromType --to ToType [--output FILE]
/// [--surface dfm|pas] --db PATH [--db ...] -- Track 3 Batch 1: auto-generate a
/// VALID reFind-superset conversion-rules file from the REAL deep-property trees
/// of the From and To types (Task 1's BuildPropTree over BOTH), pre-filling the
/// assignments it can safely infer and leaving only genuine ambiguities as '???'
/// for the user to resolve. --from (reuses CallFrom) and --to (reuses RenameTo)
/// are BOTH required (missing -&gt; usage + exit 2). --output (reuses Output) writes
/// an ASCII/CRLF file; omitted -&gt; stdout. Multiple --db are tried in order; the
/// FIRST db that resolves BOTH types is used (ids are per-DB). If either type is
/// unresolved the verb names it and exits 1. Both trees expand to --depth N, else
/// the --rules book's '#depth N', else 5 (ResolveTreeDepth; a bad value exits 2).
/// proptree assignability engine (Task 5): auto-'#link' TARGETS (the To side
/// only -- From remains an unrestricted candidate SOURCE pool) are restricted to
/// leaves that are actually valid assignment targets, using the is_writable/
/// visibility/member_kind fields BuildPropTree already stamps onto every
/// TPropNode (Tasks 2-4; no extra wiring needed since convert-scaffold's To tree
/// comes from the SAME BuildPropTree call as `proptree`). --surface dfm (the
/// default) requires member_kind='property' AND the effective visibility=
/// 'published' -- the DFM-streamable surface, matching today's dominant
/// component-conversion use case; --surface pas relaxes the bar to visibility in
/// ('published','public'), ANY member_kind (so a public FIELD can be a target
/// too). On EITHER surface a leaf with is_writable=false (a typed class CONST
/// today; a read-only PROPERTY once a later task extracts real property
/// writability) is NEVER a valid target. A To path that fails either bar is
/// fully excluded from the per-To-path loop -- no '#link', no '#default', no
/// '#note' -- mirroring how `proptree --min-visibility` silently drops a
/// tier-failing leaf with no extra annotation (the existing convention for "not
/// part of this surface"; the DSL's own '#ignore' directive was considered and
/// rejected -- it acknowledges an unmapped FROM path, a different direction,
/// not a filtered TO target). A To path's own Visibility='' (defensive-only in
/// practice -- the current parser always stamps a non-empty value; see
/// DRagLint.Convert.PropTree's ResolveInheritedVisibility remark) is treated as
/// PASSING the bar on both surfaces -- graceful degrade so an old/foreign DB
/// row whose visibility could not be resolved is never MORE aggressively
/// filtered than today's "show everything", matching a proptree/1-style
/// consumer's back-compat default. The FROM-side DROPPED-note loop (3) uses the
/// SAME valid-target test, so a From path whose only leaf-name+type counterpart
/// is a filtered-out To leaf is correctly reported DROPPED rather than silently
/// neither linked nor noted.</summary>
/// <param name="AArgs">CallFrom=--from (FromType qname), RenameTo=--to (ToType
/// qname), Output=--output (file; empty=stdout), Surface=--surface dfm|pas ('' =
/// default 'dfm'), DepthGiven/DepthRaw=--depth and RulesFile=--rules (tree
/// depth, see ResolveTreeDepth), ProgressIntervalGiven/ProgressIntervalRaw=
/// --progress-interval S (default 0 = off; one JSON line on STDERR at most every
/// S seconds while the two trees are built, see MakeProgressWriter; stdout is
/// unchanged), DbPath/DbPaths=index(es).</param>
/// <returns>0 success; 1 either type unresolved in every db; 2 bad args (missing
/// --from/--to, invalid --surface value, invalid --depth or book #depth, invalid
/// --progress-interval) or no readable db (an explicit --db that is missing or stale is exit 2).</returns>
/// <remarks>Output is DETERMINISTIC (paths sorted case-insensitively) so the
/// emitted text is stable across runs. Emission order: (1) a '#convert From -&gt;
/// To' header with a best-guess ', unit' uses-add taken from the qname unit
/// prefix(es) of From/To when discoverable (never fabricated); (2) for each
/// VALID-TARGET To path (sorted; see the surface/writability filter above) the F
/// candidates whose LEAF name equals the To leaf (case-insensitive) AND whose
/// declared TypeName is compatible (equal, case-insensitive) -- exactly ONE
/// candidate -&gt; a concrete '#link ToPath &lt;- FromPath'; MULTIPLE -&gt; '#link
/// ToPath &lt;- ???' immediately followed by '#note candidates: p1, p2, ...';
/// ZERO -&gt; '#default ToPath = ???'; (3) for each From path (sorted) with NO
/// compatible VALID-TARGET To counterpart (same leaf+type test, reversed) a
/// '#note DROPPED FromPath (no T target)'. The matching rule is LEAF-NAME +
/// COMPATIBLE-TYPE (documented, not exact-path), so a leaf name that appears at
/// more than one From path is correctly flagged ambiguous. Every concrete path
/// emitted is guaranteed to exist in the real trees and every '???' is tolerated
/// by the validator, so the emitted file round-trips clean through
/// convert-validate. Read-only.</remarks>
function DoConvertScaffold(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-apply --unit F.pas --rules FILE --db PATH [--db ...]
/// [--only Name1,Name2,...] [--apply] [--no-backup] [--no-warn-unlinked] [--format json] -- Track 3 sub-project B: locates the
/// component instances to convert in the sibling .dfm and rewrites all five surfaces
/// (#1 declaration retype, #2 uses-add, #3 .dfm re-emit, #4 property/event access-site
/// rewrite via ref-gap G's member-access index, #5 runtime-creator retype + TODO markers).
/// Without --apply this
/// is DRY-RUN ONLY (RenderDryRun preview, writes nothing). With --apply (Task 4) it actually writes:
/// a freshness guard runs first (CheckFreshness -- refuses on stale/unindexed F or T
/// types), then each touched file is backed up to its next-free NAME.EXT.BCK&lt;n&gt;
/// (DRagLint.Convert.Backup.BackupFiles) and a recovery.txt block is appended BEFORE the
/// conversion write (WriteRecoveryRecord), then the edits are written
/// (TTextEditApplier.Apply(..., AWriteBackups:=False) -- our own backup layer already
/// backed up, so the applier must NOT also write its own .bak), then the converted .pas
/// is stamped with a provenance comment (PrependConvertComment). --no-backup skips the
/// backup/recovery/comment steps entirely (still converts). --unit reuses GhostUnit (same
/// --unit -> non-document-command routing as ghost-check; see ParseArgs) and --only reuses
/// OnlySections (same comma-split TArray&lt;string&gt; already used by `index --all`).</summary>
/// <param name="AArgs">GhostUnit=--unit (the .pas file to convert); RulesFile=--rules;
/// OnlySections=--only (comma-split instance-name allow-list); Apply=--apply; NoBackup=
/// --no-backup; NoWarnUnlinked=--no-warn-unlinked (silences the per-(source type, property)
/// unlinked warnings; the json count and unlinked[] stay); DbPath/DbPaths=index(es).</param>
/// <returns>0 on success (dry-run preview shown, or --apply wrote successfully); 1 on a
/// hard error (missing .dfm when rules need it, invalid rules, BuildApplyPlan Ok=False, or
/// --apply refused by the freshness guard -- a stale or unindexed type of any block; a deliberate
/// refusal -- a #convert type that resolves in no --db (C13 d: an index gap, refused on dry run and
/// --apply alike, before any rule error), a unit-rules {$IF...} uses entry, any
/// TApplyResult.Refusal -- goes through RefuseUnit: 'REFUSED: <reason>', apply/1 refused=true,
/// reason, nothing written); 2 on bad args (missing --unit/--rules, file not
/// found, no readable db (an explicit --db that is missing or stale is exit 2)).</returns>
/// <remarks>Resolves the sibling .dfm as the same base name + '.dfm' next to --unit;
/// missing .dfm is a hard error (exit 1) for a book with NO unit rules, since every #convert
/// rule needs DFM instances to locate. A book with unit rules (#unuse / #use / #useswap,
/// 1.20.6) applies them to the unit's uses clauses (PlanUnitRules) -- alone when there is no
/// .dfm, no #convert block or no matching instance (json component_part says which),
/// otherwise folded into BuildApplyPlan's plan; a unit whose entry to remove sits in a
/// conditional region is refused (exit 1, nothing written). Every readable --db is opened
/// up front into Stores (not just the first; a stale explicit --db exits 2 here, before
/// any rule is checked). The .dfm is then read (FindInheritedInstances, 1.22.0, C8 N1/N3): an
/// inherited/inline object of a From type is NOT converted and no longer refuses the unit -- it
/// is skipped and reported with its declaring ancestor (apply/1 inherited[] {name, type, line,
/// ancestor_unit, ancestor_state unconverted|converted|mismatched|outside, reason, action}, a 'line N: warning:'
/// line in warnings[], items[] kind inherited-instance-skipped), while the unit's own instances,
/// code and unit rules convert; R26 counts it as left unconverted. One whose ancestor already has
/// the To type is RETYPED instead (1.26.0, C8 N2: action retyped), and a converted ancestor's field
/// used only in code joins the access-site rewrite (N2a, FindInheritedCodeUses: action code). Rules are then validated (ValidateConvertBook)
/// BEFORE BuildApplyPlan runs -- EVERY block against its OWN From/To classes, each path resolved
/// segment by segment (1.20.6, T2b: no property tree is built, so validating the whole book is
/// cheap and ruling R5's per-unit scope and --validate-all-blocks are gone), and a #mapping
/// against the block(s) that #apply it; a block whose type resolves in no --db REFUSES the unit
/// (C13 d, UnresolvedReason); a BARE #convert type resolves in the unit's own scope (the unit,
/// its last uses entry declaring it, a lone unit-level declarer -- never a nested class, never
/// the first class of that name), and one that scope cannot settle REFUSES the unit naming the
/// candidates (AmbiguousReason: qualify the #convert line) -- and a rules error refuses (exit 1) rather than attempting a plan
/// from a broken rule set. A #link / #default / #mapping path whose members all exist but one
/// is inaccessible on the .dfm surface is NOT an error (T2h, owner ruling R12): it is skipped
/// per block (WithoutUnreachableRules, inside each re-emit -- a #link / #default line is dropped,
/// a #mapping keeps its branch order and loses only the unreachable targets, and a mapping whose
/// #when source is unreachable is skipped whole), the unit converts everything else, and each is reported
/// -- apply/1 unreachable[] objects, the same text in warnings[] / items[]
/// (rule-path-unreachable), and a text-mode 'line N: warning: ...' line under Warnings. Validation and BuildApplyPlan share one TConvertTreeCache, so each
/// class's members are resolved once per run (json classes_built). The freshness guard
/// (CheckFreshness, every block) and BuildApplyPlan both
/// resolve From/To TYPES across ALL of Stores (first-that-resolves-wins), while unit/
/// instance-scoped lookups use whichever store actually has --unit/the .dfm indexed -- the
/// From type, To type, and the form's own instances may each live in a DIFFERENT --db. On
/// dry-run a stale/unindexed type only WARNS (the preview still renders), on --apply it
/// REFUSES (exit 1) before any write is attempted. A book whose #link carries a glyph
/// expression validates but is REFUSED here (exit 1, through the rule-error path) until
/// CV-2 realises G-links (UnrealisedGlyphLinks) -- never carried whole.
/// 1.33.0 (CONVERTER G2): a --unit whose .pas NO supplied --db indexes is REFUSED (exit 1,
/// reason 'not covered by any supplied --db'), dry run and --apply, single and batch alike --
/// it used to plan its unit rules and skip every instance, so --apply half-converted it.
/// G3: every apply/1 object carries exit_code (that unit's). G1: --progress writes one
/// stderr JSON line per finished unit ({"progress":{"verb":"convert-apply","unit_done",
/// "units","unit","ok","refused","exit_code"}}, flushed); stdout is unchanged by it.</remarks>
function DoConvertApply(const AArgs: TArgs): Integer;

/// <summary>`drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]`: extracts and decodes every streamed graphic of the .dfm/.fmx under the roots into --output.</summary>
/// <param name="AArgs">--root (one or more), --output, --append, --db (only qualifies, never guesses).</param>
/// <returns>0 on a completed walk (0 graphics is an answer); 2 on bad args or a missing root.</returns>
function DoGlyphVacuum(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, DRagLint.Core.FileTime, Winapi.Windows,
  DRagLint.Lint.MarkerUnion, DRagLint.Core.CliError, DRagLint.Core.Encoding, DRagLint.Query.Implementors,
  DRagLint.Query.CrossImpact, DRagLint.Query.SyntaxCountVerb, DRagLint.CLI.UsesRecover,
  DRagLint.Query.IdentWords, DRagLint.Core.OutputEncoding, Winapi.ShellAPI, DRagLint.Lint.MissingUses,
  System.SysUtils, System.Classes, System.Hash, System.IOUtils, DRagLint.CLI.UnitContext,
  DRagLint.CLI.LibraryReady, DRagLint.CLI.LibraryMarker, DRagLint.CLI.HelpText, DRagLint.Core.Versions,
  System.NetEncoding, System.JSON, System.StrUtils, System.DateUtils, System.RegularExpressions,
  System.Generics.Collections, System.Generics.Defaults, System.Diagnostics, System.SyncObjs, System.Math,
  System.Character, Data.DB, FireDAC.Comp.Client, FireDAC.Phys.SQLite, FireDAC.Stan.Async, FireDAC.Stan.Def,
  FireDAC.Stan.Param, FireDAC.Stan.Option, FireDAC.DApt, TreeSitter, DRagLint.Core.DeclText,
  DRagLint.Core.ForwardStub, DRagLint.Lint.RefTypeRules, DRagLint.Lint.RuleCache, DRagLint.Lint.UsesAudit,
  DRagLint.Index.LibraryOracle, DRagLint.Lint.Autofix, DRagLint.Refactor.RedundantCast,
  DRagLint.Refactor.NarrowParam, DRagLint.Refactor.ExtractInterface, DRagLint.Refactor.LazyInit,
  DRagLint.Lint.TargetCompiler, DRagLint.Project.TargetStudio, DRagLint.Core.Interfaces,
  DRagLint.Core.Indexer, DRagLint.Analysis.LintTree, DRagLint.Analysis.PurityStage, DRagLint.Storage.SQLite,
  DRagLint.Storage.Schema, DRagLint.Storage.FileMembership, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM,
  DRagLint.Parser.Sql, DRagLint.Parser.Markdown, DRagLint.Query.TextNodes, DRagLint.Sql.FbSnapshot,
  DRagLint.Sql.OrmLinker, DRagLint.Sql.Guarded, DRagLint.Core.EngineHold, DRagLint.Core.UsageLog,
  DRagLint.Core.ControlChannel, DRagLint.Core.StudioEnv, DRagLint.Lint.Config, DRagLint.Lint.RuleCatalog,
  DRagLint.Lint.Compliance, DRagLint.Lint.Linter, DRagLint.Lint.QueryRules, DRagLint.Lint.ProjectChecks,
  DRagLint.Lint.IfdefUndefined, DRagLint.Lint.PlatformDivergent, DRagLint.Lint.ProjectRules,
  DRagLint.Lint.SharedScope, DRagLint.Lint.ClassMetrics, DRagLint.Lint.TaintRules, DRagLint.Lint.DocRules,
  DRagLint.Lint.SharedUnit, DRagLint.Lint.Bookmarks, DRagLint.CLI.Bookmarks,
  DRagLint.Lint.ExceptionUnitWriter, DRagLint.Project.Resolver, DRagLint.Project.ContextFile,
  DRagLint.Project.Members, DRagLint.Project.Coherence, DRagLint.Project.OwnRoots, DRagLint.Project.Facts,
  DRagLint.Project.DefineProfile, DRagLint.FormsMap, DRagLint.MenuTree, DRagLint.MenuTree.Dfm,
  DRagLint.MenuDrift, DRagLint.MCP.Server, DRagLint.LSP.Server, DRagLint.LSP.Proxy, Vcl.Graphics,
  DRagLint.Hover.Renderer, DRagLint.Hover.Returns, DRagLint.Hover.Contrast, DRagLint.Context.Bundler,
  DRagLint.Resolver.TypeAt, DRagLint.Refactor.Rename, DRagLint.Refactor.RenameProof,
  DRagLint.Refactor.TextEdit, DRagLint.Refactor.NamingFix, DRagLint.Refactor.MultiProjectRename,
  DRagLint.Refactor.DocStub, DRagLint.Doc.Facts, DRagLint.Doc.Regions, DRagLint.Doc.Document,
  DRagLint.Doc.Drift, DRagLint.Doc.Batch, DRagLint.Doc.Strip, DRagLint.Doc.Harvest, DRagLint.Doc.SymbolFacts,
  DRagLint.Doc.SharedFacts, DRagLint.Doc.ProjectTags, DRagLint.Doc.Wiki, DRagLint.Refactor.DeadCode,
  DRagLint.Refactor.TestStub, DRagLint.Refactor.ExtractMethod, DRagLint.CLI.Unwith,
  DRagLint.Query.ExceptionFacts, DRagLint.Charts.ArchDiagram, DRagLint.Refactor.CompileGate,
  DRagLint.Refactor.EnumHelper, DRagLint.Format.Yadf, DRagLint.Diagnostics.CompileCheck,
  DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Diagnostics.DeadCodeChecks,
  DRagLint.Diagnostics.ControlFlowChecks, DRagLint.Diagnostics.ExprChecks, DRagLint.Diagnostics.DeclChecks,
  DRagLint.Diagnostics.SizeChecks, DRagLint.Diagnostics.ConcurrencyChecks,
  DRagLint.Diagnostics.EnumOrdinalCast, DRagLint.Diagnostics.DisallowedChecks,
  DRagLint.Diagnostics.ModernizeChecks, DRagLint.Diagnostics.PpChecks, DRagLint.Index.PPUnitSource,
  DRagLint.Diagnostics.OwnershipChecks, DRagLint.Diagnostics.BoundsNilChecks,
  DRagLint.Diagnostics.ExceptionThreadChecks, DRagLint.Diagnostics.DeclParityChecks,
  DRagLint.Diagnostics.ParityExtChecks, DRagLint.Diagnostics.LifetimeShapeChecks,
  DRagLint.Diagnostics.CloneChecks, DRagLint.Diagnostics.ParseCache, DRagLint.V151.Api,
  DRagLint.V151.Dispatch, DRagLint.Diagnostics.FlowChecks, DRagLint.Analysis.DataFlow,
  DRagLint.Workspace.Config, DRagLint.Index.Manifest, DRagLint.Index.ManifestWrite, DRagLint.Index.Glob,
  DRagLint.Index.IgnoreFiles, DRagLint.Index.Closure, DRagLint.Index.Reconcile, DRagLint.Index.Plan,
  DRagLint.Index.DbSelect, DRagLint.Index.Drift, DRagLint.Index.Freshness, DRagLint.Index.Coverage,
  DRagLint.Index.CallResolver, DRagLint.Wiring, DRagLint.Output.Sarif, DRagLint.Output.ExitCode,
  DRagLint.Lint.Baseline, DRagLint.Lint.ReviewMarker, DRagLint.Preprocess.Types, DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Expr, DRagLint.Preprocess, DRagLint.Preprocess.Profile, DRagLint.Report.Deps,
  DRagLint.Report.RCallTree, DRagLint.Report.Overview, DRagLint.Report.CycleHub,
  DRagLint.Report.CycleHubSurface, DRagLint.Report.CyclePlan, DRagLint.CLI.CycleFix,
  DRagLint.Convert.PropTree, DRagLint.Convert.PropCache, DRagLint.Convert.Rules, DRagLint.Convert.CastLib,
  DRagLint.Convert.GlyphVacuum, DRagLint.Convert.DfmReemit, DRagLint.Convert.Apply, DRagLint.Convert.Backup,
  DRagLint.Convert.UnitRules, DRagLint.Convert.UsesReconcile, DRagLint.Query.Callers,
  DRagLint.Query.HoverModel, DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapters, DRagLint.Charts.Producer,
  DRagLint.Charts.Producer.Delphi, DRagLint.Charts.AskVerb, DRagLint.Charts.Snapshot, DRagLint.Charts.Compare,
  DRagLint.Charts.Render, DRagLint.Core.ProtocolReg, DRagLint.MCP.ClientConfig;

/// <summary>The tree-expansion depth of proptree / convert-scaffold:
/// --depth N &gt; the --rules book's '#depth N' &gt; DEFAULT_TREE_DEPTH (5).</summary>
/// <param name="AArgs">DepthGiven/DepthRaw=--depth; RulesFile=--rules.</param>
/// <param name="ADepth">The depth to expand to (&gt;= 1); only meaningful when the
/// result is True.</param>
/// <returns>True when ADepth is set; False on a usage error, already printed
/// as one 'ERROR: ...' line (the caller exits 2): --depth that is not decimal
/// digits ('+3', '$A' and '-1' included -- the IsDecimalDigits check '#depth'
/// uses) or is &lt; 1; a --rules file that is missing or unreadable; a book whose
/// '#depth' is invalid or repeated (named by file and line).</returns>
/// <remarks>The book is read whenever --rules is given, even beside --depth, so
/// a broken '#depth' never goes unnoticed; its other parse errors are ignored
/// here (convert-validate reports them). Depth is the class-recursion budget:
/// a K-segment path needs depth &gt;= K-1.</remarks>
function ResolveTreeDepth(const AArgs: TArgs; out ADepth: Integer): Boolean;
var
  Book: TConversionRuleSet;
  E   : TRuleError        ;
  Bad : Boolean           ;
begin
  Result:= False;
  ADepth:= DEFAULT_TREE_DEPTH;
  Book  := Default(TConversionRuleSet);
  if AArgs.RulesFile <> '' then
  begin
    if not TFile.Exists(AArgs.RulesFile) then
    begin
      Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile]));
      Exit;
    end;
    try
      Book:= ParseConversionRules(TFile.ReadAllText(AArgs.RulesFile));
    except
      on Ex: Exception do
      begin
        Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message]));
        Exit;
      end;
    end;
    Bad:= False;
    for E in Book.ParseErrors do
      if E.IsDepthError then
      begin
        Writeln(Format('ERROR: %s line %d: %s', [AArgs.RulesFile, E.LineNo, E.Message]));
        Bad:= True;
      end;
    if Bad then Exit;
  end;
  if AArgs.DepthGiven then
  begin
    // Decimal digits only, exactly like '#depth': TryStrToInt alone takes '+3'
    // and '$A' (hex).
    if not IsDecimalDigits(AArgs.DepthRaw) or not TryStrToInt(AArgs.DepthRaw, ADepth) or
      (ADepth < MIN_BOOK_DEPTH) then
    begin
      Writeln(Format('ERROR: --depth must be an integer >= 1 (got "%s")', [AArgs.DepthRaw]));
      Exit;
    end;
  end
  else if Book.Depth > 0 then
    ADepth:= Book.Depth;
  Result:= True;
end;

const
  MAX_PROGRESS_INTERVAL_S = 86400; // one day; keeps S * 1000 inside an Integer

/// <summary>The progress interval of proptree / convert-scaffold, from
/// --progress-interval S (engine 1.20.6, T2e).</summary>
/// <param name="AArgs">ProgressIntervalGiven/ProgressIntervalRaw.</param>
/// <param name="AMs">The interval in milliseconds; 0 = off -- the default
/// (flag absent) and S = 0 alike. Only meaningful when the result is
/// True.</param>
/// <returns>True when AMs is set; False on a usage error, already printed as
/// one 'ERROR: ...' line (the caller exits 2): S that is not decimal digits
/// (a sign, a '$' hex prefix, a decimal point -- the IsDecimalDigits check
/// '#depth' and --depth use) or is above 86400.</returns>
function ResolveProgressInterval(const AArgs: TArgs; out AMs: Integer): Boolean;
var
  Secs: Integer;
begin
  AMs:= 0;
  if not AArgs.ProgressIntervalGiven then Exit(True);
  if not IsDecimalDigits(AArgs.ProgressIntervalRaw) or not TryStrToInt(AArgs.ProgressIntervalRaw, Secs) or
    (Secs > MAX_PROGRESS_INTERVAL_S) then
  begin
    Writeln(Format('ERROR: --progress-interval must be an integer 0..%d (seconds; got "%s")',
      [MAX_PROGRESS_INTERVAL_S, AArgs.ProgressIntervalRaw]));
    Exit(False);
  end;
  AMs   := Secs * MS_PER_SECOND;
  Result:= True;
end;

// S as a quoted JSON string ("..."), escaped, non-ASCII as \u -- for the
// progress line, which is built by hand to fix its key order and number format.
function ProgressJsonStr(const S: string): string;
var
  J: TJSONString;
begin
  J:= TJSONString.Create(S);
  try
    Result:= J.ToJSON;
  finally
    J.Free;
  end;
end;

/// <summary>The TPropTreeOptions.OnProgress handler of a tree-expanding verb:
/// writes each snapshot as ONE JSON line to STDERR (engine 1.20.6, T2e).</summary>
/// <param name="AVerb">'proptree' or 'convert-scaffold' (the line's "verb").</param>
/// <returns>A handler that writes
/// {"progress":{"elapsed_s":12.3,"verb":"proptree","class":"Unit.TX","depth":2,
/// "max_depth":5,"classes_done":41,"classes_queued":7,"nodes":3114}}
/// -- keys in exactly that order, no blanks, 7-bit ASCII (the class name is
/// JSON-escaped, non-ASCII as \u), elapsed_s with one decimal and a '.' in
/// every locale.</returns>
/// <remarks>elapsed_s counts from THIS call (the verb's arguments are valid by
/// then), so it is non-decreasing across convert-scaffold's two trees; the
/// other fields are TPropTreeProgress's. STDOUT is never written, so the
/// verb's own output is byte-identical with or without progress; a caller
/// that merges the streams (the editor slices the first '{' .. the last '}')
/// must leave progress OFF, which is the default.</remarks>
function MakeProgressWriter(const AVerb: string): TProc<TPropTreeProgress>;
var
  Clock: TStopwatch;
begin
  Clock:= TStopwatch.StartNew;
  Result:= procedure(P: TPropTreeProgress)
  begin
    Writeln(ErrOutput, Format('{"progress":{"elapsed_s":%s,"verb":%s,"class":%s,"depth":%d,' +
      '"max_depth":%d,"classes_done":%d,"classes_queued":%d,"nodes":%d}}',
      [FormatFloat('0.0', Clock.ElapsedMilliseconds / MS_PER_SECOND, TFormatSettings.Invariant),
       ProgressJsonStr(AVerb), ProgressJsonStr(P.RootQName), P.Level, P.MaxDepth, P.ClassesDone, P.ClassesQueued, P.Nodes]));
    Flush(ErrOutput);
  end;
end;

function DoPropTree(const AArgs: TArgs): Integer;
var
  Dbs   : TArray<string>  ;
  Db    : string          ;
  Store : ISymbolStore    ;
  Tree  : TPropTree       ;
  Found : Boolean         ;
  Depth : Integer         ;
  Fmt   : string          ;
  Opts  : TPropTreeOptions;
  MinVis: string          ;
  ProgMs: Integer         ;

  function KindLabel(const ANode: TPropNode): string;
  begin
    Result:= ANode.Kind;
  end;

  // proptree/2 (Task 2, R2): does ANode's effective visibility pass the
  // --min-visibility threshold? AMinVis is already lower-cased/trimmed/
  // validated by the caller ('' | 'published' | 'public').
  // R4 (Task 4 review fix): a FIELD is never a DFM-streamable target,
  // regardless of its own declared visibility -- a `published FBtn:
  // TButton;` field is legal Delphi and DOES get Modifiers='published'
  // stamped by the same declField/CurrentVisibility path a published
  // PROPERTY gets, but proptree's 'published' tier specifically means "the
  // Object Inspector / DFM-streamed property surface", which fields (even
  // published ones) are not part of. This is a member_kind-based FILTER
  // exclusion only -- the node's own Visibility value is NEVER altered
  // (KindLabel/JSON emit still reports the field's real, e.g. 'published',
  // visibility); only whether it PASSES the 'published' bar changes.
  function PassesMinVisibility(const ANode: TPropNode; const AMinVis: string): Boolean;
  var
    Vis: string;
  begin
    if AMinVis = '' then Exit(True); // unset = emit ALL leaves (back-compat)
    if (AMinVis = 'published') and (SameText(Trim(ANode.MemberKind), 'field')) then Exit(False);
    Vis:= LowerCase(Trim(ANode.Visibility));
    if AMinVis = 'published' then Exit(Vis = 'published');
    Result:= (Vis = 'published') or (Vis = 'public'); // AMinVis = 'public'
  end;

begin
  if not ExplicitDbsExist(AArgs, 'proptree') then Exit(2);
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint proptree --qname X [--depth N] [--rules FILE] [--progress-interval S] [--no-to-persistent] [--refs-as-leaves] [--no-write-back] [--min-visibility published|public] [--format text|json] [--json] --db PATH [--db ...]');
    Exit(2);
  end;

  Fmt:= LowerCase(Trim(AArgs.Format));

  // proptree/2 (Task 2, R2): validate --min-visibility up front (usage error,
  // not a silent fall-through) so a typo does not silently emit ALL leaves.
  MinVis:= LowerCase(Trim(AArgs.MinVisibility));
  if (MinVis <> '') and (MinVis <> 'published') and (MinVis <> 'public') then
  begin Writeln(Format('ERROR: --min-visibility must be published|public (got "%s")', [AArgs.MinVisibility])); Exit(2); end;

  // --depth > the --rules book's #depth > 5. Before 1.20.6 this read AArgs.Depth,
  // whose parse default is 3, so a proptree with no --depth ran at 3, not the
  // documented 6.
  if not ResolveTreeDepth(AArgs, Depth) then Exit(2);
  if not ResolveProgressInterval(AArgs, ProgMs) then Exit(2);

  Opts:= Default(TPropTreeOptions);
  Opts.Depth            := Depth;
  Opts.ToPersistent     := AArgs.ToPersistent;
  Opts.TreatRefsAsLeaves:= AArgs.RefsAsLeaves;
  Opts.ProgressIntervalMs:= ProgMs;
  if ProgMs > 0 then Opts.OnProgress:= MakeProgressWriter('proptree');

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  // Multi-db resolution: use the FIRST db whose qname resolves to a class
  // (RootType non-empty). Exit 2 if no --db is readable; exit 1 if none resolve.
  Store:= nil;
  Found:= False;
  Tree := Default(TPropTree);
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    // Write-back is AUTOMATIC: open the index WRITABLE by default so a bridged type
    // is memoized onto the property row (next query is a plain hit). --no-write-back
    // forces a read-only (query_only) open that never mutates the DB. A writable
    // open that fails (locked / read-only file / stale schema) falls back to
    // read-only so resolution still works -- memoization is best-effort.
    var CandidateStore: ISymbolStore;
    if AArgs.NoWriteBack then CandidateStore:= OpenReadOnlyStore(Db, RoOk)
    else
    begin
      CandidateStore:= OpenWritableStore(Db, RoOk);
      if not RoOk then CandidateStore:= OpenReadOnlyStore(Db, RoOk); // graceful read-only fallback
    end;
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'proptree', Db) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    Store:= CandidateStore; // at least one readable db
    var Candidate: TPropTree:= BuildPropTree(CandidateStore, AArgs.QName, Opts);
    if Candidate.RootType <> '' then
    begin
      Tree := Candidate;
      Found:= True;
      Break;
    end;
  end;
  if Store = nil then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;
  if not Found then
  begin
    ReportNotFoundFor(AArgs.AsJson or SameText(AArgs.Format, 'json'), Format('class not found: %s', [AArgs.QName]));
    Exit(1);
  end;

  if (Fmt = 'json') or ((Fmt = '') and AArgs.AsJson) then
  begin
    var JRoot: TJSONObject:= TJSONObject.Create;
    try
      JRoot.AddPair('schema'   , 'proptree/2'    );
      JRoot.AddPair('qname'    , AArgs.QName      );
      JRoot.AddPair('root_type', Tree.RootType    );
      JRoot.AddPair('truncated', TJSONBool.Create(Tree.Truncated));
      var JProps: TJSONArray:= TJSONArray.Create;
      for var N in Tree.Nodes do
      begin
        if not PassesMinVisibility(N, MinVis) then Continue;
        var JN: TJSONObject:= TJSONObject.Create;
        JN.AddPair('path'          , N.Path      );
        JN.AddPair('type'          , N.TypeName  );
        JN.AddPair('declared_in'   , N.DeclaredIn);
        JN.AddPair('kind'          , KindLabel(N));
        JN.AddPair('is_class_typed', TJSONBool.Create(N.IsClassTyped));
        JN.AddPair('visibility'    , N.Visibility);
        JN.AddPair('is_writable'   , TJSONBool.Create(N.IsWritable));
        JN.AddPair('member_kind'   , N.MemberKind);
        { The `default` clause. ADDITIVE to proptree/2. has_default=false covers
          `nodefault`, a bare `default;` (the default-ARRAY-PROPERTY directive,
          which carries no value) and no clause at all -- in every one of those
          the property is always streamed, so its absence from a .dfm is
          genuinely unknown rather than "at its default". }
        JN.AddPair('has_default'   , TJSONBool.Create(N.HasDefault));
        JN.AddPair('default_value' , N.DefaultValue);
        JProps.AddElement(JN);
      end;
      JRoot.AddPair('properties', JProps);
      // One document, one write, after every stderr byte (WriteStdoutDocument):
      // the bytes Writeln(JRoot.Format(2)) wrote before T2i.
      WriteStdoutDocument(JRoot.Format(2) + sLineBreak);
    finally
      JRoot.Free;
    end;
  end
  else // text (default, or explicit --format text)
  begin
    var ShownCount: Integer:= 0;
    for var N in Tree.Nodes do
      if PassesMinVisibility(N, MinVis) then Inc(ShownCount);
    // One document, one write (WriteStdoutDocument): the same lines Writeln
    // wrote one by one before T2i, each ended by sLineBreak as Writeln ends it.
    var Doc: TStringBuilder:= TStringBuilder.Create;
    try
      Doc.Append(Format('%s  (%d properties%s)', [Tree.RootType, ShownCount,
        IfThen(Tree.Truncated, ', truncated', '')])).Append(sLineBreak);
      for var N in Tree.Nodes do
      begin
        if not PassesMinVisibility(N, MinVis) then Continue;
        // Indent by the path's dot-depth (top-level = 0).
        var DotDepth: Integer:= 0;
        for var Ch in N.Path do if Ch = '.' then Inc(DotDepth);
        var Leaf: string:= N.Path;
        var LastDot: Integer:= LastDelimiter('.', N.Path);
        if LastDot > 0 then Leaf:= Copy(N.Path, LastDot + 1, MaxInt);
        Doc.Append(Format('%s%s: %s [%s]', [StringOfChar(' ', DotDepth * 2), Leaf, N.TypeName, KindLabel(N)])).Append(sLineBreak);
      end;
      WriteStdoutDocument(Doc.ToString);
    finally
      Doc.Free;
    end;
  end;
  Result:= 0;
end; // function

{ convert-validate / convert-reemit: the --from / --to name AName as the
  #convert classes of convert-apply resolve it, with no unit to scope it
  (TConvertTreeCache.ScopedClass with no SetScope): a qualified name is taken
  as written; a bare one is settled by the book's own qualification of it (the
  first #convert whose From -- AToSide: To -- has that bare tail), else by a
  lone unit-level declarer. Returns the qualified name, or AName unchanged when
  it is qualified or resolves nowhere (the verbs' exact-name lookup then
  decides, as before). AScoped carries the answer; PAS_RES_AMBIGUOUS means
  the caller must refuse. Opens ADbs read-only; a DB that does not open is
  skipped (ConvertClassIn reports it). }
function QualifyConvertArg(const ADbs: TArray<string>; const ARules: TConversionRuleSet;
  const AName: string; AToSide: Boolean; out AScoped: TScopedClass): string;
var
  Stores: TArray<ISymbolStore>;
begin
  Result := AName;
  AScoped:= Default(TScopedClass);
  if (Trim(AName) = '') or (Pos('.', AName) > 0) then Exit;
  var Hint: string:= '';
  for var R: TConversionRule in ARules.Rules do
    if (R.Kind = rkConvert) and (Hint = '') then
    begin
      var Spelled: string:= if AToSide then R.ToType else R.FromType;
      if SameText(Copy(Spelled, LastDelimiter('.', Spelled) + 1, MaxInt), Trim(AName)) then Hint:= Spelled;
    end;
  Stores:= nil;
  for var LDb: string in ADbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var St: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if RoOk then Stores:= Stores + [St];
  end;
  var Trees: TConvertTreeCache:= TConvertTreeCache.Create(Stores);
  try
    AScoped:= Trees.ScopedClass(AName, Hint);
  finally
    Trees.Free;
  end;
  if AScoped.Resolution = PAS_RES_RESOLVED then Result:= AScoped.QName;
end;

{ The refusal for an ambiguous --from / --to (QualifyConvertArg; owner ruling
  2026-10-11: detailed, with the fix): an 'ERROR:' line naming the candidates,
  then one ready-to-use argument per candidate. }
function AmbiguousArgMessage(const AFlag, AName: string; const AScoped: TScopedClass): string;
begin
  var QNames: TArray<string>:= nil;
  for var C: string in AScoped.Candidates do QNames:= QNames + [C + '.' + AName];
  Result:= Format('ERROR: %s %s is ambiguous -- declared by %s (no unit to scope it; the book does not qualify it). ' +
    'Qualify it, or qualify the book''s #convert line. Nothing was validated against a guess',
    [AFlag, AName, String.Join(', ', AScoped.Candidates)]);
  for var Q: string in QNames do Result:= Result + sLineBreak + Format('  use: %s %s', [AFlag, Q]);
end;

{ convert-validate / convert-reemit: the class AQName names in the first of ADbs
  whose index has it (a stale explicit --db sets AStale and stops, as
  StaleDbRefusesRun rules; a stale manifest DB is skipped). Each store opened
  gets its own TPropMemberCache, added to ACaches (which owns it); the result
  pairs AQName with the cache of the store that resolved it. Unset when AQName
  is '' or resolves nowhere. 1.20.6 (T2b): replaces the two verbs' TreeFor, which
  built a whole property tree per type. }
function ConvertClassIn(const AArgs: TArgs; const AVerb: string; const ADbs: TArray<string>;
  const AQName: string; const AOpts: TPropTreeOptions; ACaches: TObjectList<TPropMemberCache>;
  var AStale: Boolean): TClassRef;
var
  LDb  : string;
  Cache: TPropMemberCache;
begin
  Result:= Default(TClassRef);
  if AQName = '' then Exit;
  for LDb in ADbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, AVerb, LDb) then
      begin
        AStale:= True;
        Exit;
      end;
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    Cache:= TPropMemberCache.Create(CandStore, AOpts);
    ACaches.Add(Cache);
    if Cache.MembersOf(AQName).RootType <> '' then
    begin
      Result.QName:= AQName;
      Result.Cache:= Cache;
      Exit;
    end;
  end;
end;

function DoConvertValidate(const AArgs: TArgs): Integer;
var
  RulesText: string             ;
  RuleSet  : TConversionRuleSet ;
  Errors   : TArray<TRuleError> ;
  FromCls  : TClassRef          ;
  ToCls    : TClassRef          ;
  Opts     : TPropTreeOptions   ;
  Dbs      : TArray<string>     ;
  Caches   : TObjectList<TPropMemberCache>; { one per store opened -- owns them }
  E        : TRuleError         ;
  R        : TConversionRule    ;
  { ClassFor returns a TClassRef, so it cannot Exit(2) on a stale explicit --db.
    It raises this flag instead and the body refuses right after the calls. }
  StaleExplicitDb: Boolean      ;
  Unreach  : TArray<TUnreachablePath>; { T2h: paths through inaccessible members -- warnings }
  U        : TUnreachablePath   ;

  function KindStr(const AKind: TRuleKind): string;
  begin
    case AKind of
      rkUnuse  : Result:= 'unuse';
      rkRemove : Result:= 'remove';
      rkMigrate: Result:= 'migrate';
      rkConvert: Result:= 'convert';
      rkLink   : Result:= 'link';
      rkDefault: Result:= 'default';
      rkNote   : Result:= 'note';
      rkPcre   : Result:= 'pcre';
      rkIgnore : Result:= 'ignore';
      rkUse    : Result:= 'use';
      rkUseSwap: Result:= 'useswap';
      rkMapping: Result:= 'mapping';
      rkApply  : Result:= 'apply';
      rkDepth  : Result:= 'depth';
      rkWarn    : Result:= 'warn';
      rkCheckRef: Result:= 'check-ref';
    else        Result:= '?';
    end;
  end;

  // Render a #mapping branch's set list as 'A = 1, B = 2'. A pair with an empty
  // Value prints as the bare ToPath -- the shape the editor's parser accepts and
  // re-emits, so the printer must not invent an '=' that the source lacked.
  function SetsSummary(const ASets: TArray<TMappingSetPair>): string;
  var
    Parts: TArray<string>;
    P    : TMappingSetPair      ;
  begin
    Parts:= nil;
    for P in ASets do
      if P.Value = '' then
        Parts:= Parts + [P.ToPath]
      else
        Parts:= Parts + [P.ToPath + ' = ' + P.Value];
    Result:= String.Join(', ', Parts);
  end;

  // One-line summary of a parsed rule's key fields (for --print-parsed).
  function RuleSummary(const R: TConversionRule): string;
  begin
    case R.Kind of
      rkUnuse  : Result:= Format('unuse %s', [R.UnitName]);
      rkRemove : Result:= Format('remove %s%s', [R.PropName, IfThen(R.DfmOnly, ' (DFM-only)', '')]);
      rkMigrate: Result:= Format('migrate %s%s -> %s%s', [R.Scope, R.Old, R.New,
                            IfThen(Length(R.UnitsAdd) > 0, ' [+' + String.Join(',', R.UnitsAdd) + ']', '')]);
      rkConvert: Result:= Format('convert %s -> %s%s', [R.FromType, R.ToType,
                            IfThen(Length(R.UnitsAdd) > 0, ' [+' + String.Join(',', R.UnitsAdd) + ']', '')]);
      { The cast is printed as a SEPARATE, LABELLED field, not re-joined onto
        FromPath with ' : '. Re-joining is what this printer used to do by
        accident -- it echoed the corrupted FromPath as `link Size <- Size :
        Round`, which reads exactly like a captured cast and is why the parser
        defect survived a review of this very output. A reader must be able to
        tell "the cast was captured" from "the path swallowed it". }
      rkLink   : Result:= Format('link %s <- %s%s%s', [R.ToPath, R.FromPath,
                            IfThen(R.GlyphExpr <> '', ' [glyph ' + R.GlyphExpr + ']', ''),
                            IfThen(R.Cast <> '', ' [cast ' + R.Cast + ']', '')]);
      rkDefault: Result:= Format('default %s = %s', [R.ToPath, R.Value]);
      rkNote   : Result:= Format('note %s', [R.Text]);
      rkPcre   : Result:= Format('pcre %s -> %s', [R.Search, R.Replace]);
      rkIgnore : Result:= Format('ignore FromPath=%s', [R.FromPath]);
      rkUse    : Result:= Format('use %s', [R.UnitName]);
      rkUseSwap: Result:= Format('useswap %s -> %s', [R.UnitName, String.Join(', ', R.UnitsAdd)]);
      { A #mapping is THREE flat sibling line forms sharing only <Name>, so the
        summary must show WHICH form this line is -- a declaration, a #when or a
        #else -- or a reader cannot tell a captured condition from a lost one.
        Same lesson as the rkLink cast above: print the parts separately. }
      rkMapping: if R.IsElse then
                   Result:= Format('mapping %s #else -> %s', [R.MapName, SetsSummary(R.Sets)])
                 else if R.WhenFrom <> '' then
                   Result:= Format('mapping %s #when %s = %s -> %s',
                              [R.MapName, R.WhenFrom, R.WhenValue, SetsSummary(R.Sets)])
                 else if R.MapFromType <> '' then
                   Result:= Format('mapping %s from %s to %s',
                              [R.MapName, R.MapFromType, String.Join(', ', R.MapToTypes)])
                 else
                   Result:= Format('mapping %s', [R.MapName]);
      rkApply  : Result:= Format('apply %s', [R.MapName]);
      rkDepth  : Result:= Format('depth %d', [R.Depth]);
      rkWarn    : Result:= Format('warn %s "%s"', [R.FromPath, R.Text]);
      rkCheckRef: Result:= Format('check-ref %s -> %s', [R.ToPath, String.Join(', ', R.RefTargets)]);
    else        Result:= KindStr(R.Kind);
    end;
  end;

  // The class a type qname names across the resolved DBs (first DB that resolves
  // it wins), with that store's member cache. Unset if unresolved / no db.
  function ClassFor(const AQName: string): TClassRef;
  begin
    Result:= ConvertClassIn(AArgs, 'convert-validate', Dbs, AQName, Opts, Caches, StaleExplicitDb);
  end;

begin
  if not ExplicitDbsExist(AArgs, 'convert-validate') then Exit(2);
  if AArgs.RulesFile = '' then
  begin
    Writeln('Usage: drag-lint convert-validate --rules FILE [--from FromType] [--to ToType] [--print-parsed] [--glyph-stitch] [--db PATH ...]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile])); Exit(2); end;

  try
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message])); Exit(2); end;
  end;

  RuleSet:= ParseConversionRules(RulesText);

  if AArgs.PrintParsed then
  begin
    Writeln(Format('parsed %d rule(s)', [Length(RuleSet.Rules)]));
    for R in RuleSet.Rules do
      Writeln(Format('line %d: %s', [R.LineNo, RuleSummary(R)]));
    for E in RuleSet.ParseErrors do
      Writeln(Format('line %d: parse error: %s', [E.LineNo, E.Message]));
  end;

  // Resolve the from/to classes when the types are supplied. Ids are per-DB, so
  // each side is paired with the cache of the store it resolved in. When neither
  // is given this is parse-only: only parse errors surface (unset sides skip
  // path checks). Referenced components are expanded, as they always were here.
  Opts:= Default(TPropTreeOptions);
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs     := ResolveConsumerDbs(AArgs);
  StaleExplicitDb:= False; { a local Boolean is not zero-initialised }
  Caches  := TObjectList<TPropMemberCache>.Create(True);
  try
  { a bare --from / --to resolves as convert-apply's #convert classes do --
    the book's own qualification, else a lone unit-level declarer -- and an
    ambiguous one is refused below, never guessed }
  var FromScoped, ToScoped: TScopedClass;
  var FromName: string:= QualifyConvertArg(Dbs, RuleSet, AArgs.CallFrom, False, FromScoped);
  var ToName  : string:= QualifyConvertArg(Dbs, RuleSet, AArgs.RenameTo, True, ToScoped);
  FromCls := ClassFor(FromName); // --from reuses CallFrom
  ToCls   := ClassFor(ToName);   // --to   reuses RenameTo
  { ClassFor cannot Exit(2) from inside a function returning a class, so the
    refusal it could only flag is enforced here. }
  if StaleExplicitDb then Exit(2);
  if (FromScoped.Resolution = PAS_RES_AMBIGUOUS) or (ToScoped.Resolution = PAS_RES_AMBIGUOUS) then
  begin
    if FromScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--from', AArgs.CallFrom, FromScoped));
    if ToScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--to', AArgs.RenameTo, ToScoped));
    Exit(1);
  end;

  Errors:= ValidateConversionRules(RuleSet, FromCls, ToCls, Unreach);
  if AArgs.GlyphStitch then
  begin
    { --from names ONE class, so only the blocks converting THAT class are judged. }
    var GlyphBlocks: TArray<TBlockClasses>:= [Default(TBlockClasses)];
    for var GR: TConversionRule in RuleSet.Rules do
      if GR.Kind = rkConvert then
      begin
        var GB: TBlockClasses:= Default(TBlockClasses);
        if SameText(GR.FromType.Substring(GR.FromType.LastIndexOf('.') + 1), FromCls.QName.Substring(FromCls.QName.LastIndexOf('.') + 1)) then GB.FromClass:= FromCls;
        GlyphBlocks:= GlyphBlocks + [GB];
      end;
    Errors:= Errors + MissingGlyphCountReaders(RuleSet, GlyphBlocks);
  end;
  finally
    Caches.Free;
  end;

  for E in Errors do
    Writeln(Format('line %d: %s', [E.LineNo, E.Message]));
  { Warnings never change the exit code: the book is valid, just suspicious.
    T2h (owner ruling R12): a path through an inaccessible member first, each
    its whole 'line N: warning: ...' text, on stdout beside the errors. }
  for U in DistinctUnreachable(Unreach) do
    Writeln(U.Message);
  for E in ConversionRuleWarnings(RuleSet) do
    Writeln(Format('line %d: warning: %s', [E.LineNo, E.Message]));
  { G3: a member #migrate (inside a #convert block) convert-apply will not
    realise -- its own refusal sentence; a file-scope #migrate is not a member
    migration and is left alone, as convert-apply does }
  var InBlock: Boolean:= False;
  for R in RuleSet.Rules do
  begin
    InBlock:= InBlock or (R.Kind = rkConvert);
    if not InBlock or (R.Kind <> rkMigrate) then Continue;
    { 1.38 (D2): a plain rule naming uses units is an identifier #migrate,
      which convert-apply realises }
    var Plain: TConversionRule:= R;
    Plain.UnitsAdd:= nil;
    if (Length(R.UnitsAdd) > 0) and (MigrateRuleRefusal(Plain) = '') then Continue;
    var Why: string:= MigrateRuleRefusal(R);
    if Why <> '' then
      Writeln(Format('line %d: warning: #migrate %s -> %s is not applied by convert-apply -- %s', [R.LineNo, R.Old, R.New, Why]));
  end;

  { 1.26.1: without both types the paths were never checked -- say so (on
    stderr, so the stdout contract 'OK' is unchanged), or a bare run reads as
    a validated book. }
  if (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
    Writeln(ErrOutput, 'NOTE: --from and --to not both given -- the book was PARSED only; #link/#default paths were not checked (convert-apply validates every block)');
  if Length(Errors) > 0 then Exit(1);
  if not AArgs.PrintParsed then Writeln('OK');
  Result:= 0;
end; // function

{ T2h (owner ruling R12): apply/1 unreachable[] and convert-reemit's -- one
  object per UNREACHABLE rule path, keys line, path, member, visibility,
  class, reason (always 'unreachable') and message (the exact text line), in
  that order. The caller owns the array. }
function UnreachableJson(const AItems: TArray<TUnreachablePath>): TJSONArray;
var
  U : TUnreachablePath;
  JU: TJSONObject;
begin
  Result:= TJSONArray.Create;
  for U in AItems do
  begin
    JU:= TJSONObject.Create;
    JU.AddPair('line'      , TJSONNumber.Create(U.LineNo));
    JU.AddPair('path'      , U.Path);
    JU.AddPair('member'    , U.Member);
    JU.AddPair('visibility', U.Visibility);
    JU.AddPair('class'     , U.DeclaringClass);
    JU.AddPair('reason'    , 'unreachable');
    JU.AddPair('message'   , U.Message);
    Result.AddElement(JU);
  end;
end;

function DoConvertReemit(const AArgs: TArgs): Integer;
var
  FromCls  : TClassRef          ;
  ToCls    : TClassRef          ;
  Rules    : TConversionRuleSet ;
  Res      : TReemitResult      ;
  Opts     : TPropTreeOptions   ;
  Caches   : TObjectList<TPropMemberCache>; { one per store opened -- owns them }
  Dbs      : TArray<string>     ;
  BlockText: string             ;
  RulesText: string             ;
  JRoot    : TJSONObject        ;
  JReport  : TJSONObject        ;
  { ConvertClassIn cannot Exit(2) on a stale explicit --db. It raises this flag
    instead and the body refuses right after the calls. }
  StaleExplicitDb: Boolean      ;
  Unreach  : TArray<TUnreachablePath>; { T2h: skipped, and listed in unreachable[] }

  function ArrJson(const A: TArray<string>): TJSONArray;
  var S: string;
  begin
    Result:= TJSONArray.Create;
    for S in A do Result.Add(S);
  end;

begin
  if not ExplicitDbsExist(AArgs, 'convert-reemit') then Exit(2);
  if (AArgs.FromBlockFile = '') or (AArgs.RulesFile = '') or
     (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint convert-reemit --from-block FILE --rules FILE --from FromType --to ToType --db PATH');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.FromBlockFile) then
  begin Writeln('from-block not found: ' + AArgs.FromBlockFile); Exit(2); end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln('rules not found: ' + AArgs.RulesFile); Exit(2); end;

  try
    BlockText:= TFile.ReadAllText(AArgs.FromBlockFile);
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read input file (%s)', [Ex.Message])); Exit(2); end;
  end;

  Rules:= ParseConversionRules(RulesText);
  { Same refusal as convert-apply: a G-link is not realised yet (CV-2), and
    re-emitting without it would carry the source image whole. }
  var Unrealised: TArray<TRuleError>:= UnrealisedGlyphLinks(Rules);
  if Length(Unrealised) > 0 then
  begin
    for var U in Unrealised do Writeln(Format('ERROR: line %d: %s', [U.LineNo, U.Message]));
    Exit(1);
  end;

  // Resolve the F/T classes in the first DB that resolves each qname (the same
  // store-open + multi-db loop as convert-validate: ConvertClassIn). Referenced
  // components are expanded, as they always were in this verb.
  Opts:= Default(TPropTreeOptions);
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs     := ResolveConsumerDbs(AArgs);
  StaleExplicitDb:= False; { a local Boolean is not zero-initialised }
  Caches  := TObjectList<TPropMemberCache>.Create(True);
  try
  { a bare --from / --to: convert-validate's rule (QualifyConvertArg) }
  var FromScoped, ToScoped: TScopedClass;
  var FromName: string:= QualifyConvertArg(Dbs, Rules, AArgs.CallFrom, False, FromScoped);
  var ToName  : string:= QualifyConvertArg(Dbs, Rules, AArgs.RenameTo, True, ToScoped);
  FromCls := ConvertClassIn(AArgs, 'convert-reemit', Dbs, FromName, Opts, Caches, StaleExplicitDb); // --from reuses CallFrom
  ToCls   := ConvertClassIn(AArgs, 'convert-reemit', Dbs, ToName, Opts, Caches, StaleExplicitDb);   // --to   reuses RenameTo
  if StaleExplicitDb then Exit(2);
  if (FromScoped.Resolution = PAS_RES_AMBIGUOUS) or (ToScoped.Resolution = PAS_RES_AMBIGUOUS) then
  begin
    if FromScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--from', AArgs.CallFrom, FromScoped));
    if ToScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--to', AArgs.RenameTo, ToScoped));
    Exit(1);
  end;

  { T2h (owner ruling R12): a #link / #default / #mapping path through a member
    that exists but is inaccessible is skipped, as in convert-apply. Only the
    unreachable half of the validation is used here -- this verb never refused
    on a missing path, and does not start to. }
  ValidateConversionRules(Rules, FromCls, ToCls, Unreach);
  Res:= ReemitComponent(BlockText, Rules, FromCls, ToCls, ParseCastLib(AArgs.CastLibFile), Unreach);
  finally
    Caches.Free;
  end;

  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('ok', TJSONBool.Create(Res.Ok));
    JRoot.AddPair('error', Res.Error);
    JRoot.AddPair('dfm', Res.DfmText);
    JReport:= TJSONObject.Create;
    JReport.AddPair('dropped',    ArrJson(Res.Report.Dropped));
    JReport.AddPair('ignored',    ArrJson(Res.Report.Ignored));
    JReport.AddPair('mismatched', ArrJson(Res.Report.Mismatched));
    JReport.AddPair('created',    ArrJson(Res.Report.Created));
    JReport.AddPair('ownedParts', ArrJson(Res.Report.OwnedParts));
    JReport.AddPair('stubs',      ArrJson(Res.Report.Stubs));
    JReport.AddPair('relocated',  ArrJson(Res.Report.Relocated));
    var JCarried: TJSONArray:= TJSONArray.Create;
    for var CR in Res.Report.Carried do
    begin
      var JCR: TJSONObject:= TJSONObject.Create;
      JCR.AddPair('fromPath', CR.FromPath);
      JCR.AddPair('toPath'  , CR.ToPath);
      JCR.AddPair('ruleLine', TJSONNumber.Create(CR.RuleLine));
      JCR.AddPair('type'    , CR.TypeName);
      JCarried.AddElement(JCR);
    end;
    JReport.AddPair('carried', JCarried);
    JReport.AddPair('mappingNotes', ArrJson(Res.Report.MappingNotes));
    var JNotApplied: TJSONArray:= TJSONArray.Create;
    for var NA in Res.Report.NotApplied do
    begin
      var JNA: TJSONObject:= TJSONObject.Create;
      JNA.AddPair('mapName' , NA.MapName);
      JNA.AddPair('ruleLine', TJSONNumber.Create(NA.RuleLine));
      JNA.AddPair('path'    , NA.Path);
      JNA.AddPair('value'   , NA.Value);
      JNotApplied.AddElement(JNA);
    end;
    JReport.AddPair('notApplied', JNotApplied);
    var JSuperseded: TJSONArray:= TJSONArray.Create;
    for var DS in Res.Report.DefaultsSuperseded do
    begin
      var JDS: TJSONObject:= TJSONObject.Create;
      JDS.AddPair('path'    , DS.Path);
      JDS.AddPair('value'   , DS.Value);
      JDS.AddPair('existing', DS.Existing);
      JDS.AddPair('ruleLine', TJSONNumber.Create(DS.RuleLine));
      JSuperseded.AddElement(JDS);
    end;
    JReport.AddPair('defaultsSuperseded', JSuperseded);
    var JResolved: TJSONArray:= TJSONArray.Create;
    for var DR in Res.Report.DefaultsResolved do
    begin
      var JDR: TJSONObject:= TJSONObject.Create;
      JDR.AddPair('fromPath', DR.FromPath);
      JDR.AddPair('toPath'  , DR.ToPath);
      JDR.AddPair('value'   , DR.Value);
      JDR.AddPair('ruleLine', TJSONNumber.Create(DR.RuleLine));
      JResolved.AddElement(JDR);
    end;
    JReport.AddPair('defaultsResolved', JResolved);
    var JEnumUn: TJSONArray:= TJSONArray.Create;
    for var EU in Res.Report.EnumUnmapped do
    begin
      var JEU: TJSONObject:= TJSONObject.Create;
      JEU.AddPair('castName', EU.CastName);
      JEU.AddPair('fromPath', EU.FromPath);
      JEU.AddPair('toPath'  , EU.ToPath);
      JEU.AddPair('value'   , EU.Value);
      JEU.AddPair('ruleLine', TJSONNumber.Create(EU.RuleLine));
      JEnumUn.AddElement(JEU);
    end;
    JReport.AddPair('enumUnmapped', JEnumUn);
    { 'notes' deliberately stays the UNION of stubs + relocated + notes.
      DRagLint.Convert.DfmReemit split those two OUT of Notes so each entry can
      carry a stable kind instead of being classified by matching its prose; this
      key predates the split, so emitting the union keeps every existing consumer
      reading exactly what it read before. 'stubs'/'relocated' are additive. }
    JReport.AddPair('notes',      ArrJson(Res.Report.Stubs + Res.Report.Relocated +
                                          Res.Report.MappingNotes + Res.Report.Notes));
    JRoot.AddPair('report', JReport);
    JRoot.AddPair('unreachable', UnreachableJson(DistinctUnreachable(Unreach))); { T2h -- same objects as apply/1 }
    WriteStdoutDocument(JRoot.ToJSON + sLineBreak); // after every stderr byte (T2i R18)
  finally
    JRoot.Free;
  end;

  if Res.Ok then Exit(0) else Exit(1);
end; // function

function DoConvertScaffold(const AArgs: TArgs): Integer;
var
  Dbs      : TArray<string>  ;
  LDb      : string          ;
  FromTree : TPropTree       ;
  ToTree   : TPropTree       ;
  HaveStore: Boolean         ;
  Opts     : TPropTreeOptions;
  Depth    : Integer         ;
  Sb       : TStringBuilder  ;
  OutText  : string          ;
  Surface  : string          ;
  ProgMs   : Integer         ;

  // Bare leaf (last dotted segment) of a path, lowercased for matching.
  function LeafLower(const APath: string): string;
  var
    D: Integer;
  begin
    D:= LastDelimiter('.', APath);
    if D > 0 then Result:= Copy(APath, D + 1, MaxInt) else Result:= APath;
    Result:= LowerCase(Result);
  end;

  // Unit prefix of a qualified name ('ConvFix.TFrom' -> 'ConvFix'); '' if none.
  function UnitOf(const AQName: string): string;
  var
    D: Integer;
  begin
    D:= LastDelimiter('.', AQName);
    if D > 0 then Result:= Copy(AQName, 1, D - 1) else Result:= '';
  end;

  // Sorted copy of a tree's paths (case-insensitive). A Sorted TStringList with
  // CaseSensitive=False orders by CompareText -- no custom callback needed.
  function SortedPaths(const ATree: TPropTree): TArray<string>;
  var
    L: TStringList;
    N: TPropNode;
  begin
    L:= TStringList.Create;
    try
      L.CaseSensitive := False;
      L.Duplicates    := dupAccept;
      L.Sorted        := True;
      for N in ATree.Nodes do L.Add(N.Path);
      Result:= L.ToStringArray;
    finally
      L.Free;
    end;
  end;

  // The declared TypeName for a path in a tree ('' if not found).
  function TypeOfPath(const ATree: TPropTree; const APath: string): string;
  var
    N: TPropNode;
  begin
    Result:= '';
    for N in ATree.Nodes do
      if SameText(N.Path, APath) then Exit(N.TypeName);
  end;

  // The full TPropNode for a path in a tree (Path='' -- not present -- if
  // not found; every real leaf has a non-empty Path, so this is a safe
  // not-found sentinel).
  function NodeOfPath(const ATree: TPropTree; const APath: string): TPropNode;
  var
    N: TPropNode;
  begin
    Result:= Default(TPropNode);
    for N in ATree.Nodes do
      if SameText(N.Path, APath) then Exit(N);
  end;

  // proptree assignability engine (Task 5): does ANode qualify as a valid
  // auto-'#link'/'#default' TARGET under ASurface ('dfm' or 'pas', already
  // lower-cased/validated by the caller)? is_writable=false (a typed class
  // CONST today) is NEVER a valid target on EITHER surface. 'dfm' additionally
  // requires member_kind='property' (DFM streaming is properties only -- a
  // FIELD, even a published one, is never DFM-streamable, mirroring
  // DoPropTree's PassesMinVisibility 'published' tier) AND the effective
  // visibility='published'; 'pas' allows visibility in ('published','public')
  // and ANY member_kind (so a public FIELD is a valid PAS-surface target).
  // Graceful degrade: an UNRESOLVABLE effective visibility (Visibility='') is
  // treated as PASSING the bar on BOTH surfaces rather than being silently
  // dropped -- defensive-only in practice (the current parser always stamps a
  // non-empty Modifiers value; see DRagLint.Convert.PropTree's
  // ResolveInheritedVisibility remark), but this keeps an old/foreign DB row
  // whose visibility could not be resolved exactly as visible as it is today
  // (no filter existed before this task) instead of quietly vanishing it.
  function IsValidTarget(const ANode: TPropNode; const ASurface: string): Boolean;
  var
    Vis: string;
  begin
    if not ANode.IsWritable then Exit(False); // read-only -- never a valid target, any surface
    Vis:= LowerCase(Trim(ANode.Visibility));
    // GRACEFUL-DEGRADE SAFETY NET, not dead code: Visibility='' means the
    // effective visibility could not be resolved at all (own Modifiers empty
    // AND the ancestor walk in DRagLint.Convert.PropTree also came up empty).
    // Unreachable via TODAY's indexer/parser (Modifiers is always stamped
    // non-empty; see ResolveInheritedVisibility's own remark there) -- this
    // branch exists for an old/foreign DB row a FUTURE producer could still
    // emit, so it degrades to "do not filter" (pass) rather than silently
    // dropping a target more aggressively than pre-Task-5 behavior (which had
    // no filter at all). Do not delete as unreachable; it is a documented,
    // intentional back-compat contract, not leftover debris.
    if Vis = '' then Exit(True);
    if ASurface = 'dfm' then
    begin
      if SameText(Trim(ANode.MemberKind), 'field') then Exit(False); // DFM streams properties only
      Exit(Vis = 'published');
    end;
    Result:= (Vis = 'published') or (Vis = 'public'); // ASurface = 'pas'
  end;

  // From-tree paths whose leaf name = ATLeaf (lowercased) AND whose declared
  // type is compatible (equal, case-insensitive) with ATType. Sorted (a Sorted
  // CaseSensitive=False TStringList orders by CompareText).
  function FromCandidates(const ATLeaf, ATType: string): TArray<string>;
  var
    L: TStringList;
    N: TPropNode;
  begin
    L:= TStringList.Create;
    try
      L.CaseSensitive := False;
      L.Duplicates    := dupAccept;
      L.Sorted        := True;
      for N in FromTree.Nodes do
        if (LeafLower(N.Path) = ATLeaf) and SameText(N.TypeName, ATType) then
          L.Add(N.Path);
      Result:= L.ToStringArray;
    finally
      L.Free;
    end;
  end;

  // True when SOME VALID-TARGET To path has the leaf+compatible-type of the
  // given F node (used to decide whether an F path is DROPPED). Uses the same
  // IsValidTarget test as the #link loop, so a From path whose only
  // leaf+type counterpart is a filtered-out (read-only / wrong-surface) To
  // leaf is correctly reported DROPPED rather than silently neither linked
  // nor noted.
  function ToHasCounterpart(const AFLeaf, AFType: string): Boolean;
  var
    N: TPropNode;
  begin
    Result:= False;
    for N in ToTree.Nodes do
      if (LeafLower(N.Path) = AFLeaf) and SameText(N.TypeName, AFType) and IsValidTarget(N, Surface) then
        Exit(True);
  end;

var
  TPath   : string        ;
  TType   : string        ;
  Cands   : TArray<string>;
  FPath   : string        ;
  FType   : string        ;
  UFrom   : string        ;
  UTo     : string        ;
  Header  : string        ;
begin
  if not ExplicitDbsExist(AArgs, 'convert-scaffold') then Exit(2);
  if (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint convert-scaffold --from FromType --to ToType [--output FILE] [--surface dfm|pas] [--depth N] [--rules FILE] [--progress-interval S] --db PATH [--db ...]');
    Exit(2);
  end;

  // proptree assignability engine (Task 5): --surface dfm|pas picks the
  // TARGET-side visibility bar (see IsValidTarget above); unset defaults to
  // 'dfm' -- component conversion (DFM-streamable published surface) is
  // convert-scaffold's dominant use case today (the existing
  // run_convert_scaffold.ps1 fixture is all-published, so this default does
  // not change its output). A typo'd value is a usage error (exit 2), not a
  // silent fall-through, matching --min-visibility's own validation pattern
  // in DoPropTree.
  Surface:= LowerCase(Trim(AArgs.Surface));
  if Surface = '' then Surface:= 'dfm';
  if (Surface <> 'dfm') and (Surface <> 'pas') then
  begin Writeln(Format('ERROR: --surface must be dfm|pas (got "%s")', [AArgs.Surface])); Exit(2); end;

  if not ResolveTreeDepth(AArgs, Depth) then Exit(2); // --depth > #depth > 5
  if not ResolveProgressInterval(AArgs, ProgMs) then Exit(2);
  Opts:= Default(TPropTreeOptions);
  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;
  Opts.ProgressIntervalMs:= ProgMs;
  if ProgMs > 0 then Opts.OnProgress:= MakeProgressWriter('convert-scaffold');

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  // Use the FIRST db that resolves BOTH types (ids are per-DB, so both trees
  // must come from the same store). Exit 2 if no --db is readable.
  HaveStore:= False;
  FromTree := Default(TPropTree);
  ToTree   := Default(TPropTree);
  for LDb in Dbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'convert-scaffold', LDb) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    HaveStore:= True;
    // One member cache per store for BOTH trees (1.20.6 T2c): a class the two
    // sides share (TStrings, TParams, ...) is resolved once.
    var CF: TPropTree;
    var CT: TPropTree;
    var TreeCache: TPropMemberCache:= TPropMemberCache.Create(CandStore, Opts);
    try
      CF:= TreeCache.BuildTree(AArgs.CallFrom, Opts.Depth);
      CT:= TreeCache.BuildTree(AArgs.RenameTo, Opts.Depth);
    finally
      TreeCache.Free;
    end;
    if (CF.RootType <> '') and (CT.RootType <> '') then
    begin FromTree:= CF; ToTree:= CT; Break; end;
    // Keep the first db's partial trees so we can report which type failed.
    if FromTree.RootType = '' then FromTree:= CF;
    if ToTree.RootType   = '' then ToTree  := CT;
  end;
  if not HaveStore then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;
  if FromTree.RootType = '' then begin Writeln(Format('class not found: %s', [AArgs.CallFrom])); Exit(1); end;
  if ToTree.RootType   = '' then begin Writeln(Format('class not found: %s', [AArgs.RenameTo])); Exit(1); end;

  Sb:= TStringBuilder.Create;
  try
    // (1) #convert header + best-guess uses-add (the qname unit prefixes).
    UFrom:= UnitOf(AArgs.CallFrom);
    UTo  := UnitOf(AArgs.RenameTo);
    Header:= Format('#convert %s -> %s', [AArgs.CallFrom, AArgs.RenameTo]);
    if (UTo <> '') and (not SameText(UTo, UFrom)) then
      Header:= Header + ', ' + UTo
    else if (UTo = '') and (UFrom <> '') then
      Header:= Header + ', ' + UFrom;
    Sb.AppendLine(Header);
    Sb.AppendLine('#note scaffold: review every ??? -- concrete #link lines are inferred by leaf-name+type');

    // (2) One rule per VALID-TARGET To path (sorted). A To path that fails
    // IsValidTarget (read-only on either surface; wrong member_kind/visibility
    // for the DFM surface) is skipped entirely -- no '#link', no '#default',
    // no '#note' -- it is simply not part of this surface's assignable target
    // set (Task 5).
    for TPath in SortedPaths(ToTree) do
    begin
      if not IsValidTarget(NodeOfPath(ToTree, TPath), Surface) then Continue;
      TType:= TypeOfPath(ToTree, TPath);
      Cands:= FromCandidates(LeafLower(TPath), TType);
      if Length(Cands) = 1 then
        Sb.AppendLine(Format('#link %s <- %s', [TPath, Cands[0]]))
      else if Length(Cands) > 1 then
      begin
        Sb.AppendLine(Format('#link %s <- ???', [TPath]));
        Sb.AppendLine('#note candidates: ' + String.Join(', ', Cands));
      end
      else
        Sb.AppendLine(Format('#default %s = ???', [TPath]));
    end;

    // (3) DROPPED note per From path with no compatible To target (sorted).
    for FPath in SortedPaths(FromTree) do
    begin
      FType:= TypeOfPath(FromTree, FPath);
      if not ToHasCounterpart(LeafLower(FPath), FType) then
        Sb.AppendLine(Format('#note DROPPED %s (no T target)', [FPath]));
    end;

    OutText:= Sb.ToString;
  finally
    Sb.Free;
  end;

  if AArgs.Output <> '' then
  begin
    // ASCII / CRLF file (rules DSL is strict 7-bit ASCII). AppendLine already
    // emitted platform CRLFs on Windows; ANSI keeps the bytes 1:1.
    WriteOutputFile(AArgs.Output, OutText);
    Writeln('Wrote ', AArgs.Output);
  end
  else
    WriteStdoutDocument(OutText); // already CRLF-terminated per line; after every stderr byte (T2i)

  Result:= 0;
end; // function

/// <summary>Prints the human-readable summary of one convert-apply run: the
/// header line, then one block per non-empty report surface.</summary>
/// <param name="AReport">The report to print. All six of its arrays are shown in full; ResolvedDefaults is summarised as a COUNT instead, because it is the one
/// surface whose volume scales with the form rather than with its defects.</param>
/// <param name="AEditCount">Edit count for the header line.</param>
/// <param name="AVerb">'planned' (dry-run) or 'applied' (--apply).</param>
/// <remarks>
/// This replaces TWO byte-for-byte duplicated print blocks (the dry-run one and
/// the --apply one), which BOTH printed only four of the six arrays: CreatorSites
/// and ReemitNotes were computed by BuildApplyPlan and then silently discarded.
/// That is why the engine could write "verify the creator manually" and no
/// operator ever saw it.
///
/// Block order is Converted, AccessSites, CreatorSites, Todos, ReemitNotes,
/// Warnings -- work-done surfaces first, then the REMAINDER (Todos, ReemitNotes,
/// Warnings: the things a human still has to do).
///
/// Each block is preceded by a BLANK LINE. Consumers slice a block with
/// 'Heading:([\s\S]*?)(\r?\n\r?\n|\z)' (tests\autotest\run_convert_apply.ps1);
/// without a blank terminator every such slice ran to end-of-output and so
/// silently included every later block, which made those assertions pass for the
/// wrong reason. Empty surfaces print nothing at all, as before.
/// </remarks>
procedure PrintApplyReport(const AReport: TApplyReport; AEditCount: Integer; const AVerb: string);

  procedure Block(const AHeading: string; const ALines: TArray<string>);
  var
    S: string;
  begin
    if Length(ALines) = 0 then Exit;
    Writeln('');
    Writeln(AHeading + ':');
    for S in ALines do Writeln('  ' + S);
  end;

var
  S: string;
begin
  Writeln(Format('convert-apply: %d instance(s) converted, %d edit(s) %s',
    [Length(AReport.Converted), AEditCount, AVerb]));
  { Converted keeps its heading-less shape -- it reads as the header's detail. }
  for S in AReport.Converted do Writeln('  ' + S);
  for var GL: TApplyGlyph in AReport.Glyphs do
    Writeln((if GL.Outcome.Kind = 'glyph-stitched' then '  ' + GL.Instance + ': ' else '*** GLYPH TODO: ' + GL.Instance + ': ') + GL.Outcome.Message);
  Block('AccessSites',  AReport.AccessSites);
  Block('CreatorSites', AReport.CreatorSites);
  Block('Todos',        AReport.Todos);
  Block('ReemitNotes',  AReport.ReemitNotes);
  Block('Warnings',     AReport.Warnings);
  { 1.20.6 -- one line per uses-clause change a unit rule made, e.g.
      remove OldU (interface, line 6) -- #useswap OldU -> NewU1, NewU2
    under a heading carrying the two counts; nothing when there are none. }
  if Length(AReport.UsesChanges) > 0 then
  begin
    var NRemoved: Integer:= 0;
    var NSkipped: Integer:= 0;
    var NAdded  : Integer:= 0;
    var NOther  : Integer:= 0; { C9: kept + moved }
    for var UC: TUsesChange in AReport.UsesChanges do
      if UC.Action = 'remove' then Inc(NRemoved)
      else if UC.Action = 'skipped' then Inc(NSkipped)
      else if UC.Action = 'add' then Inc(NAdded)
      else Inc(NOther);
    Writeln('');
    var Head: string:= Format('Uses: %d removed, %d added', [NRemoved, NAdded]);
    if NSkipped > 0 then Head:= Head + Format(', %d removal(s) skipped (--only)', [NSkipped]);
    if NOther > 0 then Head:= Head + Format(', %d kept/moved', [NOther]);
    Writeln(Head);
    for var UC: TUsesChange in AReport.UsesChanges do
    begin
      var Need: string:= '';
      for var N: TUsesNeed in UC.NeededBy do Need:= Need + (if Need = '' then '' else ', ') + Format('%s (line %d)', [N.Name, N.Line]);
      Writeln(Format('  %s %s (%s, line %d) -- %s', [UC.Action, UC.UnitName, UC.Section, UC.Line,
        if UC.Rule <> '' then UC.Rule else UC.Source]) +
        (if UC.Reason <> '' then ' (' + UC.Reason + ')' else '') +
        (if Need <> '' then ' [' + Need + ']' else ''));
    end;
  end;
  { C9: names the conversion introduced whose unit was not added }
  for var UU: TUsesUnresolved in AReport.UsesUnresolved do
  begin
    var Units: string:= '';
    for var C: TUsesCandidate in UU.Candidates do Units:= Units + (if Units = '' then '' else ', ') + C.UnitName;
    Writeln(Format('  unresolved %s (%s, line %d) -- %s%s', [UU.Name, UU.Section, UU.Line, UU.Reason,
      if Units <> '' then ': ' + Units else '']));
  end;  { ResolvedDefaults -- a COUNT, not a listing, and that asymmetry is deliberate.
    Text mode used to print one line per resolved default under ReemitNotes,
    which on a real form is ~2,000 lines of "this worked" ahead of the handful
    that did not. A human reading the terminal needs to know the carries
    happened and how many; the per-property account is a machine's question, so
    it goes to --format json.

    Uses Block so it keeps the `Heading:` + blank-line shape the runner slices
    on, and prints nothing at all when the array is empty, like every other
    surface here. }
  if Length(AReport.ResolvedDefaults) > 0 then
    Block('ResolvedDefaults',
      [Format('%d property value(s) carried from their declared defaults (--format json lists each)',
              [Length(AReport.ResolvedDefaults)])]);
  { 1.27.0 (C15): the value casts (StripDB) -- one count line per unit }
  var VDfm : Integer:= 0;
  var VPas : Integer:= 0;
  var VChk : Integer:= 0;
  for var VI: TApplyItem in AReport.Items do
    if VI.Kind = aikValueCastCheck then Inc(VChk)
    else if (VI.Kind = aikValueCastApplied) and SameText(ExtractFileExt(VI.FilePath), '.dfm') then Inc(VDfm)
    else if VI.Kind = aikValueCastApplied then Inc(VPas);
  if VDfm + VPas + VChk > 0 then
  begin
    Writeln('');
    Writeln(Format('value casts: %d value(s) changed (.dfm %d, .pas %d), %d site(s) to check by hand',
      [VDfm + VPas, VDfm, VPas, VChk]));
  end;
  { 1.27.0 -- pas_uses[]: one summary line, then the work list (unmapped and
    not-rewritten members) with their lines; nothing when the code uses nothing }
  if Length(AReport.PasUses) > 0 then
  begin
    var NUnm : Integer:= 0;
    var NGlob: Integer:= 0;
    var NSame: Integer:= 0;
    var NMap : Integer:= 0;
    var NCast: Integer:= 0;
    var NNotW: Integer:= 0;
    for var PU: TApplyPasUse in AReport.PasUses do
      if PU.Status = PAS_USE_UNMAPPED then Inc(NUnm)
      else if PU.Status = PAS_USE_GLOBAL_DANGLING then Inc(NGlob)
      else if PU.Status = PAS_USE_SAME_NAME then Inc(NSame)
      else if PU.Status = PAS_USE_MAPPED then Inc(NMap)
      else if PU.Status = PAS_USE_NOT_REWRITTEN then Inc(NNotW)
      else Inc(NCast);
    Writeln('');
    Writeln(Format('pas uses: %d unmapped, %d global-dangling, %d same-name, %d mapped, %d cast-refused, %d not-rewritten',
      [NUnm, NGlob, NSame, NMap, NCast, NNotW]));
    for var PU: TApplyPasUse in AReport.PasUses do
    begin
      if (PU.Status <> PAS_USE_UNMAPPED) and (PU.Status <> PAS_USE_NOT_REWRITTEN) then Continue;
      var Ls: string:= '';
      for var L: Integer in PU.Lines do Ls:= Ls + (if Ls = '' then '' else ', ') + IntToStr(L);
      { 1.28.2: an unresolved declarer is SAID, never printed as empty facts }
      var Decl: string;
      if PU.Resolution = PAS_RES_AMBIGUOUS then
        Decl:= 'declaring class ambiguous: ' + string.Join(', ', PU.Candidates)
      else if PU.Resolution = PAS_RES_RESOLVED then
        Decl:= Format('%s, %s, %s in %s', [PU.Kind, PU.Visibility, PU.DeclaredIn, PU.DeclaringUnit])
      else
        Decl:= PU.Resolution;
      Writeln(Format('  %s %s.%s (%s) -- %s %s',
        [PU.Status, PU.Instance, PU.Member, Decl, if Length(PU.Lines) = 1 then 'line' else 'lines', Ls]));
    end;
  end;
end; // procedure

type

  /// <summary>Everything schema apply/1 reports about one convert-apply run.
  /// A record rather than nine parameters, per too-many-parameters (max 7).</summary>
  /// <remarks>Populated on the SUCCESS path and on both failure paths (rule
  /// validation, and BuildApplyPlan returning Ok=False), so a JSON consumer gets
  /// a parseable document with ok=false rather than nothing at all.</remarks>
  TApplyJsonCtx = record
    Report    : TApplyReport;
    UnitPas   : string;
    DfmPath   : string;
    RulesFile : string;
    Mode      : string;  { 'dry-run' or 'apply' }
    Error     : string;
    RuleErrors: TArray<TRuleError>;
    Freshness : TFreshnessResult;
    EditCount : Integer;
    Ok        : Boolean;
    { 1.20.6: what happened to the COMPONENT (#convert / .dfm) part --
      'applied', 'skipped-no-dfm', 'skipped-no-convert-rules' or
      'skipped-no-instances' (the last three: the book's unit rules ran alone);
      '' when the run stopped before planning. }
    ComponentPart: string;
    { 1.20.6 (T2b): how many classes' members the run resolved (validation and
      plan share one cache per store) -- apply/1 classes_built. }
    ClassesBuilt: Integer;
    { 1.20.6 (T2h, owner ruling R12): the rule paths through members that exist
      but are inaccessible -- skipped, never applied -- apply/1 unreachable[].
      Their messages are ALSO in Report.Warnings / Report.Items. }
    Unreachable: TArray<TUnreachablePath>;
    { 1.20.6 (T2f): True for a DELIBERATE refusal -- the unit cannot be
      converted safely and nothing was written (a unit-rules conditional-uses
      refusal, and any TApplyResult.Refusal) --
      apply/1 refused / reason. False for every other outcome, success and
      genuine failure alike. Reason is '' unless Refused. }
    Refused: Boolean;
    Reason : string;
    { 1.34.1 (CONV-ENC E1'): set with Refused when a value does not fit the target
      .pas/.dfm encoding -- apply/1 refusal_kind 'encoding_refused' + the
      encoding_refused object (file, file_encoding, raise_to, chars_total, chars[]).
      RefusalKind is '' for every other outcome (the keys are then omitted). }
    RefusalKind: string;
    EncFile    : string;
    EncName    : string;
    EncTotal   : Integer;
    EncChars   : TArray<TEncodingMisfit>;
    { 1.22.0 (C8 N1): the inherited / inline .dfm objects of a From type the
      run SKIPPED, each with its declaring ancestor -- apply/1 inherited[]. Their
      'line N: warning:' text is ALSO in Report.Warnings / Report.Items. }
    InheritedInsts: TArray<TInheritedInstance>;
    { 1.25.0: the descendant units that still stream or use an instance this
      run converts -- apply/1 descendants[]. Their 'line N: warning:' text is
      ALSO in Report.Warnings / Report.Items. }
    Descendants: TArray<TDescendantUse>;
    { 1.23.0 (C13 b2): batch mode's collector. nil -> EmitApplyJson writes the
      document to stdout (single --unit, unchanged); assigned -> the apply/1
      object is appended to it instead (owned by the array) and nothing is
      written, so DoConvertApply can wrap every unit in one apply-batch/1. }
    Sink: TJSONArray;
    { 1.27.0 (C9): apply/1 uses_reconcile ('on' | 'off' | 'degraded') and the
      post-apply project-index refresh (uses_reindex). }
    UsesReconcile: string;
    Reindex      : TUsesReindex;
    { 1.23.0 (C13 N3): the --only names that name a .dfm object of a #convert
      From type, and the ones that name none -- apply/1 only_matched[] /
      only_unmatched[], spelled as given, in --only order; both [] without
      --only. An unmatched name is ignored (never an error). }
    OnlyMatched  : TArray<string>;
    OnlyUnmatched: TArray<string>;
    { 1.25.1: objects --only left out that convert with a kept parent }
    OnlyIncluded : TArray<TNestedOnly>;
    { owner ruling 2026-10-11: the #convert lines whose bare class name had
      several declarers -- refused, or inferred and warned about --
      apply/1 qualify_fixes[] (capability convert_qualify_fix) }
    QualifyFixes : TArray<TQualifyFix>;
  end;

const
  /// <summary>The only encoding level convert-apply --raise-encoding accepts, and the apply/1
  /// encoding_refused.raise_to value (1.34.1).</summary>
  ENC_RAISE_LEVEL = 'utf8-bom';

/// <summary>apply/1 pas_uses[] (1.27.0): one object per TApplyPasUse.</summary>
/// <param name="AUses">The report's PasUses.</param>
/// <param name="ARulesFile">The book the run applied; every row names it
/// (rules_file, additive) so a consumer merging several runs keeps the book.</param>
/// <returns>A new array; the caller owns it (AddPair takes it over).</returns>
/// <remarks>Additive keys after 1.33: migrate_to (the New of the #migrate
/// convert-apply realises for the member, DL_NONE for a deliberate break, ''
/// when none; status stays mapped) and rules_file.</remarks>
function PasUsesJson(const AUses: TArray<TApplyPasUse>; const ARulesFile: string): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var PU: TApplyPasUse in AUses do
  begin
    var JP: TJSONObject:= TJSONObject.Create;
    JP.AddPair('instance'      , PU.Instance);
    JP.AddPair('from_type'     , PU.FromType);
    JP.AddPair('to_type'       , PU.ToType);
    JP.AddPair('member'        , PU.Member);
    JP.AddPair('kind'          , PU.Kind);
    JP.AddPair('visibility'    , PU.Visibility);
    JP.AddPair('declaring_unit', PU.DeclaringUnit);
    JP.AddPair('declared_in'   , PU.DeclaredIn);
    JP.AddPair('status'        , PU.Status);
    var JL: TJSONArray:= TJSONArray.Create;
    for var L: Integer in PU.Lines do JL.Add(L);
    JP.AddPair('lines'         , JL);
    JP.AddPair('count'         , TJSONNumber.Create(Length(PU.Lines)));
    JP.AddPair('resolution'    , PU.Resolution);   { 1.28.2 }
    var JC: TJSONArray:= TJSONArray.Create;
    for var C: string in PU.Candidates do JC.Add(C);
    JP.AddPair('candidates'    , JC);
    JP.AddPair('migrate_to'    , PU.MigrateTo);    { G4, additive }
    JP.AddPair('rules_file'    , ARulesFile);      { G7, additive }
    Result.AddElement(JP);
  end;
end;
/// <summary>Writes the whole convert-apply run as schema apply/1 JSON.</summary>
/// <param name="ACtx">The run to report.</param>
/// <remarks>
/// Mirrors info/1's house style -- 'schema' first, snake_case keys. It does NOT
/// follow convert-reemit's JSON, which predates the convention, carries no
/// 'schema' key at all and uses camelCase; that is not a precedent to copy.
///
/// INVARIANT, and the reason the typed items exist: items.length equals the sum
/// of the lengths of the six arrays. Each item mirrors one array entry, adding
/// the machine-readable 'kind' and the structured facts behind the prose. The
/// REMAINDER of a conversion is the subset whose 'field' is todos, reemit_notes
/// or warnings.
///
/// Compatibility: adding a kind, or a key, is additive and stays apply/1.
/// RENAMING a kind or a key is a breaking change and requires apply/2. The kind
/// spellings come from ApplyItemKindName, never from a literal here.
///
/// Emits nothing else on stdout: under JSON the caller suppresses RenderDryRun
/// and every Writeln, or the document would not parse.
/// </remarks>
procedure EmitApplyJson(const ACtx: TApplyJsonCtx);

  function ArrOf(const AItems: TArray<string>): TJSONArray;
  var
    S: string;
  begin
    Result:= TJSONArray.Create;
    for S in AItems do Result.Add(S);
  end;

  { apply/1 glyphs[]: always present, [] when none (asks N3). The key names are the
  ones the editor's ConvRules.ConvertRun.GlyphOutcomes reads. }
function GlyphsJson(const AGlyphs: TArray<TApplyGlyph>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var G: TApplyGlyph in AGlyphs do
  begin
    var O: TJSONObject:= TJSONObject.Create;
    O.AddPair('instance' , G.Instance);
    O.AddPair('from_path', G.Outcome.FromPath);
    O.AddPair('to_path'  , G.Outcome.ToPath);
    O.AddPair('kind'     , G.Outcome.Kind);
    O.AddPair('source_n' , TJSONNumber.Create(G.Outcome.SourceN));
    O.AddPair('alternative', G.Outcome.Alternative);
    var D: TJSONArray:= TJSONArray.Create;
    for var Slot: Integer in G.Outcome.DroppedSlots do D.Add(Slot);
    O.AddPair('dropped_slots', D);
    O.AddPair('rule_line', TJSONNumber.Create(G.Outcome.RuleLine));
    O.AddPair('line'     , TJSONNumber.Create(G.Line));
    O.AddPair('message'  , G.Outcome.Message);
    Result.AddElement(O);
  end;
end;

function ItemJson(const AItem: TApplyItem): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('kind'     , ApplyItemKindName(AItem.Kind));
    Result.AddPair('field'    , ApplyFieldName(AItem.Field));
    Result.AddPair('instance' , AItem.Instance);
    Result.AddPair('from_type', AItem.FromType);
    Result.AddPair('to_type'  , AItem.ToType);
    Result.AddPair('file'     , AItem.FilePath);
    Result.AddPair('path'     , AItem.Path);
    Result.AddPair('text'     , AItem.Text);
    Result.AddPair('line'     , TJSONNumber.Create(AItem.Line));
    Result.AddPair('rule_line', TJSONNumber.Create(AItem.RuleLine));
    { 1.26.5: additive, and only on the kinds that are ABOUT a value }
    if AItem.Kind in [aikBookWarning, aikRefPathLike, aikRefDangling, aikCastNotApplied, aikValueCastApplied, aikValueCastCheck,
                      aikMigrateApplied, aikMigrateCheck, aikDeliberateBreak] then
      Result.AddPair('value', AItem.Value);
    { 1.27.0 (C15): the literal a value cast replaced; C18: the member text a
      #migrate renamed or wrapped }
    if AItem.Kind in [aikValueCastApplied, aikMigrateApplied, aikDeliberateBreak, aikMigrateCheck] then { G11: + the check's Old }
      Result.AddPair('old_value', AItem.OldValue);
  end;

var
  JRoot, JFresh, JErr: TJSONObject;
  JRuleErrors, JItems: TJSONArray;
  JResolved: TJSONArray ;
  JRD      : TJSONObject;
  RE  : TRuleError;
  Item: TApplyItem;
  RD  : TApplyResolvedDefault;
begin
  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('schema', 'apply/1');
    JRoot.AddPair('mode', ACtx.Mode);
    JRoot.AddPair('unit', ACtx.UnitPas);
    JRoot.AddPair('dfm', ACtx.DfmPath);
    JRoot.AddPair('rules_file', ACtx.RulesFile);
    JRoot.AddPair('ok', TJSONBool.Create(ACtx.Ok));
    JRoot.AddPair('error', ACtx.Error);
    { T2f: always emitted; the editor keys its 'refused -- not changed' row on
      refused == true. reason is '' unless refused. }
    JRoot.AddPair('refused', TJSONBool.Create(ACtx.Refused));
    JRoot.AddPair('reason', ACtx.Reason);
    if ACtx.RefusalKind <> '' then
    begin
      JRoot.AddPair('refusal_kind', ACtx.RefusalKind);
      var JEnc: TJSONObject:= TJSONObject.Create;
      JEnc.AddPair('file'         , ACtx.EncFile);
      JEnc.AddPair('file_encoding', ACtx.EncName);
      JEnc.AddPair('raise_to'     , ENC_RAISE_LEVEL);
      JEnc.AddPair('chars_total'  , TJSONNumber.Create(ACtx.EncTotal));
      var JChars: TJSONArray:= TJSONArray.Create;
      for var Mf: TEncodingMisfit in ACtx.EncChars do
      begin
        var JC: TJSONObject:= TJSONObject.Create;
        JC.AddPair('code', TJSONNumber.Create(Mf.Code));
        JC.AddPair('text', Mf.Text);
        JC.AddPair('line', TJSONNumber.Create(Mf.Line));
        JChars.AddElement(JC);
      end;
      JEnc.AddPair('chars', JChars);
      JRoot.AddPair('encoding_refused', JEnc);
    end;

    JRuleErrors:= TJSONArray.Create;
    for RE in ACtx.RuleErrors do
    begin
      JErr:= TJSONObject.Create;
      JErr.AddPair('line', TJSONNumber.Create(RE.LineNo));
      JErr.AddPair('message', RE.Message);
      JRuleErrors.AddElement(JErr);
    end;
    JRoot.AddPair('rule_errors', JRuleErrors);

    JRoot.AddPair('edits_count', TJSONNumber.Create(ACtx.EditCount));

    JFresh:= TJSONObject.Create;
    JFresh.AddPair('fresh', TJSONBool.Create(ACtx.Freshness.Fresh));
    JFresh.AddPair('reasons', ArrOf(ACtx.Freshness.Reasons));
    JRoot.AddPair('freshness', JFresh);

    JRoot.AddPair('converted'    , ArrOf(ACtx.Report.Converted));
    JRoot.AddPair('access_sites' , ArrOf(ACtx.Report.AccessSites));
    JRoot.AddPair('creator_sites', ArrOf(ACtx.Report.CreatorSites));
    JRoot.AddPair('todos'        , ArrOf(ACtx.Report.Todos));
    JRoot.AddPair('reemit_notes' , ArrOf(ACtx.Report.ReemitNotes));
    JRoot.AddPair('warnings'     , ArrOf(ACtx.Report.Warnings));

    JItems:= TJSONArray.Create;
    for Item in ACtx.Report.Items do JItems.AddElement(ItemJson(Item));
    JRoot.AddPair('items', JItems);

    { resolved_defaults -- ALWAYS present, [] when empty, exactly like the six
      arrays: a consumer must never have to tell "none" apart from "this engine
      does not report it". Placed AFTER items so a streaming reader sees the
      remainder first, which is the half that needs a human.

      Six keys, not ten. Every entry would carry the same kind and field, `file`
      is the document's own `dfm`, and `text` -- the bulk of a TApplyItem -- now
      holds nothing that is not a typed key here. to_path and value in
      particular were previously recoverable ONLY by parsing the prose. }
    JResolved:= TJSONArray.Create;
    for RD in ACtx.Report.ResolvedDefaults do
    begin
      JRD:= TJSONObject.Create;
      JRD.AddPair('instance' , RD.Instance);
      JRD.AddPair('from_path', RD.FromPath);
      JRD.AddPair('to_path'  , RD.ToPath  );
      JRD.AddPair('value'    , RD.Value   );
      JRD.AddPair('rule_line', TJSONNumber.Create(RD.RuleLine));
      JRD.AddPair('line'     , TJSONNumber.Create(RD.Line    ));
      JResolved.AddElement(JRD);
    end;
    JRoot.AddPair('resolved_defaults', JResolved);
    JRoot.AddPair('glyphs', GlyphsJson(ACtx.Report.Glyphs));

    { unlinked_source_properties / unlinked_source_property_sites / unlinked[]
      -- row 6 steps 1-3, complete (2026-09-16). Step 1 shipped the two
      integers alone, keyed by property NAME, so a number existed before a
      design did; measured 2 distinct / 22 sites on ORM3 VARINSP, and the
      converter team's own test was "2 is a warning, 200 is a report".

      Now derived from Report.Unlinked, which is keyed by (SOURCE TYPE,
      property) -- their refinement (a): with one #convert block the two keys
      agree, with two blocks two source types both dropping 'Style' must be two
      rows. The counts keep their step-1 names and meaning (rows, and the sum of
      their sites), so a consumer written against step 1 still parses; the
      array is additive and carries the per-row fraction their refinement (b)
      asked for, '2 of 20 instances', as sites/instances.

      The matching warnings are in warnings[]/items[] as kind
      'unlinked-source-property' unless --no-warn-unlinked; this block is
      emitted either way, so silencing the warning never loses the count.

      The denominator that matters is properties PRESENT IN THE SOURCE .dfm --
      which is exactly what the reemit Dropped list holds -- never the source
      type's surface. TabcToggleBtn has 3,905 proptree leaves and sets about
      nine per button; counting the surface would be the flood they warned of. }
    var UnlinkedTotal: Integer:= 0;
    var JUnlinked: TJSONArray:= TJSONArray.Create;
    for var U: TApplyUnlinked in ACtx.Report.Unlinked do
    begin
      Inc(UnlinkedTotal, U.Sites);
      var JU: TJSONObject:= TJSONObject.Create;
      JU.AddPair('from_type', U.FromType);
      JU.AddPair('path'     , U.Path);
      JU.AddPair('sites'    , TJSONNumber.Create(U.Sites));
      JU.AddPair('instances', TJSONNumber.Create(U.Instances));
      JUnlinked.AddElement(JU);
    end;
    JRoot.AddPair('unlinked_source_properties', TJSONNumber.Create(Length(ACtx.Report.Unlinked)));
    JRoot.AddPair('unlinked_source_property_sites', TJSONNumber.Create(UnlinkedTotal));
    { 1.26.0 (C8 N2 review): the code sites NOT rewritten because the index
      could not tie them to the converted field (items[] access-site-unverified) }
    var Unverified: Integer:= 0;
    for var UIt: TApplyItem in ACtx.Report.Items do
      if UIt.Kind = aikAccessSiteUnverified then Inc(Unverified);
    JRoot.AddPair('access_sites_unverified', TJSONNumber.Create(Unverified));
    JRoot.AddPair('unlinked', JUnlinked);

    { 1.20.6 -- the unit rules. component_part says whether the #convert /
      .dfm part ran; uses[] has one row per uses-clause change a unit rule
      made (action remove|add, unit, section interface|implementation, line in
      the unit as read, rule as normalised from the book), and the two counts
      sum it by action. Always present, [] / 0 when the book has no unit
      rules, like every other array here. The #convert blocks' own uses-add is
      NOT a row: it is surface #2 and is counted in edits_count as before. }
    JRoot.AddPair('component_part', ACtx.ComponentPart);
    var UsesRemoved: Integer:= 0;
    var UsesAdded  : Integer:= 0;
    var UsesKept   : Integer:= 0;
    var UsesMoved  : Integer:= 0;
    var JUses: TJSONArray:= TJSONArray.Create;
    for var UC: TUsesChange in ACtx.Report.UsesChanges do
    begin
      if UC.Action = 'remove' then Inc(UsesRemoved)
      else if UC.Action = 'add' then Inc(UsesAdded) { 'skipped' (C13 N4) is neither }
      else if UC.Action = 'kept' then Inc(UsesKept)
      else if UC.Action = 'moved' then Inc(UsesMoved);
      var JUC: TJSONObject:= TJSONObject.Create;
      JUC.AddPair('action' , UC.Action);
      JUC.AddPair('unit'   , UC.UnitName);
      JUC.AddPair('section', UC.Section);
      JUC.AddPair('line'   , TJSONNumber.Create(UC.Line));
      JUC.AddPair('rule'   , UC.Rule);
      JUC.AddPair('reason' , UC.Reason); { '' unless skipped (C13 N4) or kept (C9) }
      { 1.27.0 (C9) -- additive: who asked (rule | reconcile | convert) and why
        the row exists (kept: the .dfm components; reconcile add: the
        introduced names; remove: the .pas references left dangling) }
      JUC.AddPair('source' , UC.Source);
      var JNeed: TJSONArray:= TJSONArray.Create;
      for var N: TUsesNeed in UC.NeededBy do
      begin
        var JN: TJSONObject:= TJSONObject.Create;
        JN.AddPair('name'   , N.Name);
        JN.AddPair('line'   , TJSONNumber.Create(N.Line));
        JN.AddPair('section', N.Section);
        JNeed.AddElement(JN);
      end;
      JUC.AddPair('needed_by', JNeed);
      JUses.AddElement(JUC);
    end;
    JRoot.AddPair('uses', JUses);
    JRoot.AddPair('uses_removed', TJSONNumber.Create(UsesRemoved));
    JRoot.AddPair('uses_added'  , TJSONNumber.Create(UsesAdded));
    { 1.27.0 (C9) -- ALWAYS present, like every array here }
    JRoot.AddPair('uses_kept'   , TJSONNumber.Create(UsesKept));
    JRoot.AddPair('uses_moved'  , TJSONNumber.Create(UsesMoved));
    var JUnres: TJSONArray:= TJSONArray.Create;
    for var UU: TUsesUnresolved in ACtx.Report.UsesUnresolved do
    begin
      var JU: TJSONObject:= TJSONObject.Create;
      JU.AddPair('name'   , UU.Name);
      JU.AddPair('line'   , TJSONNumber.Create(UU.Line));
      JU.AddPair('section', UU.Section);
      JU.AddPair('reason' , UU.Reason);
      var JC: TJSONArray:= TJSONArray.Create;
      for var C: TUsesCandidate in UU.Candidates do
      begin
        var JCO: TJSONObject:= TJSONObject.Create;
        JCO.AddPair('unit', C.UnitName);
        JCO.AddPair('db'  , C.Db);
        JC.AddElement(JCO);
      end;
      JU.AddPair('candidates', JC);
      JUnres.AddElement(JU);
    end;
    JRoot.AddPair('uses_unresolved', JUnres);
    JRoot.AddPair('uses_reconcile', ACtx.UsesReconcile);
    var JRx: TJSONObject:= TJSONObject.Create;
    JRx.AddPair('status' , ACtx.Reindex.Status);
    JRx.AddPair('db'     , ACtx.Reindex.Db);
    JRx.AddPair('project', ACtx.Reindex.Project);
    JRx.AddPair('ms'     , TJSONNumber.Create(ACtx.Reindex.Ms));
    JRx.AddPair('reason' , ACtx.Reindex.Reason);
    JRoot.AddPair('uses_reindex', JRx);
    { 1.27.0 -- what the .pas still uses that the conversion map does not
      cover: one row per (instance, member) reached through a converted
      instance, then one per global from a unit the reconciliation removes.
      ALWAYS present, [] when none. status mapped | cast-refused | same-name |
      unmapped | global-dangling; the editor filters on it. }
    JRoot.AddPair('pas_uses', PasUsesJson(ACtx.Report.PasUses, ACtx.RulesFile));
    { 1.20.6 (T2b) -- the classes whose members the run resolved, summed over
      the --db stores. No property tree is built; this is the whole cost. }
    JRoot.AddPair('classes_built', TJSONNumber.Create(ACtx.ClassesBuilt));

    { 1.20.6 (T2h, owner ruling R12, JSON shape R13) -- one OBJECT per rule path
      through a member that exists but is inaccessible on the .dfm surface
      (see UnreachableJson for the keys). ALWAYS present, [] when none.
      warnings[] above stays an array of STRINGS and carries each object's
      message too, so a consumer reading only warnings[] still sees them. }
    JRoot.AddPair('unreachable', UnreachableJson(DistinctUnreachable(ACtx.Unreachable)));

    { 1.22.0 (C8 N1) -- one OBJECT per inherited / inline .dfm object of a From
      type (1.26.0: and per code-only use of a converted ancestor's field):
      action retyped | code | skipped; ancestor_state unconverted | converted |
      mismatched | outside, ancestor_unit '' when not known. ALWAYS present, [] when none;
      warnings[] carries each one's 'line N: warning:' text too, and items[]
      its kind inherited-instance-skipped mirror. }
    var JInh: TJSONArray:= TJSONArray.Create;
    for var Inh: TInheritedInstance in ACtx.InheritedInsts do
    begin
      var JI: TJSONObject:= TJSONObject.Create;
      JI.AddPair('name'          , Inh.Name);
      JI.AddPair('type'          , Inh.TypeName);
      JI.AddPair('line'          , TJSONNumber.Create(Inh.Line));
      JI.AddPair('ancestor_unit' , Inh.AncestorUnit);
      JI.AddPair('ancestor_state', Inh.AncestorState);
      JI.AddPair('reason'        , Inh.Reason);
      JI.AddPair('action'        , Inh.Action); { 1.26.0 (C8 N2): retyped | code | skipped }
      JInh.AddElement(JI);
    end;
    JRoot.AddPair('inherited', JInh);

    { 1.25.0 -- one OBJECT per (descendant unit, converted instance) the
      descendant still streams (.dfm) or uses (code): reason dfm | code | both,
      line in the descendant .dfm, else its first code reference. ALWAYS
      present, [] when none; warnings[] carries each one's 'line N: warning:'
      text too, and items[] its kind descendant-not-converted mirror. }
    var JDesc: TJSONArray:= TJSONArray.Create;
    for var Desc: TDescendantUse in ACtx.Descendants do
    begin
      var JD: TJSONObject:= TJSONObject.Create;
      JD.AddPair('unit'  , Desc.UnitName);
      JD.AddPair('name'  , Desc.Name);
      JD.AddPair('type'  , Desc.TypeName);
      JD.AddPair('line'  , TJSONNumber.Create(Desc.Line));
      JD.AddPair('reason', Desc.Reason);
      JDesc.AddElement(JD);
    end;
    JRoot.AddPair('descendants', JDesc);

    { 1.23.0 (C13 N3) -- ALWAYS present, [] without --only. }
    JRoot.AddPair('only_matched'  , ArrOf(ACtx.OnlyMatched));
    JRoot.AddPair('only_unmatched', ArrOf(ACtx.OnlyUnmatched));
    { 1.25.1 -- ALWAYS present, [] without --only: one (name, parent) object per object
      --only did not name that converts because a kept parent contains it }
    var JInc: TJSONArray:= TJSONArray.Create;
    for var NO: TNestedOnly in ACtx.OnlyIncluded do
    begin
      var JN: TJSONObject:= TJSONObject.Create;
      JN.AddPair('name'  , NO.Instance.InstanceName);
      JN.AddPair('parent', NO.Parent);
      JInc.AddElement(JN);
    end;
    JRoot.AddPair('only_included', JInc);
    { owner ruling 2026-10-11 -- ALWAYS present, [] when every #convert class
      resolved without inference: one object per ambiguous #convert line, with
      the ready-to-paste qualified lines the editor offers as a one-click fix }
    var JFixes: TJSONArray:= TJSONArray.Create;
    for var QF: TQualifyFix in ACtx.QualifyFixes do
    begin
      var JF: TJSONObject:= TJSONObject.Create;
      JF.AddPair('rule_line', TJSONNumber.Create(QF.RuleLine));
      JF.AddPair('current'  , QF.Current);
      JF.AddPair('name'     , QF.Name);
      JF.AddPair('side'     , QF.Side);
      JF.AddPair('outcome'  , QF.Outcome);
      JF.AddPair('chosen'   , QF.Chosen);
      JF.AddPair('inference', QF.Inference);
      var JSug: TJSONArray:= TJSONArray.Create;
      for var QS: TQualifySuggestion in QF.Suggestions do
      begin
        var JS: TJSONObject:= TJSONObject.Create;
        JS.AddPair('replacement', QS.Replacement);
        JS.AddPair('candidate'  , QS.Candidate);
        JS.AddPair('why'        , QS.Why);
        JS.AddPair('alternative', QS.Alternative);
        JSug.AddElement(JS);
      end;
      JF.AddPair('suggestions', JSug);
      JF.AddPair('alternative', QF.Alternative);
      JFixes.AddElement(JF);
    end;
    JRoot.AddPair('qualify_fixes', JFixes);

    if Assigned(ACtx.Sink) then
    begin
      ACtx.Sink.AddElement(JRoot); { batch mode: the array owns it now }
      JRoot:= nil;
    end
    else
      WriteStdoutDocument(JRoot.ToJSON + sLineBreak); // after every stderr byte (T2i R18)
  finally
    JRoot.Free;
  end;
end; // procedure

{ 1.20.6: which part of a convert-apply book runs on a unit -- the value of
  apply/1's component_part. 'applied' (BuildApplyPlan runs the whole book)
  unless the book has UNIT rules and its component part has nothing to act
  on: 'skipped-no-dfm', 'skipped-no-convert-rules' (no #convert block) or
  'skipped-no-instances' (no .dfm instance a block matches, after --only). A
  book with no unit rules is 'applied', so its old errors stand -- unless the
  .dfm holds inherited / inline instances of a From type (AHasInherited, C8
  N1): those are skipped and reported, so a .dfm with no OTHER instance is
  'skipped-no-instances' and converts nothing rather than failing -- unless
  one of them is retyped or a converted ancestor's field is used in code
  (AHasRetype, C8 N2 / N2a, 1.26.0): then BuildApplyPlan runs, 'applied'. }
function ConvertApplyComponentPart(const ARules: TConversionRuleSet; const ADfmPath: string;
  const AOnly: TArray<string>; AHasInherited, AHasRetype: Boolean): string;
var
  R         : TConversionRule;
  HasConvert: Boolean;
begin
  Result:= 'applied';
  if not BookHasUnitRules(ARules) and not AHasInherited then Exit;
  HasConvert:= False;
  for R in ARules.Rules do
    if R.Kind = rkConvert then HasConvert:= True;
  if not TFile.Exists(ADfmPath) then
    Result:= 'skipped-no-dfm'
  else if not HasConvert then
    Result:= 'skipped-no-convert-rules'
  else if (Length(FindConvertInstances(ReadUnitText(ADfmPath), ARules, AOnly)) = 0) and
          not AHasRetype then
    Result:= 'skipped-no-instances';
end;

{ 1.20.6 (Task 2, T2b): the From/To classes of EVERY #convert block,
  index-aligned for ValidateConversionRulesPerBlock ([0] = the region before
  the first #convert, left unset). Each side comes from ATrees (ClassFor), shared
  with BuildApplyPlan, so each class's members are resolved once per run and only
  when a path asks for them.
  A block whose From or To type resolves in no --db goes to AUnresolved (its
  #convert line, the type in Message) -- an unset side would skip every check
  of the block and pass it silently (ruling R7). C13 d: that is an INDEX gap,
  not a rule-book error, so the caller refuses the unit on it (UnresolvedReason).
  A BARE type resolves in ATrees' SetScope unit (ScopedClass, the pas_uses[]
  rule, then inference -- owner ruling 2026-10-11). One settled by INFERENCE, and
  one still ambiguous, each add a TQualifyFix to AFixes (the #convert line from
  ARuleLines): 'inferred' converts with a warning, 'refused' is never guessed --
  the caller refuses the unit (AmbiguousReason). }
function BuildBlockClasses(ATrees: TConvertTreeCache; const ARules: TConversionRuleSet;
  const ARuleLines: TArray<string>; AUnresolved: TList<TRuleError>; AFixes: TList<TQualifyFix>): TArray<TBlockClasses>;
var
  R    : TConversionRule;
  Block: Integer;

  procedure RequireResolved(const AConv: TConversionRule; const AType, ASide: string);
  var
    E: TRuleError;
  begin
    if AType = '' then Exit;
    var Scoped: TScopedClass:= ATrees.ScopedClass(AType);
    var Text  : string:= if (AConv.LineNo >= 1) and (AConv.LineNo <= Length(ARuleLines)) then ARuleLines[AConv.LineNo - 1]
                         else Format('#convert %s -> %s', [AConv.FromType, AConv.ToType]);
    if (Scoped.Resolution = PAS_RES_AMBIGUOUS) or (Scoped.Inferred <> '') then
      AFixes.Add(MakeQualifyFix(Text, AConv.LineNo, AType, ASide, Scoped));
    if Scoped.Resolution <> PAS_RES_CLASS_NOT_FOUND then Exit;
    E        := Default(TRuleError);
    E.LineNo := AConv.LineNo;
    E.Message:= AType;
    AUnresolved.Add(E);
  end;

begin
  SetLength(Result, 1);
  Block:= 0;
  for R in ARules.Rules do
    if R.Kind = rkConvert then
    begin
      Inc(Block);
      SetLength(Result, Block + 1);
      RequireResolved(R, R.FromType, 'from');
      RequireResolved(R, R.ToType, 'to');
      Result[Block].FromClass:= ATrees.ClassFor(R.FromType);
      Result[Block].ToClass  := ATrees.ClassFor(R.ToType);
    end;
end;

{ 1.20.6: convert-apply's rule check. EVERY #convert block is validated against
  its own classes (ValidateConversionRulesPerBlock, classes from ATrees; T2b
  reverted ruling R5's per-unit scope, because resolving a path no longer costs
  a tree), a block whose type resolves nowhere comes back in AUnresolved (C13 d:
  the caller REFUSES the unit, see UnresolvedReason), a bare type the scope left
  ambiguous in AFixes (refused or inferred, see BuildBlockClasses), and a #link carrying a glyph expression is refused
  (UnrealisedGlyphLinks) unless AGlyphStitch, which checks its class has an N reader instead. A path through a member that exists but is
  inaccessible is not an error: it comes back in AUnreachable (T2h, owner
  ruling R12), one record per block it is unreachable in -- print through
  DistinctUnreachable, filter per block through WithoutUnreachableRules. }
function ValidateConvertBook(ATrees: TConvertTreeCache; const ARules: TConversionRuleSet; const ARuleLines: TArray<string>; AGlyphStitch: Boolean;
  out AUnreachable: TArray<TUnreachablePath>; out AUnresolved: TArray<TRuleError>;
  out AFixes: TArray<TQualifyFix>): TArray<TRuleError>;
var
  TypeErrs: TList<TRuleError>;
  Fixes   : TList<TQualifyFix>;
  Classes : TArray<TBlockClasses>;
begin
  TypeErrs:= TList<TRuleError>.Create;
  Fixes   := TList<TQualifyFix>.Create;
  try
    Classes    := BuildBlockClasses(ATrees, ARules, ARuleLines, TypeErrs, Fixes);
    AUnresolved:= TypeErrs.ToArray;
    AFixes     := Fixes.ToArray;
    Result     := ValidateConversionRulesPerBlock(ARules, Classes, AUnreachable);
    Result     := Result + (if AGlyphStitch then MissingGlyphCountReaders(ARules, Classes) else UnrealisedGlyphLinks(ARules));
  finally
    Fixes.Free;
    TypeErrs.Free;
  end;
end;

{ Owner ruling 2026-10-11: the REFUSED reason for bare #convert types the unit's
  scope and inference cannot settle -- every 'refused' fix's QualifyRefusalText
  (the line, the name, each candidate and why, what to do), joined. '' when
  AFixes holds none. }
function AmbiguousReason(const AFixes: TArray<TQualifyFix>): string;
begin
  var Parts: TArray<string>:= nil;
  for var F: TQualifyFix in AFixes do
    if F.Outcome = 'refused' then Parts:= Parts + [QualifyRefusalText(F)];
  Result:= String.Join('; ', Parts);
end;

{ The scope key of a book's #convert classes in ATrees' current unit: every
  block's From and To as ScopedClass resolves them (an inference included).
  Two units with the same key validate identically, so a batch validates the
  book once per distinct key. }
function BookScopeKey(ATrees: TConvertTreeCache; const ARules: TConversionRuleSet): string;
begin
  Result:= '';
  for var R: TConversionRule in ARules.Rules do
    if R.Kind = rkConvert then
      for var T: string in [R.FromType, R.ToType] do
      begin
        var S: TScopedClass:= ATrees.ScopedClass(T);
        Result:= Result + S.Resolution + ':' + S.QName + ':' + String.Join(',', S.Candidates) + ':' +
          S.Inferred + ':' + String.Join(',', S.Why) + ';';
      end;
end;
{ C13 d (owner ruling 2026-10-06): the REFUSED reason for #convert types that
  resolve in no --db. Each is '<Type> (line N)', the block's #convert line; the
  text says it is an index gap (library or project index), never a rule-book
  error, because the converter cannot convert a type it cannot see. }
function UnresolvedReason(const AUnresolved: TArray<TRuleError>): string;
var
  Parts: TArray<string>;
  U    : TRuleError;
begin
  Parts:= nil;
  for U in AUnresolved do Parts:= Parts + [Format('%s (line %d)', [U.Message, U.LineNo])];
  Result:= Format('%s %s in no --db -- index gap in the library or project index; reindex, or report it, before converting',
    [String.Join(', ', Parts), if Length(Parts) = 1 then 'resolves' else 'resolve']);
end;

{ 1.25.1 (the DMREADINGS defect): a plan the edit applier would refuse in
  part fails the WHOLE unit before anything is written. TTextEditApplier.Apply
  works file by file and refuses one file's edits whole on overlapping delete
  ranges -- after the .pas has already been written -- so a unit came out
  half-converted with exit 0. Checked on the dry run too, so the preview
  fails exactly as --apply would: Ok=False, exit 1, nothing written. }
{ 1.25.1: True when two byte arrays hold the same bytes. }
function SameBytes(const A, B: TBytes): Boolean;
begin
  Result:= (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ 1.25.1: the backup file BackupFiles made for APath ('orig -> backup'
  lines), or '' when none was made (--no-backup). }
function BackupOf(const AMappings: TArray<string>; const APath: string): string;
const
  MAP_ARROW = ' -> ';
begin
  for var M: string in AMappings do
  begin
    var At: Integer:= Pos(MAP_ARROW, M);
    if (At > 0) and SameText(Copy(M, 1, At - 1), APath) then Exit(Copy(M, At + Length(MAP_ARROW), MaxInt));
  end;
  Result:= '';
end;

{ 1.25.1 (all-or-nothing, write half): puts every file of a unit back the way
  it was before a write that failed part-way. AOriginals[I] is AFiles[I] as read
  just before the write; a file still holding those bytes is left alone, any
  other is rewritten from its .BCK backup when one was made, else from
  AOriginals, and then re-read and compared. Returns the files that could NOT
  be restored byte-identical ([] = rolled back). Never raises.
  TEST SEAM: DRAGLINT_TEST_FAIL_ROLLBACK=1 makes every restore fail, so the
  rollback-failed report can be exercised (run_convert_apply_atomic.ps1). }
function RollBackUnitFiles(const AFiles: TArray<string>; const AOriginals: TArray<TBytes>;
  const AMappings: TArray<string>): TArray<string>;
const
  TEST_FAIL_ROLLBACK = 'DRAGLINT_TEST_FAIL_ROLLBACK';
var
  Src: TBytes;
begin
  Result:= nil;
  for var I: Integer:= 0 to High(AFiles) do
    try
      if SameBytes(TFile.ReadAllBytes(AFiles[I]), AOriginals[I]) then Continue;
      if GetEnvironmentVariable(TEST_FAIL_ROLLBACK) = '1' then
        raise EInOutError.CreateFmt('%s=1: simulated restore failure', [TEST_FAIL_ROLLBACK]);
      var Bck: string:= BackupOf(AMappings, AFiles[I]);
      Src:= if (Bck <> '') and TFile.Exists(Bck) then TFile.ReadAllBytes(Bck) else AOriginals[I];
      TFile.WriteAllBytes(AFiles[I], Src);
      if not SameBytes(TFile.ReadAllBytes(AFiles[I]), AOriginals[I]) then Result:= Result + [AFiles[I]];
    except
      on Exception do Result:= Result + [AFiles[I]];
    end;
end;

{ 1.26.0 (C8 N2 review): the REFUSED reason when the --db that indexes AUnitPas
  had its edges derived by a resolver older than convert-apply's access-site
  scoping needs (E5 field binds, resolver 1.12.0), or carries no resolver stamp
  -- '' otherwise. On such a DB a field read is left unbound, and the rewrite
  would skip it as unverifiable: refusing is the honest answer, dry run and
  --apply alike. The text names the DB and the exact re-derive command. }
function ResolverRefusal(const AStores: TArray<ISymbolStore>; const ADbs: TArray<string>;
  const AUnitPas: string): string;
const
  MIN_RESOLVER = '1.12.0-alpha';
var
  Holders: TArray<Integer>;
begin
  Result:= '';
  { 1.26.5: the DBs that hold the unit, found the way its symbols are found
    (UnitFileIdIn) -- a DB copied with a moved tree stores the OLD paths, and
    the exact-path match this used to make found none and skipped the check
    in silence. When still none holds it, every non-library --db is checked:
    the guard is never skipped. }
  Holders:= nil;
  for var I: Integer:= 0 to High(AStores) do
    if (I <= High(ADbs)) and (UnitFileIdIn(AStores[I], AUnitPas) > 0) then Holders:= Holders + [I];
  if Length(Holders) = 0 then
    for var I: Integer:= 0 to High(AStores) do
      if (I <= High(ADbs)) and not SameText(AStores[I].GetMetaValue(SCAN_TYPE_KEY), SCAN_TYPE_LIBRARY) then Holders:= Holders + [I];
  for var I: Integer in Holders do
  begin
    var Ver: string:= ResolverVersionOfFingerprint(AStores[I].GetMetaValue(RESOLVER_FP_KEY));
    if (Ver <> '') and (CompareDottedVersions(Ver, MIN_RESOLVER) >= 0) then Continue;
    Exit(Format('%s: edges were derived by resolver %s; convert-apply needs %s or newer (bound field reads) -- re-derive first: drag-lint %s',
      [ADbs[I], if Ver <> '' then Ver else '(none)', MIN_RESOLVER, IndexRemedyFor(AStores[I], ADbs[I], {AResolveOnly=}True)]));
  end;
end;

{ 1.34.1 (CONV-ENC E2): the path half of one --raise-encoding "<path>=<level>" entry. }
function RaiseEntryPath(const AEntry: string): string;
begin
  var Eq: Integer:= LastDelimiter('=', AEntry);
  Result:= if Eq > 0 then Copy(AEntry, 1, Eq - 1) else AEntry;
end;

{ 1.34.1: the level half of one --raise-encoding entry ('' when it has no '='). }
function RaiseEntryLevel(const AEntry: string): string;
begin
  var Eq: Integer:= LastDelimiter('=', AEntry);
  Result:= if Eq > 0 then Copy(AEntry, Eq + 1, MaxInt) else '';
end;

{ 1.34.1: True when two paths name the same file (case-insensitive, expanded). }
function SameFilePath(const A, B: string): Boolean;
begin
  Result:= SameText(ExpandFileName(A), ExpandFileName(B));
end;

{ 1.34.1 (CONV-ENC E2): the exit-2 message for a bad --raise-encoding entry of this
  run, or '' when every entry is well formed: the level must be utf8-bom, and the path
  must be one of AUnits or the sibling .dfm of one. }
function RaiseEncodingError(const AEntries, AUnits: TArray<string>): string;
begin
  Result:= '';
  for var E: string in AEntries do
  begin
    if not SameText(RaiseEntryLevel(E), ENC_RAISE_LEVEL) then
      Exit(Format('raise-encoding: "%s" is not a supported level for %s (only %s)', [RaiseEntryLevel(E), RaiseEntryPath(E), ENC_RAISE_LEVEL]));
    var Known: Boolean:= False;
    for var U: string in AUnits do
      if SameFilePath(RaiseEntryPath(E), U) or SameFilePath(RaiseEntryPath(E), TPath.ChangeExtension(U, '.dfm')) then Known:= True;
    if not Known then Exit(Format('raise-encoding: %s is not a file of this run', [RaiseEntryPath(E)]));
  end;
end;

{ 1.34.1: True when --raise-encoding names APath. }
function IsRaisedFile(const AEntries: TArray<string>; const APath: string): Boolean;
begin
  for var E: string in AEntries do
    if SameFilePath(RaiseEntryPath(E), APath) then Exit(True);
  Result:= False;
end;

{ 1.34.1 (CONV-ENC E1'/E3): the encoding guard for one unit's plan, run on the dry run and
  --apply alike, nothing written. The .pas is checked before the .dfm. A file named by
  --raise-encoding is skipped (UTF-8 holds every character). A TEXT .dfm: its edits' string
  literals get Delphi #codes for what its encoding cannot hold (AEdits is rewritten); a
  character it cannot hold OUTSIDE a literal (an identifier: class, property, enum value),
  where DFM syntax has no #code, refuses like a .pas (lane H, 2026-10-26). A binary .dfm is never compared (one line appended to AWarnings). For a .pas
  whose encoding cannot hold a value, ACtx gets the refusal (RefusalKind and Enc*) and the
  reason text is returned; '' means the unit may proceed. }
function EncodingGuardReason(const AArgs: TArgs; const AUnitPas, ADfm: string;
  var AEdits: TArray<TTextEdit>; var AReport: TApplyReport; var ACtx: TApplyJsonCtx): string;
const
  MAX_CHARS = 8;
var
  OldText: string;
begin
  Result:= '';
  for var Path: string in [AUnitPas, ADfm] do
  begin
    if (Path = '') or not TFile.Exists(Path) then Continue;
    var Values: TArray<string>:= nil;
    for var E: TTextEdit in AEdits do
      if SameText(E.FilePath, Path) and (E.Text <> '') then Values:= Values + [E.Text];
    if Length(Values) = 0 then Continue;
    var IsDfm: Boolean:= SameText(ExtractFileExt(Path), '.dfm');
    var Bytes: TBytes:= TFile.ReadAllBytes(Path);
    if IsDfm and IsBinaryDfmFile(Bytes) then
    begin
      var It: TApplyItem:= Default(TApplyItem);
      It.Kind    := aikEncodingNotChecked;
      It.Field   := afWarnings;
      It.FilePath:= Path;
      It.Text    := Format('%s is a binary .dfm: its encoding was not checked', [Path]);
      AReport.Warnings:= AReport.Warnings + [It.Text];
      AReport.Items   := AReport.Items + [It];
      Continue;
    end;
    if IsRaisedFile(AArgs.RaiseEncoding, Path) then Continue;
    var Fmt: TTextFileFormat:= TTextFileFormat.Decode(Bytes, OldText);
    if Fmt.Encoding <> TEncoding.ANSI then Continue;
    var Where: string:= '';
    if IsDfm then
    begin
      Values:= nil;
      for var I: Integer:= 0 to High(AEdits) do
        if SameText(AEdits[I].FilePath, Path) then
        begin
          AEdits[I].Text:= EscapeUnfitForDfm(AEdits[I].Text, Fmt.Encoding);
          Values:= Values + [AEdits[I].Text];
        end;
      Where:= ' outside a string literal, where a #code is not allowed,';
    end;
    var Codes: TArray<Integer>:= UnfitCodePoints(Fmt, Values);
    if Length(Codes) = 0 then Continue;
    var Edited: string:= TTextEditApplier.ApplyToText(Path, OldText, AEdits);
    ACtx.EncChars:= nil;
    var Parts: TArray<string>:= nil;
    for var K: Integer:= 0 to Min(High(Codes), MAX_CHARS - 1) do
    begin
      var Mf: TEncodingMisfit;
      Mf.Code:= Codes[K];
      Mf.Text:= TCharacter.ConvertFromUtf32(Codes[K]);
      Mf.Line:= FirstLineOfCodePoint(Edited, Codes[K]);
      ACtx.EncChars:= ACtx.EncChars + [Mf];
      Parts:= Parts + [Format('U+%.4X line %d', [Mf.Code, Mf.Line])];
    end;
    ACtx.RefusalKind:= 'encoding_refused';
    ACtx.EncFile    := Path;
    ACtx.EncName    := TextFileEncodingName(Fmt);
    ACtx.EncTotal   := Length(Codes);
    Exit(Format('encoding: %d character(s)%s do not fit %s (%s): %s -- raise the file to UTF-8 with BOM, or skip the unit',
      [Length(Codes), Where, Path, ACtx.EncName, String.Join(', ', Parts)]));
  end;
end;

procedure RefuseUnapplicablePlan(var APlan: TApplyResult);
var
  Refusal: string;
begin
  if not APlan.Ok then Exit;
  Refusal:= TTextEditApplier.RefusalOf(APlan.Edits);
  if Refusal = '' then Exit;
  APlan.Ok   := False;
  APlan.Error:= Refusal + ' -- unit not changed, nothing written';
end;

{ 1.27.0 (C9): the index a convert-apply --apply refreshes for AUnitPas, and
  why not when it does not -- Status 'dry-run' with Db / Project set, 'off'
  (--no-reindex, --no-reconcile-uses) or 'skipped' with Reason. THE GUARANTEE:
  only a --db of this run that (a) indexes the unit, (b) is a PROJECT index
  (scan_type) and (c) holds exactly one project file (.dproj, else .dpr) is
  ever chosen -- the unit's own project DB. Two holders, a library holder, or
  none: skipped, nothing written. }
function ReindexPreview(const AStores: TArray<ISymbolStore>; const ADbs: TArray<string>;
  const AUnitPas: string; const AArgs: TArgs): TUsesReindex;
var
  Holders: TArray<Integer>;
  Proj   : TArray<string>;
begin
  Result:= Default(TUsesReindex);
  if AArgs.NoReindex or AArgs.NoReconcileUses then
  begin
    Result.Status:= 'off';
    Exit;
  end;
  Result.Status:= 'skipped';
  Holders:= nil;
  for var I: Integer:= 0 to High(AStores) do
    if (I <= High(ADbs)) and (UnitFileIdIn(AStores[I], AUnitPas) > 0) then Holders:= Holders + [I];
  if Length(Holders) <> 1 then
  begin
    Result.Reason:= if Length(Holders) = 0 then 'no --db indexes the unit'
                    else Format('%d --db indexes hold the unit -- refusing to guess which is its project DB', [Length(Holders)]);
    Exit;
  end;
  var St: ISymbolStore:= AStores[Holders[0]];
  Result.Db:= ADbs[Holders[0]];
  if not SameText(St.GetMetaValue(SCAN_TYPE_KEY), SCAN_TYPE_PROJECT) then
  begin
    Result.Reason:= Format('%s is not a project index (scan_type "%s")', [Result.Db, St.GetMetaValue(SCAN_TYPE_KEY)]);
    Exit;
  end;
  for var Ext: string in ['.dproj', '.dpr'] do
    if Length(Proj) = 0 then
      for var FS: TFileStamp in St.GetAllFileStamps do
        if SameText(ExtractFileExt(FS.Path), Ext) then Proj:= Proj + [FS.Path];
  if Length(Proj) <> 1 then
  begin
    Result.Reason:= Format('%s holds %d project files -- cannot name the one to re-index', [Result.Db, Length(Proj)]);
    Exit;
  end;
  Result.Project:= Proj[0];
  Result.Status := 'dry-run';
end;

type
  { 1.23.0 (C13): a unit's --apply write cannot be done (a read-only or locked
    file, or a failure mid-write); DoConvertApply turns it into that unit's
    failure, exit 2 }
  EConvertApplyWrite = class(Exception);

{ 1.42 (CONVAPPLY-INHERITED): True when two unit lists are the same paths in
  the same order (case-insensitive) }
function SameUnitOrder(const AA, AB: TArray<string>): Boolean;
begin
  Result:= Length(AA) = Length(AB);
  if not Result then Exit;
  for var I: Integer:= 0 to High(AA) do
    if not SameText(AA[I], AB[I]) then Exit(False);
end;

{ 1.42: the units' file names, comma-separated, for the text-mode order note }
function UnitNamesJoined(const AUnits: TArray<string>): string;
begin
  Result:= '';
  for var U: string in AUnits do
    Result:= Result + (if Result = '' then '' else ', ') + ExtractFileName(U);
end;

{ 1.42 (CONVAPPLY-INHERITED): the batch's apply/1 objects put back into --unit
  order. ABatch holds them in RUN order, unit I's objects at
  ASliceStart[I] .. ASliceStart[I + 1] - 1; ARunOrder is a permutation of
  ACmdOrder (a repeated path is matched to its occurrences in turn). Returns
  nil when the orders agree, else a NEW array of clones the caller owns;
  ABatch is never freed here. }
function ReorderBatchJson(const ABatch: TJSONArray; const ASliceStart: TArray<Integer>;
  const ARunOrder, ACmdOrder: TArray<string>): TJSONArray;
var
  Used: TArray<Boolean>;
  Done: Boolean;
begin
  if SameUnitOrder(ARunOrder, ACmdOrder) then Exit(nil);
  SetLength(Used, Length(ARunOrder));
  Done  := False;
  Result:= TJSONArray.Create;
  try
    for var C: string in ACmdOrder do
      for var R: Integer:= 0 to High(ARunOrder) do
        if not Used[R] and SameText(ARunOrder[R], C) then
        begin
          Used[R]:= True;
          for var J: Integer:= ASliceStart[R] to ASliceStart[R + 1] - 1 do
            Result.AddElement(ABatch.Items[J].Clone as TJSONValue);
          Break;
        end;
    Done:= True;
  finally
    if not Done then FreeAndNil(Result);
  end;
end;

function DoConvertApply(const AArgs: TArgs): Integer;
var
  UnitPas   : string            ;
  DfmPath   : string            ;
  RulesText : string            ;
  Rules     : TConversionRuleSet;
  RuleErrors: TArray<TRuleError>;
  Unresolved: TArray<TRuleError>;
  QualifyFixes: TArray<TQualifyFix>; { bare #convert types refused or inferred (owner ruling 2026-10-11) }
  Trees     : TConvertTreeCache ; { one per run: validation and BuildApplyPlan share its member caches }
  Dbs       : TArray<string>    ;
  Stores    : TArray<ISymbolStore>;
  RoOk      : Boolean           ;
  LDb       : string            ;
  PlanRes   : TApplyResult      ;
  Freshness   : TFreshnessResult;
  { 1.23.0 (C13 b2) batch state: every --unit; the book checks done once
    (RunUnit); the apply/1 collector under batch JSON (nil otherwise) }
  Units          : TArray<string>;
  BookChecked    : Boolean;
  BookKey        : string;  { BookScopeKey of the unit the book was last validated for }
  FreshChecked   : Boolean;
  BookUnreachable: TArray<TUnreachablePath>;
  BatchJson      : TJSONArray;
  BookBuilt      : Integer; { classes the book validation built (C13: per-unit classes_built) }
  CastLib        : TCastLib; { 1.33.1: parsed ONCE before any unit runs; a configuration error fails the whole batch (exit 6) }
  { --format json / --json. Both are parsed globally (ParseArgs), so this verb
    only has to READ them. Under JSON every Writeln on the success and failure
    paths is suppressed -- one stray line and the document stops parsing. }
  UseJson     : Boolean         ;
  JCtx        : TApplyJsonCtx   ;

  // The --apply write sequence. Nested so its five working variables
  // (TouchedFiles/TouchedSet/Ed/Timestamp/Mappings) live here instead of in
  // DoConvertApply's var block, which was already at the 25-local limit.
  procedure PerformApplyWrites;
  var
    TouchedFiles: TList<string>;
    TouchedSet  : TDictionary<string, Boolean>;
    Ed          : TTextEdit;
    Timestamp   : string;
    Mappings    : TArray<string>;
    Originals   : TArray<TBytes>; { 1.25.1: each touched file's bytes before the write, for the rollback }
  begin
    { 1.20.6: a unit-rules-only run that changes nothing writes nothing -- no
      backup, no recovery record, no provenance stamp on an untouched unit, so
      a book run over many units leaves the ones it does not touch
      byte-identical. The component path keeps its historical behaviour. }
    if (JCtx.ComponentPart <> 'applied') and (Length(PlanRes.Edits) = 0) then Exit;
    // 1. Collect the distinct touched file paths from the edit set.
    TouchedFiles:= TList<string>.Create;
    TouchedSet  := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal); { F7: UnitPas and an edit's path may differ in case }
    try
      for Ed in PlanRes.Edits do
        if not TouchedSet.ContainsKey(Ed.FilePath) then
        begin TouchedSet.Add(Ed.FilePath, True); TouchedFiles.Add(Ed.FilePath); end;

      { 1.34.1 (CONV-ENC E2): a file named by --raise-encoding joins the set even when no
        edit touches it, so it is pre-checked, backed up and rolled back with the rest }
      for var RE: string in AArgs.RaiseEncoding do
      begin
        var RPath: string:= RaiseEntryPath(RE);
        if (SameFilePath(RPath, UnitPas) or SameFilePath(RPath, JCtx.DfmPath)) and TFile.Exists(RPath)
          and not TouchedSet.ContainsKey(RPath) then
        begin
          TouchedSet.Add(RPath, True);
          TouchedFiles.Add(RPath);
        end;
      end;

      Timestamp:= FormatDateTime('yyyy-mm-dd hh:nn:ss', NowLocal);

      { F7 (2026-10-25): step 4 stamps the .pas even when no edit touches it (a
        .dfm-only conversion), so it joins the set HERE -- pre-checked, backed
        up, in recovery.txt and named in the stamp's "backup:" field. Under
        --no-backup there is no stamp, so it is not written and not checked. }
      if not AArgs.NoBackup and not TouchedSet.ContainsKey(UnitPas) then
      begin
        TouchedSet.Add(UnitPas, True);
        TouchedFiles.Add(UnitPas);
      end;

      // 1b. (1.23.0, C13) Every touched file must be writable BEFORE anything
      // is written: the applier writes file by file, so a read-only or locked
      // .pas found mid-way would leave the .dfm converted and the .pas not.
      // A refusal here leaves the unit byte-identical, with no .BCK and no
      // recovery record. (A failure AFTER this check -- a lock taken in
      // between, a full disk -- is ROLLED BACK since 1.25.1: see step 3.)
      for var F: string in TouchedFiles do
      begin
        if TFileAttribute.faReadOnly in TFile.GetAttributes(F) then
          raise EConvertApplyWrite.CreateFmt('cannot write %s: the file is read-only -- unit not changed, nothing written', [F]);
        try
          TFileStream.Create(F, fmOpenReadWrite or fmShareExclusive).Free;
        except
          on Ex: Exception do
            raise EConvertApplyWrite.CreateFmt('cannot write %s: %s -- unit not changed, nothing written', [F, Ex.Message]);
        end;
      end;

      // 2. Backup + recovery record BEFORE any conversion write. Writing the
      // recovery record first means a crash between here and the actual write
      // still leaves a complete recovery map alongside the untouched .BCK files.
      if not AArgs.NoBackup then
      begin
        BackupFiles(TouchedFiles.ToArray, Mappings);
        WriteRecoveryRecord(ExtractFileDir(UnitPas), Timestamp, AArgs.RulesFile, Mappings);
      end;

      { 1.25.1: the unit's files as they are now -- the .pas too, which step 4
        stamps even when it carries no edit -- so a failed write rolls back }
      if not TouchedSet.ContainsKey(UnitPas) then TouchedFiles.Add(UnitPas);
      Originals:= nil;
      for var F: string in TouchedFiles do Originals:= Originals + [TFile.ReadAllBytes(F)];
      try
        { 1.34.1 (E2): re-store each raised file as UTF-8 with a BOM first; the applier and
          the stamp below then keep that format. A binary .dfm is never rewritten. }
        for var RE: string in AArgs.RaiseEncoding do
          for var F: string in TouchedFiles do
            if SameFilePath(RaiseEntryPath(RE), F) and not IsBinaryDfmFile(TFile.ReadAllBytes(F)) then
              TFile.WriteAllBytes(F, RaiseBytesToUtf8Bom(TFile.ReadAllBytes(F)));
        // 3. Perform the conversion write. AWriteBackups=False: our backup layer
        // (step 2) already backed up every touched file -- letting the applier
        // ALSO write its own .bak would double-backup.
        TTextEditApplier.Apply(PlanRes.Edits, False);

        // 4. Stamp the converted .pas with a provenance comment (skipped along
        // with backups under --no-backup, per the brief: keep --no-backup simple).
        if not AArgs.NoBackup then
          PrependConvertComment(UnitPas, Timestamp, AArgs.RulesFile, Mappings);
      except
        on Ex: Exception do
        begin
          { 1.25.1: all-or-nothing -- a write that fails part-way is ROLLED
            BACK, every file of the unit restored byte-identical. Only a
            rollback that itself fails leaves the unit partly converted, and
            then the files it could not restore are named. }
          var NotRestored: TArray<string>:= RollBackUnitFiles(TouchedFiles.ToArray, Originals, Mappings);
          if Length(NotRestored) = 0 then
            raise EConvertApplyWrite.CreateFmt('write failed for %s: %s: %s -- rolled back, unit not changed',
              [ExtractFileName(UnitPas), Ex.ClassName, Ex.Message]);
          raise EConvertApplyWrite.CreateFmt('write failed for %s: %s: %s -- rollback FAILED for %s: the unit may be PARTLY converted; %s',
            [ExtractFileName(UnitPas), Ex.ClassName, Ex.Message, String.Join(', ', NotRestored),
             if AArgs.NoBackup then 'no backup was taken (--no-backup)'
             else 'restore it from the .BCK backups recorded in recovery.txt']);
        end;
      end;
    finally
      TouchedFiles.Free;
      TouchedSet.Free;
    end;
  end;

  // 1.20.6 (T2h, owner ruling R12): each UNREACHABLE rule path becomes one more
  // warnings[] line -- its whole 'line N: warning: ...' text -- and its items[]
  // mirror (kind rule-path-unreachable, the rules file and line), so Report
  // invariant 1 holds. The structured facts are JCtx.Unreachable.
  procedure MergeUnreachable(var AReport: TApplyReport);
  var
    It: TApplyItem;
    U : TUnreachablePath;
  begin
    for U in DistinctUnreachable(JCtx.Unreachable) do
    begin
      It         := Default(TApplyItem);
      It.Kind    := aikRulePathUnreachable;
      It.Field   := afWarnings;
      It.FilePath:= AArgs.RulesFile;
      It.Path    := U.Path;
      It.Text    := U.Message;
      It.Line    := U.LineNo;
      It.RuleLine:= U.LineNo;
      AReport.Warnings:= AReport.Warnings + [U.Message];
      AReport.Items   := AReport.Items + [It];
    end;
  end;

  // 1.37.0 (CHAIN H3): the book's single-pass warnings (a chain, a duplicate
  // From type) join warnings[] as plain text, beside the unreachable and
  // inferred ones; they never change the exit code.
  procedure MergeBookChain(var AReport: TApplyReport);
  begin
    for var W: TRuleError in BookChainWarnings(Rules) do
      AReport.Warnings:= AReport.Warnings + [Format('line %d: warning: %s', [W.LineNo, W.Message])];
  end;

  // Owner ruling 2026-10-11: each #convert class settled by INFERENCE becomes
  // one warnings[] line (QualifyInferredText) and its items[] mirror (kind
  // convert-class-inferred); the structured row is JCtx.QualifyFixes.
  procedure MergeInferred(var AReport: TApplyReport);
  begin
    for var QF: TQualifyFix in JCtx.QualifyFixes do
      if QF.Outcome = 'inferred' then
      begin
        var It: TApplyItem:= Default(TApplyItem);
        It.Kind    := aikConvertClassInferred;
        It.Field   := afWarnings;
        It.FilePath:= AArgs.RulesFile;
        It.Path    := QF.Name;
        It.Text    := QualifyInferredText(QF);
        It.Line    := QF.RuleLine;
        It.RuleLine:= QF.RuleLine;
        AReport.Warnings:= AReport.Warnings + [It.Text];
        AReport.Items   := AReport.Items + [It];
      end;
  end;

  // Owner ruling 2026-10-11: text mode, after a refusal -- every suggested
  // replacement line, ready to paste over the rules file's line.
  procedure PrintQualifyFixes;
  begin
    for var QF: TQualifyFix in JCtx.QualifyFixes do
      if QF.Outcome = 'refused' then
      begin
        Writeln(Format('  line %d of %s -- replace "%s" with one of:', [QF.RuleLine, AArgs.RulesFile, QF.Current]));
        for var QS: TQualifySuggestion in QF.Suggestions do
          Writeln(Format('    %s    { %s }', [QS.Replacement, QS.Why]));
        Writeln(Format('  or: %s', [QF.Alternative]));
      end;
  end;

  // 1.20.6 (T2f): the ONE exit for a deliberate refusal. JSON: ok=false,
  // refused=true, reason (and error) = AReason. Text: one 'REFUSED: ' line.
  // Nothing has been written when this is called. Exit(RefuseUnit(S)).
  function RefuseUnit(const AReason: string): Integer;
  begin
    JCtx.Ok     := False;
    JCtx.Error  := AReason;
    JCtx.Refused:= True; { set in text mode too: the batch summary counts it }
    JCtx.Reason := AReason;
    if UseJson then
      EmitApplyJson(JCtx)
    else
      Writeln('REFUSED: ' + AReason);
    Result:= 1;
  end;

  // 1.20.6: one line saying the component part was skipped, and why; nothing
  // when it ran. Text mode only -- JSON carries component_part.
  procedure PrintComponentPart;
  begin
    if JCtx.ComponentPart = 'skipped-no-dfm' then
      Writeln('dfm: none -- component part skipped, unit rules only')
    else if JCtx.ComponentPart = 'skipped-no-convert-rules' then
      Writeln('no #convert block in the book -- component part skipped, unit rules only')
    else if JCtx.ComponentPart = 'skipped-no-instances' then
      Writeln('no .dfm instance matches a #convert block -- component part skipped, unit rules only');
  end;

  // 1.33.1: the castlib configuration error, the same text for every unit.
  // Exit 6 = a CONFIGURATION error (1.28.0); 2 means a write failure / rollback.
  const EXIT_CASTLIB_UNUSABLE = 6;

  function CastLibFailure: string;
  begin
    Result:= Format('castlib %s: %s', [AArgs.CastLibFile, String.Join('; ', CastLib.Errors)]);
  end;

  // ERROR: <AMsg> for one unit -- text, or under batch JSON an apply/1 object
  // with ok=false -- and AExit as that unit's exit code.
  function FailUnit(const AMsg: string; AExit: Integer): Integer;
  begin
    if UseJson then
    begin
      JCtx.Ok   := False;
      JCtx.Error:= AMsg;
      EmitApplyJson(JCtx);
    end
    else
      Writeln('ERROR: ' + AMsg);
    Result:= AExit;
  end;

  // 1.23.0 (C13 b2): ONE unit's whole run -- its sibling .dfm, plan, writes and
  // report -- against the shared Rules / Stores / Trees. The book is validated
  // (and its freshness checked) the FIRST time a unit reaches that step, then
  // reused: a single --unit run keeps its old order, a batch pays for both and
  // for every class's members once. Returns the unit's exit code (0 / 1 / 2).
  function RunUnit(const AUnitPas: string): Integer;  // dl:ok too-many-exit-points@ab98, cyclomatic-complexity@4c61, method-too-long@9bf6, cognitive-complexity@fa3c -- (lint sweep b0bad3cf..HEAD): the branch count and length are that same early-outcome chain; splitting it is a convert-apply refactor, not a sweep fix. Each Exit is a distinct per-unit outcome (refusal incl. an unindexed unit (1.33.0), rule errors, freshness, an unexecutable castlib (1.27.0), plan failure, write failure, dry run) moved from DoConvertApply, which carried the same shape; one result per early outcome is the convert-apply contract
  var
    UnitStart: Integer; { Trees.ClassesBuilt when this unit started }
    ValHere  : Integer; { classes this unit's call to the book validation built (0 after the first) }
    OnlyEff  : TArray<string>; { this unit's instance allow-list: --only, or --only-type expanded against its .dfm }

    { apply/1 classes_built for THIS unit: the book's validation set plus what
      this unit's own run added -- what a single-unit run of it reports }
    function UnitClassesBuilt: Integer;
    begin
      Result:= BookBuilt + (Trees.ClassesBuilt - UnitStart) - ValHere;
    end;

    { C8 N2 / N2a: an inherited[] entry this run converts -- retyped or code }
    function HasRetype: Boolean;
    begin
      for var Inh: TInheritedInstance in JCtx.InheritedInsts do
        if (Inh.Action = INH_ACTION_RETYPED) or (Inh.Action = INH_ACTION_CODE) then Exit(True);
      Result:= False;
    end;

    { C8 N2a: a --only name that names no .dfm object but a code-only entry
      is MATCHED -- the split is redone in --only order }
    procedure MatchCodeOnlyNames;
    var
      Matched, Unmatched: TArray<string>;
    begin
      Matched  := nil;
      Unmatched:= nil;
      for var N: string in OnlyEff do
      begin
        var IsCode: Boolean:= False;
        for var Inh: TInheritedInstance in JCtx.InheritedInsts do
          if (Inh.Action = INH_ACTION_CODE) and SameText(Inh.Name, N) then IsCode:= True;
        if IsCode or MatchText(N, JCtx.OnlyMatched) then Matched:= Matched + [N]
        else Unmatched:= Unmatched + [N];
      end;
      JCtx.OnlyMatched  := Matched;
      JCtx.OnlyUnmatched:= Unmatched;
    end;

  begin
    UnitStart:= Trees.ClassesBuilt;
    ValHere  := 0;
    UnitPas:= AUnitPas;
    PlanRes:= Default(TApplyResult);
    JCtx   := Default(TApplyJsonCtx);
    JCtx.Mode:= if AArgs.Apply then 'apply' else 'dry-run';
    JCtx.RulesFile:= AArgs.RulesFile;
    JCtx.Freshness.Fresh:= True;
    JCtx.Sink   := BatchJson;
    JCtx.UnitPas:= UnitPas;
    { 1.33.1: an unusable castlib refuses EVERY unit of the batch, before anything else is looked at }
    if Length(CastLib.Errors) > 0 then Exit(FailUnit(CastLibFailure, EXIT_CASTLIB_UNUSABLE));
    if not TFile.Exists(UnitPas) then Exit(FailUnit(Format('unit not found: %s', [UnitPas]), 2));
    { a bare #convert / .dfm class name resolves in THIS unit's scope }
    Trees.SetScope(UnitPas, Rules);
    { 1.26.0: a DB whose edges predate bound field reads is refused, dry run too }
    var StaleResolver: string:= ResolverRefusal(Stores, Dbs, UnitPas);
    if StaleResolver <> '' then Exit(RefuseUnit(StaleResolver));
    { 1.33.0 (CONVERTER G2): a unit no --db indexes cannot locate one instance,
      yet its unit rules would still be written -- a half conversion. REFUSED,
      dry run and --apply, single and batch alike (as C13 d's index gap).
      UnitFileIdIn resolves a moved tree's unit the way its symbols are found. }
    var Indexed: Boolean:= False;
    for var St: ISymbolStore in Stores do
      if UnitFileIdIn(St, UnitPas) > 0 then Indexed:= True;
    if not Indexed then
      Exit(RefuseUnit(Format('%s is not covered by any supplied --db (%s) -- index its project, then re-run; nothing was planned',
        [UnitPas, String.Join(', ', Dbs)])));
    // Sibling .dfm: same base name + '.dfm', same folder as --unit.
    DfmPath:= TPath.ChangeExtension(UnitPas, '.dfm');
    JCtx.DfmPath:= DfmPath;
    { wave 148 CV (C12 N5): --only-type expands to this unit's instance names }
    OnlyEff:= AArgs.OnlySections;
    if Length(AArgs.OnlyTypes) > 0 then
      ExpandOnlyTypes(if TFile.Exists(DfmPath) then ReadUnitText(DfmPath) else '',
        Rules, AArgs.OnlyTypes, OnlyEff, JCtx.OnlyMatched, JCtx.OnlyUnmatched);
    { C13 N3: which --only names name an object of a #convert From type }
    if Length(AArgs.OnlySections) > 0 then
      SplitOnlyNames(if TFile.Exists(DfmPath) then ReadUnitText(DfmPath) else '',
        Rules, OnlyEff, JCtx.OnlyMatched, JCtx.OnlyUnmatched);
    { 1.25.1: a kept parent's nested From-type children convert with it
      (the --only unmatched line is printed below, once C8 N2a's code-only
      names have been matched) }
    if (Length(OnlyEff) > 0) and TFile.Exists(DfmPath) then
      JCtx.OnlyIncluded:= NestedOnlyInstances(ReadUnitText(DfmPath), Rules, OnlyEff);
    if not UseJson then
      for var NO: TNestedOnly in JCtx.OnlyIncluded do
        Writeln(Format('--only: %s converts too -- nested in %s', [NO.Instance.InstanceName, NO.Parent]));
    { 1.20.6: a missing .dfm is fatal only to a book with NO unit rules -- its
      #convert blocks have nothing to locate. A book with #unuse / #use /
      #useswap still has the unit's uses clauses to change, so it runs them and
      reports the component part as skipped (component_part skipped-no-dfm). }
    if not TFile.Exists(DfmPath) and not BookHasUnitRules(Rules) and not BookHasIdentifierMigrates(Rules) then
    begin
      var NothingWhy: string:= BookNothingToDoReason(Rules, UnitPas);
      if NothingWhy <> '' then Exit(FailUnit(NothingWhy, 1));
      Exit(FailUnit(Format('sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)', [DfmPath]), 1));
    end;

    { 1.22.0 (C8 N1, N3; replaces 1.20.6's ruling-R6 refusal). Inherited /
      inline .dfm objects of a From type are declared by an ANCESTOR, so they
      are skipped -- each reported with its declaring ancestor (apply/1
      inherited[], a 'line N: warning:' line) -- while the unit's own
      instances, code and unit rules convert. R26 still counts them as left
      unconverted, so a #unuse that would break them refuses the unit. }
    JCtx.InheritedInsts:= FindInheritedInstances(Trees, UnitPas, DfmPath, Rules, OnlyEff);
    { 1.26.0 (C8 N2a): fields a converted ancestor declares that this unit's
      code uses with no .dfm block -- inherited[] action 'code'. A --only name
      that names one counts as matched. }
    JCtx.InheritedInsts:= JCtx.InheritedInsts +
      FindInheritedCodeUses(Trees, UnitPas, Rules, OnlyEff, JCtx.InheritedInsts);
    if (Length(JCtx.OnlyUnmatched) > 0) and (Length(AArgs.OnlyTypes) = 0) then MatchCodeOnlyNames;
    if (Length(JCtx.OnlyUnmatched) > 0) and (Length(AArgs.OnlyTypes) > 0) and not UseJson then
      Writeln('--only-type: no #convert instance of type ' + String.Join(', ', JCtx.OnlyUnmatched) + ' (ignored)')
    else if (Length(JCtx.OnlyUnmatched) > 0) and not UseJson then
      Writeln('--only: no #convert instance named ' + String.Join(', ', JCtx.OnlyUnmatched) + ' (ignored)');
    { EVERY block is validated against its OWN From/To classes (1.20.6, Task 2
      and T2b) -- driven from the rules file's own #convert headers rather than
      --from/--to (convert-apply has neither). It used to take the first block's
      pair for the whole book, so every link of blocks 2..N failed. A valid
      G-expression passes validation, but nothing realises it yet (CV-2):
      refuse through the same path rather than carry the source image whole. }
    { the book's classes resolve in each unit's scope: a unit whose #convert
      classes resolve differently from the last one validated is validated
      again (BookScopeKey); a batch of like units still validates once }
    var ScopeKey: string:= BookScopeKey(Trees, Rules);
    if not BookChecked or (ScopeKey <> BookKey) then
    begin
      BookChecked:= True;
      BookKey    := ScopeKey;
      ValHere    := Trees.ClassesBuilt;
      RuleErrors := ValidateConvertBook(Trees, Rules, RulesText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]), AArgs.GlyphStitch,
        BookUnreachable, Unresolved, QualifyFixes);
      ValHere    := Trees.ClassesBuilt - ValHere;
      BookBuilt  := BookBuilt + ValHere;
    end;
    JCtx.Unreachable := BookUnreachable;
    JCtx.QualifyFixes:= QualifyFixes;
    JCtx.ClassesBuilt:= UnitClassesBuilt;
    { T2h: an UNREACHABLE path warns and its rule is skipped (BuildApplyPlan
      below gets the book without those lines); it never fails the unit. On
      every JSON exit from here on, warnings[] carries the messages too. }
    MergeUnreachable(JCtx.Report);
    MergeInferred(JCtx.Report);
    MergeBookChain(JCtx.Report);
    { C13 d: a type no --db resolves is an index gap -- the unit is REFUSED,
      dry run and --apply alike, before any rule error is reported }
    if Length(Unresolved) > 0 then Exit(RefuseUnit(UnresolvedReason(Unresolved)));
    { a bare #convert type this unit's scope cannot settle is REFUSED, never
      validated against a guessed class }
    var Ambiguity: string:= AmbiguousReason(QualifyFixes);
    if Ambiguity <> '' then
    begin
      var Code: Integer:= RefuseUnit(Ambiguity);
      if not UseJson then PrintQualifyFixes;
      Exit(Code);
    end;
    if Length(RuleErrors) > 0 then
    begin
      { A JSON consumer gets a parseable ok=false document naming every rule
        error, rather than prose on stdout that its parser would choke on. }
      if UseJson then
      begin
        JCtx.Ok        := False;
        JCtx.Error     := 'conversion rules failed validation';
        JCtx.RuleErrors:= RuleErrors;
        EmitApplyJson(JCtx);
        Exit(1);
      end;
      Writeln('ERROR: conversion rules failed validation:');
      for var RE: TRuleError in RuleErrors do Writeln(Format('  line %d: %s', [RE.LineNo, RE.Message]));
      for var UW: string in JCtx.Report.Warnings do Writeln('  ' + UW);
      Exit(1);
    end;
    // Freshness guard (Task 4): before trusting the index-derived class
    // members, verify the F and T types of every block are indexed and current. Covers two
    // failure modes -- "stale" (indexed but the source file changed on disk
    // since) and "not indexed at all" (ResolveClassQName-equivalent lookup
    // fails, which would otherwise silently hand BuildPropTree an empty tree).
    // dry-run: WARN and continue (so a user can still preview a plan while
    // reindexing). --apply: REFUSE outright -- writing a conversion built from
    // a stale/empty property tree could silently drop or mis-map properties.
    if not FreshChecked then
    begin
      FreshChecked:= True;
      Freshness   := CheckFreshness(Stores, Rules);
    end;
    { B-18 (1.31.7): the unit's OWN .pas and .dfm too -- per unit, never cached.
      A stale target warns on a dry run (merged into freshness) and REFUSES
      --apply below; a stale From/To type keeps its own error path. }
    var UnitFresh: TFreshnessResult:= CheckUnitFreshness(Stores, UnitPas, DfmPath);
    JCtx.Freshness:= Freshness;
    if not UnitFresh.Fresh then
    begin
      JCtx.Freshness.Fresh  := False;
      JCtx.Freshness.Reasons:= JCtx.Freshness.Reasons + UnitFresh.Reasons;
    end;
    if not Freshness.Fresh then
    begin
      if AArgs.Apply then
      begin
        { --apply refuses. Under JSON the reasons ride in freshness.reasons, so
          the consumer sees WHY without parsing prose. }
        if UseJson then
        begin
          JCtx.Ok   := False;
          JCtx.Error:= 'freshness guard failed -- refusing to --apply';
          EmitApplyJson(JCtx);
          Exit(1);
        end;
        Writeln('ERROR: freshness guard failed -- refusing to --apply:');
        for var S: string in Freshness.Reasons do Writeln('  ' + S);
        Exit(1);
      end
      else if not UseJson then
      begin
        { dry-run only warns. Under JSON the warning is NOT printed -- it is
          already carried structurally by freshness.fresh=false + reasons. }
        Writeln('WARNING: freshness guard failed (dry-run only, would refuse on --apply):');
        for var S: string in Freshness.Reasons do Writeln('  ' + S);
      end;
    end;
    if not UnitFresh.Fresh then
    begin
      if AArgs.Apply then Exit(RefuseUnit(UnitFresh.Reasons[0]));
      if not UseJson then
      begin
        Writeln('WARNING: freshness guard failed (dry-run only, would refuse on --apply):');
        for var S: string in UnitFresh.Reasons do Writeln('  ' + S);
      end;
    end;

    { 1.20.6: which parts of the book run on this unit. A book WITH unit rules
      runs them alone when its component part has nothing to act on -- no .dfm,
      no #convert block, or no .dfm instance a block matches; everywhere else
      BuildApplyPlan runs the whole book (its unit rules folded in). A book with
      no unit rules takes the old path unchanged, errors included. }
    JCtx.ComponentPart:= ConvertApplyComponentPart(Rules, DfmPath, OnlyEff,
      Length(JCtx.InheritedInsts) > 0, HasRetype);
    if JCtx.ComponentPart = 'skipped-no-dfm' then JCtx.DfmPath:= '';
    { 1.27.0 (C15): a castlib the engine cannot execute (an unknown value
      transform) fails the unit -- a cast silently not performed is the worse outcome.
      1.28.0 (owner 2026-10-11): its own exit code 6, a CONFIGURATION error; 2 means a
      write failure / rollback on this verb and must not be read as one. }
    { the castlib was parsed and validated once, before the unit loop (see CastLibFailure) }
    { 1.42 (MIG-TYPE): identifier #migrate rules act on the unit's CODE, so a
      unit with no .dfm, or none a #convert block matches, still runs
      BuildApplyPlan when it has a #migrate site; component_part keeps saying
      the component part was skipped. A missing .dfm gets here with no unit
      rules only because the book has identifier #migrate lines: with no site
      it keeps the old refusal. }
    var Book: TApplyBook:= TApplyBook.Create(Rules, JCtx.Unreachable);
    Book.Reconcile:= not AArgs.NoReconcileUses; { C9, default on }
    var IdSites: Boolean:= (JCtx.ComponentPart <> 'applied') or not TFile.Exists(DfmPath);
    IdSites:= IdSites and UnitHasIdentifierMigrateSites(Trees, UnitPas, Book);
    if (JCtx.ComponentPart = 'applied') and not TFile.Exists(DfmPath) then
    begin
      if not IdSites then
      begin
        var NothingWhy: string:= BookNothingToDoReason(Rules, UnitPas);
        if NothingWhy <> '' then Exit(FailUnit(NothingWhy, 1));
        Exit(FailUnit(Format('sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)', [DfmPath]), 1));
      end;
      JCtx.ComponentPart:= 'skipped-no-dfm';
      JCtx.DfmPath      := '';
    end;
    PlanRes:= if (JCtx.ComponentPart = 'applied') or IdSites then
                BuildApplyPlan(Trees, UnitPas, JCtx.DfmPath, Book,
                  OnlyEff, CastLib, not AArgs.NoWarnUnlinked, JCtx.InheritedInsts)
              else
                BuildUnitRulesOnlyPlan(Trees, UnitPas, JCtx.DfmPath, Rules, OnlyEff, not AArgs.NoReconcileUses);
    JCtx.UsesReconcile:= if AArgs.NoReconcileUses then 'off'
                         else if PlanRes.Report.UsesReconcile <> '' then PlanRes.Report.UsesReconcile
                         else 'on';
    JCtx.Reindex:= ReindexPreview(Stores, Dbs, UnitPas, AArgs);
    RefuseUnapplicablePlan(PlanRes); { 1.25.1: all-or-nothing across .pas and .dfm }
    JCtx.ClassesBuilt:= UnitClassesBuilt;
    if PlanRes.Refused then Exit(RefuseUnit(PlanRes.Error));
    if not PlanRes.Ok then
    begin
      if UseJson then
      begin
        JCtx.Ok   := False;
        JCtx.Error:= PlanRes.Error;
        EmitApplyJson(JCtx);
        Exit(1);
      end;
      Writeln('ERROR: ' + PlanRes.Error);
      Exit(1);
    end;

    { 1.34.1 (CONV-ENC E1'/E3): a value the target .pas cannot hold refuses the unit, dry
      run and --apply alike, nothing written; a text .dfm gets #codes instead }
    var EncReason: string:= EncodingGuardReason(AArgs, UnitPas, JCtx.DfmPath, PlanRes.Edits, PlanRes.Report, JCtx);
    if EncReason <> '' then Exit(RefuseUnit(EncReason));

    JCtx.Ok       := True;
    MergeUnreachable(PlanRes.Report); { text mode prints them in its Warnings block }
    MergeInferred(PlanRes.Report);    { likewise }
    MergeBookChain(PlanRes.Report);   { likewise }
    AppendInheritedReport(JCtx.InheritedInsts, DfmPath, PlanRes.Report); { likewise }
    { 1.25.0: descendants that still stream / use an instance converted here.
      A warning, never a refusal; only the instances the plan converted count. }
    if JCtx.ComponentPart = 'applied' then
    begin
      JCtx.Descendants:= FindDescendantUses(Trees, UnitPas, DfmPath, Rules,
        ConvertedInstancesOf(PlanRes.Report, DfmPath, Rules, OnlyEff));
      AppendDescendantReport(JCtx.Descendants, DfmPath, PlanRes.Report);
    end;
    JCtx.Report   := PlanRes.Report;
    JCtx.EditCount:= Length(PlanRes.Edits);

    if not AArgs.Apply then
    begin
      // DRY-RUN: writes nothing.
      if UseJson then
      begin
        { RenderDryRun and the summary are BOTH suppressed -- the edit plan is
          reported as edits_count, and the summary as the six arrays + items. }
        EmitApplyJson(JCtx);
        Exit(0);
      end;
      Writeln(TTextEditApplier.RenderDryRun(PlanRes.Edits));
      Writeln('');
      PrintComponentPart;
      PrintApplyReport(PlanRes.Report, Length(PlanRes.Edits), 'planned');
      Exit(0);
    end;

    { a write failure fails THIS unit (exit 2) instead of the run: a batch
      goes on with the next unit (see PerformApplyWrites for what is on disk) }
    try
      PerformApplyWrites;
    except
      on Ex: Exception do Exit(FailUnit(Ex.Message, 2));
    end;
    { C9: re-index after convert -- the unit's OWN project DB only }
    if (JCtx.ComponentPart <> 'applied') and (Length(PlanRes.Edits) = 0) and (JCtx.Reindex.Status = 'dry-run') then
    begin
      JCtx.Reindex.Status:= 'skipped';
      JCtx.Reindex.Reason:= 'nothing was written';
    end
    else if JCtx.Reindex.Status = 'dry-run' then
      RefreshProjectIndex(JCtx.Reindex);

    if UseJson then
      EmitApplyJson(JCtx)
    else
    begin
      PrintComponentPart;
      PrintApplyReport(PlanRes.Report, Length(PlanRes.Edits), 'applied');
    end;
    Result:= 0;
  end;

  // 1.23.0 (C13 b2): the apply-batch/1 wrapper -- one apply/1 object per unit,
  // in --unit order, plus the run's totals. exit_code is the worst unit's.
  procedure EmitBatchJson(AExit, AOk, ARefused: Integer);
  var
    JRoot: TJSONObject;
  begin
    JRoot:= TJSONObject.Create;
    try
      JRoot.AddPair('schema'       , 'apply-batch/1');
      JRoot.AddPair('mode'         , if AArgs.Apply then 'apply' else 'dry-run');
      JRoot.AddPair('rules_file'   , AArgs.RulesFile);
      JRoot.AddPair('units_count'  , TJSONNumber.Create(BatchJson.Count));
      JRoot.AddPair('ok'           , TJSONBool.Create(AOk = BatchJson.Count));
      JRoot.AddPair('exit_code'    , TJSONNumber.Create(AExit));
      JRoot.AddPair('ok_count'     , TJSONNumber.Create(AOk));
      JRoot.AddPair('refused_count', TJSONNumber.Create(ARefused));
      JRoot.AddPair('failed_count' , TJSONNumber.Create(BatchJson.Count - AOk - ARefused));
      JRoot.AddPair('classes_built', TJSONNumber.Create(Trees.ClassesBuilt));
      JRoot.AddPair('units'        , BatchJson);
      BatchJson:= nil; { JRoot owns it now }
      WriteStdoutDocument(JRoot.ToJSON + sLineBreak);
    finally
      JRoot.Free;
    end;
  end;

  // 1.33.0 (CONVERTER G3): exit_code on the apply/1 object(s) this unit
  // appended from index AFrom on (normally one) -- additive, last key.
  procedure StampUnitExit(AFrom, ACode: Integer);
  begin
    if not UseJson then Exit;
    for var K: Integer:= AFrom to BatchJson.Count - 1 do
      if BatchJson.Items[K] is TJSONObject then
        TJSONObject(BatchJson.Items[K]).AddPair('exit_code', TJSONNumber.Create(ACode));
  end;

  // 1.33.0 (CONVERTER G1): --progress -- one JSON line on STDERR per finished
  // unit, flushed now (stdout untouched; off by default -- see MakeProgressWriter).
  procedure ReportUnitProgress(AIndex, ACode: Integer);
  begin
    if not AArgs.UnitProgress then Exit;
    Writeln(ErrOutput, Format('{"progress":{"verb":"convert-apply","unit_done":%d,"units":%d,"unit":%s,' +
      '"ok":%s,"refused":%s,"exit_code":%d}}',
      [AIndex + 1, Length(Units), ProgressJsonStr(Units[AIndex]),
       BoolToStr(ACode = 0, True).ToLower, BoolToStr(JCtx.Refused, True).ToLower, ACode]));
    Flush(ErrOutput);
  end;

begin
  if not ExplicitDbsExist(AArgs, 'convert-apply') then Exit(2);
  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');
  { every --unit, in order (C13 b2); GhostUnit alone for a caller that set
    only that field }
  Units:= AArgs.ConvertUnits;
  if (Length(Units) = 0) and (AArgs.GhostUnit <> '') then Units:= [AArgs.GhostUnit];

  if (Length(Units) = 0) or (AArgs.RulesFile = '') then
  begin
    Writeln('Usage: drag-lint convert-apply --unit <F.pas> [--unit <G.pas> ...] --rules <file> --db PATH [--db ...] [--only Name1,Name2,... | --only-type Type1,Type2,...] [--castlib <file>] [--glyph-stitch] [--apply] [--no-backup] [--raise-encoding "<path>=utf8-bom" ...] [--no-warn-unlinked] [--no-reconcile-uses] [--no-reindex] [--progress] [--format json]');
    Exit(2);
  end;
  if (Length(AArgs.OnlyTypes) > 0) and (Length(AArgs.OnlySections) > 0) then
  begin
    Writeln('ERROR: --only-type and --only are mutually exclusive');
    Exit(2);
  end;
  { one unit keeps its old first check; a batch checks each unit in RunUnit }
  if (Length(Units) = 1) and not TFile.Exists(Units[0]) then
  begin
    Writeln(Format('ERROR: unit not found: %s', [Units[0]]));
    Exit(2);
  end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin
    Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile]));
    Exit(2);
  end;
  { 1.34.1 (CONV-ENC E2): a bad --raise-encoding entry is a usage error }
  var RaiseErr: string:= RaiseEncodingError(AArgs.RaiseEncoding, Units);
  if RaiseErr <> '' then
  begin
    Writeln('ERROR: ' + RaiseErr);
    Exit(2);
  end;

  try
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin
      Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message]));
      Exit(2);
    end;
  end;
  Rules:= ParseConversionRules(RulesText);

  { one unit keeps its old order: a missing .dfm (book without unit rules)
    fails before any --db is opened }
  if (Length(Units) = 1) and not TFile.Exists(TPath.ChangeExtension(Units[0], '.dfm')) and not BookHasUnitRules(Rules) and
     not BookHasIdentifierMigrates(Rules) and (BookNothingToDoReason(Rules, Units[0]) = '') then
  begin
    Writeln(Format('ERROR: sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)',
      [TPath.ChangeExtension(Units[0], '.dfm')]));
    Exit(1);
  end;

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then
  begin
    Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.');
    Exit(2);
  end;

  // Open EVERY readable --db up front (not just the first) -- Bug 2: the
  // From type, To type, and the form's own instances may each live in a
  // DIFFERENT --db, so rule validation, the freshness guard and BuildApplyPlan
  // all need cross-db type resolution (first-db-that-resolves-wins), while
  // unit/instance-scoped lookups use whichever store actually has --unit/the
  // .dfm indexed. This runs BEFORE the rules are validated, so a stale
  // explicit --db exits 2 (StaleDbRefusesRun) rather than being skipped while
  // the trees are built -- pinned by run_explicit_db_strict.ps1's T5 row.
  var StoresList: TList<ISymbolStore>:= TList<ISymbolStore>.Create;
  var OpenedDbs: TArray<string>:= nil;
  try
    for LDb in Dbs do
    begin
      if not TFile.Exists(LDb) then Continue;
      var St: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
      if not RoOk then
      begin
        if StaleDbRefusesRun(AArgs, 'convert-apply', LDb) then Exit(2);
        Continue; { manifest-resolved: stale DB reported, scan the rest }
      end;
      StoresList.Add(St);
      OpenedDbs:= OpenedDbs + [LDb];
    end;
    Stores:= StoresList.ToArray;
    Dbs   := OpenedDbs; { 1.26.0: index-aligned with Stores (ResolverRefusal names the DB) }
  finally
    StoresList.Free;
  end;
  if Length(Stores) = 0 then
  begin
    Writeln('ERROR: no readable drag-lint index among --db path(s)');
    Exit(2);
  end;

  { 1.43 ENUMMAP: named explicitly, so an unusable one stops the run: mapping against
    today's enum instead would leave the old members silently unrenamed. Read-only,
    and kept out of Stores: it answers only for a #migrate enum's OLD members. }
  var OldPlatformStores: TArray<ISymbolStore>:= nil;
  for var OldDb: string in AArgs.OldPlatformDbs do
  begin
    var OldOk: Boolean:= False;
    var OldSt: ISymbolStore:= nil;
    if TFile.Exists(OldDb) then OldSt:= OpenReadOnlyStore(OldDb, OldOk);
    if not OldOk then
    begin
      Writeln(Format('ERROR: --old-platform-db %s is not a readable drag-lint index; nothing was changed', [OldDb]));
      Exit(2);
    end;
    OldPlatformStores:= OldPlatformStores + [OldSt];
  end;

  CastLib     := ParseCastLib(AArgs.CastLibFile);
  BookBuilt   := 0;
  BookChecked := False;
  FreshChecked:= False;
  BatchJson   := nil;
  { JSON collects every unit's apply/1 object (1.33.0: a single --unit too, so
    its exit_code can be stamped); one --unit still writes a bare apply/1 }
  if UseJson then BatchJson:= TJSONArray.Create;
  Trees:= TConvertTreeCache.Create(Stores);
  try
    Trees.DbPaths:= Dbs; { C9: names the db of a uses_unresolved candidate }
    Trees.OldPlatformStores:= OldPlatformStores;
    if Length(Units) = 1 then
    begin
      { 1.33.0 G3: the apply/1 document carries exit_code, known only once the
        unit is done -- so under JSON it is collected, stamped, then written }
      Result:= RunUnit(Units[0]);
      StampUnitExit(0, Result);
      if UseJson and (BatchJson.Count > 0) then WriteStdoutDocument(BatchJson.Items[0].ToJSON + sLineBreak);
      ReportUnitProgress(0, Result);
      Exit;
    end;
    { 1.23.0 (C13 b2): batch. A unit's refusal or failure never stops the
      others; the exit code is the worst unit's (6 > 2 > 1 > 0; 6 = an unusable castlib, 1.28.0). }
    Result:= 0;
    var NOk     : Integer:= 0;
    var NRefused: Integer:= 0;
    { 1.42 (CONVAPPLY-INHERITED, owner ruling Q5): run ancestor-first, so a
      descendant's inherited objects see their ancestor already converted;
      the report keeps --unit order (ReorderBatchJson) }
    var CmdOrder: TArray<string>:= Units;
    Units:= OrderUnitsAncestorFirst(Trees, Units, Rules);
    var SliceStart: TArray<Integer>;
    SetLength(SliceStart, Length(Units) + 1);
    if not UseJson and not SameUnitOrder(CmdOrder, Units) then
      Writeln('convert-apply: units run ancestor-first: ' + UnitNamesJoined(Units));
    for var I: Integer:= 0 to High(Units) do
    begin
      if not UseJson then Writeln(Format('=== unit %d of %d: %s ===', [I + 1, Length(Units), Units[I]]));
      var Code: Integer;
      var Before: Integer:= if UseJson then BatchJson.Count else 0;
      SliceStart[I]:= Before;
      try
        Code:= RunUnit(Units[I]);
      except
        { anything else a unit raises fails that unit, never the batch }
        on Ex: Exception do
          Code:= FailUnit(Format('%s: %s: %s -- unit not finished', [ExtractFileName(Units[I]), Ex.ClassName, Ex.Message]), 2);
      end;
      StampUnitExit(Before, Code);
      ReportUnitProgress(I, Code);
      if Code > Result then Result:= Code;
      if Code = 0 then Inc(NOk)
      else if JCtx.Refused then Inc(NRefused);
      if not UseJson then Writeln('');
    end;
    if UseJson then
    begin
      SliceStart[Length(Units)]:= BatchJson.Count;
      var Reordered: TJSONArray:= ReorderBatchJson(BatchJson, SliceStart, Units, CmdOrder);
      if Reordered <> nil then
      begin
        BatchJson.Free;  // dl:ok unprotected-object-free@c94d -- REVIEWED 2026-11-03: BatchJson is owned by DoConvertApply's outer try-finally (BatchJson.Free); this swaps in the reordered copy, which that finally then frees
        BatchJson:= Reordered;
      end;
      EmitBatchJson(Result, NOk, NRefused);
    end
    else
      Writeln(Format('batch: %d unit(s) -- %d ok, %d refused, %d failed; classes_built %d; exit %d',
        [Length(Units), NOk, NRefused, Length(Units) - NOk - NRefused, Trees.ClassesBuilt, Result]));
  finally
    BatchJson.Free;
    Trees.Free;
  end;
end; // function

// drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]
// Walk every .dfm/.fmx under the roots, extract and decode every streamed graphic,
// pair it with its count property, write instances.tsv / classes.tsv / skipped.tsv /
// gallery.html / images\ into --output. --db only QUALIFIES (class_unit, declared count
// default, runtime_refs); without one those columns are empty, never guessed.
// Exit 0 on a completed walk (0 graphics is an answer); 2 on bad args or a missing root.
function DoGlyphVacuum(const AArgs: TArgs): Integer;
var
  Opts   : TGlyphVacuumOptions;
  Summary: TGlyphVacuumSummary;
  Err    : string;
  Dbs    : TArray<string>;
  LDb    : string;
  RoOk   : Boolean;
  Store  : ISymbolStore;
begin
  if (Length(AArgs.Roots) = 0) or (AArgs.Output = '') then
  begin
    Writeln('Usage: drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]');
    Exit(2);
  end;
  if not ExplicitDbsExist(AArgs, 'glyph-vacuum') then Exit(2);
  Opts:= Default(TGlyphVacuumOptions);
  Opts.Roots := AArgs.Roots;
  Opts.OutDir:= AArgs.Output;
  Opts.Append:= AArgs.AppendOut;
  { EXPLICIT --db ONLY. Every other consumer auto-selects from the manifest; this
    verb must not, because its qualification columns are documented as EMPTY
    without a --db, and a column filled from a DB nobody named is a guess. }
  Dbs:= AArgs.DbPaths;
  for LDb in Dbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    Store:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'glyph-vacuum', LDb) then Exit(2);
      Continue;
    end;
    Opts.Stores:= Opts.Stores + [Store];
  end;
  if not RunGlyphVacuum(Opts, Summary, Err) then
  begin
    Writeln('ERROR: glyph-vacuum: ' + Err);
    Exit(2);
  end;
  Writeln(Format('glyph-vacuum: dfm=%d graphics=%d distinct=%d skipped=%d -> %s',
    [Summary.DfmFiles, Summary.Graphics, Summary.DistinctPayloads, Summary.Skipped, AArgs.Output]));
  Result:= 0;
end;

end.
