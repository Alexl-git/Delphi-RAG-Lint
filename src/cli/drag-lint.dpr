program drag_lint;

{$APPTYPE CONSOLE}

{ ---------------------------------------------------------------------------
  MAIN-THREAD STACK RESERVE -- DO NOT DELETE AS CLUTTER.

  WHY IT EXISTS
    DRagLint.Parser.Delphi13.Walk (Delphi13.pas:1566) recurses ONCE PER
    EXPRESSION NODE, and its frame measures 1,776 bytes. Delphi's default
    1 MB reserve therefore tops out around 1,048,576 / 1,776 = 590 nested
    nodes; measured, real parses die between 550 and 600 because the RTL
    frames below Walk and the guard page take the rest.

    A left-nested binary expression nests one node per operand, so an
    N-operand chain costs N frames. C:\Projects\PDFlibPas\PDFlibStampAnnot.pas
    holds an 810-operand string-concatenation chain -- one file out of 1,909
    in the ORM3-Micronite2027 corpus -- and parsing it raised EStackOverflow.
    On the `index --project` path (CLI.pas:1646) that is not caught, so the
    process died 0xC0000005 at file 692 of 709 and the resolve phase never
    ran (call_edges 0). Pre-existing since the parser was written; it only
    became visible when project-closure scanning first pulled PDFlibPas in.

  THE ARITHMETIC
    64 MB = 67,108,864 / 1,776 = ~37,700 nested nodes, ~46x the 810 observed
    and ~64x the old ceiling. 16 MB would give ~9,400 and cover today's file,
    but machine-generated Pascal (string tables, generated SQL builders,
    DFM-to-code emitters) reaches chains far past that, and the extra 48 MB
    is free: a PE stack reserve is VIRTUAL ADDRESS SPACE, committed a page at
    a time on demand, so an unused reserve costs no RAM and no working set.

  WHY THE DIRECTIVE IS THE RIGHT KNOB HERE
    (Written brace-less on purpose: a CLOSING BRACE anywhere in this block
    would end the comment there -- Delphi brace comments do not nest -- and
    the first draft wrote the directive in full, terminated itself early, and
    failed to compile with "Declaration expected but identifier 'writes'".)
    $MAXSTACKSIZE writes the PE header's SizeOfStackReserve, which governs
    the MAIN THREAD (and any thread created with dwStackSize = 0). That is
    sufficient BECAUSE ALL PARSING IS ON THE MAIN THREAD: DoIndex ->
    IndexFile -> Parse -> WalkUnit -> Walk is a straight call chain, the
    indexer creates no threads, and `--jobs > 1` parallelises by spawning
    CHILD PROCESSES (CLI.pas:1863), each of which gets this same header.
    The only thread this program creates is the parent watchdog at
    CLI.pas:1019, which never parses. If parsing is ever moved onto a
    TThread, THIS DIRECTIVE STOPS PROTECTING IT -- that thread's stack comes
    from its own creation parameter and must be sized at the call site.

  THIS IS A MITIGATION, NOT THE FIX
    The real fix is to make Walk iterative -- an explicit work stack instead
    of native recursion -- which removes the ceiling entirely rather than
    moving it. That is tracked as its own task. Until then, raising the
    reserve is what keeps a single pathological file from killing a 709-file
    index. Related and also separate: the `--project` loop at CLI.pas:1646
    has no per-file try/except, unlike the folder walk at Indexer.pas:693,
    so any parse exception there is fatal to the whole run.
  --------------------------------------------------------------------------- }
{$MAXSTACKSIZE 67108864}

uses
  System.SysUtils,
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  TreeSitter.Query in '..\..\third_party\delphi-tree-sitter\TreeSitter.Query.pas',
  DRagLint.Core.Model in '..\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Wiring in '..\core\DRagLint.Wiring.pas',
  DRagLint.Core.Indexer in '..\core\DRagLint.Core.Indexer.pas',
  DRagLint.Storage.Schema in '..\storage\DRagLint.Storage.Schema.pas',
  DRagLint.Storage.SQLite in '..\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Storage.FileMembership in '..\storage\DRagLint.Storage.FileMembership.pas',
  DRagLint.Parser.Delphi13 in '..\parser\DRagLint.Parser.Delphi13.pas',
  DRagLint.Parser.SpringDI in '..\parser\DRagLint.Parser.SpringDI.pas',
  DRagLint.Parser.DFM in '..\parser\DRagLint.Parser.DFM.pas',
  DRagLint.Parser.Sql in '..\parser\DRagLint.Parser.Sql.pas',
  DRagLint.Sql.FbSnapshot in '..\sql\DRagLint.Sql.FbSnapshot.pas',
  DRagLint.Sql.OrmLinker in '..\sql\DRagLint.Sql.OrmLinker.pas',
  DRagLint.Sql.Guarded in '..\sql\DRagLint.Sql.Guarded.pas',
  DRagLint.Core.EngineHold in '..\core\DRagLint.Core.EngineHold.pas',
  DRagLint.Parser.DocComments in '..\parser\DRagLint.Parser.DocComments.pas',
  DRagLint.Query.Fuzzy in '..\query\DRagLint.Query.Fuzzy.pas',
  DRagLint.Query.Callers in '..\query\DRagLint.Query.Callers.pas',
  DRagLint.Query.HoverModel in '..\query\DRagLint.Query.HoverModel.pas',
  DRagLint.Symbol.Describe in '..\query\DRagLint.Symbol.Describe.pas',
  DRagLint.Lint.Config in '..\lint\DRagLint.Lint.Config.pas',
  DRagLint.Lint.RuleCatalog in '..\lint\DRagLint.Lint.RuleCatalog.pas',
  DRagLint.Lint.Baseline in '..\lint\DRagLint.Lint.Baseline.pas',
  DRagLint.Lint.QueryRules in '..\lint\DRagLint.Lint.QueryRules.pas',
  DRagLint.Lint.Linter in '..\lint\DRagLint.Lint.Linter.pas',
  DRagLint.Lint.ProjectChecks in '..\lint\DRagLint.Lint.ProjectChecks.pas',
  DRagLint.Lint.ProjectChecks.Parse in '..\lint\DRagLint.Lint.ProjectChecks.Parse.pas',
  DRagLint.Lint.ProjectRules in '..\lint\DRagLint.Lint.ProjectRules.pas',
  DRagLint.Lint.ClassMetrics in '..\lint\DRagLint.Lint.ClassMetrics.pas',
  DRagLint.Project.Resolver in '..\project\DRagLint.Project.Resolver.pas',
  DRagLint.Project.OwnRoots in '..\project\DRagLint.Project.OwnRoots.pas',
  DRagLint.FormsMap in '..\forms\DRagLint.FormsMap.pas',
  DRagLint.MCP.Server in '..\mcp\DRagLint.MCP.Server.pas',
  DRagLint.LSP.Server in '..\lsp\DRagLint.LSP.Server.pas',
  DRagLint.Core.LiveDocs in '..\core\DRagLint.Core.LiveDocs.pas',
  DRagLint.LSP.Completion in '..\lsp\DRagLint.LSP.Completion.pas',
  DRagLint.LSP.Proxy in '..\lsp\DRagLint.LSP.Proxy.pas',
  DRagLint.Core.JobObject in '..\core\DRagLint.Core.JobObject.pas',
  DRagLint.Hover.Renderer in 'DRagLint.Hover.Renderer.pas',
  DRagLint.Hover.Contrast in '..\core\DRagLint.Hover.Contrast.pas',
  DRagLint.Hover.Returns in 'DRagLint.Hover.Returns.pas',
  DRagLint.Context.Bundler in '..\context\DRagLint.Context.Bundler.pas',
  DRagLint.Resolver.TypeAt in '..\resolver\DRagLint.Resolver.TypeAt.pas',
  DRagLint.Refactor.Rename in '..\refactor\DRagLint.Refactor.Rename.pas',
  DRagLint.Refactor.TextEdit in '..\refactor\DRagLint.Refactor.TextEdit.pas',
  DRagLint.Refactor.DocStub in '..\refactor\DRagLint.Refactor.DocStub.pas',
  DRagLint.Refactor.DeadCode in '..\refactor\DRagLint.Refactor.DeadCode.pas',
  DRagLint.Refactor.TestStub in '..\refactor\DRagLint.Refactor.TestStub.pas',
  DRagLint.Format.Yadf in '..\refactor\DRagLint.Format.Yadf.pas',
  DRagLint.Diagnostics.CompileCheck in '..\diagnostics\DRagLint.Diagnostics.CompileCheck.pas',
  DRagLint.Diagnostics.AstChecks in '..\diagnostics\DRagLint.Diagnostics.AstChecks.pas',
  DRagLint.Diagnostics.NamingChecks in '..\diagnostics\DRagLint.Diagnostics.NamingChecks.pas',
  DRagLint.Diagnostics.DeadCodeChecks in '..\diagnostics\DRagLint.Diagnostics.DeadCodeChecks.pas',
  DRagLint.Diagnostics.CloneChecks in '..\diagnostics\DRagLint.Diagnostics.CloneChecks.pas',
  DRagLint.Diagnostics.ParseCache in '..\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Analysis.Cfg in '..\analysis\DRagLint.Analysis.Cfg.pas',
  DRagLint.Analysis.DataFlow in '..\analysis\DRagLint.Analysis.DataFlow.pas',
  DRagLint.Analysis.Flow.Lattices in '..\analysis\DRagLint.Analysis.Flow.Lattices.pas',
  DRagLint.Diagnostics.FlowChecks in '..\diagnostics\DRagLint.Diagnostics.FlowChecks.pas',
  DRagLint.Output.Sarif in '..\output\DRagLint.Output.Sarif.pas',
  DRagLint.Output.ExitCode in '..\output\DRagLint.Output.ExitCode.pas',
  DRagLint.Workspace.Config in '..\workspace\DRagLint.Workspace.Config.pas',
  DRagLint.Index.Manifest in '..\index\DRagLint.Index.Manifest.pas',
  DRagLint.Index.ManifestWrite in '..\index\DRagLint.Index.ManifestWrite.pas',
  DRagLint.Index.Glob in '..\index\DRagLint.Index.Glob.pas',
  DRagLint.Index.IgnoreFiles in '..\index\DRagLint.Index.IgnoreFiles.pas',
  DRagLint.Index.Closure in '..\index\DRagLint.Index.Closure.pas',
  DRagLint.Index.Reconcile in '..\index\DRagLint.Index.Reconcile.pas',
  DRagLint.Index.Plan in '..\index\DRagLint.Index.Plan.pas',
  DRagLint.Index.DbSelect in '..\index\DRagLint.Index.DbSelect.pas',
  DRagLint.Index.Drift in '..\index\DRagLint.Index.Drift.pas',
  DRagLint.Index.Coverage in '..\index\DRagLint.Index.Coverage.pas',
  DRagLint.Report.Deps in '..\report\DRagLint.Report.Deps.pas',
  DRagLint.Report.RCallTree in '..\report\DRagLint.Report.RCallTree.pas',
  DRagLint.Analysis.Liveness in '..\analysis\DRagLint.Analysis.Liveness.pas',
  DRagLint.Core.Encoding in '..\core\DRagLint.Core.Encoding.pas',
  DRagLint.Doc.Batch in '..\doc\DRagLint.Doc.Batch.pas',
  DRagLint.Doc.Document in '..\doc\DRagLint.Doc.Document.pas',
  DRagLint.Doc.Facts in '..\doc\DRagLint.Doc.Facts.pas',
  DRagLint.Doc.GitSince in '..\doc\DRagLint.Doc.GitSince.pas',
  DRagLint.Doc.Harvest in '..\doc\DRagLint.Doc.Harvest.pas',
  DRagLint.Doc.Regions in '..\doc\DRagLint.Doc.Regions.pas',
  DRagLint.Doc.SharedFacts in '..\doc\DRagLint.Doc.SharedFacts.pas',
  DRagLint.Doc.Strip in '..\doc\DRagLint.Doc.Strip.pas',
  DRagLint.Doc.SymbolFacts in '..\doc\DRagLint.Doc.SymbolFacts.pas',
  DRagLint.Doc.Wiki in '..\doc\DRagLint.Doc.Wiki.pas',
  DRagLint.Index.CallResolver in '..\index\DRagLint.Index.CallResolver.pas',
  DRagLint.Lint.DocRules in '..\lint\DRagLint.Lint.DocRules.pas',
  DRagLint.Preprocess.Expr in '..\preprocess\DRagLint.Preprocess.Expr.pas',
  DRagLint.Preprocess.Lexer in '..\preprocess\DRagLint.Preprocess.Lexer.pas',
  DRagLint.Preprocess.Profile in '..\preprocess\DRagLint.Preprocess.Profile.pas',
  DRagLint.Preprocess.Tolerance in '..\preprocess\DRagLint.Preprocess.Tolerance.pas',
  DRagLint.Preprocess.Types in '..\preprocess\DRagLint.Preprocess.Types.pas',
  DRagLint.Preprocess in '..\preprocess\DRagLint.Preprocess.pas',
  DRagLint.Refactor.EnumHelper in '..\refactor\DRagLint.Refactor.EnumHelper.pas',
  DRagLint.Refactor.ExtractMethod in '..\refactor\DRagLint.Refactor.ExtractMethod.pas',
  DRagLint.Refactor.NamingFix in '..\refactor\DRagLint.Refactor.NamingFix.pas',
  DRagLint.Convert.Apply in '..\report\DRagLint.Convert.Apply.pas',
  DRagLint.Convert.Backup in '..\report\DRagLint.Convert.Backup.pas',
  DRagLint.Convert.DfmReemit in '..\report\DRagLint.Convert.DfmReemit.pas',
  DRagLint.Convert.PropTree in '..\report\DRagLint.Convert.PropTree.pas',
  DRagLint.Convert.Rules in '..\report\DRagLint.Convert.Rules.pas',
  DRagLint.Lint.SharedUnit in '..\lint\DRagLint.Lint.SharedUnit.pas',
  DRagLint.Lint.ReviewMarker in '..\lint\DRagLint.Lint.ReviewMarker.pas',
  DRagLint.CLI in 'DRagLint.CLI.pas';

begin
  ExitCode := DRagLint.CLI.Run;
end.
