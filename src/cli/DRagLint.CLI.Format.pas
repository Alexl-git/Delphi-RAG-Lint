unit DRagLint.CLI.Format;

// ---------------------------------------------------------------------------
// The purge-locals and format (YADF) verbs. Moved verbatim out of DRagLint.CLI (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>v14 (D5 T12): drag-lint purge-locals --db PATH [--json] -- the SIZE
/// ESCAPE HATCH. Deletes every skLocalVar/skParam symbol (kind IN 'local_var',
/// 'param'), then VACUUMs to reclaim the freed pages, and reports how many rows
/// were removed plus the DB file size before/after. Once ResolveCallTargets has
/// populated call_edges, these numerous per-local / per-param symbols have done
/// their job (they let the resolver type call-site receivers), so purging them
/// slims the index. The resolved CALL GRAPH is unchanged: call_edges references
/// call TARGETS (methods) and receiver TYPES (classes), never a local/param, so
/// no edge can cascade-delete. Requires an explicit --db (it MUTATES a specific
/// index -- never purges across an auto-selected DB set). NOT wired into any
/// auto-index path: a reindex re-emits locals/params and rebuilds call_edges, so
/// this is a manual, point-in-time slim only, correctly re-inflated on the next
/// full index. Idempotent: a second run removes 0 rows and still exits 0.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath is the index to purge; AsJson picks JSON output.</param>
/// <returns>0 on success (including the idempotent 0-removed second run); 2 on
/// usage error / missing --db / missing db file.</returns>
function DoPurgeLocals(const AArgs: TArgs): Integer;

/// <summary>drag-lint format FILE [--yadf-path PATH] [--dry-run|--diff]: formats one unit with YADF; --dry-run / --diff never write the file.</summary>
/// <param name="AArgs">The file, --yadf-path, --dry-run, --diff.</param>
/// <returns>0 on success; 2 on a usage error or a missing file; 3 / 4 passed on from the formatter.</returns>
function DoFormat(const AArgs: TArgs): Integer;

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

function DoPurgeLocals(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore;
  Removed   : Int64        ;
  SizeBefore: Int64        ;
  SizeAfter : Int64        ;
begin
  { DbPaths, not DbPath: Run defaults DbPath from --project, and a DESTRUCTIVE
    verb must not act on a database the user did not name. }
  if Length(AArgs.DbPaths) = 0 then
  begin
    Writeln('ERROR: purge-locals needs an explicit --db <db>');
    Exit(2);
  end;
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;

  { 1.40 IDX-LOCK: purge MUTATES the index -- take <db>.indexing.lock like `index` does. }
  if ConfigDbRedirectsWrite('purge-locals', AArgs, '') then Exit(2);
  if not AcquireIndexLock(AArgs.DbPath, {AQuiet=}False, 'purge-locals') then Exit(2);
  SizeBefore:= TFile.GetSize(AArgs.DbPath);
  { Read-WRITE open (purge MUTATES) -- same path as index/rename/safe-delete, NOT
    the query_only OpenReadOnlyStore used by read verbs. Migrate ensures the
    schema (incl. the symbols.kind values) is current before we touch it. }
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
  Removed:= Store.PurgeLocals;
  Store:= nil; { close the connection so the VACUUM's file resize is flushed before we stat }
  SizeAfter:= TFile.GetSize(AArgs.DbPath);

  if AArgs.AsJson then
  begin
    var JO: TJSONObject:= TJSONObject.Create;
    try
      JO.AddPair('db'         , AArgs.DbPath                      );
      JO.AddPair('removed'    , TJSONNumber.Create(Removed   )    );
      JO.AddPair('size_before', TJSONNumber.Create(SizeBefore)    );
      JO.AddPair('size_after' , TJSONNumber.Create(SizeAfter )    );
      Writeln(JO.Format(2));
    finally JO.Free; end;
  end
  else
    Writeln(Format('purge-locals: removed %d local/param symbol(s); db size %d -> %d bytes',
      [Removed, SizeBefore, SizeAfter]));
  Result:= 0;
end; // function

// v0.27: drag-lint format <file> [--yadf-path PATH]
// Runs YADF formatter on the given file (YADF rewrites in place).
// Exit 2 on usage error, 1 on formatter failure, 0 on success.
{ `drag-lint format <file> [--yadf-path PATH] [--dry-run | --diff]`

  THE EXIT CODES ARE DISTINCT ON PURPOSE. This verb REWRITES THE USER'S SOURCE,
  so "it did not format" is not an actionable answer -- a script (or a person)
  has to be able to tell "no formatter" from "the formatter is too old" from
  "the formatter corrupted the file and I put it back":

    0  formatted (or dry-run/diff completed), or YADF DECLINED the file (its
       exit 3: content guard refused, file unchanged -- B-36; not a failure)
    2  usage: no target, or the target does not exist
    3  no usable YADF resolved            (TFormatResult -3)
    4  resolved YADF is BELOW the floor   (TFormatResult -4) -- nothing written
    5  post-format verification FAILED    (TFormatResult -5) -- file RESTORED
    1  any other formatter failure

  `--dry-run` USED TO BE A SILENT LIE. The flag parsed (it is global) and this
  routine ignored it, so a user who typed it specifically to avoid touching the
  file had the file rewritten anyway. Measured 2026-09-16 and pinned by
  tests\autotest\run_format_verb_guard.ps1 (A3b). }
function DoFormat(const AArgs: TArgs): Integer;
var
  Res   : TFormatResult;
  Target: string       ;
  Mode  : TFormatMode  ;
begin
  Target:= AArgs.Target;
  if Target = '' then Target:= AArgs.QName; // fallback: reuse qname slot
  if Target = '' then begin Writeln('Usage: drag-lint format <file> [--yadf-path PATH] [--dry-run|--diff]'); Exit (2 ); end;
  if not FileExists(Target) then begin Writeln(Format('File not found: %s', [Target])); Exit(2); end;

  if AArgs.ShowDiff then Mode:= fmDiff
  else if AArgs.DryRun then Mode:= fmDryRun
  else Mode:= fmApply;

  Res:= TYadfFormatter.Format(Target, AArgs.YadfPath, Mode);

  if not Res.Success then
  begin
    Writeln(Format('YADF format failed (exit %d):'#13#10'%s', [Res.ExitCode, Res.StdoutText]));
    case Res.ExitCode of
      -3: Exit(3);
      -4: Exit(4);
      -5: Exit(5);
    else
      Exit(1);
    end;
  end;

  if Res.Declined then
  begin
    if Trim(Res.StdoutText) <> '' then Writeln(Res.StdoutText);
    Writeln(Format('Declined: %s  (YADF''s content guard left it unchanged; not a failure)', [Target]));
    Exit(0);
  end;

  case Mode of
    fmDryRun: Writeln(Res.StdoutText);
    fmDiff  : Writeln(Res.DiffText  );
  else
    begin
      if Trim(Res.StdoutText) <> '' then Writeln(Res.StdoutText);
      Writeln(Format('Formatted: %s  (via %s%s)',
        [Target, Res.ResolvedPath,
         (if Res.YadfVersion <> '' then ' ' + Res.YadfVersion else '')]));
    end;
  end;
  Result:= 0;
end; // function

end.
