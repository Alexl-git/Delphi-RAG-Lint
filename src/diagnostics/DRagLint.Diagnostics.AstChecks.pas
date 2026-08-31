unit DRagLint.Diagnostics.AstChecks;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Refactor.TextEdit
  , System.StrUtils { ContainsText -- visibility test in CheckWithHiding }
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze (DRagLint.Doc.SymbolFacts.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Doc.SymbolFacts, DRagLint.LSP.Completion, DRagLint.MCP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAstChecker = class
    strict private
      /// <returns><!-- drag-lint:auto -->TDictionary&lt;string, Boolean&gt; -- Observed:
      /// D.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ParamStr, Trim</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function LoadBuiltinAllowlist          : TDictionary<string, Boolean>;
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
      /// GKeywordSet.ContainsKey(System.SysUtils.LowerCase(AName)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared (DRagLint.Diagnostics.AstChecks.pas)</para>
      /// <para>Calls: DRagLint.Diagnostics.AstChecks.BuildKeywordSet</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.BuildKeywordSet"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function IsKeyword(const AName: string): Boolean                     ;
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// All.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Check(const AStore: ISymbolStore; const AFile: string)          : TArray<TLintFinding>;
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.Check (DRagLint.Diagnostics.AstChecks.pas)</para>
      /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Diagnostics.AstChecks.MaskCommentsAndStrings, DRagLint.Diagnostics.AstChecks.TAstChecker.IsKeyword, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.MaskCommentsAndStrings"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.IsKeyword"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUndeclared(const AStore: ISymbolStore; const AFile: string): TArray<TLintFinding>;
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed: nil;
      /// [Finding].</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.Check (DRagLint.Diagnostics.AstChecks.pas)</para>
      /// <para>Calls: CharInSet, Copy, Default, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, SameText</para>
      /// <para>Complexity: 33 (cyclomatic, outer body), 172 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUnbalancedBeginEnd( const AFile: string)                   : TArray<TLintFinding>;
      { Tree-sitter ERROR / MISSING nodes -> located 'syntax-error' findings.
      Live syntax diagnostics (Error-Insight-style) without a compiler. }
      /// <summary><!-- drag-lint:auto -->Tree-sitter ERROR / MISSING nodes -&gt; located
      /// 'syntax-error' findings. Live syntax diagnostics (Error-Insight-style) without a
      /// compiler.</summary>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed: nil;
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.Check (DRagLint.Diagnostics.AstChecks.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
      /// <para>Calls: AnsiUpperCase, Copy, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.BuildConditionalRanges, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, IsInConditionalRegion, StraddlesConditionalRegion</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.BuildConditionalRanges"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckSyntaxErrors(const AFile: string): TArray<TLintFinding>;
      { v0.46: unused local variables (the compiler's H2164). For each defProc,
      a local declared in its var section that occurs exactly once in the whole
      routine subtree (i.e. only its declaration) is flagged. Counting over the
      subtree is intentionally false-positive-SAFE: a name used anywhere (incl.
      a nested routine = closure, or via with/property) raises the count and
      suppresses the finding. No compiler / no DB needed. }
      /// <summary><!-- drag-lint:auto -->v0.46: unused local variables (the compiler's
      /// H2164). For each defProc, a local declared in its var section that occurs
      /// exactly once in the whole routine subtree (i.e. only its declaration) is
      /// flagged. Counting over the subtree is intentionally false-positive-SAFE: a name
      /// used anywhere (incl. a nested routine = closure, or via with/property) raises
      /// the count and suppresses the finding. No compiler / no DB needed.</summary>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed: nil;
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestUnusedLocals (DRagLint.CLI.pas)</para>
      /// <para>Calls: CheckProc, CountIdents, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, LowerCase, NodeStr</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUnusedLocals(const AFile: string): TArray<TLintFinding>;
      /// <summary>Builds the text edits that REMOVE the unused locals reported by
      /// CheckUnusedLocals for AFile. Driven off the same declVars/declVar AST nodes
      /// the check itself walks, so the edit always matches the real declaration
      /// shape rather than guessing from line text.</summary>
      /// <param name="AFile">The .pas/.inc file the edits apply to; findings for any
      /// other path are ignored.</param>
      /// <param name="AFindings">Findings to act on; non-'unused-local' rules are skipped.</param>
      /// <param name="AFixedCount">Receives the number of findings that produced an edit.</param>
      /// <returns>Edits for AFile, or nil when nothing can be safely removed.</returns>
      /// <remarks>
      /// Three shapes, and the distinction is load-bearing: when EVERY name in a
      /// declVar is unused the whole declaration is deleted; when only SOME are, the name
      /// list is spliced so the surviving names keep their declaration -- deleting the line
      /// would silently remove variables that are still used. A declVars left with no
      /// surviving declVar also loses its now-orphaned 'var' keyword line, because a bare
      /// 'var' before 'begin' does not compile. If that orphaned keyword cannot be located,
      /// the section's deletions are DISCARDED rather than emitted, since a partial edit
      /// there produces code that will not build. Multi-line name lists are skipped.
      /// Edits never overlap: at most one edit per declVar, one per declVars.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildAutofixEdits (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.PosKey, DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, HandleProc, Integer, IntToStr, NodeKey, NStr, SameText, Trim</para>
      /// <para>Returns: nil; Edits.ToArray</para>
      /// <para>Mutates: AFixedCount (out)</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.PosKey"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildUnusedLocalFixEdits(const AFile: string;
        const AFindings: TArray<TLintFinding>; out AFixedCount: Integer): TArray<TTextEdit>;
      /// <summary>Flags a 'raise' statement located inside a 'finally' block.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>One finding per raise found within a finally body (capped at 100); nil/empty if none.</returns>
      /// <remarks>
      /// A raise in a finally masks the exception currently propagating out of the protected
      /// section. The walk does not descend into nested try blocks, so each try's finally is attributed
      /// to that try. Pure tree-sitter AST; no DB or compiler required. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, SearchForRaise</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckRaiseInFinally(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags the first statement that follows an unconditional Exit / raise / Break /
      /// Continue / Halt within the same statement list (unreachable code).</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>One 'code-after-exit' finding per statement list with dead code (capped); empty if none.</returns>
      /// <remarks>
      /// Only direct siblings are considered, so a terminator nested inside an if/case does not
      /// mark code after the if/case as dead. Pure tree-sitter AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CheckList, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, IsTerminator, LowerCase, NodeStr</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckCodeAfterExit(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a constructor or destructor whose body never calls 'inherited'.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>Findings tagged 'missing-inherited-ctor' / 'missing-inherited-dtor'; empty if none.</returns>
      /// <remarks>
      /// A missing inherited Create skips ancestor initialization; a missing inherited Destroy
      /// skips ancestor cleanup (resource leak). Class constructors/destructors and asm-bodied routines
      /// are skipped. The search ignores 'inherited' inside nested routines. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CheckProc, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMissingInherited.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, HasInherited, Integer</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMissingInherited.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckMissingInherited(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags Exit / Break / Continue / Halt inside a finally block.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>One 'control-flow-in-finally' finding per offending statement (capped); empty if none.</returns>
      /// <remarks>
      /// An Exit/Break/Continue/Halt in a finally silently discards any exception currently
      /// propagating out of the protected section. Walks each finally body, not descending into nested
      /// try blocks. Companion to CheckRaiseInFinally. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, IsCtrlFlow, LowerCase, NodeStr, SearchFinally</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckControlFlowInFinally(const AFile: string): TArray<TLintFinding>;
      /// <summary>Routine size/complexity metrics: too many parameters, too many locals,
      /// method too long, and excessive nesting depth.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <param name="AMaxParams">Parameter count above which 'too-many-parameters' fires.</param>
      /// <param name="AMaxLocals">Local-variable count above which 'too-many-locals' fires.</param>
      /// <param name="AMaxLines">Body line span above which 'method-too-long' fires.</param>
      /// <param name="AMaxNesting">Control-structure nesting depth above which 'deep-nesting' fires.</param>
      /// <returns>Findings tagged with the four metric rule ids; empty if all within limits.</returns>
      /// <remarks>
      /// One AST walk per routine. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CheckProc, CountNames, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Emit, Format, Integer, MaxNest, NodeStr</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckRoutineMetrics(const AFile: string; AMaxParams, AMaxLocals, AMaxLines, AMaxNesting: Integer): TArray<TLintFinding>;
      /// <summary>Type-aware checks using a lightweight per-file name-to-type map:
      /// floating-point equality comparison, and FreeAndNil on an interface-typed variable.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>Findings 'float-equality-comparison' / 'freeandnil-on-interface'; empty if none.</returns>
      /// <remarks>The type map is flat (declared types of vars/params/fields, no scope resolution),
      /// so rare same-name shadowing may mis-type; the rules are heuristic. Interface detection uses the
      /// Delphi I-prefix convention. Pure AST; no DB. Never raises.</remarks>
      // v11 (M1): AStore (+ AFileId, the file's id in that store) make the
      // operand-type decisions exact via ResolveTypeCategory; when AStore is nil
      // (the bare `lint <file>` path) it falls back to the name heuristics.
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore = nil</param>
      /// <param name="AFileId"><!-- drag-lint:auto type -->Int64 = 0</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed: nil;
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
      /// <para>Calls: CatOf, CharInSet, Copy, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CheckExpr, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CollectDecls, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CollectEnums, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CollectGuards, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.VisitProcsDualHandle, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (+24 more)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CheckExpr"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CollectDecls"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CollectEnums"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CollectGuards"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.VisitProcsDualHandle"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckTypeAware(const AFile: string; const AStore: ISymbolStore = nil; AFileId: Int64 = 0): TArray<TLintFinding>;
      /// <summary>FireDAC misuse: 'Open' on a data-modifying statement, or 'ExecSQL' on a SELECT.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'firedac-open-execsql-mismatch' findings; empty if none.</returns>
      /// <remarks>
      /// Per routine, correlates a literal 'X.SQL.Text := ''...''' (classified SELECT vs
      /// INSERT/UPDATE/DELETE/MERGE) with a later 'X.Open' / 'X.ExecSQL' on the same variable, in
      /// program order. Only fires when the SQL is a recognizable literal, so false positives are rare.
      /// Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Copy, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFireDacSqlMismatch.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, LowerCase, MatchCall, MatchSqlTextAssign, NodeStr, SameText, TrimLeft, UpperCase, WalkBody</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFireDacSqlMismatch.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckFireDacSqlMismatch(const AFile: string): TArray<TLintFinding>;
      /// <summary>A locally-created object that is freed without try-finally protection (leaks if
      /// code between creation and Free raises).</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'unprotected-object-free' findings; empty if none.</returns>
      /// <remarks>
      /// Per routine, in program order: records 'X := ...Create...' constructions, then flags a
      /// later 'X.Free' / 'FreeAndNil(X)' on the same variable that is NOT lexically inside a finally
      /// block. Requiring same-routine construction filters destructor field-frees. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CollectLocals, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnprotectedFree.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, IsConstruction, IsFree, LowerCase, NodeStr, SameText, UpperCase, WalkBody</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnprotectedFree.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUnprotectedFree(const AFile: string): TArray<TLintFinding>;
      /// <summary>Detects interface reference cycles across the given files: class A holds an
      /// interface implemented by class B, and B holds an interface implemented by A (mutual).</summary>
      /// <param name="AFiles">Source files to parse (project-wide); typically the indexed file set.</param>
      /// <returns>'interface-reference-cycle' findings (one per mutual pair); empty if none.</returns>
      /// <remarks>
      /// Under ARC these mutual strong interface references leak; fix by marking one side
      /// [weak] or [unsafe]. Interface detection uses the I-prefix convention; only mutual (2-cycle)
      /// pairs are reported. Pure AST across all files; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)</para>
      /// <para>Calls: AddImpl, CharInSet, CollectFields, Copy, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles.ExtractFile, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles.HoldsImplementedBy, ExtractFileExt, Format, HandleClass (+8 more)</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 210 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles.ExtractFile"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles.HoldsImplementedBy"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckInterfaceCycles(const AFiles: TArray<string>): TArray<TLintFinding>;
      /// <summary>Use of an object after 'X.Free' (dangling reference) within the same block.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'use-after-free' findings; empty if none.</returns>
      /// <remarks>
      /// Block-scoped (siblings only, to keep false positives low): after a raw 'X.Free' it
      /// flags a later 'X.&lt;member&gt;' access (incl. a second X.Free) until X is reassigned. FreeAndNil(X)
      /// clears tracking (it nils X). Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CheckBlock, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUseAfterFree.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, FindUse, Integer, IsFreeAndNil, IsRawFree, LowerCase, NodeStr, Primary, SameText</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUseAfterFree.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUseAfterFree(const AFile: string): TArray<TLintFinding>;
      /// <summary>UI (VCL/FMX) access inside a TThread.Execute that is not on the main thread.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'ui-access-in-thread' findings; empty if none.</returns>
      /// <remarks>
      /// Heuristic, tuned for low false positives: only inside a method named 'Execute' whose
      /// class (declared in the same file) has a base type whose name contains 'Thread', and only for
      /// strong UI members (assignment to '.Caption'; calls to '.SetFocus'/'.Repaint'/'.BringToFront').
      /// Access inside a nested anonymous method (a likely Synchronize/Queue body) is skipped. Pure AST;
      /// no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread.CollectClasses, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Flag, Format, Integer, LowerCase, NodeStr, Pos, SameText, WalkExec</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread.CollectClasses"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUiThread(const AFile: string): TArray<TLintFinding>;
      /// <summary>Warns when a form unit declares a unit-level global variable whose type
      /// matches a class declared in the same file. Such globals leak the first form instance
      /// if the form is ever shown more than once.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per offending variable declaration.</returns>
      /// <remarks>
      /// Skipped entirely when no sibling .dfm file exists beside AFile. Pure AST;
      /// no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: ChangeFileExt, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars.CheckGlobalVarDecls, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars.CollectClassNames, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, LowerCase, Move, NodeStr</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars.CheckGlobalVarDecls"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars.CollectClassNames"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckGlobalFormVars(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags every unit-level writable 'var' declaration (Fowler "Global Data"
      /// refactoring smell): shared mutable state is hard to reason about and test.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per declared identifier name in a unit-scope declVars block.</returns>
      /// <remarks>
      /// Unit-scope only: recursion exits on defProc/defFunc so local vars and
      /// parameters are excluded. 'const' sections are a distinct declConst node, so named
      /// and typed constants are naturally excluded (no special-casing needed). Runs on every
      /// .pas file (no .dfm gate, no type filter) -- broader than CheckGlobalFormVars, which
      /// this method does not modify. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMutableGlobalVars.CheckGlobalVarDecls, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, Move, NodeStr</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMutableGlobalVars.CheckGlobalVarDecls"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      /// <summary>Flags a bare identifier inside a `with` body that binds to a
      /// member of the with-target while an OUTER scope declares the same name --
      /// the silent misbinding the compiler never warns about.</summary>
      /// <param name="AFile">Source file to parse; must exist.</param>
      /// <param name="AStore">Project symbol store; nil yields no findings (the
      /// rule cannot prove either side without it).</param>
      /// <param name="ALibStore">Platform library store, or nil. Without it the
      /// VCL half of an ancestry walk is invisible, so the rule reports FEWER
      /// findings -- never wrong ones.</param>
      /// <param name="AFileId">The file's id in AStore; 0 is tolerated.</param>
      /// <returns>'with-hides-outer-symbol' findings, one per identifier per
      /// with-body, at the first use site; empty when nothing is provable.</returns>
      /// <remarks>Never raises. Silence is the answer to every doubt -- see the
      /// implementation's own header for the four things that buy silence.</remarks>
      class function CheckWithHiding(const AFile: string; const AStore: ISymbolStore;
        const ALibStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
      class function CheckMutableGlobalVars(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a value-returning FUNCTION that also mutates observable state
      /// (a Command-Query Separation violation, Fowler): a query that is also a command.
      /// The conservative mutation predicate is a write to a class FIELD -- either an
      /// explicit 'Self.X := ...' or a bare 'FXxx := ...' whose target is an F-prefixed
      /// identifier NOT declared as a local/parameter of that function (the project's
      /// FMyField convention). Only functions with a return type are considered, which
      /// naturally excludes constructors, destructors and setter procedures.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per offending function, at its header.</returns>
      /// <remarks>
      /// OFF by default (inherently noisy -- getters that lazily cache, fluent
      /// mutators). Fires at most once per function. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: AddIdentsUnder, BodyMutatesField, CharInSet, CollectLocalsAndParams, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSeparateQueryFromModifier.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, IsFunction, LooksLikeFieldName (+7 more)</para>
      /// <para>Returns: Hit; nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSeparateQueryFromModifier.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckSeparateQueryFromModifier(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags WinExec/ShellExecute/CreateProcess called with a non-literal
      /// command/executable argument -- a runtime-built command path is a command-injection
      /// risk (CWE-78).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per launcher call whose command argument is not a string literal.</returns>
      /// <remarks>
      /// Severity error. Per-callee command-arg index: WinExec=0, ShellExecute=2,
      /// CreateProcess=1. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: ArgIsFixedSchemeUri, CharInSet, CmdArgIndex, CollectAssignments, Copy, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckShellExec.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer (+6 more)</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckShellExec.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckShellExec(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a file API (AssignFile/FileOpen/CreateFile/TFile.Open) whose path
      /// argument is a string concatenation -- a user-controlled segment can escape the
      /// intended directory (path traversal, CWE-22).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per call whose path argument is a binary '+' expression.</returns>
      /// <remarks>
      /// Severity warning. Path-arg index: AssignFile=1, FileOpen/CreateFile=0,
      /// TFile.Open=0. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckPathTraversal.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Integer, NodeStr, PathArgIndex, SameText</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckPathTraversal.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckPathTraversal(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a for/while/repeat loop whose body's first statement is an
      /// unconditional Exit, Break, or raise -- the loop can never reach a second
      /// iteration.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per loop whose first body statement is Exit/Break/raise.</returns>
      /// <remarks>
      /// Severity warning. Only the direct first statement is inspected, so an
      /// Exit nested in an if is not flagged. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckLoopAtMostOnce.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, FirstStmtInner, Integer, IsAtMostOnceExit, NodeStr, SameText</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckLoopAtMostOnce.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckLoopAtMostOnce(const AFile: string): TArray<TLintFinding>;
      /// <summary>Checks a Format('literal', [literals]) call for two faults: the conversion
      /// specifier count not matching the argument count (format-argument-count), and a literal
      /// argument whose type is incompatible with its specifier family (format-specifier-type-mismatch).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>Findings tagged 'format-argument-count' and/or 'format-specifier-type-mismatch'.</returns>
      /// <remarks>
      /// Severity error. Requires a literalString format + exprBrackets argument array;
      /// skips silently otherwise. Variable arguments are not type-checked. Pure AST; no DB.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CharInSet, Copy, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFormatCall.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, LowerCase, NodeStr, Pos, SameText, SpecKinds, StringReplace</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFormatCall.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckFormatCall(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a try..except whose handler neither re-raises nor logs nor calls
      /// Application.HandleException/ShowException nor assigns Result/a var/out parameter --
      /// the exception is silently swallowed.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per swallowing except clause, pinned to the 'except' keyword.</returns>
      /// <remarks>
      /// Severity warning. A handler counts as handling if it contains a raise, an
      /// identifier/call whose text contains handleexception/showexception/log/report, a CALL
      /// whose text carries the exception's own .Message or .ClassName (a sink may be named
      /// anything, but an exception cannot be reported without being touched), OR an
      /// assignment to the enclosing routine's Result (function only) or one of its var/out
      /// parameters (Task 9c) -- the standard Delphi TryXxx idiom that converts a caught
      /// exception into a status the caller must inspect. Deliberately does NOT extend this to
      /// plain locals: an assignment nothing outside the routine can observe still communicates
      /// nothing, and stays flagged (see tests/lint/try-except-swallowed.pas's LocalOnly case) --
      /// which is why the .Message/.ClassName test is restricted to a call and not an assignment.
      /// try-finally is ignored. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CollectHandlingAssignTargets, Copy, Default, Delete, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, EnclosingDefProc, HandlesException, Integer, IsExplanatoryComment (+7 more)</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckSwallowedExcept(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a dataset opened (X.Open or X.Active := True) in a routine with no
      /// matching X.Close / X.Active := False in a finally block -- leaks a server cursor
      /// on an exception path.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per opened-but-not-finally-closed dataset variable.</returns>
      /// <remarks>
      /// Severity warning. Per-routine flow analysis (mirrors CheckUnprotectedFree).
      /// Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DotMethod, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, IsActiveAssign, IsDestroyingCall, LowerCase, NodeStr, SameText, WalkBody</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckDatasetOpen(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a critical section acquired (X.Enter or X.Acquire) in a routine with
      /// no matching X.Leave / X.Release in a finally block -- a lock leaked on an exception
      /// path deadlocks.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per acquired-but-not-finally-released lock variable.</returns>
      /// <remarks>
      /// Severity error. Per-routine flow analysis (mirrors CheckDatasetOpen).
      /// Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DotMethod, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection.VisitProcs, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, LowerCase, NodeStr, SameText, WalkBody</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection.VisitProcs"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckCriticalSection(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a routine with more than 5 Exit statements -- hard to reason about
      /// control flow; consolidate exits or use guard clauses consistently.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per routine exceeding the Exit-count threshold, at its header.</returns>
      /// <remarks>
      /// Severity info. Threshold = 5 (const). Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints/2</para>
      /// <para>Returns: CheckTooManyExitPoints(AFile, 5)</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      /// <summary>Flags a destructive act gated on a file-existence check.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per gated destructive call.</returns>
      /// <remarks>FileExists/TFile.Exists answer False for ANY failure to stat, so
      /// gating a truncate or a delete on one turns a transient fault into silent data
      /// loss that still returns success. See INBOX-stat-gated-destructive-acts.</remarks>
      class function CheckStatGatedDestructive(const AFile: string): TArray<TLintFinding>;
      class function CheckTooManyExitPoints(const AFile: string): TArray<TLintFinding>; overload;
      /// <summary>Flags routines exceeding AMaxExits Exit statements (configurable threshold).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <param name="AMaxExits">Maximum allowed Exit statements before flagging (inclusive).</param>
      /// <returns>One finding per routine exceeding the threshold, at its header.</returns>
      /// <remarks>
      /// Severity info. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints/1 (DRagLint.Diagnostics.AstChecks.pas)</para>
      /// <para>Calls: CountExits, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, NodeStr, SameText</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckTooManyExitPoints(const AFile: string; AMaxExits: Integer): TArray<TLintFinding>; overload;
      /// <summary>Flags a routine whose cyclomatic complexity exceeds 15. Decision points:
      /// if/ifElse/while/for/repeat, each case branch, and each and/or operator; base 1.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per routine over the complexity threshold, at its header.</returns>
      /// <remarks>
      /// Severity info. Threshold = 15 (const). Node kinds: kAnd/kOr/caseCase verified
      /// against the grammar. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity/2</para>
      /// <para>Returns: CheckCyclomaticComplexity(AFile, 15)</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckCyclomaticComplexity(const AFile: string): TArray<TLintFinding>; overload;
      /// <summary>Flags routines exceeding AMaxComplexity cyclomatic complexity (configurable threshold).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <param name="AMaxComplexity">Maximum allowed complexity before flagging (inclusive).</param>
      /// <returns>One finding per routine over the threshold, at its header.</returns>
      /// <remarks>
      /// Severity info. Pure AST; no DB. Never raises.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity/1 (DRagLint.Diagnostics.AstChecks.pas)</para>
      /// <para>Calls: CyclomaticOf, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, NodeStr</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckCyclomaticComplexity(const AFile: string; AMaxComplexity: Integer): TArray<TLintFinding>; overload;
      /// <summary>v(ADP2 T3): the McCabe cyclomatic complexity of one routine body --
      /// 1 + the count of decision-point nodes (if/ifElse/while/for/repeat/kAnd/kOr/
      /// caseCase) anywhere under ABody, not recursing into a nested defProc (a
      /// local routine is counted separately, on its own). Extracted from
      /// CheckCyclomaticComplexity so the cyclomatic-complexity LINT RULE and the
      /// Auto-Document 'Complexity:' fact (DRagLint.Doc.SymbolFacts) share the exact
      /// same formula and can never diverge on what one routine's complexity is.</summary>
      /// <param name="ABody">A routine's body node (defProc.ChildByField('body')).
      /// A null node (no body) yields 1 (base complexity, zero decisions).</param>
      /// <returns>The routine's cyclomatic complexity, always &gt;= 1.</returns>
      /// <remarks>
      /// Pure AST; no DB; never raises. Node kinds verified against the
      /// grammar by CheckCyclomaticComplexity's own tests (tests\lint\cyclomatic-
      /// complexity.pas/.expected).
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze (DRagLint.Doc.SymbolFacts.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity.Visit (DRagLint.Diagnostics.AstChecks.pas) ?</para>
      /// <para>Calls: DRagLint.Diagnostics.AstChecks.CyclomaticCountDecisions</para>
      /// <para>Returns: 1 + CyclomaticCountDecisions(ABody)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.CyclomaticCountDecisions"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CyclomaticOf(const ABody: TTSNode): Integer;
      /// <summary>v0.75 (#6): flags routines whose SonarSource-style cognitive complexity exceeds
      /// the threshold -- each control-flow structure adds 1 + its nesting depth, each and/or/xor
      /// adds 1. Rewards flat code, penalises deep nesting (unlike flat cyclomatic count).</summary>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// CheckCognitiveComplexity(AFile, 25).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity/2</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckCognitiveComplexity(const AFile: string): TArray<TLintFinding>; overload;
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AMaxScore"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed: nil;
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity/1 (DRagLint.Diagnostics.AstChecks.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity.Visit, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, Format, Integer, Score</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity.Visit"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckCognitiveComplexity(const AFile: string; AMaxScore: Integer): TArray<TLintFinding>; overload;
      /// <summary>Flags a constructor that calls a virtual/dynamic/override method declared in
      /// its OWN class -- the VMT is live before the body runs, so the call dispatches to a
      /// descendant override whose fields are not yet initialised (AV or corrupt state).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One 'virtual-method-in-constructor' finding per offending call site.</returns>
      /// <remarks>Severity warning. Same-file, same-class only: the virtual-method set is gathered
      /// from each class's own declaration in this file (procAttribute kVirtual/kDynamic/kOverride);
      /// inherited (static ancestor) calls and methods inherited unchanged from a base class are not
      /// flagged. Cross-unit ancestry needs a type resolver (future). Pure AST; no DB. Never raises.</remarks>
      // v12 (M1): when AStore is present, the virtual-method set is augmented with
      // inherited virtuals from cross-unit ancestors (GetVirtualMethodsIncludingAncestors);
      // nil keeps the same-file/same-class behavior.
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore = nil</param>
      /// <param name="AFileId"><!-- drag-lint:auto type -->Int64 = 0</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed: nil;
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: CollectClassMethods, Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor.CheckCtors, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor.CollectClasses, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, FlagCalls, Format, HasVirtualAttr, Integer, LowerCase, NodeStr, SameText, Walk</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor.CheckCtors"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor.CollectClasses"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.Check"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckVirtualInConstructor(const AFile: string; const AStore: ISymbolStore = nil; AFileId: Int64 = 0): TArray<TLintFinding>;
  end;

implementation

function tree_sitter_delphi13: PTSLanguage; cdecl;
external 'tree-sitter-delphi13';

const
  { Recorded in the per-file TypeMap when a name is declared with two DIFFERENT
    types in the same file -- two routines each declaring `W`, say. The map is
    flat and file-scoped (the class comment on CheckTypeAware admits as much:
    "no scope resolution, so rare same-name shadowing may mis-type"), so without
    this the LAST declaration visited silently decided the type for every use in
    the file, including uses inside the other routine.

    Measured: YADF.Layout.pas declares `W: string` (:1076) and
    `W: TArray<string>` (:2357). length-zero-compare typed the array one as a
    string and advised `W = ''` for a dynamic array -- wrong advice, and it fired
    in all three YADF projects because the unit is shared.

    The value is chosen so no CatOf / IsStringType / IsFloatType /
    IsInterfaceType / IsPointerType predicate can match it, so EVERY type-aware
    rule declines at once rather than each needing its own guard. Two
    declarations of the same type are not a conflict. Absence over wrong. }
  AMBIGUOUS_DECL_TYPE = '<ambiguous-decl>';

var
  GKeywordSet: TDictionary<string, Boolean> = nil;

procedure BuildKeywordSet;
var
  KW: TStringList;
begin
  GKeywordSet:= TDictionary<string, Boolean>.Create(256);
  KW:= TStringList.Create;
  try
    KW.CommaText:= 'and,array,as,asm,begin,case,class,const,' + 'constructor,destructor,dispinterface,div,do,downto,' + 'else,end,except,exports,file,finalization,finally,' +
    'for,function,goto,if,implementation,in,inherited,' + 'initialization,inline,interface,is,label,library,' + 'mod,nil,not,object,of,on,operator,or,out,' +
    'packed,procedure,program,property,protected,public,' + 'published,raise,record,reintroduce,repeat,resourcestring,' + 'set,shl,shr,string,then,threadvar,to,try,type,' +
    'unit,until,uses,var,while,with,xor,' + 'absolute,abstract,assembler,automated,cdecl,contains,' + 'default,deprecated,dynamic,experimental,export,external,' +
    'far,final,forward,helper,implements,index,message,' + 'name,near,nodefault,overload,override,package,pascal,' + 'platform,private,read,readonly,register,' +
    'requires,resident,result,safecall,sealed,self,static,' + 'stdcall,strict,stored,true,false,virtual,winapi,' + 'write,writeonly,integer,boolean,char,byte,' +
    'word,cardinal,int64,double,single,real';
    var I: Integer;
    for I:= 0 to KW.Count - 1 do GKeywordSet.AddOrSetValue(KW[I], True);
  finally
    KW.Free;
  end; // try
end; // procedure

class function TAstChecker.IsKeyword(const AName: string): Boolean;
begin
  if GKeywordSet = nil then BuildKeywordSet;
  Result:= GKeywordSet.ContainsKey(System.SysUtils.LowerCase(AName));
end;

class function TAstChecker.LoadBuiltinAllowlist: TDictionary<string, Boolean>;
var
  AllowPath: string                      ;
  Lines    : TArray<string>              ;
  Line     : string                      ;
  D        : TDictionary<string, Boolean>;
begin
  D:= TDictionary<string, Boolean>.Create(256);
  AllowPath:= TPath.Combine( TPath.GetDirectoryName(ParamStr(0)), 'rules\builtin-symbols.txt');
  if TFile.Exists(AllowPath) then
  begin
    Lines:= TFile.ReadAllLines(AllowPath, TEncoding.ASCII);
    for Line in Lines do
    begin
      var Trimmed:= Trim(Line);
      if Trimmed <> '' then D.AddOrSetValue(Trimmed, True);
    end;
  end;
  Result:= D;
end;

{ Returns ASource with every character that sits inside a comment or a string
  literal replaced by a SPACE, keeping length and all line breaks -- so byte
  offsets and the line/column arithmetic downstream stay valid.

  CheckUndeclared regex-scans the raw file text for capitalised words. It lives in
  AstChecks and is wired in under `check-ast`, but it is not AST-based, and
  nothing stripped comments before the regex ran. So any capitalised 3+-character
  word in a comment that is not already an indexed symbol was reported as an
  undeclared identifier: `Fixture`, `This`, `MUST`, `FIELD`, `CallDefs`, and the
  three segments of `YADF.LineScan.ComputeBlockCommentLock` -- eight spurious
  findings from four comment blocks in one fixture. It specifically punishes
  well-commented code: the more explanatory prose, the more false findings.

  FOURTH instance in this tree of "a text scan cannot tell code from comment",
  after the dl:shared reader (which ships the original state machine and argues
  the point at length in DRagLint.Lint.SharedUnit's header), the dl:ok
  unused-marker walk, and the Calls:/raises body scans in DRagLint.Doc.Facts.
  String literals are masked too -- the note that reported this suspected they
  were affected but had not verified it; masking both costs nothing extra. }
function MaskCommentsAndStrings(const ASource: string): string;
var
  I, N       : Integer;
  InBrace    : Integer;
  InStarParen: Boolean;
  InLineCmt  : Boolean;
  InStr      : Boolean;

  procedure Blank(ACount: Integer);
  var K: Integer;
  begin
    for K := 0 to ACount - 1 do
      if (I + K <= N) and (Result[I + K] <> #10) and (Result[I + K] <> #13) then
        Result[I + K] := ' ';
  end;

begin
  Result     := ASource;
  N          := Length(Result);
  InBrace    := 0;
  InStarParen:= False;
  InLineCmt  := False;
  InStr      := False;
  I          := 1;
  while I <= N do
  begin
    if InLineCmt then
    begin
      if (Result[I] = #10) or (Result[I] = #13) then InLineCmt := False
      else Result[I] := ' ';
      Inc(I);
      Continue;
    end;
    if InBrace > 0 then
    begin
      { Brace comments in Object Pascal do NOT nest: the FIRST closing brace ends
        the comment, whatever appeared inside it. An earlier draft of this
        function incremented the depth on an inner opening brace, which would
        have kept the mask open past the real end and blanked live code -- and a
        comment that documents a compiler directive contains one routinely.
        Blanking live code here is a FALSE NEGATIVE: it hides genuine undeclared
        identifiers, which is the quiet direction and the harder one to notice. }
      if Result[I] = '}' then Dec(InBrace);
      Blank(1);
      Inc(I);
      Continue;
    end;
    if InStarParen then
    begin
      if (Result[I] = '*') and (I < N) and (Result[I + 1] = ')') then
      begin
        InStarParen := False;
        Blank(2);
        Inc(I, 2);
        Continue;
      end;
      Blank(1);
      Inc(I);
      Continue;
    end;
    if InStr then
    begin
      if Result[I] = '''' then InStr := False;
      Blank(1);
      Inc(I);
      Continue;
    end;
    { code }
    if Result[I] = '''' then begin InStr := True; Blank(1); Inc(I); Continue; end;
    if Result[I] = '{'  then begin Inc(InBrace);  Blank(1); Inc(I); Continue; end;
    if (Result[I] = '(') and (I < N) and (Result[I + 1] = '*') then
    begin
      InStarParen := True;
      Blank(2);
      Inc(I, 2);
      Continue;
    end;
    if (Result[I] = '/') and (I < N) and (Result[I + 1] = '/') then
    begin
      InLineCmt := True;
      Blank(2);
      Inc(I, 2);
      Continue;
    end;
    Inc(I);
  end;
end;

class function TAstChecker.CheckUndeclared(const AStore: ISymbolStore; const AFile: string): TArray<TLintFinding>;
var
  Source   : string                      ;
  Findings : TList<TLintFinding>         ;
  Seen     : TDictionary<string, Boolean>;
  Allowlist: TDictionary<string, Boolean>;
  Matches  : TMatchCollection            ;
  M        : TMatch                      ;
  Name     : string                      ;
  Syms     : TArray<TSymbol>             ;
  Finding  : TLintFinding                ;
  LineStart: Integer                     ;
  SrcBytes : TBytes                      ;
  PF       : TParsedFile                 ;
  I        : Integer                     ;
  LineNum  : Integer                     ;
  ColNum   : Integer                     ;
begin
  if AStore = nil then Exit(nil);
  PF:= TAstParseCache.Get(AFile);
  SrcBytes:= PF.Src;
  { Comments and string literals blanked to spaces -- same length, same line
    breaks, so the line/column arithmetic below is unaffected. Without this the
    regex reads prose as code; see MaskCommentsAndStrings. }
  Source:= MaskCommentsAndStrings(TEncoding.Default.GetString(SrcBytes));

  Findings:= TList<TLintFinding>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  Allowlist:= LoadBuiltinAllowlist;
  try
    Matches:= TRegEx.Matches(Source, '\b([A-Z][A-Za-z0-9_]{2,})\b');
    for M in Matches do
    begin
      Name:= M.Groups[1].Value;
      if Seen.ContainsKey(Name) then Continue;
      Seen.Add(Name, True);

      if IsKeyword(Name) then Continue;
      if Allowlist.ContainsKey(Name) then Continue;

      Syms:= AStore.FindSymbolsByExactName(Name);
      if Length(Syms) > 0 then Continue;

      LineNum  := 1;
      ColNum   := 1;
      LineStart:= 1;
      for I:= 1 to M.Index - 1 do
      begin
        if Source[I] = #10 then
        begin
          Inc(LineNum);
          LineStart:= I + 1;
        end;
      end;
      ColNum:= M.Index - LineStart + 1;

      Finding:= Default(TLintFinding);
      Finding.RuleId  := 'undeclared-identifier';
      Finding.Severity:= 'warning';
      Finding.Message:= 'Identifier "' + Name + '" not found in symbol index (may be undeclared or from an unindexed unit)';
      Finding.FilePath := AFile;
      Finding.StartLine:= LineNum;
      Finding.StartCol := ColNum;
      Finding.EndLine  := LineNum;
      Finding.EndCol:= ColNum + Length(Name);
      Findings.Add(Finding);
    end; // for
    Result:= Findings.ToArray;
  finally
    Allowlist.Free;
    Seen.Free;
    Findings.Free;
  end; // try
end; // function

class function TAstChecker.CheckUnbalancedBeginEnd( const AFile: string): TArray<TLintFinding>;
var
  Source           : string      ;
  SrcBytes         : TBytes      ;
  PF               : TParsedFile ;
  I                : Integer     ;
  Len              : Integer     ;
  C                : Char        ;
  Depth            : Integer     ;
  InStr            : Boolean     ;
  InLineComment    : Boolean     ;
  InBraceCmt       : Boolean     ;
  InParenStarCmt   : Boolean     ;
  WordStart        : Integer     ;
  Word             : string      ;
  LastUnmatchedLine: Integer     ;
  LastUnmatchedCol : Integer     ;
  LineNum          : Integer     ;
  ColNum           : Integer     ;
  LineStart        : Integer     ;
  Finding          : TLintFinding;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  SrcBytes:= PF.Src;
  Source:= TEncoding.Default.GetString(SrcBytes);
  Len:= Length(Source);

  Depth            := 0;
  InStr            := False;
  InLineComment    := False;
  InBraceCmt       := False;
  InParenStarCmt   := False;
  LastUnmatchedLine:= 1;
  LastUnmatchedCol := 1;
  LineNum          := 1;
  LineStart        := 1;
  I                := 1;

  while I <= Len do
  begin
    C:= Source[I];

    if C = #10 then
    begin
      Inc(LineNum);
      LineStart:= I + 1;
      InLineComment:= False;
      Inc(I);
      Continue;
    end;
    if C = #13 then
    begin
      Inc(I);
      Continue;
    end;

    if InLineComment then
    begin
      Inc(I);
      Continue;
    end;

    if InBraceCmt then
    begin
      if C = '}' then InBraceCmt:= False;
      Inc(I);
      Continue;
    end;

    if InParenStarCmt then
    begin
      if (C = '*') and (I < Len) and (Source[I + 1] = ')') then
      begin
        InParenStarCmt:= False;
        Inc(I, 2);
      end
      else Inc(I);
      Continue;
    end;

    if InStr then
    begin
      if C = '''' then
      begin
        if (I < Len) and (Source[I + 1] = '''') then Inc(I, 2)
        else
        begin
          InStr:= False;
          Inc(I);
        end;
      end
      else Inc(I);
      Continue;
    end;

    if C = '''' then
    begin
      InStr:= True;
      Inc(I);
      Continue;
    end;

    if C = '{' then
    begin
      InBraceCmt:= True;
      Inc(I);
      Continue;
    end;

    if (C = '(') and (I < Len) and (Source[I + 1] = '*') then
    begin
      InParenStarCmt:= True;
      Inc(I, 2);
      Continue;
    end;

    if (C = '/') and (I < Len) and (Source[I + 1] = '/') then
    begin
      InLineComment:= True;
      Inc(I, 2);
      Continue;
    end;

    if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) then
    begin
      WordStart:= I;
      while (I <= Len) and CharInSet(Source[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(I);
      Word:= Copy(Source, WordStart, I - WordStart);

      if (I <= Len) and not CharInSet(Source[I], [#0..#32, '(', ')', ',', ';', '.', '[', ']', ':', '=', '+', '-', '*', '/', '@', '^', '{', '}', #39]) then
      begin
        Continue;
      end;

      if SameText(Word, 'begin') then
      begin
        Inc(Depth);
        ColNum:= WordStart - LineStart + 1;
        LastUnmatchedLine:= LineNum;
        LastUnmatchedCol := ColNum;
      end
      else if SameText(Word, 'end') then
      begin
        if Depth > 0 then Dec(Depth)
        else
        begin
          ColNum:= WordStart - LineStart + 1;
          LastUnmatchedLine:= LineNum;
          LastUnmatchedCol := ColNum;
        end;
      end;
      Continue;
    end; // if

    Inc(I);
  end; // while

  if Depth <> 0 then
  begin
    Finding:= Default(TLintFinding);
    Finding.RuleId  := 'unbalanced-begin-end';
    Finding.Severity:= 'warning';
    Finding.Message:= Format( 'Unbalanced begin/end: depth %d at end of file ' + '(last unmatched keyword near line %d)', [Depth, LastUnmatchedLine]);
    Finding.FilePath := AFile;
    Finding.StartLine:= LastUnmatchedLine;
    Finding.StartCol := LastUnmatchedCol;
    Finding.EndLine  := LastUnmatchedLine;
    Finding.EndCol:= LastUnmatchedCol + 5;
    Result:= [Finding];
  end;
end; // function

class function TAstChecker.CheckSyntaxErrors( const AFile: string): TArray<TLintFinding>;
type
  TLineRange = record
    StartLine, EndLine: Integer;
  end;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;
  ConditionalRanges: TArray<TLineRange>;
  HasCond   : Boolean          ; // hoisted: true iff file has any conditional directives
  TotalLines: Integer          ; // hoisted: total line count, used by M4 line-1 guard
  SrcUp     : string           ; // hoisted upper-case source, decoded once

  // Returns True when ALine falls inside any conditional compilation region.
  function IsInConditionalRegion(ALine: Integer): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    for I:= 0 to Length(ConditionalRanges) - 1 do
      if (ALine >= ConditionalRanges[I].StartLine) and (ALine <= ConditionalRanges[I].EndLine) then
        Exit(True);
  end;

  // True when an error node [AStart..AEnd] fully engulfs ANY single conditional
  // region. Tested per-range (not against the outer hull) so a file with several
  // separate {$IF}..{$IFEND} blocks still suppresses a node straddling a middle
  // one, not only one spanning the entire first..last span.
  function StraddlesConditionalRegion(AStart, AEnd: Integer): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    for I:= 0 to Length(ConditionalRanges) - 1 do
      if (AStart < ConditionalRanges[I].StartLine) and (AEnd > ConditionalRanges[I].EndLine) then
        Exit(True);
  end;

  procedure BuildConditionalRanges;
  var
    I, Depth, Pos2, LineNum, StartLine: Integer;
    LineUp: string;
    R: TLineRange;
  begin
    // Reuse the hoisted SrcUp (decoded + upper-cased once) rather than decoding
    // Src again and AnsiUpperCase-ing every line -- the slices are already upper.
    Depth:= 0;
    StartLine:= -1;
    LineNum:= 1;
    I:= 1;
    while I <= Length(SrcUp) do
    begin
      Pos2:= I;
      while (Pos2 <= Length(SrcUp)) and (SrcUp[Pos2] <> #10) do Inc(Pos2);
      LineUp:= Copy(SrcUp, I, Pos2 - I);
      if (Pos2 <= Length(SrcUp)) and (SrcUp[Pos2] = #10) then
        Inc(Pos2);

      // Check closing directives FIRST: a line with IFEND must not also match
      // the opening IF prefix and spuriously increment Depth on the same line.
      if (System.Pos('{$IFEND', LineUp) > 0) or (System.Pos('{$ENDIF', LineUp) > 0) then
      begin
        if Depth > 0 then Dec(Depth);
        if (Depth = 0) and (StartLine >= 0) then
        begin
          R.StartLine:= StartLine;
          R.EndLine:= LineNum;
          SetLength(ConditionalRanges, Length(ConditionalRanges) + 1);
          ConditionalRanges[Length(ConditionalRanges) - 1]:= R;
          StartLine:= -1;
        end;
      end
      // Opening directive -- only reached when the line has NO closing directive.
      // Matches IF/IFDEF/IFNDEF/IFOPT but NOT IFEND/ENDIF (handled above).
      else if System.Pos('{$IF', LineUp) > 0 then
      begin
        if Depth = 0 then StartLine:= LineNum;
        Inc(Depth);
      end;

      I:= Pos2;
      Inc(LineNum);
    end;
    TotalLines:= LineNum - 1;
  end;

  procedure Visit(const N: TTSNode);
  var
    I: Integer     ;
    F: TLintFinding;
    P, EndP: TTSPoint;
    ErrorLine, EndLine: Integer;
    SkipDueToConditional: Boolean;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.IsError or N.IsMissing then
    begin
      P:= N.StartPoint;
      EndP:= N.EndPoint;
      ErrorLine:= Integer(P.Row) + 1;
      EndLine:= Integer(EndP.Row) + 1;

      SkipDueToConditional:= False;

      if HasCond then
      begin
        if Length(ConditionalRanges) > 0 then
          // Skip when the error starts or ends inside a region, or engulfs any
          // single region (per-range straddle handles multiple separate blocks).
          SkipDueToConditional:= IsInConditionalRegion(ErrorLine)
            or IsInConditionalRegion(EndLine)
            or StraddlesConditionalRegion(ErrorLine, EndLine)
        else
          SkipDueToConditional:= False; // no ranges produced -- only M4 guard below

        // M4 narrow line-1 guard: a root ERROR node at line 1 that spans nearly
        // the whole file is a grammar-confusion artefact of conditional directives,
        // not a genuine error. Suppress only when end row >= 75 % of file length.
        // A small genuine line-1 error (EndLine near line 1) always fires.
        if (not SkipDueToConditional) and (ErrorLine = 1)
           and (TotalLines > 1)
           and ((EndLine - ErrorLine) >= (TotalLines * 3) div 4) then
          SkipDueToConditional:= True;
      end;

      if not SkipDueToConditional then
      begin
        F:= Default(TLintFinding);
        F.RuleId  := 'syntax-error';
        F.Severity:= 'error';
        if N.IsMissing then F.Message:= 'Syntax error: missing token'
        else F.Message:= 'Syntax error near here';
        F.FilePath:= AFile;
        F.StartLine:= ErrorLine;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol:= F.StartCol + 1;
        Findings.Add(F);
        Exit; // reported -- children of this error node are part of the same error; stop here
      end;
      // Skipped due to conditional region or M4 guard: still descend into children
      // so genuine errors nested inside the suppressed node are not lost.
      for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
      Exit;
    end; // if
    if not N.HasError then Exit;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  { RawSrc, NOT Src -- this is the one check that reads DIRECTIVE TEXT out of
    the source, and since the lint walk started preprocessing, Src has had the
    directives themselves blanked to spaces. Reading Src here would make HasCond
    false for every file and BuildConditionalRanges would find no regions at
    all, silently disabling the conditional-aware half of the syntax check.
    Offsets are identical between the two buffers, so the ranges it builds still
    line up with the tree's error nodes. }
  Src:= PF.RawSrc;
  // Hoist the directive scan: decode once, reuse HasCond in both Visit and
  // BuildConditionalRanges (was re-decoded per error node = O(N)).
  SrcUp:= AnsiUpperCase(TEncoding.UTF8.GetString(Src));
  HasCond:= (System.Pos('{$IF', SrcUp) > 0) or (System.Pos('{$IFEND', SrcUp) > 0)
            or (System.Pos('{$ENDIF', SrcUp) > 0);
  TotalLines:= 1;
  if HasCond then
    BuildConditionalRanges;
  Findings:= TList<TLintFinding>.Create;
  try
    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

class function TAstChecker.CheckUnusedLocals( const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S: Integer;
    E: Integer;
    L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

{ Count every identifier occurrence (lowercased) in the subtree. A declared
    local's own declaration counts as one; any use raises it above one. }
  procedure CountIdents(const N: TTSNode; AMap: TDictionary<string, Integer>);
  var
    I: Integer;
    C: Integer;
    T: string ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'identifier' then
    begin
      T:= LowerCase(NodeStr(N));
      if T <> '' then
        if AMap.TryGetValue(T, C) then AMap[T]:= C + 1 else AMap.Add(T, 1);
    end;
    for I:= 0 to N.NamedChildCount - 1 do CountIdents(N.NamedChild(I), AMap);
  end;

  procedure CheckProc(const ADefProc: TTSNode);
  var
    Counts     : TDictionary<string, Integer>;
    I          : Integer                     ;
    J          : Integer                     ;
    K          : Integer                     ;
    Cnt        : Integer                     ;
    TypeStart  : Integer                     ;
    Child      : TTSNode                     ;
    DV         : TTSNode                     ;
    TypeNode   : TTSNode                     ;
    NameId     : TTSNode                     ;
    Hdr        : TTSNode                     ;
    Nm         : TTSNode                     ;
    Body       : TTSNode                     ;
    RoutineName: string                      ;
    DisplayName: string                      ;
    LowerName  : string                      ;
    P          : TTSPoint                    ;
    F          : TLintFinding                ;
  begin
    { skip asm routines -- identifiers in an asm block are not 'identifier'
      nodes, so a local used only in asm would be a false positive. }
    Body:= ADefProc.ChildByField('body');
    if (not Body.IsNull) and (Body.NodeType = 'asm') then Exit;

    Counts:= TDictionary<string, Integer>.Create;
    try
      CountIdents(ADefProc, Counts);

      RoutineName:= '';
      Hdr:= ADefProc.ChildByField('header');
      if not Hdr.IsNull then
      begin
        Nm:= Hdr.ChildByField('name');
        if not Nm.IsNull then RoutineName:= NodeStr(Nm);
      end;

      { direct declVars children = THIS routine's local var sections (a nested
        routine's declVars are grandchildren, handled when we recurse to it). }
      for I:= 0 to ADefProc.NamedChildCount - 1 do
      begin
        Child:= ADefProc.NamedChild(I);
        if Child.NodeType <> 'declVars' then Continue;
        for J:= 0 to Child.NamedChildCount - 1 do
        begin
          DV:= Child.NamedChild(J);
          if DV.NodeType <> 'declVar' then Continue;
          TypeNode:= DV.ChildByField('type');
          if TypeNode.IsNull then TypeStart:= MaxInt
          else TypeStart:= Integer(TypeNode.StartByte);
          { name identifiers come before the type field (A, B: T) }
          for K:= 0 to DV.NamedChildCount - 1 do
          begin
            NameId:= DV.NamedChild(K);
            if NameId.NodeType <> 'identifier' then Continue;
            if Integer(NameId.StartByte) >= TypeStart then Continue;
            DisplayName:= NodeStr  (NameId     );
            LowerName  := LowerCase(DisplayName);
            if LowerName = '' then Continue;
            Cnt:= 0;
            Counts.TryGetValue(LowerName, Cnt);
            if Cnt <= 1 then { only the declaration occurrence -> unused }
            begin
              P:= NameId.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'unused-local';
              F.Severity:= 'hint';
              if RoutineName <> '' then F.Message:= Format( 'H2164 Variable ''%s'' is declared but never used in ''%s''', [DisplayName, RoutineName])
              else F.Message:= Format( 'H2164 Variable ''%s'' is declared but never used', [DisplayName]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(P.Row   ) + 1;
              F.StartCol := Integer(P.Column) + 1;
              F.EndLine:= F.StartLine;
              F.EndCol:= F.StartCol + Length(DisplayName);
              Findings.Add(F);
            end; // if
          end; // for
        end; // for
      end; // for
    finally
      Counts.Free;
    end; // try
  end; // procedure

  procedure VisitProcs(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then CheckProc(N);
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // begin

class function TAstChecker.BuildUnusedLocalFixEdits(const AFile: string;
  const AFindings: TArray<TLintFinding>; out AFixedCount: Integer): TArray<TTextEdit>;
var
  Src     : TBytes                        ;
  PF      : TParsedFile                   ;
  Edits   : TList<TTextEdit>              ;
  Flagged : TDictionary<string, Boolean>  ;
  F       : TLintFinding                  ;
  Fixed   : Integer                       ;

  function NStr(const N: TTSNode): string;
  var
    S: Integer;
    E: Integer;
    L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { The finding's StartLine/StartCol are the name identifier's own start point
    (+1 on each axis), so a node keys back to its finding exactly. }
  function PosKey(ALine, ACol: Integer): string;
  begin
    Result:= IntToStr(ALine) + ':' + IntToStr(ACol);
  end;

  function NodeKey(const N: TTSNode): string;
  begin
    Result:= PosKey(Integer(N.StartPoint.Row) + 1, Integer(N.StartPoint.Column) + 1);
  end;

  { One routine's own var sections. Mirrors CheckUnusedLocals: only declVars
    that are DIRECT children of the defProc, so a nested routine's sections are
    handled when the walk reaches that routine. }
  procedure HandleProc(const ADefProc: TTSNode);
  var
    I         : Integer          ;
    J         : Integer          ;
    K         : Integer          ;
    DeclVars  : TTSNode          ;
    DV        : TTSNode          ;
    KwVar     : TTSNode          ;
    TypeNode  : TTSNode          ;
    NameId    : TTSNode          ;
    TypeStart : Integer          ;
    Names     : TArray<TTSNode>  ;
    FlagCount : Integer          ;
    AnyKept   : Boolean          ;
    AnyDeleted: Boolean          ;
    Section   : TList<TTextEdit> ;
    SectFixed : Integer          ;
    E         : TTextEdit        ;
    Keep      : string           ;
    KwLine    : Integer          ;
    Covered   : Boolean          ;
  begin
    for I:= 0 to ADefProc.NamedChildCount - 1 do
    begin
      DeclVars:= ADefProc.NamedChild(I);
      if DeclVars.NodeType <> 'declVars' then Continue;

      Section   := TList<TTextEdit>.Create;
      SectFixed := 0;
      try
        KwVar     := Default(TTSNode);
        AnyKept   := False;
        AnyDeleted:= False;

        for J:= 0 to DeclVars.NamedChildCount - 1 do
        begin
          DV:= DeclVars.NamedChild(J);
          if DV.NodeType = 'kVar' then begin KwVar:= DV; Continue; end;
          if DV.NodeType <> 'declVar' then Continue;

          { name identifiers precede the type field -- the rule CheckUnusedLocals uses }
          TypeNode:= DV.ChildByField('type');
          if TypeNode.IsNull then TypeStart:= MaxInt
          else TypeStart:= Integer(TypeNode.StartByte);
          Names:= nil;
          for K:= 0 to DV.NamedChildCount - 1 do
          begin
            NameId:= DV.NamedChild(K);
            if NameId.NodeType <> 'identifier' then Continue;
            if Integer(NameId.StartByte) >= TypeStart then Continue;
            Names:= Names + [NameId];
          end;
          if Length(Names) = 0 then begin AnyKept:= True; Continue; end;

          FlagCount:= 0;
          for K:= 0 to High(Names) do
            if Flagged.ContainsKey(NodeKey(Names[K])) then Inc(FlagCount);

          if FlagCount = 0 then
          begin
            AnyKept:= True;
            Continue;
          end;

          if FlagCount = Length(Names) then
          begin
            { every name here is dead -> the whole declaration goes }
            E:= Default(TTextEdit);
            E.FilePath:= AFile;
            E.Kind    := tekDeleteLines;
            E.Line    := Integer(DV.StartPoint.Row) + 1;
            E.EndLine := Integer(DV.EndPoint.Row  ) + 1;
            Section.Add(E);
            Inc(SectFixed, FlagCount);
            AnyDeleted:= True;
            Continue;
          end;

          { Only SOME names are dead. Splice the name list and keep the
            declaration -- deleting the line here would take live variables
            with it. Requires the whole list on one line so a single
            replace-in-line span covers it exactly. }
          if Integer(Names[0].StartPoint.Row) <> Integer(Names[High(Names)].EndPoint.Row) then
          begin
            AnyKept:= True;
            Continue;
          end;
          Keep:= '';
          for K:= 0 to High(Names) do
            if not Flagged.ContainsKey(NodeKey(Names[K])) then
            begin
              if Keep <> '' then Keep:= Keep + ', ';
              Keep:= Keep + NStr(Names[K]);
            end;
          if Trim(Keep) = '' then begin AnyKept:= True; Continue; end;
          E:= Default(TTextEdit);
          E.FilePath:= AFile;
          E.Kind    := tekReplaceInLine;
          E.Line    := Integer(Names[0].StartPoint.Row      ) + 1;
          E.Col     := Integer(Names[0].StartPoint.Column   ) + 1;
          E.EndCol  := Integer(Names[High(Names)].EndPoint.Column) + 1;
          E.Text    := Keep;
          Section.Add(E);
          Inc(SectFixed, FlagCount);
          AnyKept:= True;
        end; // for J

        { A declVars with nothing left must lose its 'var' keyword too -- a bare
          'var' before 'begin' is a compile error. If the keyword cannot be
          found, DROP this section's deletions: emitting them would be exactly
          the breakage this guard exists to prevent. }
        if AnyDeleted and (not AnyKept) then
        begin
          if KwVar.IsNull then
          begin
            { cannot locate the keyword -> cannot prove the collapse is safe.
              Discard this section only; other sections still stand. }
            Section.Clear;
            SectFixed:= 0;
          end
          else
          begin
            KwLine := Integer(KwVar.StartPoint.Row) + 1;
            Covered:= False;
            for J:= 0 to DeclVars.NamedChildCount - 1 do
            begin
              DV:= DeclVars.NamedChild(J);
              if (DV.NodeType = 'declVar') and (Integer(DV.StartPoint.Row) + 1 = KwLine) then
              begin Covered:= True; Break; end;
            end;
            if not Covered then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= AFile;
              E.Kind    := tekDeleteLines;
              E.Line    := KwLine;
              E.EndLine := KwLine;
              Section.Add(E);
            end;
          end;
        end;

        Edits.AddRange(Section.ToArray);
        Inc(Fixed, SectFixed);
      finally
        Section.Free;
      end;
    end; // for I
  end; // procedure

  procedure VisitProcs(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then HandleProc(N);
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end;

begin
  Result     := nil;
  AFixedCount:= 0;
  Fixed      := 0;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;

  Edits  := TList<TTextEdit>.Create;
  Flagged:= TDictionary<string, Boolean>.Create;
  try
    for F in AFindings do
      if SameText(F.RuleId, 'unused-local') and SameText(F.FilePath, AFile) then
        Flagged.AddOrSetValue(PosKey(F.StartLine, F.StartCol), True);
    if Flagged.Count = 0 then Exit;

    VisitProcs(PF.Tree.RootNode);
    Result     := Edits.ToArray;
    AFixedCount:= Fixed;
  finally
    Flagged.Free;
    Edits.Free;
  end;
end;

class function TAstChecker.CheckRaiseInFinally(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  { Search a finally body subtree for raise statements. Does NOT descend into a
    nested 'try' -- a raise inside an inner try is attributed to that try when
    the main walk reaches it. }
  procedure SearchForRaise(const N: TTSNode);
  var
    I: Integer     ;
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.NodeType = 'try' then Exit;
    if N.NodeType = 'raise' then
    begin
      P:= N.StartPoint;
      F:= Default(TLintFinding);
      F.RuleId  := 'raise-in-finally';
      F.Severity:= 'warning';
      F.Message := 'raise inside a finally block masks the exception currently propagating -- move it out of the finally';
      F.FilePath:= AFile;
      F.StartLine:= Integer(P.Row   ) + 1;
      F.StartCol := Integer(P.Column) + 1;
      F.EndLine:= F.StartLine;
      F.EndCol := F.StartCol + 5;
      Findings.Add(F);
      Exit; { do not descend into the raise expression }
    end;
    for I:= 0 to N.ChildCount - 1 do SearchForRaise(N.Child(I));
  end; // procedure

  { Walk the whole tree; for each 'try', scan its finally body (the 'statements'
    child that follows the kFinally keyword). }
  procedure Visit(const N: TTSNode);
  var
    I        : Integer;
    InFinally: Boolean;
    C        : TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'try' then
    begin
      InFinally:= False;
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        if C.NodeType = 'kFinally' then InFinally:= True
        else if InFinally and (C.NodeType = 'statements') then SearchForRaise(C);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckCodeAfterExit(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Is this statement an unconditional flow-terminator (Exit/raise/Break/Continue/Halt)? }
  function IsTerminator(const Stmt: TTSNode): Boolean;
  var
    Inner : TTSNode;
    Entity: TTSNode;
    Nm    : string ;
  begin
    Result:= False;
    if Stmt.IsNull then Exit;
    if Stmt.NodeType = 'raise' then Exit(True);
    if Stmt.NodeType <> 'statement' then Exit;
    if Stmt.NamedChildCount = 0 then Exit;
    Inner:= Stmt.NamedChild(0);
    if Inner.NodeType = 'identifier' then
    begin
      Nm:= LowerCase(NodeStr(Inner));
      Result:= (Nm = 'exit') or (Nm = 'break') or (Nm = 'continue') or (Nm = 'halt');
    end
    else if Inner.NodeType = 'exprCall' then
    begin
      Entity:= Inner.ChildByField('entity');
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        Nm:= LowerCase(NodeStr(Entity));
        Result:= (Nm = 'exit') or (Nm = 'halt');
      end;
    end;
  end; // function

  { In a block/statements node, flag the first real statement that directly
    follows a terminator. Keyword children (kBegin/kEnd/kUntil...) are skipped. }
  procedure CheckList(const Parent: TTSNode);
  var
    I   : Integer         ;
    C   : TTSNode         ;
    Kids: TList<TTSNode>  ;
    P   : TTSPoint        ;
    F   : TLintFinding    ;
  begin
    Kids:= TList<TTSNode>.Create;
    try
      for I:= 0 to Parent.NamedChildCount - 1 do
      begin
        C:= Parent.NamedChild(I);
        if C.IsNull then Continue;
        if C.NodeType.StartsWith('k') then Continue; { keyword token, not a statement }
        if C.NodeType = 'comment' then Continue; { a trailing/standalone comment is not executable code (FP-5/FP-6) }
        Kids.Add(C);
      end;
      for I:= 0 to Kids.Count - 2 do
        if IsTerminator(Kids[I]) then
        begin
          C:= Kids[I + 1];
          P:= C.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'code-after-exit';
          F.Severity:= 'warning';
          F.Message := 'Unreachable code: this statement follows an unconditional Exit/raise/Break/Continue/Halt';
          F.FilePath:= AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine:= F.StartLine;
          F.EndCol := F.StartCol + 1;
          Findings.Add(F);
          Break; { one finding per statement list }
        end;
    finally
      Kids.Free;
    end;
  end; // procedure

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if (N.NodeType = 'block') or (N.NodeType = 'statements') then CheckList(N);
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckMissingInherited(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  { Does the subtree call 'inherited' anywhere, not counting nested routines? }
  function HasInherited(const N: TTSNode): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'inherited' then Exit(True);
    if N.NodeType = 'defProc' then Exit(False); { nested routine -> its inherited is its own }
    for I:= 0 to N.ChildCount - 1 do
      if HasInherited(N.Child(I)) then Exit(True);
  end; // function

  procedure CheckProc(const ADefProc: TTSNode);
  var
    Hdr  : TTSNode     ;
    Body : TTSNode     ;
    I    : Integer     ;
    Kind : string      ;
    IsCtor: Boolean    ;
    IsDtor: Boolean    ;
    P    : TTSPoint    ;
    F    : TLintFinding;
  begin
    Hdr:= ADefProc.ChildByField('header');
    if Hdr.IsNull then Exit;
    IsCtor:= False; IsDtor:= False;
    for I:= 0 to Hdr.ChildCount - 1 do
    begin
      Kind:= Hdr.Child(I).NodeType;
      if Kind = 'kConstructor' then IsCtor:= True
      else if Kind = 'kDestructor' then IsDtor:= True
      else if Kind = 'kClass' then Exit; { class constructor/destructor -> no inherited }
    end;
    if not (IsCtor or IsDtor) then Exit;
    Body:= ADefProc.ChildByField('body');
    if Body.IsNull then Exit;
    if Body.NodeType = 'asm' then Exit;
    if HasInherited(Body) then Exit;
    P:= Hdr.StartPoint;
    F:= Default(TLintFinding);
    F.Severity:= 'warning';
    if IsCtor then
    begin
      F.RuleId := 'missing-inherited-ctor';
      F.Message:= 'Constructor does not call inherited -- ancestor initialization may be skipped';
    end
    else
    begin
      F.RuleId := 'missing-inherited-dtor';
      F.Message:= 'Destructor does not call inherited -- ancestor cleanup may be skipped (resource leak)';
    end;
    F.FilePath:= AFile;
    F.StartLine:= Integer(P.Row   ) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine:= F.StartLine;
    F.EndCol := F.StartCol + 5;
    Findings.Add(F);
  end; // procedure

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.NodeType = 'defProc' then CheckProc(N);
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckControlFlowInFinally(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Is this statement an Exit/Break/Continue/Halt? (raise is handled by the
    separate raise-in-finally rule.) }
  function IsCtrlFlow(const Stmt: TTSNode): Boolean;
  var
    Inner : TTSNode;
    Entity: TTSNode;
    Nm    : string ;
  begin
    Result:= False;
    if (Stmt.IsNull) or (Stmt.NodeType <> 'statement') or (Stmt.NamedChildCount = 0) then Exit;
    Inner:= Stmt.NamedChild(0);
    if Inner.NodeType = 'identifier' then
    begin
      Nm:= LowerCase(NodeStr(Inner));
      Result:= (Nm = 'exit') or (Nm = 'break') or (Nm = 'continue') or (Nm = 'halt');
    end
    else if Inner.NodeType = 'exprCall' then
    begin
      Entity:= Inner.ChildByField('entity');
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        Nm:= LowerCase(NodeStr(Entity));
        Result:= (Nm = 'exit') or (Nm = 'halt');
      end;
    end;
  end; // function

  procedure SearchFinally(const N: TTSNode);
  var
    I: Integer     ;
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.NodeType = 'try' then Exit; { nested try handled on its own }
    if IsCtrlFlow(N) then
    begin
      P:= N.StartPoint;
      F:= Default(TLintFinding);
      F.RuleId  := 'control-flow-in-finally';
      F.Severity:= 'warning';
      F.Message := 'Exit/Break/Continue/Halt in a finally block silently discards any exception currently propagating -- move it out of the finally';
      F.FilePath:= AFile;
      F.StartLine:= Integer(P.Row   ) + 1;
      F.StartCol := Integer(P.Column) + 1;
      F.EndLine:= F.StartLine;
      F.EndCol := F.StartCol + 1;
      Findings.Add(F);
      Exit;
    end;
    for I:= 0 to N.ChildCount - 1 do SearchFinally(N.Child(I));
  end; // procedure

  procedure Visit(const N: TTSNode);
  var
    I        : Integer;
    InFinally: Boolean;
    C        : TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'try' then
    begin
      InFinally:= False;
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        if C.NodeType = 'kFinally' then InFinally:= True
        else if InFinally and (C.NodeType = 'statements') then SearchFinally(C);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckRoutineMetrics(const AFile: string; AMaxParams, AMaxLocals, AMaxLines, AMaxNesting: Integer): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Counts the declared names in a declArgs/declVars container (handles 'A, B: T'
    multi-name items by counting identifiers that precede the item's 'type' field). }
  function CountNames(const ADecls: TTSNode; const AItemKind: string): Integer;
  var
    I, J     : Integer;
    Item     : TTSNode;
    TypeNode : TTSNode;
    NameId   : TTSNode;
    TypeStart: Integer;
  begin
    Result:= 0;
    if ADecls.IsNull then Exit;
    for I:= 0 to ADecls.NamedChildCount - 1 do
    begin
      Item:= ADecls.NamedChild(I);
      if Item.NodeType <> AItemKind then Continue;
      TypeNode:= Item.ChildByField('type');
      if TypeNode.IsNull then TypeStart:= MaxInt else TypeStart:= Integer(TypeNode.StartByte);
      for J:= 0 to Item.NamedChildCount - 1 do
      begin
        NameId:= Item.NamedChild(J);
        if (NameId.NodeType = 'identifier') and (Integer(NameId.StartByte) < TypeStart) then Inc(Result);
      end;
    end;
  end;

  { Deepest nesting of control structures within N. }
  { AN ELSE-IF CHAIN IS ONE LEVEL, NOT ONE LEVEL PER BRANCH.

    Delphi has no `elif`, so `if A then .. else if B then .. else if C then ..`
    can only be spelled as an if nested in the else of the previous if, and the
    grammar represents exactly that: ifElse(A, .., ifElse(B, .., ifElse(C, ..))).
    Counting one level per if-node therefore measures the SPELLING, not the
    shape of the code -- a flat dispatch table reads as a staircase.

    Measured before this change (drag-lint on its own source): ParseArgs "nests
    control structures 141 deep", Run 84. Those two routines are argument
    dispatchers -- every branch is at the same logical level and none is inside
    another. A generated chain scaled exactly 1:1: 6 branches -> 6, 8 -> 8,
    12 -> 12, 20 -> 20. At the default threshold of 5 that makes the rule fire on
    any dispatcher with six arms, which is most of them, and the advice it gives
    ("flatten with early exits") cannot be followed because there is nothing
    nested to flatten.

    So: descending into the ELSE branch does not deepen when that branch is
    itself an if -- it is the next arm of the same chain. Every other descent,
    including into the THEN branch, still deepens, which is what keeps genuine
    nesting (six ifs down the then side) firing at 6.

    Identity by StartPoint rather than node equality: two children of one parent
    cannot begin at the same row and column, and TTSNode exposes no equality
    operator. The same chain-walking shape is already used by
    DeadCodeChecks' repeated-else-if-condition check. }
  function MaxNest(const N: TTSNode; ADepth: Integer): Integer;
  var
    I, D, M    : Integer;
    Inc1       : Integer;
    ElseN, C   : TTSNode;
    ChildDepth : Integer;
  begin
    Result:= ADepth;
    if N.IsNull then Exit;
    { 'exprIf', NOT 'ifElse'. An if WITH an else parses as `exprIf` in this
      grammar; there is no `ifElse` node at all, so the old list counted the
      plain `if` form and scored the else form ZERO. One trailing else on the
      innermost statement therefore cost a whole level: a routine nested 6 deep
      measured 5 and, against the default max of 5, said nothing. Measured
      2026-08-16 with three routines side by side -- six plain ifs fired "6
      deep", seven fired "7 deep", and six whose innermost was
      `if A6 then Go1 else Go2` was SILENT.
      The dead `ifElse` branch is removed rather than kept alongside: a
      condition keyed on a node type the grammar never produces reads as
      coverage that does not exist. (Same family as the kAt/kVar/exprIf
      "keywords are NAMED nodes" bugs already fixed in this tree.)
      See docs\INBOX-deep-nesting-silent-on-trailing-else-call.md. }
    Inc1:= 0;
    if (N.NodeType = 'if') or (N.NodeType = 'exprIf') or (N.NodeType = 'while') or (N.NodeType = 'for') or (N.NodeType = 'repeat') or (N.NodeType = 'case') or
      (N.NodeType = 'with') or (N.NodeType = 'try') then Inc1:= 1;

    { The else BRANCH is the child immediately after the kElse keyword --
      exprIf's children are positional (kIf, cond, kThen, then, kElse, else) and
      expose no 'else' field, so ChildByField('else') returned null and the
      chain guard never fired even when the node type matched. Locate it by
      index instead. }
    var ElseIdx: Integer:= -1;
    if Inc1 = 1 then
      for I:= 0 to N.ChildCount - 1 do
        if N.Child(I).NodeType = 'kElse' then begin ElseIdx:= I + 1; Break; end;

    M:= ADepth;
    for I:= 0 to N.ChildCount - 1 do
    begin
      C:= N.Child(I);
      ChildDepth:= ADepth + Inc1;
      { `else if ...` is a CHAIN, not deeper nesting -- flattening it is not what
        the rule is asking for, and counting it would make any long dispatch
        chain look pathological. }
      if (I = ElseIdx) and (not C.IsNull) and
         ((C.NodeType = 'if') or (C.NodeType = 'exprIf')) then
        ChildDepth:= ADepth;   { chain continuation -- same logical level }
      D:= MaxNest(C, ChildDepth);
      if D > M then M:= D;
    end;
    Result:= M;
  end;

  procedure CheckProc(const ADefProc: TTSNode);
  var
    Hdr  : TTSNode     ;
    Args : TTSNode     ;
    Loc  : TTSNode     ;
    Body : TTSNode     ;
    Nm   : TTSNode     ;
    Name : string      ;
    NP   : Integer     ;
    NL   : Integer     ;
    Lines: Integer     ;
    Nest : Integer     ;
    HP   : TTSPoint    ;
    F    : TLintFinding;

    procedure Emit(const AId, AMsg: string);
    begin
      F:= Default(TLintFinding);
      F.RuleId  := AId;
      F.Severity:= 'info';
      F.Message := AMsg;
      F.FilePath:= AFile;
      F.StartLine:= Integer(HP.Row   ) + 1;
      F.StartCol := Integer(HP.Column) + 1;
      F.EndLine:= F.StartLine;
      F.EndCol := F.StartCol + 1;
      Findings.Add(F);
    end;

  begin
    Hdr:= ADefProc.ChildByField('header');
    if Hdr.IsNull then Exit;
    HP:= Hdr.StartPoint;
    Name:= '';
    Nm:= Hdr.ChildByField('name');
    if not Nm.IsNull then Name:= NodeStr(Nm);

    Args:= Hdr.ChildByField('args');
    NP:= CountNames(Args, 'declArg');
    if (AMaxParams > 0) and (NP > AMaxParams) then
      Emit('too-many-parameters', Format('Routine %s has %d parameters (max %d) -- consider grouping into a record', [Name, NP, AMaxParams]));

    Loc:= ADefProc.ChildByField('local');
    NL:= CountNames(Loc, 'declVar');
    if (AMaxLocals > 0) and (NL > AMaxLocals) then
      Emit('too-many-locals', Format('Routine %s declares %d local variables (max %d) -- consider extracting sub-routines', [Name, NL, AMaxLocals]));

    Body:= ADefProc.ChildByField('body');
    if not Body.IsNull then
    begin
      Lines:= Integer(Body.EndPoint.Row) - Integer(Body.StartPoint.Row) + 1;
      if (AMaxLines > 0) and (Lines > AMaxLines) then
        Emit('method-too-long', Format('Routine %s body is %d lines (max %d) -- consider breaking it up', [Name, Lines, AMaxLines]));
      Nest:= MaxNest(Body, 0);
      if (AMaxNesting > 0) and (Nest > AMaxNesting) then
        Emit('deep-nesting', Format('Routine %s nests control structures %d deep (max %d) -- flatten with early exits or sub-routines', [Name, Nest, AMaxNesting]));
    end;
  end; // procedure

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then CheckProc(N);
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckTypeAware(const AFile: string; const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
var
  Src     : TBytes                    ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>       ;
  TypeMap : TDictionary<string,string>;
  Guards  : TDictionary<string,Integer>; { v0.71: 'x|TFoo' set of 'x is TFoo' guards }
  EnumMems: TDictionary<string,TStringList>; { v0.74: same-file enum type (lower) -> member names }

  { v11 (M1): the store's resolved category for a declared type text, or
    tcUnknown when there is no store / it can't resolve (caller then falls back
    to the name heuristic). }
  function CatOf(const T: string): TTypeCategory;
  begin
    if AStore <> nil then Result:= AStore.ResolveTypeCategory(T, AFileId)
    else Result:= tcUnknown;
  end;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  function IsFloatType(const T: string): Boolean;
  var
    L: string;
  begin
    L:= LowerCase(Trim(T));
    Result:= (L = 'single') or (L = 'double') or (L = 'extended') or (L = 'real') or (L = 'real48') or (L = 'tdatetime') or (L = 'tdate') or (L = 'ttime');
  end;

  function IsInterfaceType(const T: string): Boolean;
  var
    S: string;
  begin
    S:= Trim(T);
    Result:= (Length(S) >= 2) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
  end;

  { Pointer-sized types whose value is truncated by a 32-bit cast on Win64.
    Conservative: 'Pointer' and P-prefix pointer types only (T-prefix is ambiguous --
    could be an int-sized enum/record -- so it is excluded to keep false positives low). }
  function IsPointerType(const T: string): Boolean;
  var
    S: string;
  begin
    S:= Trim(T);
    Result:= SameText(S, 'Pointer') or ((Length(S) >= 2) and (S[1] = 'P') and CharInSet(S[2], ['A'..'Z']));
  end;

  { v11 (M1): store category authoritative when known, name heuristic otherwise.
    This both catches non-conventional types (a non-I interface, an aliased float)
    and suppresses the heuristic's false positives (an I-prefixed class). }
  function TypeTextIsFloat(const T: string): Boolean;
  var C: TTypeCategory;
  begin
    C:= CatOf(T);
    if C <> tcUnknown then Result:= (C = tcFloat)
    else Result:= IsFloatType(T);
  end;

  function TypeTextIsInterface(const T: string): Boolean;
  var C: TTypeCategory;
  begin
    C:= CatOf(T);
    if C <> tcUnknown then Result:= (C = tcInterface)
    else Result:= IsInterfaceType(T);
  end;

  function TypeTextIsPointer(const T: string): Boolean;
  var C: TTypeCategory;
  begin
    C:= CatOf(T);
    if C <> tcUnknown then Result:= (C = tcPointer)
    else Result:= IsPointerType(T);
  end;

  { Intrinsic string types by name (no store needed). ShortString[n] handled via
    the 'string[' prefix. }
  function IsStringType(const T: string): Boolean;
  var
    L: string;
  begin
    L:= LowerCase(Trim(T));
    Result:= (L = 'string') or (L = 'ansistring') or (L = 'widestring')
          or (L = 'unicodestring') or (L = 'shortstring') or (L = 'utf8string')
          or (L = 'rawbytestring') or (Copy(L, 1, 7) = 'string[');
  end;

  { v0.67: operand resolves to a string -- store category authoritative when
    known, the intrinsic-string name heuristic otherwise. Backs the type-aware
    length-zero-compare: the X = '' / X <> '' suggestion is valid ONLY for strings;
    for dynamic arrays Length(X) = 0 is the idiomatic check with no clearer form. }
  function TypeTextIsString(const T: string): Boolean;
  var C: TTypeCategory;
  begin
    C:= CatOf(T);
    if C <> tcUnknown then Result:= (C = tcString)
    else Result:= IsStringType(T);
  end;

  { v0.71: a T-prefixed name that is plausibly a CLASS (reference) type -- excludes
    the well-known value/record/alias T-types where 'is'/'as' do not apply (a hard
    'value cast' like TDateTime(d) is not a downcast). Name-only heuristic for the
    no-store file-harness path; backs unsafe-typecast-without-is. When a store is
    present it is authoritative (tcClass). }
  function LooksLikeClassType(const T: string): Boolean;
  var
    S, L: string;
    C   : TTypeCategory;
  begin
    S:= Trim(T);
    Result:= (Length(S) >= 2) and (S[1] = 'T') and (S[2] >= 'A') and (S[2] <= 'Z');
    if not Result then Exit;
    C:= CatOf(S);
    if C <> tcUnknown then begin Result:= (C = tcClass); Exit; end;
    L:= LowerCase(S);
    if (L = 'tdatetime') or (L = 'tdate') or (L = 'ttime') or (L = 'tcolor')
    or (L = 'talphacolor') or (L = 'tpoint') or (L = 'tsize') or (L = 'trect')
    or (L = 'tsmallpoint') or (L = 'tguid') or (L = 'tbytes') or (L = 'tvalue')
    or (L = 'tpair') or (L = 'tdatetimefield')
    or (Copy(L, 1, 6) = 'tarray') or (Copy(L, 1, 5) = 'tproc') or (Copy(L, 1, 5) = 'tfunc') then
      Result:= False;
  end;

  { Collect declared name -> type text for vars, params and fields (flat map). }
  procedure CollectDecls(const N: TTSNode);
  var
    I, J     : Integer;
    TypeNode : TTSNode;
    NameId   : TTSNode;
    TypeStart: Integer;
    TTxt     : string ;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'declVar') or (N.NodeType = 'declArg') or (N.NodeType = 'declField') then
    begin
      TypeNode:= N.ChildByField('type');
      if not TypeNode.IsNull then
      begin
        TTxt:= Trim(NodeStr(TypeNode));
        TypeStart:= Integer(TypeNode.StartByte);
        for J:= 0 to N.NamedChildCount - 1 do
        begin
          NameId:= N.NamedChild(J);
          if (NameId.NodeType = 'identifier') and (Integer(NameId.StartByte) < TypeStart) then
          begin
            { TWO ROUTINES MAY EACH DECLARE THE SAME NAME. TypeMap is flat and
              FILE-scoped, so a plain AddOrSetValue lets whichever declaration is
              visited last decide the type for every use in the file -- including
              uses inside the OTHER routine.

              Measured: YADF.Layout.pas declares `W: string` at :1076 and
              `W: TArray<string>` at :2357. `length-zero-compare` resolved the
              array one to `string` and told the author to write `W = ''` for a
              dynamic array, which is wrong advice. It fired in all three YADF
              projects, since the unit is shared.

              A name whose declarations DISAGREE is recorded as ambiguous rather
              than as either answer. The sentinel is deliberately a type name
              nothing can match, so every type-aware rule reading TypeMap
              (string / float / interface / pointer / integer / no-op cast) fails
              safe on it at once, instead of each needing its own guard. Two
              declarations of the SAME type are not a conflict and are left
              alone. Absence over wrong -- the same rule MineReturnExpressions
              follows for a mutated Result. }
            var LowName: string:= LowerCase(NodeStr(NameId));
            var Prior  : string;
            if TypeMap.TryGetValue(LowName, Prior) and (not SameText(Prior, TTxt)) then
              TypeMap.AddOrSetValue(LowName, AMBIGUOUS_DECL_TYPE)
            else
              TypeMap.AddOrSetValue(LowName, TTxt);
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectDecls(N.NamedChild(I));
  end;

  { v0.71: collect 'x is TFoo' guards into a set of 'x|TFoo' keys (both lowercased).
    lhs must be a simple identifier; rhs is taken by source text (single token) so
    this is independent of whether the grammar labels the type node identifier/typeref.
    The operator is matched by TEXT ('is') to avoid depending on its node-kind name.
    Backs unsafe-typecast-without-is: a hard cast TFoo(x) is suppressed when some
    'x is TFoo' guard exists anywhere in the file (flat, file-scoped like TypeMap). }
  procedure CollectGuards(const N: TTSNode);
  var
    I      : Integer;
    Op, L, R: TTSNode;
    RT     : string ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'exprBinary' then
    begin
      Op:= N.ChildByField('operator');
      if (not Op.IsNull) and SameText(Trim(NodeStr(Op)), 'is') then
      begin
        L:= N.ChildByField('lhs');
        R:= N.ChildByField('rhs');
        if (not L.IsNull) and (L.NodeType = 'identifier') and (not R.IsNull) then
        begin
          RT:= Trim(NodeStr(R));
          if (RT <> '') and (Pos(' ', RT) = 0) then
            Guards.AddOrSetValue(LowerCase(NodeStr(L)) + '|' + LowerCase(RT), 1);
        end;
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do CollectGuards(N.Child(I));
  end;

  { v0.74: collect same-file enum types -> member-name lists. A declType whose
    'type' child wraps a declEnum: name = declType.name, members = each
    declEnumValue's 'name'. Backs exhaustive-enum-case on the no-store path (the
    file harness); the store supplies cross-unit enums. }
  { recursively fill AOut with declEnumValue names if M's subtree contains a
    declEnum (the declEnum may be the 'type' field directly or nested in it). }
  function FindEnumMembers(const M: TTSNode; const AOut: TStringList): Boolean;
  var
    K     : Integer;
    ValN  : TTSNode;
    VNameN: TTSNode;
    VN    : string ;
  begin
    Result:= False;
    if M.IsNull then Exit;
    if M.NodeType = 'declEnum' then
    begin
      for K:= 0 to M.NamedChildCount - 1 do
      begin
        ValN:= M.NamedChild(K);
        if ValN.NodeType = 'declEnumValue' then
        begin
          VNameN:= ValN.ChildByField('name');
          if VNameN.IsNull and (ValN.NamedChildCount >= 1) then VNameN:= ValN.NamedChild(0);
          if not VNameN.IsNull then
          begin
            VN:= Trim(NodeStr(VNameN));
            if VN <> '' then AOut.Add(VN);
          end;
        end;
      end;
      Exit(True);
    end;
    for K:= 0 to M.ChildCount - 1 do
      if FindEnumMembers(M.Child(K), AOut) then Exit(True);
  end;

  procedure CollectEnums(const N: TTSNode);
  var
    I       : Integer ;
    NameN, TypeN: TTSNode;
    Members : TStringList;
    En      : string  ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declType' then
    begin
      NameN:= N.ChildByField('name');
      TypeN:= N.ChildByField('type');
      if (not NameN.IsNull) and (not TypeN.IsNull) then
      begin
        En:= LowerCase(Trim(NodeStr(NameN)));
        if (En <> '') and (not EnumMems.ContainsKey(En)) then
        begin
          Members:= TStringList.Create;
          Members.CaseSensitive:= False;
          if FindEnumMembers(TypeN, Members) and (Members.Count > 0) then
            EnumMems.Add(En, Members)
          else
            Members.Free;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectEnums(N.NamedChild(I));
  end;

  { v0.74: enum member names for a declared type text -- the same-file map first,
    then the store (skEnum symbol -> its skEnumValue children). Returns nil when
    the type is not a known enum. The caller OWNS + frees the returned list. }
  function ResolveEnumMembers(const ATypeText: string): TStringList;
  var
    L   : string      ;
    Own : TStringList ;
  begin
    Result:= nil;
    L:= LowerCase(Trim(ATypeText));
    if L = '' then Exit;
    if EnumMems.TryGetValue(L, Own) then
    begin
      Result:= TStringList.Create; Result.CaseSensitive:= False;
      Result.AddStrings(Own);
      Exit;
    end;
    if AStore <> nil then
      for var S in AStore.FindSymbolsByExactName(Trim(ATypeText)) do
        if S.Kind = skEnum then
        begin
          Result:= TStringList.Create; Result.CaseSensitive:= False;
          for var K in AStore.FindAllChildSymbols(S.Id) do
            if K.Kind = skEnumValue then Result.Add(K.Name);
          Break;
        end;
  end;

  function OperandIsFloat(const N: TTSNode): Boolean;
  var
    T  : string;
    Txt: string;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'identifier' then
    begin
      if TypeMap.TryGetValue(LowerCase(NodeStr(N)), T) then Result:= TypeTextIsFloat(T);
    end
    else if N.NodeType = 'literalNumber' then
    begin
      Txt:= NodeStr(N);
      Result:= (Pos('.', Txt) > 0) and (Pos('$', Txt) = 0);
    end;
  end;

  { A quoted string/char literal ('...' or #NN) can never be a float, so it forces
    string/char context. Guards float-equality against the flat (no-scope) type map
    mis-resolving a same-named variable to a float -- e.g. SS = '+' where another
    routine declares SS: Double (the documented heuristic limitation). }
  function OperandIsStringLiteral(const N: TTSNode): Boolean;
  var
    Txt: string;
  begin
    Result:= False;
    if N.IsNull then Exit;
    Txt:= Trim(NodeStr(N));
    Result:= (Txt <> '') and ((Txt[1] = '''') or (Txt[1] = '#'));
  end;

  { v12 (M1): operand resolves to a string -- a string-typed identifier (via the
    store) or a quoted literal with alphabetic content. Backs the precise
    store-path string-equality built-in. (A non-alpha literal like '+' is not a
    case-sensitivity concern, matching the .scm rule's guard.) }
  function OperandIsString(const N: TTSNode): Boolean;
  var
    T, Txt: string ;
    i     : Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'identifier' then
    begin
      if TypeMap.TryGetValue(LowerCase(NodeStr(N)), T) then Result:= (CatOf(T) = tcString);
    end
    else if N.NodeType = 'literalString' then
    begin
      Txt:= NodeStr(N);
      for i:= 1 to Length(Txt) do
        if CharInSet(Txt[i], ['A'..'Z', 'a'..'z']) then Exit(True);
    end;
  end;

  procedure CheckExpr(const N: TTSNode);
  var
    I     : Integer    ;
    Op    : TTSNode    ;
    L      : TTSNode    ;
    R      : TTSNode    ;
    Entity: TTSNode    ;
    Args  : TTSNode    ;
    A0    : TTSNode    ;
    T     : string     ;
    P     : TTSPoint   ;
    F     : TLintFinding;
    Call    : TTSNode  ; // v0.67: the Length() call side of a length-zero compare
    HaveCall: Boolean  ;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    { v0.74: exhaustive-enum-case -- a 'case' on an enum-typed selector that omits
      some members AND has no 'else' silently ignores them (and any future member
      added to the enum). Selector = NamedChild(0) when it is a plain identifier;
      resolve its declared type to an enum (same-file map or store); flag the
      missing members. Bail on a range label (can't expand without ordinals). }
    if N.NodeType = 'case' then
    begin
      var HasElse: Boolean:= False;
      for var Ei:= 0 to N.ChildCount - 1 do
        if N.Child(Ei).NodeType = 'kElse' then begin HasElse:= True; Break; end;
      if not HasElse then
      begin
        { the selector is the first named child that is an expression -- skip the
          keyword tokens (kCase/kOf/...), the caseCase arms, and any else body. }
        var Selector: TTSNode:= N.ChildByField('selector');
        if Selector.IsNull then
          for var Si:= 0 to N.NamedChildCount - 1 do
          begin
            var Sc: TTSNode:= N.NamedChild(Si);
            var St: string:= Sc.NodeType;
            if (St <> 'caseCase') and (St <> 'statement') and (St <> 'statements')
               and ((Length(St) = 0) or (St[1] <> 'k')) then
            begin Selector:= Sc; Break; end;
          end;
        if (not Selector.IsNull) and (Selector.NodeType = 'identifier')
           and TypeMap.TryGetValue(LowerCase(NodeStr(Selector)), T) then
        begin
          var Members: TStringList:= ResolveEnumMembers(T);
          if Members <> nil then
          try
            var Covered: TStringList:= TStringList.Create;
            Covered.CaseSensitive:= False;
            var HasRange: Boolean:= False;
            try
              for var Ci:= 0 to N.NamedChildCount - 1 do
              begin
                var Arm: TTSNode:= N.NamedChild(Ci);
                if Arm.NodeType <> 'caseCase' then Continue;
                var Lbl: TTSNode:= Arm.ChildByField('label');
                if Lbl.IsNull then Continue;
                for var Li:= 0 to Lbl.ChildCount - 1 do
                begin
                  var Lc: TTSNode:= Lbl.Child(Li);
                  if Lc.NodeType = 'identifier' then Covered.Add(Trim(NodeStr(Lc)))
                  else if Trim(NodeStr(Lc)) = '..' then HasRange:= True;
                end;
              end;
              if not HasRange then
              begin
                var Missing: string:= '';
                for var Mi:= 0 to Members.Count - 1 do
                  if Covered.IndexOf(Members[Mi]) < 0 then
                  begin
                    if Missing <> '' then Missing:= Missing + ', ';
                    Missing:= Missing + Members[Mi];
                  end;
                if Missing <> '' then
                begin
                  P:= N.StartPoint;
                  F:= Default(TLintFinding);
                  F.RuleId  := 'exhaustive-enum-case';
                  F.Severity:= 'warning';
                  F.Message := Format('case on enum %s does not handle %s and has no else -- handle the missing value(s) or add an else', [Trim(T), Missing]);
                  F.FilePath:= AFile;
                  F.StartLine:= Integer(P.Row   ) + 1;
                  F.StartCol := Integer(P.Column) + 1;
                  F.EndLine := F.StartLine;
                  F.EndCol  := F.StartCol + 4;
                  Findings.Add(F);
                end;
              end;
            finally
              Covered.Free;
            end;
          finally
            Members.Free;
          end;
        end;
      end;
    end;
    if N.NodeType = 'exprBinary' then
    begin
      Op:= N.ChildByField('operator');
      if (not Op.IsNull) and ((Op.NodeType = 'kEq') or (Op.NodeType = 'kNeq')) then
      begin
        L:= N.ChildByField('lhs');
        R:= N.ChildByField('rhs');
        if (OperandIsFloat(L) or OperandIsFloat(R))
           and not (OperandIsStringLiteral(L) or OperandIsStringLiteral(R)) then
        begin
          P:= N.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'float-equality-comparison';
          F.Severity:= 'warning';
          F.Message := 'Floating-point values compared with = / <> -- rounding makes exact equality unreliable; use SameValue or an epsilon';
          F.FilePath:= AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine:= F.StartLine;
          F.EndCol := F.StartCol + 1;
          Findings.Add(F);
        end;
        { v12 (M1): precise string-equality (store path only, '=' as in the .scm).
          Fires only when BOTH operands resolve to a string type -- replaces the
          broad .scm rule on store-bearing paths (lint-all drops the .scm finding
          when a store is present; check-ast never runs the .scm). }
        if (AStore <> nil) and (Op.NodeType = 'kEq') and OperandIsString(L) and OperandIsString(R) then
        begin
          P:= N.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'string-equality-comparison';
          F.Severity:= 'info';
          F.Message := '''='' compares strings case-sensitively. Use SameText for case-insensitive comparison.';
          F.FilePath:= AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine:= F.StartLine;
          F.EndCol := F.StartCol + 1;
          Findings.Add(F);
        end;
      end;
      { v0.67: type-aware length-zero-compare. Length(X) compared to 0 with
        = <> > or < -- the X = empty-string suggestion is correct ONLY when X is a
        string; for a dynamic array it is wrong advice. Fire only when the Length
        argument is a simple identifier whose declared type resolves to a string
        (store-exact, or the intrinsic-string name heuristic on the no-store path). }
      if (not Op.IsNull) and ((Op.NodeType = 'kEq') or (Op.NodeType = 'kNeq') or (Op.NodeType = 'kGt') or (Op.NodeType = 'kLt')) then
      begin
        L:= N.ChildByField('lhs');
        R:= N.ChildByField('rhs');
        HaveCall:= False;
        if (not R.IsNull) and (R.NodeType = 'literalNumber') and (Trim(NodeStr(R)) = '0') and (not L.IsNull) and (L.NodeType = 'exprCall') then
        begin Call:= L; HaveCall:= True; end
        else if (not L.IsNull) and (L.NodeType = 'literalNumber') and (Trim(NodeStr(L)) = '0') and (not R.IsNull) and (R.NodeType = 'exprCall') then
        begin Call:= R; HaveCall:= True; end;
        if HaveCall then
        begin
          Entity:= Call.ChildByField('entity');
          if (not Entity.IsNull) and (Entity.NodeType = 'identifier') and SameText(NodeStr(Entity), 'Length') then
          begin
            Args:= Call.ChildByField('args');
            if (not Args.IsNull) and (Args.NamedChildCount >= 1) then
            begin
              A0:= Args.NamedChild(0);
              if (not A0.IsNull) and (A0.NodeType = 'identifier')
                 and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T)
                 and TypeTextIsString(T) then
              begin
                P:= N.StartPoint;
                F:= Default(TLintFinding);
                F.RuleId  := 'length-zero-compare';
                F.Severity:= 'info';
                F.Message := '''Length(X) = 0'' / ''> 0'' -- for strings prefer X = '''' / X <> '''' (clearer).';
                F.FilePath:= AFile;
                F.StartLine:= Integer(P.Row   ) + 1;
                F.StartCol := Integer(P.Column) + 1;
                F.EndLine:= F.StartLine;
                F.EndCol := F.StartCol + 1;
                Findings.Add(F);
              end;
            end;
          end;
        end;
      end;
    end;
    if N.NodeType = 'exprCall' then
    begin
      Entity:= N.ChildByField('entity');
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') and SameText(NodeStr(Entity), 'FreeAndNil') then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount >= 1) then
        begin
          A0:= Args.NamedChild(0);
          if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) and TypeTextIsInterface(T) then
          begin
            P:= Entity.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'freeandnil-on-interface';
            F.Severity:= 'warning';
            F.Message := Format('FreeAndNil on interface-typed %s -- interfaces are reference-counted; assign nil instead of freeing', [NodeStr(A0)]);
            F.FilePath:= AFile;
            F.StartLine:= Integer(P.Row   ) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine:= F.StartLine;
            F.EndCol := F.StartCol + 1;
            Findings.Add(F);
          end;
        end;
      end;
      { v0.52: a 32-bit cast (Integer/Cardinal/LongInt/LongWord) of a pointer-typed
        value truncates on Win64 -- use NativeInt/NativeUInt. }
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        var Cn: string:= LowerCase(NodeStr(Entity));
        if (Cn = 'integer') or (Cn = 'cardinal') or (Cn = 'longint') or (Cn = 'longword') then
        begin
          Args:= N.ChildByField('args');
          if (not Args.IsNull) and (Args.NamedChildCount >= 1) then
          begin
            A0:= Args.NamedChild(0);
            if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) and TypeTextIsPointer(T) then
            begin
              P:= Entity.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'win64-pointer-cast';
              F.Severity:= 'warning';
              F.Message := Format('32-bit cast (%s) of pointer-typed %s -- truncates on Win64; use NativeInt/NativeUInt', [NodeStr(Entity), NodeStr(A0)]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(P.Row   ) + 1;
              F.StartCol := Integer(P.Column) + 1;
              F.EndLine:= F.StartLine;
              F.EndCol := F.StartCol + 1;
              Findings.Add(F);
            end;
          end;
        end;
      end;
      { v0.76 nativeint-truncation (#9): a 32-bit cast (Integer/Cardinal/LongInt/
        LongWord) of a NativeInt/NativeUInt/pointer-sized-integer value. NativeInt is
        64-bit on Win64, so the cast silently drops the high 32 bits -- use NativeInt/
        NativeUInt (or Int64) for the result. Distinct from win64-pointer-cast (which
        fires on true pointer types); this covers the integer pointer-sized family. }
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        var Cn: string:= LowerCase(NodeStr(Entity));
        if (Cn = 'integer') or (Cn = 'cardinal') or (Cn = 'longint') or (Cn = 'longword') then
        begin
          Args:= N.ChildByField('args');
          if (not Args.IsNull) and (Args.NamedChildCount >= 1) then
          begin
            A0:= Args.NamedChild(0);
            if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) then
            begin
              var Tl: string:= LowerCase(Trim(T));
              if (Tl = 'nativeint') or (Tl = 'nativeuint') or (Tl = 'intptr') or (Tl = 'uintptr')
                 or (Tl = 'ptrint') or (Tl = 'ptruint') then
              begin
                P:= Entity.StartPoint;
                F:= Default(TLintFinding);
                F.RuleId  := 'nativeint-truncation';
                F.Severity:= 'warning';
                F.Message := Format('32-bit cast (%s) of NativeInt-sized %s -- truncates the high 32 bits on Win64; use NativeInt/NativeUInt or Int64.', [NodeStr(Entity), NodeStr(A0)]);
                F.FilePath:= AFile;
                F.StartLine:= Integer(P.Row   ) + 1;
                F.StartCol := Integer(P.Column) + 1;
                F.EndLine := F.StartLine;
                F.EndCol  := F.StartCol + Length(NodeStr(Entity));
                Findings.Add(F);
              end;
            end;
          end;
        end;
      end;
      { v0.71: redundant-cast -- 'TFoo(x)' where x is declared EXACTLY TFoo (per
        the per-file TypeMap) is a no-op cast. T-prefixed class-like entity only
        (avoids scalar-cast noise), single identifier argument only. Pure-AST via
        the type map -> near-zero FP (an exact declared-type match to the cast
        target is not a protected-member hack, which needs a base-typed operand). }
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        var En: string:= NodeStr(Entity);
        if (Length(En) >= 2) and (En[1] = 'T') and (En[2] >= 'A') and (En[2] <= 'Z') then
        begin
          Args:= N.ChildByField('args');
          if (not Args.IsNull) and (Args.NamedChildCount = 1) then
          begin
            A0:= Args.NamedChild(0);
            if (A0.NodeType = 'identifier')
               and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T)
               and SameText(Trim(T), En) then
            begin
              P:= Entity.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'redundant-cast';
              F.Severity:= 'hint';
              F.Message := Format('Redundant cast: %s is already of type %s', [NodeStr(A0), En]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(P.Row   ) + 1;
              F.StartCol := Integer(P.Column) + 1;
              F.EndLine := F.StartLine;
              F.EndCol  := F.StartCol + Length(En);
              Findings.Add(F);
            end;
          end;
        end;
      end;
      { v0.71: unsafe-typecast-without-is (OFF by default) -- a hard cast TFoo(x) of
        an object reference to a DIFFERENT class, with no guarding 'x is TFoo'. If x
        is not really a TFoo at run time the cast crashes/corrupts. Pure-AST cannot
        prove the run-time type, so this is a heuristic: fire only when both target
        and operand are plausible class types (x declared TObject or a *different*
        T-class -> a genuine down/cross-cast), never for value/record casts, the
        redundant exact-type case, or a TObject upcast. Still FP-prone (many
        unguarded casts are provably safe to the author) -> ships OFF; opt in via
        drag-lint-lint.json "enabled" or --rule unsafe-typecast-without-is. }
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        var Un: string:= NodeStr(Entity);
        if LooksLikeClassType(Un) and not SameText(Un, 'TObject') then
        begin
          Args:= N.ChildByField('args');
          if (not Args.IsNull) and (Args.NamedChildCount = 1) then
          begin
            A0:= Args.NamedChild(0);
            if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) then
            begin
              var Xn: string:= NodeStr(A0);
              if (SameText(Trim(T), 'TObject') or (LooksLikeClassType(T) and not SameText(Trim(T), Un)))
                 and not Guards.ContainsKey(LowerCase(Xn) + '|' + LowerCase(Un)) then
              begin
                P:= Entity.StartPoint;
                F:= Default(TLintFinding);
                F.RuleId  := 'unsafe-typecast-without-is';
                F.Severity:= 'warning';
                F.Message := Format('Unchecked hard cast %s(%s) -- no ''%s is %s'' guard; a wrong run-time type crashes or corrupts. Guard with ''is'' or use the ''as'' operator.', [Un, Xn, Xn, Un]);
                F.FilePath:= AFile;
                F.StartLine:= Integer(P.Row   ) + 1;
                F.StartCol := Integer(P.Column) + 1;
                F.EndLine := F.StartLine;
                F.EndCol  := F.StartCol + Length(Un);
                Findings.Add(F);
              end;
            end;
          end;
        end;
      end;
      { v0.75 lossy-cast (#4): an Ansi-narrowing cast of a Unicode-string operand
        drops characters outside the active code page (compiler W1057). Fires on an
        Ansi-family cast (AnsiString/AnsiChar/ShortString/RawByteString) of a single
        identifier whose declared type is a Unicode string. }
      if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        var Cn: string:= LowerCase(NodeStr(Entity));
        if (Cn = 'ansistring') or (Cn = 'ansichar') or (Cn = 'shortstring') or (Cn = 'rawbytestring') then
        begin
          Args:= N.ChildByField('args');
          if (not Args.IsNull) and (Args.NamedChildCount = 1) then
          begin
            A0:= Args.NamedChild(0);
            if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) then
            begin
              var Tl: string:= LowerCase(Trim(T));
              if (Tl = 'string') or (Tl = 'unicodestring') or (Tl = 'widestring') or (Tl = 'widechar') then
              begin
                P:= Entity.StartPoint;
                F:= Default(TLintFinding);
                F.RuleId  := 'lossy-cast';
                F.Severity:= 'info';
                F.Message := Format('%s(%s) narrows a Unicode string to Ansi -- characters outside the active code page are lost (W1057).', [NodeStr(Entity), NodeStr(A0)]);
                F.FilePath:= AFile;
                F.StartLine:= Integer(P.Row   ) + 1;
                F.StartCol := Integer(P.Column) + 1;
                F.EndLine := F.StartLine;
                F.EndCol  := F.StartCol + Length(NodeStr(Entity));
                Findings.Add(F);
              end;
            end;
          end;
        end;
      end;
    end;
    { v0.76 abstract-method-instantiation (#5, store-backed): a constructor call
      'TFoo.Create' (with or without parens -- both surface the exprDot 'TFoo.Create')
      where TFoo or a class ancestor declares an abstract method that has NO concrete
      override anywhere in the hierarchy. Instantiating such a class and calling that
      method raises EAbstractError (compiler W1020). Needs the store to see methods +
      ancestors across units. }
    if (AStore <> nil) and (N.NodeType = 'exprDot') then
    begin
      var Rhs: TTSNode:= N.ChildByField('rhs');
      var Lhs: TTSNode:= N.ChildByField('lhs');
      if (not Rhs.IsNull) and (not Lhs.IsNull) and (Lhs.NodeType = 'identifier')
         and SameText(Trim(NodeStr(Rhs)), 'Create') then
      begin
        var ClsName: string:= Trim(NodeStr(Lhs));
        var ClsSym : TSymbol; var Found: Boolean:= False;
        for var Sy in AStore.FindSymbolsByExactName(ClsName) do
          if Sy.Kind = skClass then begin ClsSym:= Sy; Found:= True; Break; end;
        if Found then
        begin
          var AbstractNames: TStringList:= TStringList.Create;
          var ConcreteNames: TStringList:= TStringList.Create;
          var ClassIds     : TList<Int64>:= TList<Int64>.Create;
          try
            AbstractNames.CaseSensitive:= False; AbstractNames.Sorted:= False;
            ConcreteNames.CaseSensitive:= False;
            ClassIds.Add(ClsSym.Id);
            for var Anc in AStore.GetTransitiveAncestors(ClsSym.Id) do
              if (Anc.SymbolId > 0) and SameText(Anc.Kind, 'class') then ClassIds.Add(Anc.SymbolId);
            for var Cid in ClassIds do
              for var M in AStore.FindAllChildSymbols(Cid) do
                if (M.Kind = skMethod) or (M.Kind = skProcedure) or (M.Kind = skFunction) then
                begin
                  { The store records visibility ('public') in Modifiers, not the
                    virtual/abstract directive -- so detect an abstract method by its
                    shape instead: a VIRTUAL method with NO implementation body
                    (ImplStartLine = 0). A concrete method (any body) overrides it. }
                  if M.IsVirtual and (M.ImplStartLine = 0) then
                  begin if AbstractNames.IndexOf(M.Name) < 0 then AbstractNames.Add(M.Name); end
                  else if M.ImplStartLine > 0 then
                  begin if ConcreteNames.IndexOf(M.Name) < 0 then ConcreteNames.Add(M.Name); end;
                end;
            var Unimpl: string:= '';
            for var AName in AbstractNames do
              if ConcreteNames.IndexOf(AName) < 0 then
              begin
                if Unimpl <> '' then Unimpl:= Unimpl + ', ';
                Unimpl:= Unimpl + AName;
              end;
            if Unimpl <> '' then
            begin
              P:= Lhs.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'abstract-method-instantiation';
              F.Severity:= 'warning';
              F.Message := Format('%s.Create instantiates a class with unimplemented abstract method(s): %s -- calling one raises EAbstractError.', [ClsName, Unimpl]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(P.Row   ) + 1;
              F.StartCol := Integer(P.Column) + 1;
              F.EndLine := F.StartLine;
              F.EndCol  := F.StartCol + Length(ClsName);
              Findings.Add(F);
            end;
          finally
            ClassIds.Free; AbstractNames.Free; ConcreteNames.Free;
          end;
        end;
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do CheckExpr(N.Child(I));
  end;

  { v0.82 (#4 first cut): interface-object-mixing (OFF) -- the ARC/manual
    dual-handle double-free, restricted to a NARROW, low-FP SAME-ROUTINE slice.
    Within ONE routine body detect the co-occurrence of BOTH:
      (a) an object local X (class-typed) aliased into an interface-typed var
          I in the same routine -- 'I := X' or 'I := X as ISomething'; AND
      (b) that same X manually freed in that routine -- 'X.Free' / 'FreeAndNil(X)'.
    When X has both an interface alias (refcount lifetime) and a manual free,
    the object is double-freed once the last interface reference drops. Fire at
    the manual-free site, 'info'. If only (a) OR only (b) is present we do NOT
    fire (a plain object create+free, or a lone interface assignment, is fine) --
    that single-handle exclusion is the whole point of the narrow slice. Pure-AST,
    same-routine, reusing TypeMap/TypeTextIsInterface/LooksLikeClassType; accepts
    the flat-TypeMap type approximation (same limitation freeandnil-on-interface
    tolerates). }
  procedure VisitDualHandle(const ADefProc: TTSNode);
  var
    Aliased : TDictionary<string, string>;  { X (lower) -> X's original-case source text, aliased into an interface var }
    FreedAt : TDictionary<string, TTSNode>; { X (lower) -> the manual-free node (fire site) }

    { 'I := X' / 'I := X as ISomething' where I is interface-typed and X is a
      simple class-typed identifier -> record X (lower key, original-case
      value) in Aliased. }
    procedure ScanAlias(const N: TTSNode);
    var
      Lhs, Rhs, Src2: TTSNode;
      TI, TX, Xn    : string ;
      I             : Integer;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'defProc' then Exit; { nested routine handled separately }
      if N.NodeType = 'assignment' then
      begin
        Lhs:= N.ChildByField('lhs');
        Rhs:= N.ChildByField('rhs');
        if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') and (not Rhs.IsNull)
           and TypeMap.TryGetValue(LowerCase(NodeStr(Lhs)), TI) and TypeTextIsInterface(TI) then
        begin
          { RHS is either a bare identifier X, or 'X as ISomething' (exprBinary,
            operator text 'as', lhs = identifier X). }
          Src2:= Default(TTSNode);
          if Rhs.NodeType = 'identifier' then Src2:= Rhs
          else if Rhs.NodeType = 'exprBinary' then
          begin
            var OpN: TTSNode:= Rhs.ChildByField('operator');
            if (not OpN.IsNull) and SameText(Trim(NodeStr(OpN)), 'as') then
            begin
              var Ln: TTSNode:= Rhs.ChildByField('lhs');
              if (not Ln.IsNull) and (Ln.NodeType = 'identifier') then Src2:= Ln;
            end;
          end;
          if (not Src2.IsNull) and (Src2.NodeType = 'identifier') then
          begin
            Xn:= LowerCase(NodeStr(Src2));
            { X must be a declared CLASS-typed local (an object handle), not itself
              an interface -- that is what makes it a genuine dual handle. }
            if TypeMap.TryGetValue(Xn, TX) and LooksLikeClassType(TX) and (not TypeTextIsInterface(TX)) then
              Aliased.AddOrSetValue(Xn, NodeStr(Src2));
          end;
        end;
      end;
      for I:= 0 to N.ChildCount - 1 do ScanAlias(N.Child(I));
    end;

    { 'X.Free' (exprDot) or 'FreeAndNil(X)' (exprCall) -> record X (lower) -> node. }
    procedure ScanFree(const N: TTSNode);
    var
      Lhs, Rhs, Ent, Args, A0: TTSNode;
      I                      : Integer;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'defProc' then Exit; { nested routine handled separately }
      if N.NodeType = 'exprDot' then
      begin
        Lhs:= N.ChildByField('lhs');
        Rhs:= N.ChildByField('rhs');
        if (not Lhs.IsNull) and (not Rhs.IsNull) and (Lhs.NodeType = 'identifier')
           and (Rhs.NodeType = 'identifier') and SameText(NodeStr(Rhs), 'Free') then
          if not FreedAt.ContainsKey(LowerCase(NodeStr(Lhs))) then
            FreedAt.Add(LowerCase(NodeStr(Lhs)), N);
      end
      else if N.NodeType = 'exprCall' then
      begin
        Ent:= N.ChildByField('entity');
        if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and SameText(NodeStr(Ent), 'FreeAndNil') then
        begin
          Args:= N.ChildByField('args');
          if (not Args.IsNull) and (Args.NamedChildCount >= 1) then
          begin
            A0:= Args.NamedChild(0);
            if (A0.NodeType = 'identifier') and not FreedAt.ContainsKey(LowerCase(NodeStr(A0))) then
              FreedAt.Add(LowerCase(NodeStr(A0)), N);
          end;
        end;
      end;
      for I:= 0 to N.ChildCount - 1 do ScanFree(N.Child(I));
    end;

  var
    Body    : TTSNode     ;
    Pair    : TPair<string, TTSNode>;
    P       : TTSPoint    ;
    F       : TLintFinding;
    OrigName: string      ;
  begin
    Body:= ADefProc.ChildByField('body');
    if Body.IsNull then Exit;
    Aliased:= TDictionary<string, string>.Create;
    FreedAt:= TDictionary<string, TTSNode>.Create;
    try
      ScanAlias(Body);
      ScanFree (Body);
      for Pair in FreedAt do
        if Aliased.TryGetValue(Pair.Key, OrigName) then
        begin
          P:= Pair.Value.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'interface-object-mixing';
          F.Severity:= 'info';
          F.Message := Format('%s is both aliased into an interface (reference-counted lifetime) and manually freed in the same routine -- a dual handle risks a double free when the last interface reference drops. Keep it purely an object OR purely an interface.', [OrigName]);
          F.FilePath:= AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine := F.StartLine;
          F.EndCol  := F.StartCol + 1;
          Findings.Add(F);
        end;
    finally
      FreedAt.Free;
      Aliased.Free;
    end;
  end;

  procedure VisitProcsDualHandle(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then VisitDualHandle(N);
    for I:= 0 to N.NamedChildCount - 1 do VisitProcsDualHandle(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  TypeMap := TDictionary<string,string>.Create;
  Guards  := TDictionary<string,Integer>.Create;
  EnumMems:= TDictionary<string,TStringList>.Create;
  try

    if PF.Tree <> nil then
    begin
      CollectDecls (PF.Tree.RootNode);
      CollectGuards(PF.Tree.RootNode);
      CollectEnums (PF.Tree.RootNode);
      CheckExpr    (PF.Tree.RootNode);
      VisitProcsDualHandle(PF.Tree.RootNode); { v0.82 #4 first cut (OFF): interface-object-mixing }
    end;
    Result:= Findings.ToArray;
  finally
    for var Ml in EnumMems.Values do Ml.Free;
    EnumMems.Free;
    Guards.Free;
    TypeMap.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckFireDacSqlMismatch(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Recognize 'X.SQL.Text := ''<sql>''' and return X (lowercased) + 'select'/'dml'. }
  function MatchSqlTextAssign(const ANode: TTSNode; out AVar, AKind: string): Boolean;
  var
    Lhs, Inner, V, Rhs: TTSNode;
    Lit, Up           : string ;
  begin
    Result:= False;
    if ANode.NodeType <> 'assignment' then Exit;
    Lhs:= ANode.ChildByField('lhs');
    if Lhs.IsNull or (Lhs.NodeType <> 'exprDot') then Exit;
    if not SameText(NodeStr(Lhs.ChildByField('rhs')), 'Text') then Exit;
    Inner:= Lhs.ChildByField('lhs');
    if Inner.IsNull or (Inner.NodeType <> 'exprDot') then Exit;
    if not SameText(NodeStr(Inner.ChildByField('rhs')), 'SQL') then Exit;
    V:= Inner.ChildByField('lhs');
    if V.IsNull or (V.NodeType <> 'identifier') then Exit;
    Rhs:= ANode.ChildByField('rhs');
    if Rhs.IsNull or (Rhs.NodeType <> 'literalString') then Exit;
    Lit:= NodeStr(Rhs);
    if (Length(Lit) >= 2) and (Lit[1] = '''') and (Lit[Length(Lit)] = '''') then Lit:= Copy(Lit, 2, Length(Lit) - 2);
    Up:= UpperCase(TrimLeft(Lit));
    if Up.StartsWith('SELECT') or Up.StartsWith('WITH ') then AKind:= 'select'
    else if Up.StartsWith('INSERT') or Up.StartsWith('UPDATE') or Up.StartsWith('DELETE') or Up.StartsWith('MERGE') then AKind:= 'dml'
    else Exit;
    AVar:= LowerCase(NodeStr(V));
    Result:= True;
  end;

  { Recognize 'X.Open' / 'X.ExecSQL' (the exprDot form). }
  function MatchCall(const ANode: TTSNode; out AVar, AMethod: string): Boolean;
  var
    V, M: TTSNode;
    Mn  : string ;
  begin
    Result:= False;
    if ANode.NodeType <> 'exprDot' then Exit;
    V:= ANode.ChildByField('lhs');
    M:= ANode.ChildByField('rhs');
    if V.IsNull or M.IsNull or (V.NodeType <> 'identifier') or (M.NodeType <> 'identifier') then Exit;
    Mn:= NodeStr(M);
    if SameText(Mn, 'Open') or SameText(Mn, 'ExecSQL') then
    begin
      AVar   := LowerCase(NodeStr(V));
      AMethod:= LowerCase(Mn);
      Result := True;
    end;
  end;

  procedure WalkBody(const N: TTSNode; AMap: TDictionary<string, string>);
  var
    I        : Integer    ;
    V, K, M  : string     ;
    Kind     : string     ;
    P        : TTSPoint   ;
    F        : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then Exit; { nested routine handled separately }
    if (N.NodeType = 'assignment') and MatchSqlTextAssign(N, V, K) then AMap.AddOrSetValue(V, K)
    else if (N.NodeType = 'exprDot') and MatchCall(N, V, M) then
    begin
      if AMap.TryGetValue(V, Kind) then
        if ((M = 'open') and (Kind = 'dml')) or ((M = 'execsql') and (Kind = 'select')) then
        begin
          P:= N.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'firedac-open-execsql-mismatch';
          F.Severity:= 'warning';
          if M = 'open' then F.Message:= 'Open on a data-modifying statement (INSERT/UPDATE/DELETE) -- use ExecSQL; Open expects a result set'
          else F.Message:= 'ExecSQL on a SELECT -- use Open to fetch the result set; ExecSQL discards it';
          F.FilePath:= AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine:= F.StartLine;
          F.EndCol := F.StartCol + 1;
          Findings.Add(F);
        end;
    end;
    for I:= 0 to N.ChildCount - 1 do WalkBody(N.Child(I), AMap);
  end; // procedure

  procedure VisitProcs(const N: TTSNode);
  var
    I   : Integer                     ;
    Body: TTSNode                     ;
    Map : TDictionary<string, string> ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      if not Body.IsNull then
      begin
        Map:= TDictionary<string, string>.Create;
        try
          WalkBody(Body, Map);
        finally
          Map.Free;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckUnprotectedFree(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;
  Locals  : TDictionary<string, Boolean>; { the current routine's declared local var names }

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { 'X := <something>.Create[...]' (paren or no-paren) -> returns lowercased X. }
  function IsConstruction(const ANode: TTSNode; out AVar: string): Boolean;
  var
    Lhs, Rhs, Ent, Mth: TTSNode;
    HasMth            : Boolean;
  begin
    Result:= False;
    if ANode.NodeType <> 'assignment' then Exit;
    Lhs:= ANode.ChildByField('lhs');
    if Lhs.IsNull or (Lhs.NodeType <> 'identifier') then Exit;
    Rhs:= ANode.ChildByField('rhs');
    if Rhs.IsNull then Exit;
    HasMth:= False;
    if Rhs.NodeType = 'exprDot' then
    begin
      Mth:= Rhs.ChildByField('rhs');
      HasMth:= True;
    end
    else if Rhs.NodeType = 'exprCall' then
    begin
      Ent:= Rhs.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then
      begin
        Mth:= Ent.ChildByField('rhs');
        HasMth:= True;
      end;
    end;
    if (not HasMth) or Mth.IsNull or (Mth.NodeType <> 'identifier') then Exit;
    if not UpperCase(NodeStr(Mth)).StartsWith('CREATE') then Exit;
    AVar:= LowerCase(NodeStr(Lhs));
    Result:= True;
  end;

  { 'X.Free' (exprDot) or 'FreeAndNil(X)' (exprCall) -> returns lowercased X. }
  function IsFree(const ANode: TTSNode; out AVar: string): Boolean;
  var
    Lhs, Rhs, Ent, Args, A0: TTSNode;
  begin
    Result:= False;
    if ANode.NodeType = 'exprDot' then
    begin
      Lhs:= ANode.ChildByField('lhs');
      Rhs:= ANode.ChildByField('rhs');
      if (not Lhs.IsNull) and (not Rhs.IsNull) and (Lhs.NodeType = 'identifier') and (Rhs.NodeType = 'identifier') and SameText(NodeStr(Rhs), 'Free') then
      begin
        AVar:= LowerCase(NodeStr(Lhs));
        Result:= True;
      end;
    end
    else if ANode.NodeType = 'exprCall' then
    begin
      Ent:= ANode.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and SameText(NodeStr(Ent), 'FreeAndNil') then
      begin
        Args:= ANode.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount >= 1) then
        begin
          A0:= Args.NamedChild(0);
          if A0.NodeType = 'identifier' then
          begin
            AVar:= LowerCase(NodeStr(A0));
            Result:= True;
          end;
        end;
      end;
    end;
  end;

  { Populate ASet with the routine's declared local var names (the 'local' declVars
    block). Used to restrict the rule to LOCALS -- class fields, Result, and params
    are not in here, so created-and-freed fields/Result are not flagged (FP-7). }
  procedure CollectLocals(const ADefProc: TTSNode; ASet: TDictionary<string, Boolean>);
  var
    Loc, Item, NameId, TypeNode: TTSNode;
    I, J, TypeStart            : Integer;
  begin
    Loc:= ADefProc.ChildByField('local');
    if Loc.IsNull then Exit;
    for I:= 0 to Loc.NamedChildCount - 1 do
    begin
      Item:= Loc.NamedChild(I);
      if Item.NodeType <> 'declVar' then Continue;
      TypeNode:= Item.ChildByField('type');
      if TypeNode.IsNull then TypeStart:= MaxInt else TypeStart:= Integer(TypeNode.StartByte);
      for J:= 0 to Item.NamedChildCount - 1 do
      begin
        NameId:= Item.NamedChild(J);
        if (NameId.NodeType = 'identifier') and (Integer(NameId.StartByte) < TypeStart) then
          ASet.AddOrSetValue(LowerCase(NodeStr(NameId)), True);
      end;
    end;
  end;

  procedure WalkBody(const N: TTSNode; AInFinally: Boolean; AConstructed: TDictionary<string, Boolean>);
  var
    I  : Integer    ;
    V  : string     ;
    Lf : Boolean    ;
    C  : TTSNode    ;
    P  : TTSPoint   ;
    F  : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then Exit; { nested routine handled separately }
    if (N.NodeType = 'assignment') and IsConstruction(N, V) then AConstructed.AddOrSetValue(V, True)
    else if (not AInFinally) and IsFree(N, V) and (V <> 'result') and Locals.ContainsKey(V) and AConstructed.ContainsKey(V) then
    begin
      P:= N.StartPoint;
      F:= Default(TLintFinding);
      F.RuleId  := 'unprotected-object-free';
      F.Severity:= 'warning';
      F.Message := Format('Object %s is created and freed without try-finally -- it leaks if code in between raises; wrap creation and use in try..finally', [V]);
      F.FilePath:= AFile;
      F.StartLine:= Integer(P.Row   ) + 1;
      F.StartCol := Integer(P.Column) + 1;
      F.EndLine:= F.StartLine;
      F.EndCol := F.StartCol + 1;
      Findings.Add(F);
    end;
    if N.NodeType = 'try' then
    begin
      Lf:= False;
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        { both finally AND except are protected/cleanup regions -- a Free there is
          not an unprotected leak (FP-7: free-in-except then re-raise is the idiom). }
        if (C.NodeType = 'kFinally') or (C.NodeType = 'kExcept') then Lf:= True;
        WalkBody(C, AInFinally or Lf, AConstructed);
      end;
    end
    else
      for I:= 0 to N.ChildCount - 1 do WalkBody(N.Child(I), AInFinally, AConstructed);
  end; // procedure

  procedure VisitProcs(const N: TTSNode);
  var
    I   : Integer                    ;
    Body: TTSNode                    ;
    Con : TDictionary<string, Boolean>;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      if not Body.IsNull then
      begin
        Con   := TDictionary<string, Boolean>.Create;
        Locals:= TDictionary<string, Boolean>.Create;
        try
          CollectLocals(N, Locals);
          WalkBody(Body, False, Con);
        finally
          Con.Free;
          Locals.Free;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

type
  TCycNode = record
    Disp : string         ; { display class name }
    Path : string         ;
    Line : Integer        ;
    Col  : Integer        ;
    Holds: TArray<string> ; { lowercased interface names held via fields }
  end;

class function TAstChecker.CheckInterfaceCycles(const AFiles: TArray<string>): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>             ;
  Nodes   : TDictionary<string, TCycNode>  ; { classLower -> node }
  ImplBy  : TDictionary<string, TStringList>; { intfLower -> classLowers implementing it }
  Seen    : TDictionary<string, Boolean>   ; { reported "a|b" pairs }
  Path    : string                         ;
  Key     : string                         ;
  Node    : TCycNode                        ;
  Ix      : string                         ;
  L       : TStringList                     ;
  K       : Integer                        ;
  BLow    : string                         ;
  F       : TLintFinding                    ;

  function IsIntfName(const S: string): Boolean;
  begin
    Result:= (Length(S) >= 2) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
  end;

  function LeadIdent(const S: string): string;
  var
    T: string ;
    I: Integer;
  begin
    T:= Trim(S);
    I:= 1;
    while (I <= Length(T)) and CharInSet(T[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(I);
    Result:= Copy(T, 1, I - 1);
  end;

  procedure AddImpl(const AIntf, AClass: string);
  var
    Lst: TStringList;
  begin
    if not ImplBy.TryGetValue(AIntf, Lst) then
    begin
      Lst:= TStringList.Create;
      ImplBy.Add(AIntf, Lst);
    end;
    if Lst.IndexOf(AClass) < 0 then Lst.Add(AClass);
  end;

  procedure ExtractFile(const APath: string);
  var
    Src   : TBytes   ;
    PF    : TParsedFile;

    function NodeStr(const N: TTSNode): string;
    var
      S, E, Ln: Integer;
    begin
      Result:= '';
      if N.IsNull then Exit;
      S:= Integer(N.StartByte); E:= Integer(N.EndByte); Ln:= E - S;
      if (Ln <= 0) or (S < 0) or (E > Length(Src)) then Exit;
      Result:= TEncoding.UTF8.GetString(Src, S, Ln);
    end;

    procedure CollectFields(const N: TTSNode; AHolds: TList<string>);
    var
      I  : Integer;
      Tn : TTSNode;
      Nm : string ;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'declField' then
      begin
        Tn:= N.ChildByField('type');
        if not Tn.IsNull then
        begin
          Nm:= LeadIdent(NodeStr(Tn));
          if IsIntfName(Nm) then AHolds.Add(LowerCase(Nm));
        end;
      end;
      for I:= 0 to N.NamedChildCount - 1 do CollectFields(N.NamedChild(I), AHolds);
    end;

    procedure HandleClass(const ADeclType: TTSNode);
    var
      NameN, TypeN, Cls, Ch: TTSNode      ;
      I                    : Integer      ;
      FoundCls             : Boolean      ;
      Disp, Low, P         : string       ;
      Holds                : TList<string>;
      N2                   : TCycNode      ;
      Pt                   : TTSPoint     ;
    begin
      NameN:= ADeclType.ChildByField('name');
      TypeN:= ADeclType.ChildByField('type');
      if NameN.IsNull or TypeN.IsNull then Exit;
      FoundCls:= False;
      if TypeN.NodeType = 'declClass' then begin Cls:= TypeN; FoundCls:= True; end
      else
        for I:= 0 to TypeN.ChildCount - 1 do
          if TypeN.Child(I).NodeType = 'declClass' then begin Cls:= TypeN.Child(I); FoundCls:= True; Break; end;
      if not FoundCls then Exit;
      Disp:= NodeStr(NameN);
      Low := LowerCase(Disp);
      if Low = '' then Exit;
      { implemented interfaces = direct typeref children with an I-prefix name }
      for I:= 0 to Cls.ChildCount - 1 do
      begin
        Ch:= Cls.Child(I);
        if Ch.NodeType = 'typeref' then
        begin
          P:= LeadIdent(NodeStr(Ch));
          if IsIntfName(P) then AddImpl(LowerCase(P), Low);
        end;
      end;
      Holds:= TList<string>.Create;
      try
        CollectFields(Cls, Holds);
        N2.Disp := Disp;
        N2.Path := APath;
        Pt:= NameN.StartPoint;
        N2.Line := Integer(Pt.Row) + 1;
        N2.Col  := Integer(Pt.Column) + 1;
        N2.Holds:= Holds.ToArray;
      finally
        Holds.Free;
      end;
      Nodes.AddOrSetValue(Low, N2);
    end;

    procedure Walk(const N: TTSNode);
    var
      I: Integer;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'declType' then HandleClass(N);
      for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
    end;

  begin
    if not TFile.Exists(APath) then Exit;
    PF:= TAstParseCache.Get(APath);
    if PF.Tree = nil then Exit;
    Src:= PF.Src;
    Walk(PF.Tree.RootNode);
  end; // ExtractFile

  { does class AFrom hold an interface implemented by class ATo? }
  function HoldsImplementedBy(const AFrom, ATo: string): Boolean;
  var
    Nd : TCycNode  ;
    H  : string    ;
    Lst: TStringList;
  begin
    Result:= False;
    if not Nodes.TryGetValue(AFrom, Nd) then Exit;
    for H in Nd.Holds do
      if ImplBy.TryGetValue(H, Lst) and (Lst.IndexOf(ATo) >= 0) then Exit(True);
  end;

begin
  Result:= nil;
  Findings:= TList<TLintFinding>.Create;
  Nodes   := TDictionary<string, TCycNode>.Create;
  ImplBy  := TDictionary<string, TStringList>.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  try
    for Path in AFiles do
      if (SameText(ExtractFileExt(Path), '.pas')) or (SameText(ExtractFileExt(Path), '.inc')) then ExtractFile(Path);

    for Key in Nodes.Keys do
    begin
      Node:= Nodes[Key];
      for Ix in Node.Holds do
      begin
        if not ImplBy.TryGetValue(Ix, L) then Continue;
        for K:= 0 to L.Count - 1 do
        begin
          BLow:= L[K];
          if BLow = Key then Continue;                 { self-reference, not a cycle }
          if not Nodes.ContainsKey(BLow) then Continue;
          if not HoldsImplementedBy(BLow, Key) then Continue; { B must also hold an interface A implements }
          { dedup the unordered pair }
          if Key < BLow then
          begin
            if Seen.ContainsKey(Key + '|' + BLow) then Continue;
            Seen.Add(Key + '|' + BLow, True);
          end
          else
          begin
            if Seen.ContainsKey(BLow + '|' + Key) then Continue;
            Seen.Add(BLow + '|' + Key, True);
          end;
          F:= Default(TLintFinding);
          F.RuleId  := 'interface-reference-cycle';
          F.Severity:= 'warning';
          F.Message := Format('Interface reference cycle: %s and %s each hold an interface the other implements -- under ARC this leaks; mark one side''s field [weak] or [unsafe]', [Node.Disp, Nodes[BLow].Disp]);
          F.FilePath:= Node.Path;
          F.StartLine:= Node.Line;
          F.StartCol := Node.Col;
          F.EndLine:= Node.Line;
          F.EndCol := Node.Col + Length(Node.Disp);
          Findings.Add(F);
          if Findings.Count >= 200 then Break;
        end;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    for L in ImplBy.Values do L.Free;
    Seen.Free;
    ImplBy.Free;
    Nodes.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckUseAfterFree(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Unwrap a 'statement' wrapper to its primary expression. }
  function Primary(const N: TTSNode): TTSNode;
  begin
    if (N.NodeType = 'statement') and (N.NamedChildCount > 0) then Result:= N.NamedChild(0) else Result:= N;
  end;

  { 'X.Free' -> X. }
  function IsRawFree(const N: TTSNode; out AVar: string): Boolean;
  var
    L, R: TTSNode;
  begin
    Result:= False;
    if N.NodeType <> 'exprDot' then Exit;
    L:= N.ChildByField('lhs'); R:= N.ChildByField('rhs');
    if (not L.IsNull) and (not R.IsNull) and (L.NodeType = 'identifier') and (R.NodeType = 'identifier') and SameText(NodeStr(R), 'Free') then
    begin
      AVar:= LowerCase(NodeStr(L));
      Result:= True;
    end;
  end;

  { 'FreeAndNil(X)' -> X. }
  function IsFreeAndNil(const N: TTSNode; out AVar: string): Boolean;
  var
    Ent, Args, A0: TTSNode;
  begin
    Result:= False;
    if N.NodeType <> 'exprCall' then Exit;
    Ent:= N.ChildByField('entity');
    if Ent.IsNull or (Ent.NodeType <> 'identifier') or not SameText(NodeStr(Ent), 'FreeAndNil') then Exit;
    Args:= N.ChildByField('args');
    if Args.IsNull or (Args.NamedChildCount < 1) then Exit;
    A0:= Args.NamedChild(0);
    if A0.NodeType = 'identifier' then begin AVar:= LowerCase(NodeStr(A0)); Result:= True; end;
  end;

  { Find an 'X.<member>' access where X is in AFreed; returns the node or null-via-found-flag. }
  function FindUse(const N: TTSNode; AFreed: TDictionary<string, Boolean>; out AHit: TTSNode): Boolean;
  var
    I   : Integer;
    L   : TTSNode;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'exprDot' then
    begin
      L:= N.ChildByField('lhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') and AFreed.ContainsKey(LowerCase(NodeStr(L))) then
      begin
        AHit:= N;
        Exit(True);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do
      if FindUse(N.Child(I), AFreed, AHit) then Exit(True);
  end;

  procedure CheckBlock(const ABlock: TTSNode);
  var
    Freed: TDictionary<string, Boolean>;
    I    : Integer    ;
    Child: TTSNode    ;
    Prim : TTSNode    ;
    Hit  : TTSNode    ;
    V    : string     ;
    P    : TTSPoint   ;
    F    : TLintFinding;
  begin
    Freed:= TDictionary<string, Boolean>.Create;
    try
      for I:= 0 to ABlock.NamedChildCount - 1 do
      begin
        Child:= ABlock.NamedChild(I);
        if Child.IsNull or Child.NodeType.StartsWith('k') then Continue;
        { step 1: any use of an already-freed var in this statement? }
        if (Freed.Count > 0) and FindUse(Child, Freed, Hit) then
        begin
          P:= Hit.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'use-after-free';
          F.Severity:= 'warning';
          F.Message := 'Use of an object after it was freed (dangling reference) -- nil it after Free, or use FreeAndNil';
          F.FilePath:= AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine:= F.StartLine;
          F.EndCol := F.StartCol + 1;
          Findings.Add(F);
          if Findings.Count >= 200 then Break;
        end;
        { step 2: update the freed set for subsequent statements }
        Prim:= Primary(Child);
        if (Child.NodeType = 'assignment') then
        begin
          var Lv: TTSNode:= Child.ChildByField('lhs');
          if (not Lv.IsNull) and (Lv.NodeType = 'identifier') then Freed.Remove(LowerCase(NodeStr(Lv)));
        end
        else if IsFreeAndNil(Prim, V) then Freed.Remove(V)
        else if IsRawFree(Prim, V) then Freed.AddOrSetValue(V, True);
      end;
    finally
      Freed.Free;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if (N.NodeType = 'block') or (N.NodeType = 'statements') then CheckBlock(N);
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckUiThread(const AFile: string): TArray<TLintFinding>;
var
  Src      : TBytes                    ;
  PF      : TParsedFile        ;
  Findings : TList<TLintFinding>       ;
  ClassBase: TDictionary<string,string>; { classLower -> base type name (as written) }

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Record className -> base type name for every class declaration. }
  procedure CollectClasses(const N: TTSNode);
  var
    I, J     : Integer;
    NameN    : TTSNode;
    TypeN    : TTSNode;
    Cls      : TTSNode;
    FoundCls : Boolean;
    Ch       : TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declType' then
    begin
      NameN:= N.ChildByField('name');
      TypeN:= N.ChildByField('type');
      if (not NameN.IsNull) and (not TypeN.IsNull) then
      begin
        FoundCls:= False;
        if TypeN.NodeType = 'declClass' then begin Cls:= TypeN; FoundCls:= True; end
        else
          for J:= 0 to TypeN.ChildCount - 1 do
            if TypeN.Child(J).NodeType = 'declClass' then begin Cls:= TypeN.Child(J); FoundCls:= True; Break; end;
        if FoundCls then
          for J:= 0 to Cls.ChildCount - 1 do
          begin
            Ch:= Cls.Child(J);
            if Ch.NodeType = 'typeref' then
            begin
              ClassBase.AddOrSetValue(LowerCase(NodeStr(NameN)), NodeStr(Ch));
              Break; { first parent typeref = base class }
            end;
          end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectClasses(N.NamedChild(I));
  end;

  procedure Flag(const ANode: TTSNode; const AMember: string);
  var
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId  := 'ui-access-in-thread';
    F.Severity:= 'warning';
    F.Message := Format('UI access (.%s) inside a TThread.Execute -- VCL/FMX is not thread-safe; wrap it in Synchronize/Queue', [AMember]);
    F.FilePath:= AFile;
    F.StartLine:= Integer(P.Row   ) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine:= F.StartLine;
    F.EndCol := F.StartCol + 1;
    Findings.Add(F);
  end;

  procedure WalkExec(const N: TTSNode);
  var
    I    : Integer;
    Lhs  : TTSNode;
    Rhs  : TTSNode;
    Mname: string ;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit; { likely Synchronize/Queue body, or nested routine }
    if N.NodeType = 'assignment' then
    begin
      Lhs:= N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'exprDot') then
      begin
        Rhs:= Lhs.ChildByField('rhs');
        if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') and SameText(NodeStr(Rhs), 'Caption') then Flag(Lhs, 'Caption');
      end;
    end
    else if N.NodeType = 'exprDot' then
    begin
      Rhs:= N.ChildByField('rhs');
      if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') then
      begin
        Mname:= NodeStr(Rhs);
        if SameText(Mname, 'SetFocus') or SameText(Mname, 'Repaint') or SameText(Mname, 'BringToFront') then Flag(N, Mname);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do WalkExec(N.Child(I));
  end;

  procedure VisitProcs(const N: TTSNode);
  var
    I    : Integer;
    Hdr  : TTSNode;
    Nm   : TTSNode;
    Lhs  : TTSNode;
    Rhs  : TTSNode;
    Body : TTSNode;
    Base : string ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
    begin
      Hdr:= N.ChildByField('header');
      if not Hdr.IsNull then
      begin
        Nm:= Hdr.ChildByField('name');
        if (not Nm.IsNull) and (Nm.NodeType = 'genericDot') then
        begin
          Lhs:= Nm.ChildByField('lhs');
          Rhs:= Nm.ChildByField('rhs');
          if (not Lhs.IsNull) and (not Rhs.IsNull) and (Lhs.NodeType = 'identifier') and SameText(NodeStr(Rhs), 'Execute') then
            if ClassBase.TryGetValue(LowerCase(NodeStr(Lhs)), Base) and (Pos('thread', LowerCase(Base)) > 0) then
            begin
              Body:= N.ChildByField('body');
              if not Body.IsNull then WalkExec(Body);
            end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings := TList<TLintFinding>.Create;
  ClassBase:= TDictionary<string,string>.Create;
  try

    if PF.Tree <> nil then
    begin
      CollectClasses(PF.Tree.RootNode);
      VisitProcs(PF.Tree.RootNode);
    end;
    Result:= Findings.ToArray;
  finally
    ClassBase.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckGlobalFormVars(const AFile: string): TArray<TLintFinding>;
var
  Src           : TBytes;
  PF      : TParsedFile        ;
  Findings      : TList<TLintFinding>;
  FormClassNames: TDictionary<string, Boolean>;

  function NodeStr(const ANode: TTSNode): string;
  var B: TBytes;
  begin
    if ANode.IsNull or (ANode.StartByte >= ANode.EndByte) then Exit('');
    SetLength(B, Integer(ANode.EndByte) - Integer(ANode.StartByte));
    Move(Src[ANode.StartByte], B[0], Length(B));
    Result:= TEncoding.UTF8.GetString(B);
  end;

  { Pass 1: collect unit-level class type names.
    Mirrors CheckUiThread.CollectClasses: uses ChildByField('name'/'type') to detect
    declType nodes that have a declClass body. Skips defProc/defFunc subtrees. }
  procedure CollectClassNames(const N: TTSNode);
  var
    I     : Integer;
    NmN   : TTSNode;
    TypeN : TTSNode;
    IsClass: Boolean;
    ClsName: string;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc') or (N.NodeType = 'defFunc') then Exit;
    if N.NodeType = 'declType' then
    begin
      NmN  := N.ChildByField('name');
      TypeN := N.ChildByField('type');
      IsClass:= False;
      if not TypeN.IsNull then
      begin
        if TypeN.NodeType = 'declClass' then IsClass:= True
        else
          for I:= 0 to TypeN.ChildCount - 1 do
            if TypeN.Child(I).NodeType = 'declClass' then begin IsClass:= True; Break; end;
      end;
      if IsClass and (not NmN.IsNull) then
      begin
        ClsName:= LowerCase(NodeStr(NmN));
        if ClsName <> '' then FormClassNames.AddOrSetValue(ClsName, True);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
      CollectClassNames(N.NamedChild(I));
  end;

  { Pass 2: find global declVars entries whose declared type is a form class. }
  procedure CheckGlobalVarDecls(const N: TTSNode);
  var
    I, J, K           : Integer;
    DV, DVType, NameId: TTSNode;
    VarTypeName, VarName: string;
    TypeStart         : Integer;
    P                 : TTSPoint;
    F                 : TLintFinding;
  begin
    if N.IsNull then Exit;
    { skip all procedure/function bodies -- vars inside are local }
    if (N.NodeType = 'defProc') or (N.NodeType = 'defFunc') then Exit;
    if N.NodeType = 'declVars' then
    begin
      for J:= 0 to N.NamedChildCount - 1 do
      begin
        DV:= N.NamedChild(J);
        if DV.NodeType <> 'declVar' then Continue;
        DVType:= DV.ChildByField('type');
        if DVType.IsNull then Continue;
        VarTypeName:= LowerCase(NodeStr(DVType));
        if not FormClassNames.ContainsKey(VarTypeName) then Continue;
        TypeStart:= Integer(DVType.StartByte);
        for K:= 0 to DV.NamedChildCount - 1 do
        begin
          NameId:= DV.NamedChild(K);
          if NameId.NodeType <> 'identifier' then Continue;
          if Integer(NameId.StartByte) >= TypeStart then Continue;
          VarName:= NodeStr(NameId);
          if VarName = '' then Continue;
          P:= NameId.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'global-form-variable';
          F.Severity:= 'warning';
          F.Message := Format(
            'Global form variable ''%s: %s'' may leak if the form is created more than ' +
            'once. Consider removing the global and creating/freeing the form locally.',
            [VarName, NodeStr(DVType)]);
          F.FilePath := AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine  := F.StartLine;
          F.EndCol   := F.StartCol + Length(VarName);
          Findings.Add(F);
        end;
      end;
      Exit; { handled; do not recurse into the var block itself }
    end;
    for I:= 0 to N.NamedChildCount - 1 do
      CheckGlobalVarDecls(N.NamedChild(I));
  end;

begin
  Result:= nil;
  { Only analyse form units -- a sibling .dfm is the authoritative signal. }
  if not TFile.Exists(ChangeFileExt(AFile, '.dfm')) then Exit;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  FormClassNames:= TDictionary<string, Boolean>.Create;
  try
    CollectClassNames(PF.Tree.RootNode);
    if FormClassNames.Count > 0 then
      CheckGlobalVarDecls(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    FormClassNames.Free;
    Findings.Free;
  end;
end; // function

type
  { One layer of an active `with` stack, for CheckWithHiding below. Declared at
    unit level rather than inside the routine because TList<T> instantiated on a
    routine-LOCAL type is exactly the shape that trips E2506. }
  TWithLayer = record
    EntityText: string     ; // the entity as written -- 'FPanel', 'X as TFoo'
    TypeName  : string     ; // its resolved type, '' when it did not resolve
    Surface   : TStringList; // member names of that type; nil when unresolved
  end;

{ with-hides-outer-symbol (owner request 2026-08-30). Inside `with`, a bare
  `Height` or `Width` silently binds to the with-target instead of the form the
  author meant, and the compiler says nothing. The owner asked for it in those
  words, having spent a long time on exactly that bug months earlier.

  IT SHIPS ENABLED AND NOISY, ON THE OWNER'S EXPLICIT RULING: "Even 1 out of 100
  might be really useful." The plan's volume gate (kill above 300 findings) was
  WITHDRAWN by him. What was NOT withdrawn is the PRECISION gate, and the two
  are different failures: he accepted noise, not wrong findings. So every
  silencer below stays.

  FOUR THINGS BUY SILENCE, and each is a decision rather than a shortcut:
   1. The with-target's type does not resolve -> nothing. No surface, no claim.
   2. The name is not a member of any layer -> nothing. It is an ordinary
      identifier that happens to live in a with body.
   3. No OUTER declaration of the name is provable -> nothing. Both halves must
      be real or the finding is a guess.
   4. The name is a member of TObject -> nothing, on BOTH sides. Free,
      ClassName and ToString are members of everything, so counting them would
      make every `with` in the codebase a finding.

  DEVIATION FROM THE PLAN TEXT, recorded because it is deliberate: the plan says
  Self's side counts "methods only". Its OWN worked example is
  `it hides TfrmReport.Width (inherited from TCustomForm)` -- and Width is a
  PROPERTY, not a method. Methods-only would have missed the example the rule
  was specified from, and with it the owner's actual bug. Fields, properties and
  methods all count, on both sides.

  Resolution is INNERMOST-FIRST, matching Delphi: `with A, B do` makes B inner,
  and a nested `with` stacks on top. }
class function TAstChecker.CheckWithHiding(const AFile: string; const AStore: ISymbolStore;
  const ALibStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
const
  { The floor. Also resolved from the stores when they carry TObject, but
    hardcoded as well so the floor exists even against an index that does not --
    a missing floor turns every with body into findings, and this list only ever
    SILENCES, so a stale entry costs a finding rather than inventing one. }
  CObjectMembers: array[0..24] of string = (
    'Free', 'Create', 'Destroy', 'ClassName', 'ClassType', 'ClassParent',
    'ClassInfo', 'InstanceSize', 'InheritsFrom', 'ToString', 'Equals',
    'GetHashCode', 'DisposeOf', 'FieldAddress', 'GetInterface',
    'GetInterfaceEntry', 'GetInterfaceTable', 'UnitName', 'QualifiedClassName',
    'SafeCallException', 'AfterConstruction', 'BeforeDestruction', 'Dispatch',
    'DefaultHandler', 'NewInstance');
var
  Src        : TBytes             ;
  PF         : TParsedFile        ;
  Findings   : TList<TLintFinding>;
  SurfaceMemo: TObjectDictionary<string, TStringList>;
  Floor      : TStringList        ;

  function NodeStr(const ANode: TTSNode): string;
  var B: TBytes;
  begin
    if ANode.IsNull or (ANode.StartByte >= ANode.EndByte) then Exit('');
    SetLength(B, Integer(ANode.EndByte) - Integer(ANode.StartByte));
    Move(Src[ANode.StartByte], B[0], Length(B));
    Result:= TEncoding.UTF8.GetString(B);
  end;

  { Every member name of AClassName and of its whole ancestry, across the project
    store and then the library store. nil when no class of that name exists in
    either -- which is silencer 1, and the reason this returns nil rather than an
    empty list. Memoized: lint-all visits thousands of with statements. }
  function SurfaceOf(const AClassName: string): TStringList;
  var
    Key  : string     ;
    L    : TStringList;
    Found: Boolean    ;

    procedure AddMembersFrom(const S: ISymbolStore; ASymId: Int64);
    begin
      for var M: TSymbol in S.FindAllChildSymbols(ASymId) do
      begin
        if M.Name = '' then Continue;
        if not (M.Kind in [skMethod, skProcedure, skFunction, skConstructor,
                           skDestructor, skProperty, skField]) then Continue;
        { A private member of a type declared in ANOTHER unit is not visible
          here, so it can neither hide nor be hidden. }
        if (M.FileId <> AFileId) and ContainsText(M.Modifiers, 'private') then Continue;
        if L.IndexOf(M.Name) < 0 then L.Add(M.Name);
      end;
    end;

    procedure Harvest(const S: ISymbolStore; const AName: string; ADepth: Integer);
    begin
      if (S = nil) or (ADepth > 8) or (Trim(AName) = '') then Exit;
      for var Sy: TSymbol in S.FindSymbolsByExactName(AName) do
      begin
        if Sy.Kind <> skClass then Continue;
        Found:= True;
        AddMembersFrom(S, Sy.Id);
        for var Anc: TTypeAncestor in S.GetTransitiveAncestors(Sy.Id) do
          if (Anc.SymbolId > 0) and SameText(Anc.Kind, 'class') then
            AddMembersFrom(S, Anc.SymbolId)
          else if (ALibStore <> nil) and (S <> ALibStore) then
            { THE ANCESTRY BRIDGE. A project class descends TForm, which the
              project index cannot resolve; the climb continues by NAME in the
              library index. Without it every VCL-derived form has a surface of
              only its own members, and the owner's Width/Height case -- which
              lives on TCustomForm -- is invisible. }
            Harvest(ALibStore, Anc.Name, ADepth + 1);
      end;
    end;

  begin
    Result:= nil;
    Key:= LowerCase(Trim(AClassName));
    if Key = '' then Exit;
    if SurfaceMemo.TryGetValue(Key, L) then Exit(L);
    L:= TStringList.Create;
    L.CaseSensitive:= False;
    Found:= False;
    Harvest(AStore   , Trim(AClassName), 0);
    Harvest(ALibStore, Trim(AClassName), 0);
    if not Found then
    begin
      L.Free;
      SurfaceMemo.AddOrSetValue(Key, nil);
      Exit(nil);
    end;
    SurfaceMemo.AddOrSetValue(Key, L);
    Result:= L;
  end;

  { A bare type name, or '' when the text is anything else -- an array, a
    pointer, a generic instantiation. Silencer 1 again: no bare name, no
    surface, no finding. }
  function BareTypeName(const AText: string): string;
  var I: Integer;
  begin
    Result:= Trim(AText);
    if Result = '' then Exit;
    for I:= 1 to Length(Result) do
      if not CharInSet(Result[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then Exit('');
  end;

  procedure CheckProc(const ADefProc: TTSNode);
  var
    LocalNames: TDictionary<string, Boolean>;   { locals + params, lowercased }
    LocalTypes: TDictionary<string, string> ;   { name -> declared type text }
    SelfClass : string                      ;
    Layers    : TList<TWithLayer>               ;
    Reported  : TDictionary<string, Boolean>;

    procedure CollectDecls(const N: TTSNode);
    var TypeN: TTSNode; TB: Integer; TName: string;
    begin
      if N.IsNull then Exit;
      if (N.NodeType = 'declArg') or (N.NodeType = 'declVar') then
      begin
        TypeN:= N.ChildByField('type');
        TB:= -1;
        TName:= '';
        if not TypeN.IsNull then
        begin
          TB   := Integer(TypeN.StartByte);
          TName:= BareTypeName(NodeStr(TypeN));
        end;
        for var I: Integer:= 0 to N.NamedChildCount - 1 do
        begin
          var C: TTSNode:= N.NamedChild(I);
          if C.NodeType <> 'identifier' then Continue;
          { names precede the type node in `A, B: T` }
          if (TB >= 0) and (Integer(C.StartByte) >= TB) then Continue;
          var Nm: string:= LowerCase(NodeStr(C));
          if Nm = '' then Continue;
          LocalNames.AddOrSetValue(Nm, True);
          if TName <> '' then LocalTypes.AddOrSetValue(Nm, TName);
        end;
        Exit;
      end;
      for var I: Integer:= 0 to N.NamedChildCount - 1 do
      begin
        if N.NamedChild(I).NodeType = 'defProc' then Continue; { own scope }
        CollectDecls(N.NamedChild(I));
      end;
    end;

    { The type a with-entity denotes, or '' for silence. Deliberately narrow: a
      routine local or parameter, a field of the enclosing class, an `as` cast,
      or a constructor call. Anything else is not worth a guess -- and the
      per-ROUTINE decl map matters, not a file-wide one: a same-named local in
      another routine must not decide this routine's type. }
    function EntityType(const E: TTSNode): string;
    var Nm: string;
    begin
      Result:= '';
      if E.IsNull then Exit;
      if E.NodeType = 'identifier' then
      begin
        Nm:= LowerCase(NodeStr(E));
        if LocalTypes.TryGetValue(Nm, Result) then Exit;
        if (SelfClass <> '') and (AStore <> nil) then
          for var Sy: TSymbol in AStore.FindSymbolsByExactName(SelfClass) do
          begin
            if Sy.Kind <> skClass then Continue;
            for var M: TSymbol in AStore.FindAllChildSymbols(Sy.Id) do
              if (M.Kind = skField) and SameText(M.Name, NodeStr(E)) then
                Exit(BareTypeName(M.Signature));
          end;
        Exit('');
      end;
      if E.NodeType = 'exprBinary' then
      begin
        var Op: TTSNode:= E.ChildByField('operator');
        if (not Op.IsNull) and SameText(Trim(NodeStr(Op)), 'as') then
          Exit(BareTypeName(NodeStr(E.ChildByField('rhs'))));
        Exit('');
      end;
      if E.NodeType = 'exprDot' then
      begin
        var R: TTSNode:= E.ChildByField('rhs');
        if (not R.IsNull) and SameText(Trim(NodeStr(R)), 'Create') then
          Exit(BareTypeName(NodeStr(E.ChildByField('lhs'))));
        Exit('');
      end;
      if E.NodeType = 'exprCall' then
        Exit(EntityType(E.ChildByField('entity')));
    end;

    procedure Consider(const N: TTSNode);
    var
      Nm : string ;
      Win: Integer;
      Hid: string ;
      I  : Integer;
    begin
      if Layers.Count = 0 then Exit;
      Nm:= Trim(NodeStr(N));
      if Nm = '' then Exit;
      if Floor.IndexOf(Nm) >= 0 then Exit;                      { silencer 4 }

      Win:= -1;
      for I:= Layers.Count - 1 downto 0 do                      { innermost first }
        if (Layers[I].Surface <> nil) and (Layers[I].Surface.IndexOf(Nm) >= 0) then
        begin
          Win:= I;
          Break;
        end;
      if Win < 0 then Exit;                                     { silencer 2 }

      Hid:= '';
      for I:= Win - 1 downto 0 do
        if (Layers[I].Surface <> nil) and (Layers[I].Surface.IndexOf(Nm) >= 0) then
        begin
          Hid:= Format('the outer with layer ''%s'' (%s)',
                       [Layers[I].EntityText, Layers[I].TypeName]);
          Break;
        end;
      if (Hid = '') and LocalNames.ContainsKey(LowerCase(Nm)) then
        Hid:= 'this routine''s own local or parameter';
      if (Hid = '') and (SelfClass <> '') then
      begin
        var SelfSurface: TStringList:= SurfaceOf(SelfClass);
        if (SelfSurface <> nil) and (SelfSurface.IndexOf(Nm) >= 0) then
          if SameText(Layers[Win].TypeName, SelfClass) then
            { THE Assign/AssignTo SHAPE, and it needs its own sentence. When the
              with-target is another instance of the class we are already inside,
              'TmcFoo.ID hides TmcFoo.ID' reads like a defect in this rule -- and
              a reader who concludes that stops reading the rest. The hazard is
              real and is about INSTANCES, not types: measured 2026-08-30, every
              generated `Assign`/`AssignTo` in ORM3 written as
              `with Source as TmcFoo do fID := ID` assigns Source's property to
              Source's own field and copies NOTHING. }
            Hid:= Format('Self.%s -- the with-target is a DIFFERENT instance of %s, ' +
                         'so this copies nothing', [Nm, SelfClass])
          else
            Hid:= Format('%s.%s', [SelfClass, Nm]);
      end;
      if Hid = '' then Exit;                                    { silencer 3 }

      { ONE finding per identifier per with body, at the first use site. The
        depth is part of the key so an inner with reporting the same name is a
        different, and genuinely different, finding. }
      var K: string:= LowerCase(Nm) + '@' + IntToStr(Layers.Count);
      if Reported.ContainsKey(K) then Exit;
      Reported.AddOrSetValue(K, True);

      var P: TTSPoint:= N.StartPoint;
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId   := 'with-hides-outer-symbol';
      F.Severity := 'warning';
      F.FilePath := AFile;
      F.StartLine:= Integer(P.Row   ) + 1;
      F.StartCol := Integer(P.Column) + 1;
      F.EndLine  := F.StartLine;
      F.EndCol   := F.StartCol + Length(Nm);
      F.Message  := Format(
        '''%s'' binds to %s.%s via ''with %s do''; it hides %s. Qualify it explicitly.',
        [Nm, Layers[Win].TypeName, Nm, Layers[Win].EntityText, Hid]);
      Findings.Add(F);
    end;

    { One walker, self-recursive. A `with` pushes its layers, walks its body and
      pops them; nested withs therefore stack naturally. Called on the whole
      routine body, so identifiers outside any `with` are visited too -- they
      cost one Layers.Count test each and can never produce a finding. }
    procedure WalkBody(const N: TTSNode);
    var
      Body : TTSNode;
      Added: Integer;
      Lay  : TWithLayer;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'defProc' then Exit;          { nested routine, own scope }

      if N.NodeType = 'with' then
      begin
        Body := N.ChildByField('body');
        Added:= 0;
        { The entities are every named child EXCEPT the body. `with A, B do` is
          ONE with node with REPEATED 'entity' fields, so ChildByField('entity')
          would see only A -- the same single-field trap that costs the indexer
          its refs for entities 2..n. }
        for var I: Integer:= 0 to N.NamedChildCount - 1 do
        begin
          var C: TTSNode:= N.NamedChild(I);
          if (not Body.IsNull) and (C.StartByte = Body.StartByte)
                               and (C.EndByte   = Body.EndByte  ) then Continue;
          Lay.EntityText:= Trim(NodeStr(C));
          Lay.TypeName  := EntityType(C);
          if Lay.TypeName = '' then Lay.Surface:= nil
          else Lay.Surface:= SurfaceOf(Lay.TypeName);
          Layers.Add(Lay);
          Inc(Added);
        end;
        try
          WalkBody(Body);
        finally
          for var K: Integer:= 1 to Added do Layers.Delete(Layers.Count - 1);
        end;
        Exit;
      end;

      if N.NodeType = 'identifier' then
      begin
        Consider(N);
        Exit;
      end;

      if N.NodeType = 'exprDot' then
      begin
        { The rhs NAMES A MEMBER of the lhs. It is already qualified -- it is
          exactly what this rule tells people to write -- so it is never a
          finding. Its arguments still are, when it is a call. }
        WalkBody(N.ChildByField('lhs'));
        var R: TTSNode:= N.ChildByField('rhs');
        if (not R.IsNull) and (R.NodeType <> 'identifier') then WalkBody(R);
        Exit;
      end;

      for var I: Integer:= 0 to N.NamedChildCount - 1 do WalkBody(N.NamedChild(I));
    end;

  var
    Hdr, Nm, Body: TTSNode;
  begin
    LocalNames:= TDictionary<string, Boolean>.Create;
    LocalTypes:= TDictionary<string, string> .Create;
    Layers    := TList<TWithLayer>               .Create;
    Reported  := TDictionary<string, Boolean>.Create;
    try
      CollectDecls(ADefProc);
      SelfClass:= '';
      Hdr:= ADefProc.ChildByField('header');
      if not Hdr.IsNull then
      begin
        Nm:= Hdr.ChildByField('name');
        if (not Nm.IsNull) and (Nm.NodeType = 'genericDot') then
          SelfClass:= Trim(NodeStr(Nm.ChildByField('lhs')));
      end;
      Body:= ADefProc.ChildByField('body');
      if Body.IsNull then Exit;
      WalkBody(Body);
    finally
      Reported  .Free;
      Layers    .Free;
      LocalTypes.Free;
      LocalNames.Free;
    end;
  end;

  procedure VisitProcs(const N: TTSNode);
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then CheckProc(N);
    for var I: Integer:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;              { neither half is provable without it }
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings   := TList<TLintFinding>.Create;
  SurfaceMemo:= TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  Floor      := TStringList.Create;
  try
    Floor.CaseSensitive:= False;
    for var S: string in CObjectMembers do Floor.Add(S);
    { and whatever the indexes actually say TObject carries, on top }
    var TObj: TStringList:= SurfaceOf('TObject');
    if TObj <> nil then
      for var I: Integer:= 0 to TObj.Count - 1 do
        if Floor.IndexOf(TObj[I]) < 0 then Floor.Add(TObj[I]);
    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Floor      .Free;
    SurfaceMemo.Free;
    Findings   .Free;
  end;
end;

class function TAstChecker.CheckMutableGlobalVars(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes;
  PF      : TParsedFile;
  Findings: TList<TLintFinding>;

  function NodeStr(const ANode: TTSNode): string;
  var B: TBytes;
  begin
    if ANode.IsNull or (ANode.StartByte >= ANode.EndByte) then Exit('');
    SetLength(B, Integer(ANode.EndByte) - Integer(ANode.StartByte));
    Move(Src[ANode.StartByte], B[0], Length(B));
    Result:= TEncoding.UTF8.GetString(B);
  end;

  { Find every unit-scope declVars -> declVar and emit one finding per declared identifier.
    Exits on defProc/defFunc so locals/params are excluded. 'const' sections are declConst
    nodes (not declVars), so they are never visited here. }
  procedure CheckGlobalVarDecls(const N: TTSNode);
  var
    I, J, K   : Integer;
    DV, DVType, NameId: TTSNode;
    VarName   : string;
    TypeStart : Integer;
    P         : TTSPoint;
    F         : TLintFinding;
  begin
    if N.IsNull then Exit;
    { skip all procedure/function bodies -- vars inside are local }
    if (N.NodeType = 'defProc') or (N.NodeType = 'defFunc') then Exit;
    if N.NodeType = 'declVars' then
    begin
      for J:= 0 to N.NamedChildCount - 1 do
      begin
        DV:= N.NamedChild(J);
        if DV.NodeType <> 'declVar' then Continue;
        DVType:= DV.ChildByField('type');
        if DVType.IsNull then Continue;
        TypeStart:= Integer(DVType.StartByte);
        for K:= 0 to DV.NamedChildCount - 1 do
        begin
          NameId:= DV.NamedChild(K);
          if NameId.NodeType <> 'identifier' then Continue;
          if Integer(NameId.StartByte) >= TypeStart then Continue;
          VarName:= NodeStr(NameId);
          if VarName = '' then Continue;
          P:= NameId.StartPoint;
          F:= Default(TLintFinding);
          F.RuleId  := 'mutable-global-variable';
          F.Severity:= 'info';
          F.Message := Format(
            'Mutable global variable ''%s'' -- shared mutable state; prefer a scoped/encapsulated alternative.',
            [VarName]);
          F.FilePath := AFile;
          F.StartLine:= Integer(P.Row   ) + 1;
          F.StartCol := Integer(P.Column) + 1;
          F.EndLine  := F.StartLine;
          F.EndCol   := F.StartCol + Length(VarName);
          Findings.Add(F);
        end;
      end;
      Exit; { handled; do not recurse into the var block itself }
    end;
    for I:= 0 to N.NamedChildCount - 1 do
      CheckGlobalVarDecls(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try
    CheckGlobalVarDecls(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckSeparateQueryFromModifier(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes;
  PF      : TParsedFile;
  Findings: TList<TLintFinding>;

  function NodeStr(const ANode: TTSNode): string;
  var B: TBytes;
  begin
    if ANode.IsNull or (ANode.StartByte >= ANode.EndByte) then Exit('');
    SetLength(B, Integer(ANode.EndByte) - Integer(ANode.StartByte));
    Move(Src[ANode.StartByte], B[0], Length(B));
    Result:= TEncoding.UTF8.GetString(B);
  end;

  { True when AName looks like an F-prefixed field ('F' + an uppercase letter). }
  function LooksLikeFieldName(const AName: string): Boolean;
  begin
    Result:= (Length(AName) >= 2) and (AName[1] = 'F') and CharInSet(AName[2], ['A'..'Z']);
  end;

  { Collect the lowercased names of a function's locals + parameters, so an
    F-prefixed LOCAL (a shadowing local, rare but possible) is not mistaken for a
    field write. Walks the defProc's declArgs (header) and declVars sections; does
    NOT descend into nested defProcs (their vars are their own scope). }
  procedure CollectLocalsAndParams(const ADefProc: TTSNode; ANames: TDictionary<string, Boolean>);
    procedure AddIdentsUnder(const N: TTSNode; ATypeBoundary: Integer);
    var I: Integer; Nm: string;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'identifier' then
      begin
        { for declVar/declArg the name identifiers precede the type node; skip
          identifiers at/after the type start (they name the type, not a var). }
        if (ATypeBoundary < 0) or (Integer(N.StartByte) < ATypeBoundary) then
        begin
          Nm:= LowerCase(NodeStr(N));
          if Nm <> '' then ANames.AddOrSetValue(Nm, True);
        end;
        Exit;
      end;
      for I:= 0 to N.NamedChildCount - 1 do AddIdentsUnder(N.NamedChild(I), ATypeBoundary);
    end;
    procedure WalkDecls(const N: TTSNode);
    var I: Integer; TypeN: TTSNode; TB: Integer;
    begin
      if N.IsNull then Exit;
      if (N.NodeType = 'declArg') or (N.NodeType = 'declVar') then
      begin
        TypeN:= N.ChildByField('type');
        TB:= -1;
        if not TypeN.IsNull then TB:= Integer(TypeN.StartByte);
        AddIdentsUnder(N, TB);
        Exit;
      end;
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        { do not cross into a nested routine's own scope (the top-level call is on
          ADefProc itself, so a defProc encountered as a descendant is always a
          nested routine). }
        if N.NamedChild(I).NodeType = 'defProc' then Continue;
        WalkDecls(N.NamedChild(I));
      end;
    end;
  begin
    WalkDecls(ADefProc);
  end;

  { True if this defProc header declares a value-returning function (has a return
    'type' child). Constructors/destructors/procedures have no return type. }
  function IsFunction(const ADefProc: TTSNode): Boolean;
  var Hdr: TTSNode;
  begin
    Hdr:= ADefProc.ChildByField('header');
    Result:= (not Hdr.IsNull) and (not Hdr.ChildByField('type').IsNull);
  end;

  { Scan a function body for a state mutation: 'Self.X := ...' OR 'FXxx := ...'
    (F-prefixed, not a local/param). Returns True on the first hit. Does not
    descend into nested defProcs (own scope). }
  function BodyMutatesField(const ABody: TTSNode; ALocals: TDictionary<string, Boolean>): Boolean;
  var Hit: Boolean;
    procedure Walk(const N: TTSNode);
    var I: Integer; Lhs, Base, Mem: TTSNode; Nm: string;
    begin
      if N.IsNull or Hit then Exit;
      if N.NodeType = 'defProc' then Exit; { nested routine -- its own scope }
      if N.NodeType = 'assignment' then
      begin
        Lhs:= N.ChildByField('lhs');
        if not Lhs.IsNull then
        begin
          { 'Self.X := ...' -- explicit field/property write }
          if Lhs.NodeType = 'exprDot' then
          begin
            Base:= Lhs.ChildByField('lhs');
            Mem := Lhs.ChildByField('rhs');
            if (not Base.IsNull) and (Base.NodeType = 'identifier')
               and SameText(NodeStr(Base), 'Self') and (not Mem.IsNull) then
            begin Hit:= True; Exit; end;
          end
          { 'FXxx := ...' -- bare F-prefixed identifier that is not a local/param }
          else if Lhs.NodeType = 'identifier' then
          begin
            Nm:= NodeStr(Lhs);
            if LooksLikeFieldName(Nm) and (not ALocals.ContainsKey(LowerCase(Nm))) then
            begin Hit:= True; Exit; end;
          end;
        end;
      end;
      for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
    end;
  begin
    Hit:= False;
    Walk(ABody);
    Result:= Hit;
  end;

  procedure VisitProc(const ADefProc: TTSNode);
  var
    Body, Hdr: TTSNode;
    Locals   : TDictionary<string, Boolean>;
    P        : TTSPoint;
    F        : TLintFinding;
  begin
    if not IsFunction(ADefProc) then Exit;
    Body:= ADefProc.ChildByField('body');
    if Body.IsNull then Exit;
    Locals:= TDictionary<string, Boolean>.Create;
    try
      CollectLocalsAndParams(ADefProc, Locals);
      if BodyMutatesField(Body, Locals) then
      begin
        Hdr:= ADefProc.ChildByField('header');
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'separate-query-from-modifier';
        F.Severity:= 'info';
        F.Message := 'Function returns a value AND mutates state (writes a field) -- a Command-Query Separation violation. Split it into a pure query and a separate command.';
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine := F.StartLine;
        F.EndCol  := F.StartCol + 1;
        Findings.Add(F);
      end;
    finally
      Locals.Free;
    end;
  end;

  procedure VisitProcs(const N: TTSNode);
  var I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then VisitProc(N);
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try
    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.Check(const AStore: ISymbolStore; const AFile: string): TArray<TLintFinding>;
var
  All : TList<TLintFinding> ;
  Part: TArray<TLintFinding>;
  F   : TLintFinding        ;
begin
  All:= TList<TLintFinding>.Create;
  try
    Part:= CheckSyntaxErrors(AFile);
    for F in Part do All.Add(F);

    Part:= CheckUnbalancedBeginEnd(AFile);
    for F in Part do All.Add(F);

    if AStore <> nil then
    begin
      Part:= CheckUndeclared(AStore, AFile);
      for F in Part do All.Add(F);
    end;

    Result:= All.ToArray;
  finally
    All.Free;
  end; // try
end; // function

class function TAstChecker.CheckShellExec(const AFile: string): TArray<TLintFinding>;
var
  Src      : TBytes             ;
  PF       : TParsedFile        ;
  Findings : TList<TLintFinding>;
  AsgnCount: TDictionary<string, Integer>;
  AsgnRhs  : TDictionary<string, TTSNode>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { ---------------------------------------------------------------------------
    v(2026-08-14): the FIXED-SCHEME URI exemption.

    THE FALSE POSITIVE. This rule asked one syntactic question -- "is the command
    argument a literalString?" -- and answered `error` for everything else. That
    reports CWE-78 on the standard, correct way to open a URL:

        Uri:= 'obsidian://open?vault=' + TNetEncoding.URL.Encode(BaseName);
        ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);

    which is `DRagLint.CLI.DoObsidian`, where the argument had ALREADY been
    hardened for this rule (the encode call exists because of it) and the finding
    fired anyway. A rule whose advice has been followed and which still fires
    teaches people to disable it.

    THE PRINCIPLE, not a heuristic. CWE-78 is about the attacker choosing WHAT
    RUNS. When the argument opens with a hardcoded URI scheme, the program is
    selected by the OS registration for that scheme; the variable part lands in
    the path/query of a URI whose handler is already decided, and no amount of
    user data changes it. So a fixed scheme is a genuine safety property, not a
    guess about intent.

    `file:` IS DELIBERATELY EXCLUDED from the exemption, and it is the whole
    reason this is scheme-aware rather than "starts with a literal": `file://` +
    user data lets the caller pick an arbitrary file, and the program that then
    runs is chosen by that file's EXTENSION -- exactly the thing this rule
    exists to catch. `'cmd.exe /c ' + X` is likewise unaffected: it has no
    scheme, so it is still reported.

    ONE ASSIGNMENT ONLY. The argument is normally a variable (`PChar(Uri)`), so
    this has to look at what was assigned to it. It does that file-wide and
    refuses to reason when the name is assigned more than ONCE anywhere in the
    file -- a second assignment could be the unsafe one, and this is a security
    rule where a false negative costs more than a false positive. Same-named
    locals in other routines only push the count up, so the failure direction is
    "keep reporting", which is the safe one.
    --------------------------------------------------------------------------- }

  { Leftmost string literal of a (possibly nested) binary chain: `'a' + X + Y`
    descends to 'a'. '' when the leftmost leaf is not a literal. }
  function LeftmostLiteralText(const N: TTSNode): string;
  var
    Cur, L: TTSNode;
  begin
    Result:= '';
    Cur   := N;
    while (not Cur.IsNull) and (Cur.NodeType = 'exprBinary') do
    begin
      L:= Cur.ChildByField('lhs');
      if L.IsNull then Exit;
      Cur:= L;
    end;
    if (not Cur.IsNull) and (Cur.NodeType = 'literalString') then Result:= NodeStr(Cur);
  end;

  { True when ALit is a Delphi string literal opening `scheme://` for a scheme
    other than file:. }
  function IsFixedSchemeUri(const ALit: string): Boolean;
  var
    S, Scheme: string;
    I        : Integer;
  begin
    Result:= False;
    if (Length(ALit) < 2) or (ALit[1] <> '''') then Exit;
    S:= Copy(ALit, 2, MaxInt);
    if (S = '') or (not CharInSet(S[1], ['A'..'Z', 'a'..'z'])) then Exit;
    I     := 1;
    Scheme:= '';
    while (I <= Length(S)) and CharInSet(S[I], ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) do
    begin
      Scheme:= Scheme + S[I];
      Inc(I);
    end;
    if Copy(S, I, 3) <> '://' then Exit;
    Result:= not SameText(Scheme, 'file');
  end;

  { PChar(X) / PWideChar(X) / PAnsiChar(X) -> X; anything else unchanged. }
  function UnwrapCast(const A: TTSNode): TTSNode;
  var
    E, Args: TTSNode;
    Nm     : string ;
  begin
    Result:= A;
    if A.IsNull or (A.NodeType <> 'exprCall') then Exit;
    E:= A.ChildByField('entity');
    if E.IsNull or (E.NodeType <> 'identifier') then Exit;
    Nm:= NodeStr(E);
    if not (SameText(Nm, 'PChar') or SameText(Nm, 'PWideChar') or SameText(Nm, 'PAnsiChar')) then Exit;
    Args:= A.ChildByField('args');
    if Args.IsNull or (Args.NamedChildCount <> 1) then Exit;
    Result:= Args.NamedChild(0);
  end;

  { Every `X := <rhs>` in ASubtree, counted by lowercased LHS name. }
  procedure CollectAssignments(const N: TTSNode);
  var
    I  : Integer;
    L  : TTSNode;
    Nm : string ;
    Cnt: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'assignment' then
    begin
      L:= N.ChildByField('lhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') then
      begin
        Nm:= LowerCase(NodeStr(L));
        if AsgnCount.TryGetValue(Nm, Cnt) then
          AsgnCount[Nm]:= Cnt + 1
        else
        begin
          AsgnCount.Add(Nm, 1);
          AsgnRhs  .Add(Nm, N.ChildByField('rhs'));
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectAssignments(N.NamedChild(I));
  end;

  { AProc is the ENCLOSING routine, and the scope must be exactly that.
    File-wide counting was tried first and is wrong in the direction that
    matters: `Uri` / `Cmd` / `S` are assigned once per routine in a dozen
    routines, the file-wide count is therefore >1 everywhere, and the exemption
    never applies to the very code it was written for. Measured on the probe --
    five of six cases behaved and the one real-world shape did not. }
  function ArgIsFixedSchemeUri(const A0, AProc: TTSNode): Boolean;
  var
    A, Rhs: TTSNode;
    Nm    : string ;
    Cnt   : Integer;
  begin
    Result:= False;
    A     := UnwrapCast(A0);
    if A.IsNull then Exit;
    if A.NodeType = 'exprBinary' then Exit(IsFixedSchemeUri(LeftmostLiteralText(A)));
    if A.NodeType <> 'identifier' then Exit;
    { No enclosing routine -> no scope to reason within -> keep reporting. }
    if AProc.IsNull then Exit;
    AsgnCount.Clear;
    AsgnRhs  .Clear;
    CollectAssignments(AProc);
    Nm:= LowerCase(NodeStr(A));
    if not AsgnCount.TryGetValue(Nm, Cnt) then Exit;
    if Cnt <> 1 then Exit; { assigned more than once IN THIS ROUTINE -- refuse to reason }
    if not AsgnRhs.TryGetValue(Nm, Rhs) then Exit;
    Result:= IsFixedSchemeUri(LeftmostLiteralText(Rhs));
  end;

  { ---------------------------------------------------------------------
    THE INJECTION HAS TO HAVE SOMEWHERE TO GO.

    This rule fired `error` on:

      ShellExecute(Handle, 'open', PChar(FConfigService.DataFolder), nil, nil, SW_SHOWNORMAL);

    which opens a config-derived folder in Explorer. It was flagged because
    lpFile is not a literal -- but ShellExecute's signature is
    (hWnd, lpOperation, lpFile, lpParameters, lpDirectory, nShowCmd), and with
    lpParameters nil and lpOperation the literal 'open' there is NO COMMAND
    LINE AT ALL. lpFile is passed as one opaque path; nothing tokenises it, so
    no metacharacter can split an argument off. CWE-78 cannot occur.

    WHAT IS STILL DANGEROUS, and stays flagged:
      * a non-literal lpParameters -- that IS a command line being built;
      * a verb that is not a plain open ('runas' elevates; a non-literal verb
        is unknowable);
      * lpFile naming an INTERPRETER, because `cmd.exe` with a runtime path is
        the classic payload even when lpParameters looks harmless.

    THE RESIDUAL RISK, STATED RATHER THAN HIDDEN: a runtime lpFile could still
    name an executable instead of a folder. That is CWE-73/427 (untrusted
    search path), a different and weaker class than what this rule claims, and
    a rule that cries CWE-78 at every ShellExecute('open') teaches people to
    ignore it. Per the owner's standard -- a finding count in the thousands IS
    the defect -- the answer is to narrow the rule, not to sprinkle dl:ok
    markers over a pervasive benign idiom.
    --------------------------------------------------------------------- }

  { Interpreters: an lpFile naming one of these is a command processor no
    matter how benign the rest of the call looks. Matched on the leftmost
    literal so a concatenated 'cmd' + '.exe' is caught too. }
  { LeftmostLiteralText returns NodeStr -- the RAW SOURCE of the literal, quotes
    and all. IsFixedSchemeUri knows that and skips ALit[1] by hand; these
    comparisons need the same, and the first version of them did not do it, so
    Verb was "'open'" and never equalled "open". Every suppression silently
    failed and the fixture reported the unchanged 7 findings.
    Doubled quotes inside the literal are irrelevant here: every string being
    compared is a shell verb or a program name. }
  function UnquoteLiteral(const ALit: string): string;
  begin
    Result:= Trim(ALit);
    if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
      Result:= Copy(Result, 2, Length(Result) - 2);
  end;

  function NamesAnInterpreter(const A0, AProc: TTSNode): Boolean;
  const
    SHELLS: array[0..8] of string = (
      'cmd', 'cmd.exe', 'command.com', 'powershell', 'powershell.exe',
      'pwsh', 'wscript', 'cscript', 'mshta');
  var
    Txt : string ;
    Sh  : string ;
    P   : Integer;
    A   : TTSNode;
    Rhs : TTSNode;
    Cnt : Integer;
  begin
    Result:= False;
    A:= UnwrapCast(A0);
    Txt:= LowerCase(UnquoteLiteral(LeftmostLiteralText(A)));
    { See through ONE local assignment, the same reasoning (and the same
      refusal above one) ArgIsFixedSchemeUri already applies:
      `Cmd := 'cmd.exe /c ' + P; ShellExecute(..., PChar(Cmd), ...)` hides
      the interpreter behind a variable, and that is the shape a real
      attacker-facing call actually has. }
    if (Txt = '') and (not A.IsNull) and (A.NodeType = 'identifier')
       and (not AProc.IsNull) then
    begin
      AsgnCount.Clear;
      AsgnRhs  .Clear;
      CollectAssignments(AProc);
      if AsgnCount.TryGetValue(LowerCase(NodeStr(A)), Cnt) and (Cnt = 1)
         and AsgnRhs.TryGetValue(LowerCase(NodeStr(A)), Rhs) then
        Txt:= LowerCase(UnquoteLiteral(LeftmostLiteralText(Rhs)));
    end;
    if Txt = '' then Exit;
    { FIRST TOKEN, not the whole literal. `Cmd := 'cmd.exe /c ' + P` leaves
      'cmd.exe /c ' as the leftmost literal; the program is the part before
      the first space, and the rest is already its argument list. }
    P:= Pos(' ', Txt);
    if P > 0 then Txt:= Copy(Txt, 1, P - 1);
    Txt:= ExtractFileName(Txt);
    for Sh in SHELLS do
      if Txt = Sh then Exit(True);
    { rundll32 takes its payload in lpParameters, but the file itself is the
      launcher -- treat it as an interpreter so the pair is never suppressed. }
    Result:= (Txt = 'rundll32') or (Txt = 'rundll32.exe');
  end;

  { Can this ShellExecute call carry a command line the caller controls?

    THE ONE PREDICATE the rule now turns on for ShellExecute. Its three limbs
    are the only ways a command line can exist; lpFile merely being runtime-
    built is NOT one of them, which is the owner ruling of 2026-08-27 and the
    whole reason this replaced the old literal test.

    AInterp reports the interpreter limb so the message can name it, because
    "cmd.exe with your data appended" and "runas on a variable" deserve
    different sentences. }
  function ShellExecuteIsInjectable(const AArgs, AProc: TTSNode;
    out AInterp: Boolean): Boolean;
  const
    SAFE_VERBS: array[0..4] of string = ('open', 'explore', 'edit', 'print', 'find');
    OP_IDX    = 1;  { lpOperation  }
    FILE_IDX  = 2;  { lpFile       }
    PARAM_IDX = 3;  { lpParameters }
  var
    Op, Prm : TTSNode;
    Verb, V : string ;
    VerbSafe: Boolean;
    HasArgs : Boolean;
  begin
    AInterp:= False;
    Result := False;
    { Too few arguments to be the WinAPI ShellExecute -- say nothing rather
      than index past the end and guess. }
    if AArgs.IsNull or (AArgs.NamedChildCount <= PARAM_IDX) then Exit;

    { LIMB ORDER IS ABOUT THE MESSAGE, not about correctness -- any limb alone
      makes the call injectable. The interpreter check runs FIRST because it is
      the most specific thing we can say; when it ran last, a `cmd.exe` call
      that also had runtime parameters got the generic sentence and the reader
      lost the actual diagnosis. }

    { 1. lpFile naming an INTERPRETER. This is why nil lpParameters proves
         nothing on its own: `Cmd := 'cmd.exe /c ' + P` puts the arguments
         INSIDE lpFile. The old rule -- which only asked whether lpFile was a
         literal -- could not see `ShellExecute(0, 'open', 'cmd.exe',
         PChar(Data), ...)` at all, because 'cmd.exe' IS a literal. }
    if NamesAnInterpreter(AArgs.NamedChild(FILE_IDX), AProc) then
    begin
      AInterp:= True;
      Exit(True);
    end;

    { 2. The verb. Only a LITERAL plain verb is provably harmless: `runas`
         elevates, and a verb read from a variable could be anything. }
    Op      := UnwrapCast(AArgs.NamedChild(OP_IDX));
    VerbSafe:= False;
    if (not Op.IsNull) and (Op.NodeType = 'literalString') then
    begin
      Verb:= LowerCase(UnquoteLiteral(LeftmostLiteralText(Op)));
      for V in SAFE_VERBS do
        if Verb = V then begin VerbSafe:= True; Break; end;
    end;
    if not VerbSafe then Exit(True);

    { 3. lpParameters. nil or a literal carries nothing the caller controls;
         anything else IS a runtime-built command line. }
    Prm    := UnwrapCast(AArgs.NamedChild(PARAM_IDX));
    HasArgs:= (not Prm.IsNull)
              and (Prm.NodeType <> 'literalString')
              and (not SameText(Trim(NodeStr(Prm)), 'nil'));
    if HasArgs then Exit(True);
  end;

  function CmdArgIndex(const ACallee: string; out AIdx: Integer): Boolean;
  begin
    Result:= True;
    AIdx  := -1;
    if SameText(ACallee, 'WinExec') then AIdx:= 0
    else if SameText(ACallee, 'ShellExecute') then AIdx:= 2
    else if SameText(ACallee, 'CreateProcess') then AIdx:= 1
    else Result:= False;
  end;

  procedure Visit(const N: TTSNode; const AProc: TTSNode);
  var
    I, Idx      : Integer ;
    Flag, Interp: Boolean ;
    Ent, Args, A: TTSNode ;
    P           : TTSPoint;
    F           : TLintFinding;
    Cur         : TTSNode ;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    { Innermost enclosing routine wins, so a nested procedure reasons about its
      OWN locals rather than the outer routine's. }
    Cur:= AProc;
    if N.NodeType = 'defProc' then Cur:= N;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and CmdArgIndex(NodeStr(Ent), Idx) then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount > Idx) then
        begin
          A:= Args.NamedChild(Idx);
          Interp:= False;

          if SameText(NodeStr(Ent), 'ShellExecute') then
          begin
            { SHELLEXECUTE IS JUDGED ON WHETHER A COMMAND LINE CAN EXIST,
              NOT ON WHETHER lpFile IS A LITERAL. Owner ruling 2026-08-27.

              The old test -- "lpFile is not a string literal" -- fired `error`
              on `ShellExecute(h, 'open', PChar(SomeFolder), nil, nil, ...)`,
              which is how every Delphi program opens a folder in Explorer. With
              lpParameters nil and a plain literal verb there is NO COMMAND LINE:
              lpFile is one opaque path, nothing tokenises it, and CWE-78 cannot
              occur. It is now SILENT.

              WHAT THIS GIVES UP, stated plainly rather than discovered later.
              tests\autotest\run_shellexec_fixed_scheme.ps1 previously required
              three of these to fire -- a bare runtime path, a `file://` + data
              URI, and a variable reassigned after a safe value -- on the
              reasoning that a runtime path can still CHOOSE THE PROGRAM
              (CWE-73/427). That reasoning is sound and is NOT refuted here; the
              owner has ruled that the noise costs more than the signal, since
              there is no AST difference between a config folder and an
              attacker's path, and the rule fired on every benign open. Those
              three cases were rewritten to expect silence, with this note.

              WHAT STILL FIRES, and why each one is a real command line:
                * runtime-built lpParameters -- that IS a command line;
                * a verb that is not a plain literal open/explore/edit/print/
                  find -- `runas` elevates, and a variable verb is unknowable;
                * lpFile naming an INTERPRETER -- `cmd.exe /c ` + data hides the
                  arguments inside lpFile itself, so nil lpParameters proves
                  nothing. This is the case the old rule MISSED entirely,
                  because it only looked at whether lpFile was a literal. }
            Flag:= ShellExecuteIsInjectable(Args, Cur, Interp);
          end
          else
            { WinExec and CreateProcess take a whole COMMAND LINE in the argument
              CmdArgIndex selects, so a non-literal there is injection by
              construction. Unchanged. }
            Flag:= (A.NodeType <> 'literalString') and (not ArgIsFixedSchemeUri(A, Cur));

          if Flag then
          begin
            P:= Ent.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'unsafe-shellexecute';
            F.Severity:= 'error';
            if Interp then
              F.Message := Format('%s launches a command interpreter -- whatever follows it is a command line, so this is command injection (CWE-78). Launch the target program directly instead.', [NodeStr(Ent)])
            else if SameText(NodeStr(Ent), 'ShellExecute') then
              F.Message := 'ShellExecute builds a command line at runtime -- a non-literal lpParameters, or a verb that is not a plain literal open/explore/edit/print/find (CWE-78). Pass fixed arguments, or use a plain open with no parameters.'
            else
              F.Message := Format('%s called with a non-literal command argument -- a runtime-built command path is an injection risk (CWE-78). Validate or use a fixed literal.', [NodeStr(Ent)]);
            F.FilePath:= AFile;
            F.StartLine:= Integer(P.Row   ) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine:= F.StartLine;
            F.EndCol := F.StartCol + 1;
            Findings.Add(F);
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I), Cur);
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings := TList<TLintFinding>.Create;
  AsgnCount:= TDictionary<string, Integer>.Create;
  AsgnRhs  := TDictionary<string, TTSNode>.Create;
  try
    { The maps are (re)built per ShellExecute site from its enclosing routine --
      see ArgIsFixedSchemeUri -- so nothing is collected up front. }
    Visit(PF.Tree.RootNode, Default(TTSNode));
    Result:= Findings.ToArray;
  finally
    AsgnRhs  .Free;
    AsgnCount.Free;
    Findings .Free;
  end;
end; // function

class function TAstChecker.CheckPathTraversal(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  function PathArgIndex(const N: TTSNode; out AIdx: Integer): Boolean;
  var
    Ent, R: TTSNode;
    Nm    : string ;
  begin
    Result:= False;
    AIdx  := -1;
    Ent:= N.ChildByField('entity');
    if Ent.IsNull then Exit;
    if Ent.NodeType = 'identifier' then
    begin
      Nm:= NodeStr(Ent);
      if SameText(Nm, 'AssignFile') then begin AIdx:= 1; Exit(True); end;
      if SameText(Nm, 'FileOpen') or SameText(Nm, 'CreateFile') then begin AIdx:= 0; Exit(True); end;
    end
    else if Ent.NodeType = 'exprDot' then
    begin
      R:= Ent.ChildByField('rhs');
      if (not R.IsNull) and (R.NodeType = 'identifier') and SameText(NodeStr(R), 'Open') then begin AIdx:= 0; Exit(True); end;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, Idx     : Integer ;
    Args, A, Op: TTSNode ;
    P          : TTSPoint;
    F          : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if (N.NodeType = 'exprCall') and PathArgIndex(N, Idx) then
    begin
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount > Idx) then
      begin
        A:= Args.NamedChild(Idx);
        if A.NodeType = 'exprBinary' then
        begin
          Op:= A.ChildByField('operator');
          if (not Op.IsNull) and (Op.NodeType = 'kAdd') then
          begin
            P:= A.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'path-traversal';
            F.Severity:= 'warning';
            F.Message := 'Concatenated file path -- a user-controlled segment can escape the intended directory (path traversal, CWE-22). Validate or canonicalize the path.';
            F.FilePath:= AFile;
            F.StartLine:= Integer(P.Row   ) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine:= F.StartLine;
            F.EndCol := F.StartCol + 1;
            Findings.Add(F);
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckLoopAtMostOnce(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { The first executable statement of a loop body, unwrapped from its 'statement'
    node. For a begin..end body (block) the first 'statement' child is taken,
    skipping the kBegin/kEnd keyword tokens. Returns the body itself (which will
    not match) when no statement is found. }
  function FirstStmtInner(const ABody: TTSNode): TTSNode;
  var
    I    : Integer;
    B, C : TTSNode;
    Found: Boolean;
  begin
    Result:= ABody;
    B:= ABody;
    if B.IsNull then Exit;
    if B.NodeType = 'block' then
    begin
      Found:= False;
      for I:= 0 to B.NamedChildCount - 1 do
      begin
        C:= B.NamedChild(I);
        { Skip keyword tokens (kBegin/kEnd). The first real statement is the first
          non-keyword child -- which may be a BARE construct node (case/if/while/for/
          with/try) and NOT a 'statement' wrapper. Searching only for 'statement'
          here skipped a leading 'case' and wrongly landed on a later Exit (FP-4). }
        if (C.NodeType <> '') and (C.NodeType[1] = 'k') then Continue;
        B:= C; Found:= True; Break;
      end;
      if not Found then Exit;
    end;
    if B.NodeType = 'statement' then
    begin
      if B.NamedChildCount >= 1 then Result:= B.NamedChild(0) else Result:= B;
    end
    else
      Result:= B;
  end;

  function IsAtMostOnceExit(const N: TTSNode): Boolean;
  var
    T: string;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'raise' then Exit(True);
    if N.NodeType = 'identifier' then T:= NodeStr(N)
    else if N.NodeType = 'exprCall' then T:= NodeStr(N.ChildByField('entity'))
    else Exit(False);
    Result:= SameText(T, 'Exit') or SameText(T, 'Break');
  end;

  procedure Visit(const N: TTSNode);
  var
    I        : Integer ;
    Body, Fs : TTSNode ;
    P        : TTSPoint;
    F        : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if (N.NodeType = 'for') or (N.NodeType = 'while') or (N.NodeType = 'repeat') then
    begin
      Body:= N.ChildByField('body');
      Fs:= FirstStmtInner(Body);
      if IsAtMostOnceExit(Fs) then
      begin
        P:= Fs.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'loop-executes-at-most-once';
        F.Severity:= 'warning';
        F.Message := 'Loop body begins with Exit/Break/raise -- the loop runs at most once. Move the statement before the loop, or fix the loop logic.';
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckFormatCall(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Ordered conversion chars (lowercased) in a Format literal, excluding %% escapes. }
  { Conversion chars (lowercased) in a Format literal, excluding %% escapes. Sets
    AComplex when the format uses an argument index (%N:) or a *-width/precision,
    which consume arguments in ways this simple counter cannot model -- the caller
    then skips the call (better silent than a false positive; field report FP-2/FP-3). }
  function SpecKinds(const ALit: string; out AComplex: Boolean): TArray<Char>;
  var
    M    : TMatch     ;
    Kinds: TList<Char>;
    Body : string     ;
    Conv : string     ;
  begin
    AComplex:= False;
    Body:= ALit;
    if (Length(Body) >= 2) and (Body[1] = '''') then Body:= Copy(Body, 2, Length(Body) - 2);
    Body:= StringReplace(Body, '%%', '', [rfReplaceAll]);
    if TRegEx.IsMatch(Body, '%\d+\s*:') then AComplex:= True; { %N: argument index }
    Kinds:= TList<Char>.Create;
    try
      for M in TRegEx.Matches(Body, '%[-+ 0#]*(\d+|\*)?(\.(\d+|\*))?([a-zA-Z])') do
      begin
        if Pos('*', M.Value) > 0 then AComplex:= True; { *-width or *-precision }
        Conv:= M.Groups[4].Value;
        if Conv <> '' then Kinds.Add(LowerCase(Conv)[1]);
      end;
      Result:= Kinds.ToArray;
    finally
      Kinds.Free;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, J, AI                 : Integer ;
    Ent, Args, Fmt, Arr, Elem: TTSNode ;
    Elems                    : TArray<TTSNode>;
    Kinds                    : TArray<Char>;
    P, PE                    : TTSPoint;
    F                        : TLintFinding;
    K                        : Char    ;
    IsNum, IsIntOnly, BadType: Boolean ;
    IsComplex                : Boolean ;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and SameText(NodeStr(Ent), 'Format') then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount >= 2) then
        begin
          Fmt:= Args.NamedChild(0);
          Arr:= Args.NamedChild(1);
          if (Fmt.NodeType = 'literalString') and (Arr.NodeType = 'exprBrackets') then
          begin
            { A comment INSIDE the argument array is a named child of
              exprBrackets, so counting NamedChildCount counted it as an
              argument: an array holding one commented-out argument followed by
              one real argument was reported as "1 specifier but 2 arguments"
              against a single-specifier format string. Every 'error'-severity
              finding on the DataCopy corpus was this. Same skip as the
              executable-code walk above: a comment is not an argument. }
            Elems:= nil;
            for AI:= 0 to Arr.NamedChildCount - 1 do
              if Arr.NamedChild(AI).NodeType <> 'comment' then
                Elems:= Elems + [Arr.NamedChild(AI)];
            Kinds:= SpecKinds(NodeStr(Fmt), IsComplex);
            { count check -- skipped for indexed/star formats we cannot count reliably }
            if (not IsComplex) and (Length(Kinds) <> Length(Elems)) then
            begin
              P:= Ent.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'format-argument-count';
              F.Severity:= 'error';
              F.Message := Format('Format string has %d specifier(s) but %d argument(s) were supplied.', [Length(Kinds), Length(Elems)]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(P.Row   ) + 1;
              F.StartCol := Integer(P.Column) + 1;
              F.EndLine:= F.StartLine;
              F.EndCol := F.StartCol + 1;
              Findings.Add(F);
            end;
            { type check (literal arguments only) -- skipped for complex formats }
            if not IsComplex then
            for J:= 0 to Length(Kinds) - 1 do
            begin
              if J >= Length(Elems) then Break;
              Elem:= Elems[J]; { comment-free, so specifier J lines up with argument J }
              K:= Kinds[J];
              IsNum    := CharInSet(K, ['d', 'u', 'x', 'i', 'f', 'g', 'e', 'n']);
              IsIntOnly:= CharInSet(K, ['d', 'u', 'x', 'i']);
              BadType:= False;
              if Elem.NodeType = 'literalString' then BadType:= IsNum
              else if Elem.NodeType = 'literalNumber' then BadType:= IsIntOnly and (Pos('.', NodeStr(Elem)) > 0);
              if BadType then
              begin
                PE:= Elem.StartPoint;
                F:= Default(TLintFinding);
                F.RuleId  := 'format-specifier-type-mismatch';
                F.Severity:= 'error';
                F.Message := Format('Argument %d is incompatible with format specifier "%%%s".', [J + 1, string(K)]);
                F.FilePath:= AFile;
                F.StartLine:= Integer(PE.Row   ) + 1;
                F.StartCol := Integer(PE.Column) + 1;
                F.EndLine:= F.StartLine;
                F.EndCol := F.StartCol + 1;
                Findings.Add(F);
              end;
            end;
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckSwallowedExcept(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { The nearest enclosing 'defProc' ancestor of N (its own routine), or a null
    node if N is not inside one. Used to look up Result / var / out parameter
    names for the "assignment is handling" check below. }
  function EnclosingDefProc(const N: TTSNode): TTSNode;
  begin
    Result:= N.Parent;
    while (not Result.IsNull) and (Result.NodeType <> 'defProc') do
      Result:= Result.Parent;
  end;

  { Populates AHandled (case-insensitive) with the names an assignment INSIDE
    an except handler may target to count as "handling" the exception rather
    than swallowing it: the routine's own Result (only when it actually has a
    return type -- a procedure has no Result, so a coincidental local named
    "Result" does not count), and any 'var'/'out' parameter (the standard
    Delphi TryXxx idiom converts a caught exception into a status the caller
    is required to inspect via one of these). Value/const parameters and
    plain locals are deliberately excluded -- an assignment to a local that
    nothing outside the routine can observe does not communicate the failure
    anywhere, so it is not handling. }
  procedure CollectHandlingAssignTargets(const ADefProc: TTSNode; AHandled: TStrings);
  var
    Hdr, RetType, Args, DA, Modi, NameId: TTSNode;
    I, J: Integer;
    IsVarOrOut: Boolean;
  begin
    if ADefProc.IsNull then Exit;
    Hdr:= ADefProc.ChildByField('header');
    if Hdr.IsNull then Exit;
    RetType:= Hdr.ChildByField('type');
    if not RetType.IsNull then AHandled.Add('result');
    Args:= Hdr.ChildByField('args');
    if Args.IsNull then Exit;
    for I:= 0 to Args.NamedChildCount - 1 do
    begin
      DA:= Args.NamedChild(I);
      if DA.NodeType <> 'declArg' then Continue;
      IsVarOrOut:= False;
      for J:= 0 to DA.ChildCount - 1 do
      begin
        Modi:= DA.Child(J);
        if (Modi.NodeType = 'kVar') or (Modi.NodeType = 'kOut') then IsVarOrOut:= True;
      end;
      if not IsVarOrOut then Continue;
      for J:= 0 to DA.NamedChildCount - 1 do
      begin
        NameId:= DA.NamedChild(J);
        if NameId.NodeType = 'identifier' then AHandled.Add(LowerCase(Trim(NodeStr(NameId))));
      end;
    end;
  end;

  { True if the subtree contains a raise, an identifier/call whose text names a
    handler (HandleException/ShowException) or a logging/reporting routine, or
    an assignment to one of AHandled (the routine's Result / var / out
    parameters -- see CollectHandlingAssignTargets). That last case is the
    standard Delphi TryXxx shape: 'except Result:= False; end' converts the
    exception into a status the caller is required to check, so it is not
    silent even though it neither raises nor logs. An assignment to any other
    (plain local) name does NOT count -- that is still the case this rule
    exists to catch, and stays flagged. }
  { True when the already-lowercased node text is a call to `exit` WITH an
    argument -- `exit(False)`, `exit (X)`. A bare `exit;` answers False: it
    returns without saying anything, which is the swallow this rule is for. }
  function StartsWithExitCall(const AText: string): Boolean;
  var S: string; I: Integer;
  begin
    Result:= False;
    S:= TrimLeft(AText);
    if Copy(S, 1, 4) <> 'exit' then Exit;
    I:= 5;
    while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
    Result:= (I <= Length(S)) and (S[I] = '(');
  end;

  function HandlesException(const N: TTSNode; const AHandled: TStrings): Boolean;
  var
    I  : Integer;
    T  : string ;
    Lhs: TTSNode;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'raise' then Exit(True);
    if N.NodeType = 'assignment' then
    begin
      Lhs:= N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier')
         and (AHandled.IndexOf(LowerCase(Trim(NodeStr(Lhs)))) >= 0) then Exit(True);
      { v(2026-08-13b): writing the exception's own text THROUGH another object --
        `FResult.Text := '[Format error] ' + E.ClassName + ': ' + E.Message` puts
        it in a VCL memo on screen -- is reporting, and Task 9c's own test says
        why: the question is whether anything outside this routine can observe
        it. A member access reaches an object that outlives the routine, so it
        can. A bare local cannot, which is why this is keyed on exprDot and the
        LocalOnly/LocalOnlyFromException cases still fire.

        Deliberately narrower than "any exprDot LHS": the RHS must carry the
        exception. Assigning an unrelated value to a field is not reporting, and
        blanket-accepting a field write would gut the rule. }
      if (not Lhs.IsNull) and (Lhs.NodeType = 'exprDot') then
      begin
        T:= LowerCase(NodeStr(N));
        if (Pos('.message', T) > 0) or (Pos('.classname', T) > 0) then Exit(True);
      end;
    end;
    if (N.NodeType = 'identifier') or (N.NodeType = 'exprCall') or (N.NodeType = 'exprDot') then
    begin
      T:= LowerCase(NodeStr(N));
      if (Pos('handleexception', T) > 0) or (Pos('showexception', T) > 0)
         or (Pos('log', T) > 0) or (Pos('report', T) > 0) then Exit(True);
      { v(2026-08-10): a CONSOLE diagnostic is reporting, same as calling a
        routine with 'log' in its name. This rule already accepted log*/report*,
        but drag-lint is a CLI: its actual logging idiom is
        `Writeln(ErrOutput, ...)`, which contains neither substring -- so the
        rule reported "silently swallowed" on except bodies that visibly print
        the error. Two of twelve sampled findings were exactly that.

        Matched on 'writeln' rather than 'write' deliberately: bare 'write'
        appears in ordinary calls (WriteSymbol, TFile.WriteAllText, Rewrite),
        and accepting those would turn a real swallow into a false negative --
        the direction that costs more for this rule. }
      if (Pos('writeln', T) > 0) or (Pos('outputdebugstring', T) > 0)
         or (Pos('showmessage', T) > 0) then Exit(True);
      { v(2026-08-13): a MODAL DIALOG carrying the exception is reporting, and it
        is the loudest form of it -- the user cannot miss it. The rule already
        accepted ShowMessage but not MessageDlg/MessageBox, which are the VCL and
        Win32 idioms for the same act. Measured on YADFOT: two of three sampled
        findings were `except on E: Exception do MessageDlg('YADFOT: format
        failed.' + E.ClassName + ': ' + E.Message, mtError, [mbOK], 0)` --
        reported as "silently swallowed" while putting the class AND message on
        screen. }
      if (Pos('messagedlg', T) > 0) or (Pos('messagebox', T) > 0) then Exit(True);
      { v(2026-08-13b): stop guessing the SINK's name and look at what is being
        passed instead. The three amendments above (log/report, then writeln,
        then messagedlg/messagebox) are the same patch three times: each new
        codebase reports through a routine whose name nobody had listed yet.
        YADF's idiom is `DoIniStatus('  (save failed: ' + E.Message + ')')` --
        a UI status line carrying the message, matching none of the substrings,
        reported as "silently swallowed" on six handlers that visibly show the
        error.

        A sink can be called anything, but an exception cannot be reported
        without TOUCHING it. So: a CALL whose text carries the exception's own
        message or class name is reporting it, whoever it calls.

        Restricted to exprCall on purpose -- that is what keeps Task 9c's line
        intact. `FLocal := E.Message` is an ASSIGNMENT, not a call, and stays
        flagged exactly as tests/lint/try-except-swallowed.pas's LocalOnly case
        requires: handing the text to a local nothing outside the routine can
        observe still communicates nothing, while handing it to a callee, by
        definition, hands it somewhere else. }
      if (N.NodeType = 'exprCall')
         and ((Pos('.message', T) > 0) or (Pos('.classname', T) > 0)) then Exit(True);
      { v(2026-08-13c): `exit(X)` IS "assign Result, then return" -- the very
        TryXxx conversion Task 9c already accepts, written the other way round.
        The check above it looks for an `assignment` NODE, so the most common
        Delphi spelling of that idiom read as a silent swallow:

            except
              exit(False);          <- reported "silently swallowed"
            end;

        Measured on DataCopy: 3 of the 5 findings that survived every other
        clause were exactly this (uFileUtils.pas 1099, 1669, 1699), one of them
        returning a documented safe default. `exit` WITH an argument is legal
        only in a function, so accepting it cannot loosen the procedure case --
        a bare `exit;` carries no status and is deliberately NOT matched here. }
      if (N.NodeType = 'exprCall') and StartsWithExitCall(T) then Exit(True);
    end;
    for I:= 0 to N.ChildCount - 1 do
      if HandlesException(N.Child(I), AHandled) then Exit(True);
  end;

  { True when a comment carries HUMAN PROSE rather than a tool-written marker.

    `// dl:ok <rule>@<hash>` and `// drag-lint:ignore <rule>` are written by
    drag-lint itself (or for it), never as an explanation of why an exception is
    dropped. Letting one count as documentation would make the marker
    self-fulfilling: allow the finding, the marker silences the rule, the marker
    is then reported unused, removing it brings the finding back. Excluding them
    here is what keeps `try-except-swallowed` OUT of COMMENT_SENSITIVE -- the
    marker leaves the rule firing, so it suppresses normally and is accounted
    for. A human comment that merely also carries a marker still documents the
    swallow and still counts; the payload check, not Parse(), draws that line. }
  function IsExplanatoryComment(const AComment: TTSNode): Boolean;
  const
    MARKERS: array[0..1] of string = ('dl:ok', 'drag-lint:ignore');
  var
    S: string;
    M: string;
  begin
    S:= Trim(NodeStr(AComment));
    if Copy(S, 1, 2) = '//' then Delete(S, 1, 2)
    else if Copy(S, 1, 2) = '(*' then
    begin
      Delete(S, 1, 2);
      if Copy(S, Length(S) - 1, 2) = '*)' then SetLength(S, Length(S) - 2);
    end
    else if Copy(S, 1, 1) = '{' then
    begin
      Delete(S, 1, 1);
      if Copy(S, Length(S), 1) = '}' then SetLength(S, Length(S) - 1);
    end;
    { A doc-comment's third slash, and the leading $ of a compiler directive,
      are not prose either. A directive is code; it explains nothing. }
    while Copy(S, 1, 1) = '/' do Delete(S, 1, 1);
    if Copy(S, 1, 1) = '$' then Exit(False);
    S:= Trim(S);
    if S = '' then Exit(False);
    for M in MARKERS do
      if SameText(Copy(S, 1, Length(M)), M) then Exit(False);
    Result:= True;
  end;

  procedure Visit(const N: TTSNode);
  var
    I        : Integer ;
    HasExcept: Boolean ;
    Handled  : Boolean ;
    Documented  : Boolean;
    CommentsOnly: Boolean;
    C        : TTSNode ;
    ExceptPt : TTSPoint;
    F        : TLintFinding;
    HandledNames: TStringList;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.NodeType = 'try' then
    begin
      HasExcept:= False;
      Handled  := False;
      Documented  := False;
      CommentsOnly:= True;
      ExceptPt := Default(TTSPoint);
      HandledNames:= TStringList.Create;
      try
        HandledNames.CaseSensitive:= False;
        CollectHandlingAssignTargets(EnclosingDefProc(N), HandledNames);
        for I:= 0 to N.ChildCount - 1 do
        begin
          C:= N.Child(I);
          if C.NodeType = 'kExcept' then
          begin
            HasExcept:= True;
            ExceptPt := C.StartPoint;
          end
          else if HasExcept then
          begin
            { STOP at the closing keyword, do not merely skip it. A `try` node's
              LAST child is an anonymous `;` that sits AFTER kEnd, and the
              s-expression form of the tree does not show it (ToString prints
              named children only). Skipping kEnd and continuing therefore let
              that semicolon through as "a non-comment child of the handler",
              which silently set CommentsOnly to False on EVERY try node in the
              file -- so a documented swallow still fired and the shape looked
              impossible to reproduce. `tools\dumpnode` prints named and
              anonymous children alike, which is what made it visible. }
            if (C.NodeType = 'kEnd') or (C.NodeType = 'kFinally') then Break;
            if not C.IsNamed then Continue; { punctuation is not code }
            if C.NodeType = 'comment' then
            begin
              if IsExplanatoryComment(C) then Documented:= True;
            end
            else
            begin
              CommentsOnly:= False;
              if HandlesException(C, HandledNames) then Handled:= True;
            end;
          end;
        end;
      finally
        HandledNames.Free;
      end;
      { v(2026-08-13, owner ruling): a DOCUMENTED deliberate swallow is accepted.
        The shape is an except body that runs NO code and carries an explanation
        of why dropping the exception is the lesser evil -- the canonical case
        being a destructor running during Spring's GlobalContainer finalization,
        where an escaping exception is far worse than a lost settings write.

        Both halves are required. `CommentsOnly` is what keeps the rule's teeth:
        a handler that DOES run code and merely carries a trailing `// retry
        backoff` still fires, because there the exception vanishes while
        something else happens -- the more dangerous case, not the documented
        one. Only a handler that visibly does nothing, on purpose, in writing,
        is accepted.

        This also lines the rule up with `empty-except`, which stops firing on
        the same shape (its .scm anchors kExcept ADJACENT to kEnd, and a comment
        breaks the adjacency). Before this, a documented empty handler produced
        one finding and not the other, from the same two lines of source. }
      if HasExcept and (not Handled) and (not (Documented and CommentsOnly)) then
      begin
        F:= Default(TLintFinding);
        F.RuleId  := 'try-except-swallowed';
        F.Severity:= 'warning';
        F.Message := 'Exception silently swallowed -- add raise, logging, or Application.HandleException.';
        F.FilePath:= AFile;
        F.StartLine:= Integer(ExceptPt.Row   ) + 1;
        F.StartCol := Integer(ExceptPt.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 6;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckDatasetOpen(const AFile: string): TArray<TLintFinding>;
var
  Src            : TBytes                     ;
  PF      : TParsedFile        ;
  Findings       : TList<TLintFinding>        ;
  Opened         : TDictionary<string, TTSPoint>;
  ClosedInFinally: TDictionary<string, Boolean> ;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { X.M or X.M(...) -> AVar=lower(X), AMethod=M. }
  function DotMethod(const N: TTSNode; out AVar, AMethod: string): Boolean;
  var
    Dot, L, R, Ent: TTSNode;
  begin
    Result:= False;
    Dot:= N;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if Ent.IsNull or (Ent.NodeType <> 'exprDot') then Exit;
      Dot:= Ent;
    end
    else if N.NodeType <> 'exprDot' then Exit;
    L:= Dot.ChildByField('lhs');
    R:= Dot.ChildByField('rhs');
    if L.IsNull or R.IsNull or (L.NodeType <> 'identifier') or (R.NodeType <> 'identifier') then Exit;
    AVar   := LowerCase(NodeStr(L));
    AMethod:= NodeStr(R);
    Result := True;
  end;

  { X.Active := True (AWantTrue) or X.Active := False. }
  function IsActiveAssign(const N: TTSNode; AWantTrue: Boolean; out AVar: string): Boolean;
  var
    L, R, DL, DR: TTSNode;
  begin
    Result:= False;
    if N.NodeType <> 'assignment' then Exit;
    L:= N.ChildByField('lhs');
    R:= N.ChildByField('rhs');
    if L.IsNull or (L.NodeType <> 'exprDot') then Exit;
    DR:= L.ChildByField('rhs');
    if DR.IsNull or not SameText(NodeStr(DR), 'Active') then Exit;
    DL:= L.ChildByField('lhs');
    if DL.IsNull or (DL.NodeType <> 'identifier') then Exit;
    if AWantTrue and (R.NodeType <> 'kTrue') then Exit;
    if (not AWantTrue) and (R.NodeType <> 'kFalse') then Exit;
    AVar:= LowerCase(NodeStr(DL));
    Result:= True;
  end;

  { DESTROYING a dataset closes it. TDataSet.Destroy calls Close before it frees
    anything, so `try Q.Open ... finally Q.Free end` leaks no cursor and is a
    perfectly ordinary Delphi idiom -- the same one the RTL's own examples use.

    The rule did not model this, and that single omission was 95 of the findings
    on this repo alone (Storage.SQLite.pas:491, 524, 626 among them). Every one
    told the reader to add a Close that the language already guarantees. A rule
    whose advice is redundant is not a lesser bug than one whose advice is
    wrong: it costs the same attention and it teaches the reader to skim.

    Free / Destroy / DisposeOf as a method call, and FreeAndNil(X) as a free
    function, all mean the same thing here. }
  function IsDestroyingCall(const N: TTSNode; out AVar: string): Boolean;
  var
    M   : string ;
    Ent, Args, A0: TTSNode;
  begin
    if DotMethod(N, AVar, M) then
      Exit(SameText(M, 'Free') or SameText(M, 'Destroy') or SameText(M, 'DisposeOf'));
    Result:= False;
    if N.NodeType <> 'exprCall' then Exit;
    Ent:= N.ChildByField('entity');
    if Ent.IsNull or (Ent.NodeType <> 'identifier') or not SameText(NodeStr(Ent), 'FreeAndNil') then Exit;
    Args:= N.ChildByField('args');
    if Args.IsNull or (Args.NamedChildCount < 1) then Exit;
    A0:= Args.NamedChild(0);
    if A0.NodeType = 'identifier' then begin AVar:= LowerCase(NodeStr(A0)); Result:= True; end;
  end;

  procedure WalkBody(const N: TTSNode; AInFinally: Boolean);
  var
    I   : Integer;
    V, M: string ;
    Lf  : Boolean;
    C   : TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Exit;
    if DotMethod(N, V, M) then
    begin
      if SameText(M, 'Open') then
      begin if not Opened.ContainsKey(V) then Opened.Add(V, N.StartPoint); end
      else if SameText(M, 'Close') and AInFinally then ClosedInFinally.AddOrSetValue(V, True);
    end
    else if IsActiveAssign(N, True, V) then
    begin if not Opened.ContainsKey(V) then Opened.Add(V, N.StartPoint); end
    else if IsActiveAssign(N, False, V) and AInFinally then ClosedInFinally.AddOrSetValue(V, True);
    { Checked SEPARATELY, not as an else-arm: the branch above already consumed
      the DotMethod result for the Open/Close names, and a Free would otherwise
      fall through it. }
    if AInFinally and IsDestroyingCall(N, V) then ClosedInFinally.AddOrSetValue(V, True);
    if N.NodeType = 'try' then
    begin
      Lf:= False;
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        if C.NodeType = 'kFinally' then Lf:= True;
        WalkBody(C, AInFinally or Lf);
      end;
    end
    else
      for I:= 0 to N.ChildCount - 1 do WalkBody(N.Child(I), AInFinally);
  end; // procedure

  procedure VisitProcs(const N: TTSNode);
  var
    I   : Integer ;
    Body: TTSNode ;
    Pair: TPair<string, TTSPoint>;
    F   : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      if not Body.IsNull then
      begin
        Opened         := TDictionary<string, TTSPoint>.Create;
        ClosedInFinally:= TDictionary<string, Boolean> .Create;
        try
          WalkBody(Body, False);
          for Pair in Opened do
            if not ClosedInFinally.ContainsKey(Pair.Key) then
            begin
              F:= Default(TLintFinding);
              F.RuleId  := 'dataset-open-without-close';
              F.Severity:= 'warning';
              F.Message := Format('Dataset %s is opened without a matching Close in a finally block -- it leaks a server cursor on an exception path.', [Pair.Key]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(Pair.Value.Row   ) + 1;
              F.StartCol := Integer(Pair.Value.Column) + 1;
              F.EndLine:= F.StartLine;
              F.EndCol := F.StartCol + 1;
              Findings.Add(F);
            end;
        finally
          Opened.Free;
          ClosedInFinally.Free;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckCriticalSection(const AFile: string): TArray<TLintFinding>;
var
  Src             : TBytes                       ;
  PF      : TParsedFile        ;
  Findings        : TList<TLintFinding>          ;
  Acquired        : TDictionary<string, TTSPoint>;
  ReleasedInFinally: TDictionary<string, Boolean>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { X.M or X.M(...) -> AVar=lower(X), AMethod=M. }
  function DotMethod(const N: TTSNode; out AVar, AMethod: string): Boolean;
  var
    Dot, L, R, Ent: TTSNode;
  begin
    Result:= False;
    Dot:= N;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if Ent.IsNull or (Ent.NodeType <> 'exprDot') then Exit;
      Dot:= Ent;
    end
    else if N.NodeType <> 'exprDot' then Exit;
    L:= Dot.ChildByField('lhs');
    R:= Dot.ChildByField('rhs');
    if L.IsNull or R.IsNull or (L.NodeType <> 'identifier') or (R.NodeType <> 'identifier') then Exit;
    AVar   := LowerCase(NodeStr(L));
    AMethod:= NodeStr(R);
    Result := True;
  end;

  procedure WalkBody(const N: TTSNode; AInFinally: Boolean);
  var
    I   : Integer;
    V, M: string ;
    Lf  : Boolean;
    C   : TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Exit;
    if DotMethod(N, V, M) then
    begin
      if SameText(M, 'Enter') or SameText(M, 'Acquire') then
      begin if not Acquired.ContainsKey(V) then Acquired.Add(V, N.StartPoint); end
      else if (SameText(M, 'Leave') or SameText(M, 'Release')) and AInFinally then ReleasedInFinally.AddOrSetValue(V, True);
    end;
    if N.NodeType = 'try' then
    begin
      Lf:= False;
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        if C.NodeType = 'kFinally' then Lf:= True;
        WalkBody(C, AInFinally or Lf);
      end;
    end
    else
      for I:= 0 to N.ChildCount - 1 do WalkBody(N.Child(I), AInFinally);
  end; // procedure

  procedure VisitProcs(const N: TTSNode);
  var
    I   : Integer ;
    Body: TTSNode ;
    Pair: TPair<string, TTSPoint>;
    F   : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      if not Body.IsNull then
      begin
        Acquired         := TDictionary<string, TTSPoint>.Create;
        ReleasedInFinally:= TDictionary<string, Boolean> .Create;
        try
          WalkBody(Body, False);
          for Pair in Acquired do
            if not ReleasedInFinally.ContainsKey(Pair.Key) then
            begin
              F:= Default(TLintFinding);
              F.RuleId  := 'criticalsection-not-released';
              F.Severity:= 'error';
              F.Message := Format('Critical section %s is acquired without a matching Leave/Release in a finally block -- a lock leaked on an exception path deadlocks.', [Pair.Key]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(Pair.Value.Row   ) + 1;
              F.StartCol := Integer(Pair.Value.Column) + 1;
              F.EndLine:= F.StartLine;
              F.EndCol := F.StartCol + 1;
              Findings.Add(F);
            end;
        finally
          Acquired.Free;
          ReleasedInFinally.Free;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    VisitProcs(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckTooManyExitPoints(const AFile: string): TArray<TLintFinding>;
begin
  Result:= CheckTooManyExitPoints(AFile, 5);   // historic default
end;

class function TAstChecker.CheckTooManyExitPoints(const AFile: string; AMaxExits: Integer): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  function CountExits(const N: TTSNode): Integer;
  var
    I  : Integer;
    T  : string ;
    Ent: TTSNode;
    C  : TTSNode;
    ViaCall: Boolean;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Exit; { nested routine counted separately }
    ViaCall:= False;
    if N.NodeType = 'identifier' then T:= NodeStr(N)
    else if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      T  := NodeStr(Ent);
      ViaCall:= True;
    end
    else T:= '';
    if SameText(T, 'Exit') then Inc(Result);
    for I:= 0 to N.ChildCount - 1 do
    begin
      C:= N.Child(I);
      { THE DOUBLE COUNT. `Exit(Value)` parses as exprCall(entity: identifier
        'Exit', args: ...). The arm above counts the CALL, and then this loop
        used to descend into that same entity identifier -- whose text is also
        'Exit' -- and count it a SECOND time. A bare `exit;` is a plain
        identifier with no entity child, so it counted once, and the two forms
        disagreed inside the same routine with nothing to show for it.

        Measured before the fix: 3 x `Exit(False)` reported "6", so a routine in
        the modern guard-clause style was judged against an effective threshold
        of ~2.5 instead of 5 -- the rule fired hardest on the CLEANEST code.

        The entity is skipped by BYTE RANGE rather than by testing the child's
        text for 'Exit': a text test would also swallow a genuine second exit
        that happened to sit inside this call's arguments (`Exit(F(Exit))` is
        not legal, but `Exit(A[Ord(x)])` shows arguments do get walked), and the
        args subtree must keep being counted. }
      if ViaCall and (not Ent.IsNull)
         and (C.StartByte = Ent.StartByte) and (C.EndByte = Ent.EndByte) then Continue;
      Result:= Result + CountExits(C);
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, NExit  : Integer ;
    Hdr, Body : TTSNode ;
    P         : TTSPoint;
    F         : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      NExit:= CountExits(Body);
      if NExit > AMaxExits then
      begin
        Hdr:= N.ChildByField('header');
        if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'too-many-exit-points';
        F.Severity:= 'info';
        F.Message := Format('Routine has %d Exit statements (max %d) -- consolidate exits or use guard clauses.', [NExit, AMaxExits]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

// v(ADP2 T3): shared cyclomatic decision-count, extracted from
// CheckCyclomaticComplexity's former local CountDecisions so BOTH the lint
// rule (via TAstChecker.CyclomaticOf below) and the Auto-Document Complexity
// fact (DRagLint.Doc.SymbolFacts) use the exact same formula and can never
// diverge on what one routine's complexity is. Recursively counts
// decision-point nodes -- if/ifElse/while/for/repeat/kAnd/kOr/caseCase --
// under N, stopping at (not descending into) a nested defProc: a local
// routine is counted separately, the next time it is visited on its own.
// Node kinds verified against the grammar by
// tests\lint\cyclomatic-complexity.pas/.expected.
function CyclomaticCountDecisions(const N: TTSNode): Integer;
var
  I: Integer;
  K: string ;
begin
  Result:= 0;
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then Exit; { nested routine counted separately }
  K:= N.NodeType;
  if (K = 'if') or (K = 'ifElse') or (K = 'while') or (K = 'for') or (K = 'repeat')
     or (K = 'kAnd') or (K = 'kOr') or (K = 'caseCase') then Inc(Result);
  for I:= 0 to N.ChildCount - 1 do Result:= Result + CyclomaticCountDecisions(N.Child(I));
end;

{ stat-gated-destructive -- INBOX-stat-gated-destructive-acts (from DataCopy).

  THE DEFECT CLASS. FileExists / TFile.Exists return False for ANY failure to
  stat -- a network blip, a permission change, a share dropping -- not only for
  genuine absence. Cash that boolean as a destructive act and a transient fault
  silently destroys data and returns success. Confirmed six times in one
  codebase, once inside the RTL itself.

  WHY A LINT RULE AND NOT A TEST, in the requester's words: the correct fix
  REMOVES the stat from the decision, so a test that injects a fake FileExists
  hooks nothing after the fix and degenerates into a trivial pass -- a test that
  certifies its own bug. Only a rule fires at write time, on code not yet
  written.

  ARGUMENT EQUALITY IS DELIBERATELY NOT REQUIRED, and that is a CORRECTION to
  the note, which asked for the destructive call to be "on the same path
  expression X". Measured against its own headline instance:

      if FileExists(F) then Append(TF) else Rewrite(TF);

  the stat is on the PATH and the destructive call takes the TEXTFILE HANDLE, so
  a same-argument matcher would have missed the very site the rule was requested
  for. Precision comes instead from the destructive NAME SET being small and
  specific, and from the whole match staying inside ONE statement.

  NOT MATCHED, deliberately: the note's pattern 3 (`if Exists then Size :=
  GetSize else Size := 0`, whose destructive consequence is a rollback hundreds
  of lines later). Its harm is genuinely cross-statement, the note itself
  declines dataflow, and a capture-site heuristic needs its own false-positive
  measurement before it earns any severity. }
class function TAstChecker.CheckStatGatedDestructive(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { The callee as written: `FileExists`, or the whole dotted `TFile.Exists`. }
  function CalleeText(const ACall: TTSNode): string;
  begin
    Result:= '';
    if ACall.IsNull or (ACall.NodeType <> 'exprCall') then Exit;
    if ACall.ChildCount = 0 then Exit;
    Result:= Trim(NodeStr(ACall.Child(0)));
  end;

  function IsExistenceName(const AName: string): Boolean;
  begin
    Result:= SameText(AName, 'FileExists'      ) or SameText(AName, 'TFile.Exists') or
             SameText(AName, 'DirectoryExists' ) or SameText(AName, 'TDirectory.Exists');
  end;

  { Small and specific ON PURPOSE. `Rewrite` is CREATE_ALWAYS; the rest delete
    or truncate. Anything wider -- every Free, every Clear -- turns this into
    noise, on a rule whose requester asked for error severity. }
  function IsDestructiveName(const AName: string): Boolean;
  begin
    Result:= SameText(AName, 'Rewrite'         ) or SameText(AName, 'DeleteFile') or
             SameText(AName, 'TFile.Delete'    ) or SameText(AName, 'SafeDelete') or
             SameText(AName, 'TruncateOutputTo');
  end;

  { The filename+append TStreamWriter overload, banned flat. Its RTL body is
    `if not Append or not FileExists(Filename) then TFileStream.Create(...,
    fmCreate)` -- the identical race one layer down, where no care at the call
    site can reach it. Told apart from the safe Create(Stream, Encoding) form by
    a BOOLEAN LITERAL as the second argument, which the stream overload -- whose
    second argument is an encoding -- never has. }
  function IsFilenameAppendWriter(const ACall: TTSNode): Boolean;
  var Args: TTSNode; A1: string;
  begin
    Result:= False;
    if not SameText(CalleeText(ACall), 'TStreamWriter.Create') then Exit;
    Args:= ACall.ChildByField('args');
    if Args.IsNull and (ACall.ChildCount > 2) then Args:= ACall.Child(2);
    if Args.IsNull or (Args.NamedChildCount < 2) then Exit;
    A1:= Trim(NodeStr(Args.NamedChild(1)));
    { APPEND=TRUE ONLY. With False the caller is ASKING to create/truncate and
      the RTL's internal FileExists cannot change the outcome; the race only
      bites when append was requested and a failed stat silently turns it into
      fmCreate. Measured: without this, DRagLint.CLI.pas:9295
      `TStreamWriter.Create(AArgs.Output, False, TEncoding.UTF8)` -- a
      deliberate create -- was reported. }
    Result:= SameText(A1, 'True');
  end;

  { First matching call in the subtree. Does not descend into a nested routine,
    whose statements are not part of this decision. }
  function FindCall(const N: TTSNode; AWantExistence: Boolean): TTSNode;
  var I: Integer; R: TTSNode; T: string;
  begin
    Result:= Default(TTSNode);
    if N.IsNull or (N.NodeType = 'defProc') then Exit;
    if N.NodeType = 'exprCall' then
    begin
      T:= CalleeText(N);
      if AWantExistence and IsExistenceName(T) then Exit(N);
      if (not AWantExistence) and IsDestructiveName(T) then Exit(N);
    end;
    for I:= 0 to N.ChildCount - 1 do
    begin
      R:= FindCall(N.Child(I), AWantExistence);
      if not R.IsNull then Exit(R);
    end;
  end;

  procedure Emit(const AAt: TTSNode; const AMsg: string);
  var P: TTSPoint; F: TLintFinding;
  begin
    if AAt.IsNull then Exit;
    P:= AAt.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId  := 'stat-gated-destructive';
    F.Severity:= 'warning';
    F.Message := AMsg;
    F.FilePath:= AFile;
    F.StartLine:= Integer(P.Row) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine:= F.StartLine;
    F.EndCol := F.StartCol + 1;
    Findings.Add(F);
  end;

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
    Cond, Branch, Ex, De: TTSNode;
    Handled: Boolean;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    Handled:= False;

    { Pattern 4 -- flow-free, so it is asked of every call node. }
    if (N.NodeType = 'exprCall') and IsFilenameAppendWriter(N) then
      Emit(N, 'TStreamWriter.Create(filename, append) decides internally with FileExists and ' +
              'can truncate on a failed stat -- open the stream yourself and use the ' +
              'Create(Stream, Encoding) overload.');

    { Pattern 1 -- an existence check in the CONDITION, a destructive call in a
      BRANCH. `if` (then only) and `ifElse` (then + else) are SEPARATE node
      types in this grammar; handling only one of them was the obvious way to
      half-implement this. }
    if (N.NodeType = 'if') or (N.NodeType = 'ifElse') then
    begin
      Cond:= Default(TTSNode);
      for I:= 0 to N.ChildCount - 1 do
        if N.Child(I).NodeType = 'kThen' then Break
        else if N.Child(I).NodeType <> 'kIf' then Cond:= N.Child(I);
      Ex:= FindCall(Cond, True);
      if not Ex.IsNull then
        for I:= 0 to N.ChildCount - 1 do
        begin
          Branch:= N.Child(I);
          if (Branch.NodeType = 'kIf') or (Branch.NodeType = 'kThen') or
             (Branch.NodeType = 'kElse') then Continue;
          if Branch.StartByte < Cond.EndByte then Continue; { the condition itself }
          { SINGLE-STATEMENT BRANCHES ONLY, which is the note's own stated design
            ("keeping the match within one statement is what makes this precise
            rather than noisy") and is here because the wider form measured
            noisy. DRagLint.CLI.pas:20433 redirects stdout to the null device --
            `AssignFile(Output, 'NUL'); Rewrite(Output);` -- inside a try inside
            a multi-statement branch, and got paired with an unrelated
            TDirectory.Exists in the condition far above it. Rewriting the NUL
            device destroys nothing.

            KNOWN LIMITATION, named rather than hidden: `if Exists(F) then begin
            TFile.Delete(F); end;` is a genuine instance and is NOT matched. The
            block form is where an incidental destructive call is most likely to
            be unrelated to the stat, and a false ERROR on correct code costs
            more here than a missed one. }
          if Branch.NodeType = 'block' then Continue;
          De:= FindCall(Branch, False);
          if not De.IsNull then
          begin
            Emit(De, Format('Destructive call %s is gated on %s -- a failed stat (a network blip, ' +
                            'a permission change) answers False, takes this branch, destroys data ' +
                            'and returns success. Act first and read the OS error instead.',
                            [CalleeText(De), CalleeText(Ex)]));
            Handled:= True;
            Break;
          end;
        end;
    end;

    { Pattern 2 -- ONE expression carrying both, e.g.
      `Result := (not TFile.Exists(X)) or SafeDelete(X, E);`
      Skipped when the if arm above already reported, so a single site is never
      counted twice. }
    if (not Handled) and ((N.NodeType = 'assignment') or (N.NodeType = 'statement')) then
    begin
      Ex:= FindCall(N, True);
      De:= FindCall(N, False);
      if (not Ex.IsNull) and (not De.IsNull) then
        Emit(De, Format('%s is short-circuited by %s in one expression -- a failed stat answers ' +
                        'False, the destructive call never runs, and the result still reads as ' +
                        'success.', [CalleeText(De), CalleeText(Ex)]));
    end;

    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try
    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CyclomaticOf(const ABody: TTSNode): Integer;
begin
  Result:= 1 + CyclomaticCountDecisions(ABody);
end;

class function TAstChecker.CheckCyclomaticComplexity(const AFile: string): TArray<TLintFinding>;
begin
  Result:= CheckCyclomaticComplexity(AFile, 15);   // historic default
end;

class function TAstChecker.CheckCyclomaticComplexity(const AFile: string; AMaxComplexity: Integer): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  procedure Visit(const N: TTSNode);
  var
    I, CC     : Integer ;
    Hdr, Body : TTSNode ;
    P         : TTSPoint;
    F         : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      CC:= CyclomaticOf(Body); // v(ADP2 T3): shared formula (was: 1 + CountDecisions(Body))
      if CC > AMaxComplexity then
      begin
        Hdr:= N.ChildByField('header');
        if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'cyclomatic-complexity';
        F.Severity:= 'info';
        F.Message := Format('Routine has cyclomatic complexity %d (max %d) -- consider extracting sub-routines.', [CC, AMaxComplexity]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try

    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckCognitiveComplexity(const AFile: string): TArray<TLintFinding>;
begin
  Result:= CheckCognitiveComplexity(AFile, 25);   // default limit (cognitive scores higher than cyclomatic)
end;

class function TAstChecker.CheckCognitiveComplexity(const AFile: string; AMaxScore: Integer): TArray<TLintFinding>;
var
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  { SonarSource-style: each control-flow structure adds 1 + its nesting depth;
    each boolean operator (and/or/xor) adds 1 (no nesting). Nested routines are
    scored separately (recursion stops at a nested defProc). }
  function Score(const N: TTSNode; ANest: Integer): Integer;
  var I: Integer; K: string;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    K:= N.NodeType;
    if K = 'defProc' then Exit;
    if (K = 'if') or (K = 'ifElse') or (K = 'while') or (K = 'for') or (K = 'repeat')
       or (K = 'case') or (K = 'exceptionHandler') then
    begin
      Result:= 1 + ANest;
      for I:= 0 to N.ChildCount - 1 do Result:= Result + Score(N.Child(I), ANest + 1);
      Exit;
    end;
    if (K = 'kAnd') or (K = 'kOr') or (K = 'kXor') then Result:= 1;
    for I:= 0 to N.ChildCount - 1 do Result:= Result + Score(N.Child(I), ANest);
  end;

  procedure Visit(const N: TTSNode);
  var
    I, CC     : Integer ;
    Hdr, Body : TTSNode ;
    P         : TTSPoint;
    F         : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      CC:= Score(Body, 0);
      if CC > AMaxScore then
      begin
        Hdr:= N.ChildByField('header');
        if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'cognitive-complexity';
        F.Severity:= 'info';
        F.Message := Format('Routine cognitive complexity %d (max %d) -- deeply nested / branchy control flow is hard to follow; flatten or extract sub-routines.', [CC, AMaxScore]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckVirtualInConstructor(const AFile: string; const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
var
  Src        : TBytes                                          ;
  PF      : TParsedFile        ;
  Findings   : TList<TLintFinding>                             ;
  VirtByClass: TDictionary<string, TDictionary<string, Boolean>>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { True if the subtree declares a virtual/dynamic/override attribute. }
  function HasVirtualAttr(const N: TTSNode): Boolean;
  var
    I: Integer;
    K: string ;
  begin
    Result:= False;
    if N.IsNull then Exit;
    K:= N.NodeType;
    if (K = 'kVirtual') or (K = 'kDynamic') or (K = 'kOverride') then Exit(True);
    for I:= 0 to N.ChildCount - 1 do
      if HasVirtualAttr(N.Child(I)) then Exit(True);
  end;

  { Add the names of virtually-dispatched methods declared directly in ADeclClass. }
  procedure CollectClassMethods(const ADeclClass: TTSNode; const ASet: TDictionary<string, Boolean>);

    procedure Walk(const N: TTSNode);
    var
      I       : Integer;
      NameNode: TTSNode;
      MName   : string ;
    begin
      if N.IsNull then Exit;
      if N.NodeType = 'declProc' then
      begin
        if HasVirtualAttr(N) then
        begin
          NameNode:= N.ChildByField('name');
          if (not NameNode.IsNull) and (NameNode.NodeType = 'identifier') then
          begin
            MName:= LowerCase(NodeStr(NameNode));
            if MName <> '' then ASet.AddOrSetValue(MName, True);
          end;
        end;
        Exit; { a method decl has no virtual methods of its own nested below }
      end;
      for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
    end; // procedure

  begin
    Walk(ADeclClass);
  end; // procedure

  { Pass 1: map each class name (lower) -> set of its virtual method names (lower). }
  procedure CollectClasses(const N: TTSNode);
  var
    I, K              : Integer ;
    NameNode, TypeNode: TTSNode ;
    CName             : string  ;
    Setm              : TDictionary<string, Boolean>;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declType' then
    begin
      NameNode:= N.ChildByField('name');
      TypeNode:= N.ChildByField('type');
      if (not NameNode.IsNull) and (not TypeNode.IsNull) then
        for K:= 0 to TypeNode.ChildCount - 1 do
          if TypeNode.Child(K).NodeType = 'declClass' then
          begin
            CName:= LowerCase(NodeStr(NameNode));
            if CName <> '' then
            begin
              if not VirtByClass.TryGetValue(CName, Setm) then
              begin
                Setm:= TDictionary<string, Boolean>.Create;
                VirtByClass.Add(CName, Setm);
              end;
              CollectClassMethods(TypeNode.Child(K), Setm);
            end;
            Break;
          end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectClasses(N.NamedChild(I));
  end; // procedure

  { Flag any virtually-dispatched self-call inside a constructor body. }
  procedure FlagCalls(const M: TTSNode; const ASet: TDictionary<string, Boolean>);
  var
    I        : Integer    ;
    Lhs, Rhs : TTSNode    ;
    P        : TTSPoint   ;
    F        : TLintFinding;
  begin
    if M.IsNull or (Findings.Count >= 200) then Exit;
    if (M.NodeType = 'defProc') or (M.NodeType = 'inherited') then Exit; { nested routine / static ancestor call }
    if M.NodeType = 'exprDot' then
    begin
      Lhs:= M.ChildByField('lhs');
      Rhs:= M.ChildByField('rhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') and SameText(NodeStr(Lhs), 'Self') and
         (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') and ASet.ContainsKey(LowerCase(NodeStr(Rhs))) then
      begin
        P:= Rhs.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'virtual-method-in-constructor';
        F.Severity:= 'warning';
        F.Message := Format('Constructor calls virtual/dynamic method "%s" -- it dispatches to a descendant override whose fields are not yet initialised. Move the call out of the constructor or make the method non-virtual.', [NodeStr(Rhs)]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + Length(NodeStr(Rhs));
        Findings.Add(F);
      end;
      FlagCalls(Lhs, ASet); { receiver may itself contain a call; member name (rhs) is not a self-call }
      Exit;
    end;
    if M.NodeType = 'identifier' then
    begin
      if ASet.ContainsKey(LowerCase(NodeStr(M))) then
      begin
        P:= M.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'virtual-method-in-constructor';
        F.Severity:= 'warning';
        F.Message := Format('Constructor calls virtual/dynamic method "%s" -- it dispatches to a descendant override whose fields are not yet initialised. Move the call out of the constructor or make the method non-virtual.', [NodeStr(M)]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row   ) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + Length(NodeStr(M));
        Findings.Add(F);
      end;
      Exit;
    end;
    for I:= 0 to M.NamedChildCount - 1 do FlagCalls(M.NamedChild(I), ASet);
  end; // procedure

  { Pass 2: walk constructor implementations, resolve their class's virtual set. }
  procedure CheckCtors(const N: TTSNode);
  var
    I              : Integer;
    Hdr, NameNode  : TTSNode;
    Lhs, Body      : TTSNode;
    CName          : string ;
    IsCtor         : Boolean;
    Setm           : TDictionary<string, Boolean>;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
    begin
      Hdr:= N.ChildByField('header');
      if not Hdr.IsNull then
      begin
        IsCtor:= False;
        for I:= 0 to Hdr.ChildCount - 1 do
          if Hdr.Child(I).NodeType = 'kConstructor' then begin IsCtor:= True; Break; end;
        if IsCtor then
        begin
          NameNode:= Hdr.ChildByField('name');
          if (not NameNode.IsNull) and (NameNode.NodeType = 'genericDot') then
          begin
            Lhs:= NameNode.ChildByField('lhs');
            if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') then
            begin
              CName:= LowerCase(NodeStr(Lhs));
              { Effective virtual set = this class's own virtuals (from the file
                AST) UNION, when a store is present, the inherited virtuals from
                cross-unit ancestors. So a ctor calling an ancestor-declared
                virtual is caught even though it is not declared in this file. }
              var Eff:= TDictionary<string, Boolean>.Create;
              try
                if VirtByClass.TryGetValue(CName, Setm) then
                  for var Kn in Setm.Keys do Eff.AddOrSetValue(Kn, True);
                if AStore <> nil then
                  for var Vn in AStore.GetVirtualMethodsIncludingAncestors(NodeStr(Lhs), AFileId) do
                    Eff.AddOrSetValue(LowerCase(Vn), True);
                if Eff.Count > 0 then
                begin
                  Body:= N.ChildByField('body');
                  if not Body.IsNull then FlagCalls(Body, Eff);
                end;
              finally
                Eff.Free;
              end;
            end;
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CheckCtors(N.NamedChild(I));
  end; // procedure

var
  Inner: TDictionary<string, Boolean>;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  VirtByClass:= TDictionary<string, TDictionary<string, Boolean>>.Create;
  try

    if PF.Tree <> nil then
    begin
      CollectClasses(PF.Tree.RootNode);
      CheckCtors   (PF.Tree.RootNode);
    end;
    Result:= Findings.ToArray;
  finally
    for Inner in VirtByClass.Values do Inner.Free;
    VirtByClass.Free;
    Findings.Free;
  end;
end; // function

initialization

finalization
GKeywordSet.Free;
GKeywordSet:= nil;

end.
