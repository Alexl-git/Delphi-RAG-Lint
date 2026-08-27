unit DRagLint.Lint.Linter;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.Math
  , System.Types
  , System.Generics.Collections
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core  .Model
  , DRagLint.Core  .Encoding
  , DRagLint.Parser.Delphi13
  , DRagLint.Lint  .QueryRules
  , DRagLint.Lint  .ReviewMarker { REVIEW_MARK -- a tool-written marker is not a hand-written inline comment }
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas), declaration (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.EnsureLinter (DRagLint.LSP.Server.pas), declaration (DRagLint.MCP.Server.pas) (+1 more)
  /// Used in units: DRagLint.LSP.Completion, DRagLint.LSP.Server, DRagLint.MCP.Server
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  { STAGE 1 of exception-class-unit. A candidate is a class someone already
    raises with a literal message; a site is a bare `raise Exception.Create(...)`
    waiting to be told which candidate covers it. Both are harvested from the
    AST during the parse the linter already does. }
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Lint.Linter.TLinter.HarvestExceptions (DRagLint.Lint.Linter.pas)</para>
  /// <para>Used in units: DRagLint.Lint.Linter</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragExcCand = record
    ClsName: string; { the exception class raised, e.g. EInvoiceNotFound }
    Msg    : string; { its message, NORMALIZED                          }
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Lint.Linter.TLinter.HarvestExceptions (DRagLint.Lint.Linter.pas)</para>
  /// <para>Used in units: DRagLint.Lint.Linter</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragExcSite = record
    FilePath: string ;
    Line    : Integer;
    Col     : Integer;
    Msg     : string ; { the bare raise's static message, NORMALIZED }
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas), declaration (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.EnsureLinter (DRagLint.LSP.Server.pas), declaration (DRagLint.MCP.Server.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.LSP.Completion, DRagLint.LSP.Server, DRagLint.MCP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLinter = class
    strict private
      FLanguage  : PTSLanguage                                             ;
      FQueryRules: TArray<TQueryRule>                                      ;
      { exception-class-unit stage 1. FExcUnit = '' means the feature is OFF and
        HarvestExceptions never runs, so a project that has not opted in pays
        nothing. Plain arrays rather than dictionaries: these hold tens of
        entries on a real project (64 distinct messages measured on ORM3), the
        lookup is linear over that once per finding, and an array needs no
        construction in Create or teardown in Destroy. }
      FExcUnit   : string                                                  ;
      FExcCand   : TArray<TDragExcCand>                                    ;
      FExcSites  : TArray<TDragExcSite>                                    ;
      /// <summary><!-- drag-lint:auto -->The first literalString inside the argument list
      /// is taken deliberately: for `Create('Disk quota exceeded on ' + S)` that is the
      /// STATIC PREFIX, which is what a class name can be derived from. Ruling 2 (exactly
      /// where the literal ends and the runtime data begins) is still open and gates
      /// stage 3, not this.</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <param name="ASource"><!-- drag-lint:auto type -->const TBytes</param>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.HarvestExceptions (DRagLint.Lint.Linter.pas)</para>
      /// <para>Calls: DRagLint.Lint.Linter.NodeText, DRagLint.Lint.Linter.NormalizeExcMessage, DRagLint.Lint.Linter.TLinter.HarvestExceptions, DRagLint.Lint.Linter.TLinter.HarvestExceptions.FirstLiteralString, DRagLint.Lint.Linter.UnquotePascalString, Integer, SameText</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 61 lines (full implementation)</para>
      /// <para>Reads: FExcSites, FExcCand   Writes: FExcSites, FExcCand</para>
      /// <para>Recursive</para>
      /// <seealso cref="DRagLint.Lint.Linter.NodeText"/>
      /// <seealso cref="DRagLint.Lint.Linter.NormalizeExcMessage"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.HarvestExceptions.FirstLiteralString"/>
      /// <seealso cref="DRagLint.Lint.Linter.UnquotePascalString"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HarvestExceptions(const ANode: TTSNode; const ASource: TBytes; const AFilePath: string);
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;TLintFinding&gt;</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.Linter.TLinter.LintFile (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.LintFolder (DRagLint.Lint.Linter.pas)</para>
      /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Lint.Linter.CheckDfmCredentials, DRagLint.Lint.Linter.CheckInlineCommentInMultilineArgs, DRagLint.Lint.Linter.CollectDfmParseErrors, DRagLint.Lint.Linter.EmptyBranchIsCommented, DRagLint.Lint.Linter.TLinter.HarvestExceptions, DRagLint.Lint.Linter.WalkForFieldByNameInLoop, ExtractFileExt, Integer, LowerCase, Move, SameText, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 98 lines (full implementation)</para>
      /// <para>Reads: FLanguage, FExcUnit, FQueryRules</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
      /// <seealso cref="DRagLint.Lint.Linter.CheckDfmCredentials"/>
      /// <seealso cref="DRagLint.Lint.Linter.CheckInlineCommentInMultilineArgs"/>
      /// <seealso cref="DRagLint.Lint.Linter.CollectDfmParseErrors"/>
      /// <seealso cref="DRagLint.Lint.Linter.EmptyBranchIsCommented"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function CheckFileImpl(const AFilePath: string): TArray<TLintFinding>;
    public
      /// <summary><!-- drag-lint:auto -->TLinter</summary>
      /// <param name="ARulesDir"><!-- drag-lint:auto type -->const string = ''</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.EnsureLinter (DRagLint.LSP.Server.pas), DRagLint.MCP.Server.TMCPServer.Create (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll, ParamStr</para>
      /// <para>constructor</para>
      /// <para>Reads: FLanguage   Writes: FLanguage, FQueryRules</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Destroy"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.EnrichExceptionFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ARulesDir: string = '');
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FQueryRules</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.EnrichExceptionFindings"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.ExternalRuleCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <summary>Lints a single file, dispatching by extension. A <c>.dfm</c> is parsed
      /// with the tree-sitter DFM grammar and only genuine grammar errors surface (as
      /// 'parser-error'); any other extension is parsed with the Pascal grammar and run
      /// through the built-in walks plus the external <c>.scm</c> query rules.</summary>
      /// <param name="AFilePath">Path to an existing file.</param>
      /// <returns>All findings for the file; empty array if clean.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.Linter.TLinter.CheckFileImpl</para>
      /// <para>Returns: CheckFileImpl(AFilePath)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Destroy"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.EnrichExceptionFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LintFile(const AFilePath: string): TArray<TLintFinding>                          ;
      /// <summary>Names the unit that owns the project's exception classes,
      /// enabling stage 1 of exception-class-unit. Set it BEFORE linting; empty
      /// (the default) disables the harvest entirely.</summary>
      property ExceptionsUnit: string read FExcUnit write FExcUnit;
      /// <summary>Rewrites every raise-bare-exception finding to name the
      /// existing exception class whose message covers it, or to say plainly
      /// that none does.</summary>
      /// <param name="AFindings">Findings for the WHOLE run; modified in place.</param>
      /// <remarks>
      /// Must be called after every file has been linted and while the
      /// linter is still alive: a class's message routinely lives in a different
      /// unit from the bare raise, so no per-file answer can be correct. No-op
      /// when ExceptionsUnit is empty.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Format, SameText</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 29 lines (full implementation)</para>
      /// <para>Reads: FExcUnit, FExcSites, FExcCand</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Destroy"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.ExternalRuleCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure EnrichExceptionFindings(var AFindings: TArray<TLintFinding>);
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ARecursive"><!-- drag-lint:auto type -->Boolean = True</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// All.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.Linter.TLinter.CheckFileImpl, Format, Writeln</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Destroy"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.EnrichExceptionFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LintFolder(const APath: string; ARecursive: Boolean = True): TArray<TLintFinding>;
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: Length(FQueryRules).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas)</para>
      /// <para>Reads: FQueryRules</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Destroy"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.EnrichExceptionFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ExternalRuleCount: Integer                                                       ;
      /// <summary>Rule ids of loaded .scm rules whose sidecar json declared
      /// "enabled": false (ship off-by-default). Findings from these are dropped
      /// downstream unless re-enabled via config "enabled" / --enable.</summary>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas)</para>
      /// <para>Reads: FQueryRules</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.CheckFileImpl"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Destroy"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.EnrichExceptionFindings"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.ExternalRuleCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DefaultDisabledRuleIds: TArray<string>                                          ;
  end;

/// <summary>Ticks spent building the tree-sitter tree inside CheckFileImpl,
/// across every LintFile call so far. Diagnostic only.</summary>
/// <returns>Accumulated TStopwatch ticks; divide by TStopwatch.Frequency.</returns>
/// <remarks>
/// TLinter builds its OWN parser rather than sharing TAstParseCache
/// with the AST checks, so every file is parsed twice per lint-all. This
/// separates that parse from executing the .scm queries, because only the parse
/// half could be recovered by sharing the cache -- and the split had never been
/// measured. Not thread-safe; lint-all is single-threaded here.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Returns: GLintParseTicks</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LinterParseTicks: Int64;
/// <summary>Number of files parsed by CheckFileImpl so far. Diagnostic only.</summary>
/// <returns>Call count, for the ms/file figure beside LinterParseTicks.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Returns: GLintParseCount</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LinterParseCount: Int64;

implementation

uses
  System.Diagnostics; { TStopwatch -- the parse-vs-query split below }

{ SESSION 25 B2 follow-up, DIAGNOSTIC ONLY. `Linter.LintFile` is 56.17 s of
  ORM3's 145.86 s per-file scan and this splits it into READ+PARSE versus
  executing the 114 .scm queries. Read by LinterParseProfile, printed under
  DRAGLINT_PROFILE beside the per-check breakdown. }
var
  GLintParseTicks: Int64;
  GLintParseCount: Int64;

{ Ticks and call count spent building the tree inside CheckFileImpl. }
function LinterParseTicks: Int64;
begin
  Result:= GLintParseTicks;
end;

function LinterParseCount: Int64;
begin
  Result:= GLintParseCount;
end;

{ The DFM grammar lives in tree-sitter-dfm.dll (already a runtime dependency of
  the exe via the indexer's TDFMParser). Re-declared here so the linter can parse
  .dfm files with the correct grammar -- same pattern AstChecks uses for
  tree_sitter_delphi13. }
function tree_sitter_dfm: PTSLanguage; cdecl;
external 'tree-sitter-dfm';

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

// v0.9: detect `// comment` placed inside a multi-line argument list,
// set literal, or array literal. YADF (and similar reformatters) will
// reflow the next element into the comment and silently destroy code.
//
// Detection is textual because the hazard is about source layout, not
// semantics: scan line by line, track paren/bracket depth (ignoring
// content inside string/char literals and comments themselves), and
// flag any line where a `//` comment appears while depth > 0 AND the
// next non-blank line continues the construct (i.e., either another
// argument or a closing `)`/`]`).
procedure CheckInlineCommentInMultilineArgs(const ASource: TBytes; const AFilePath: string; AFindings: TList<TLintFinding>);
type
  TLineInfo = record
    Text         : string ;
    DepthEntry   : Integer; // paren+bracket depth at start of line
    DepthExit    : Integer; // depth at end of line
    SlashSlashCol: Integer; // 1-based column of //, or 0 if none
  end;
var
  Lines         : TStringDynArray  ;
  Infos         : TArray<TLineInfo>;
  I             : Integer          ;
  J             : Integer          ;
  Depth         : Integer          ;
  Col           : Integer          ;
  Line          : string           ;
  C             : Char             ;
  InStr         : Boolean          ;
  InCmt         : Boolean          ;
  InBraceCmt    : Boolean          ;
  InParenStarCmt: Boolean          ;
  Finding       : TLintFinding     ;
  HasNext       : Boolean          ;
begin
  if Length(ASource) = 0 then Exit;
  Lines:= SplitString(StringReplace( TEncoding.UTF8.GetString(ASource), #13#10, #10, [rfReplaceAll]), #10);
  SetLength(Infos, Length(Lines));
  Depth         := 0;
  InBraceCmt    := False;
  InParenStarCmt:= False;
  for I:= 0 to High(Lines) do
  begin
    Line:= Lines[I];
    Infos[I].Text         := Line;
    Infos[I].DepthEntry   := Depth;
    Infos[I].SlashSlashCol:= 0;
    InStr:= False;
    InCmt:= False;
    Col  := 1;
    while Col <= Length(Line) do
    begin
      C:= Line[Col];
      if InCmt then Break // // runs to end of line; bail this column
      else if InBraceCmt then
      begin
        if C = '}' then InBraceCmt:= False;
        Inc(Col);
      end
      else if InParenStarCmt then
      begin
        if (C = '*') and (Col < Length(Line)) and (Line[Col + 1] = ')') then
        begin
          InParenStarCmt:= False;
          Inc(Col, 2);
        end
        else Inc(Col);
      end
      else if InStr then
      begin
        if C = '''' then InStr:= False;
        Inc(Col);
      end
      else
      begin
        if C = '''' then
        begin
          InStr:= True;
          Inc(Col);
        end
        else if C = '{' then
        begin
          InBraceCmt:= True;
          Inc(Col);
        end
        else if (C = '(') and (Col < Length(Line)) and (Line[Col + 1] = '*') then
        begin
          InParenStarCmt:= True;
          Inc(Col, 2);
        end
        else if (C = '/') and (Col < Length(Line)) and (Line[Col + 1] = '/') then
        begin
          // Only count `//` as a hazard if it carries a comment payload
          // (whitespace + at least one non-space). A bare `//` is rare
          // but harmless; require some text after to flag.
          if (Col + 2 <= Length(Line)) and (Trim(Copy(Line, Col + 2, Length(Line) - Col - 1)) <> '') then Infos[I].SlashSlashCol:= Col;
          InCmt:= True;
          Break;
        end
        else if (C = '(') or (C = '[') then
        begin
          Inc(Depth);
          Inc(Col  );
        end
        else if (C = ')') or (C = ']') then
        begin
          if Depth > 0 then Dec(Depth);
          Inc(Col);
        end
        else Inc(Col);
      end; // else
    end; // while
    Infos[I].DepthExit:= Depth;
  end; // for

  for I:= 0 to High(Infos) do
  begin
    if (Infos[I].SlashSlashCol > 0) and (Infos[I].DepthEntry > 0) then
    begin
      // Whole-line comments aren't the YADF hazard; only trailing
      // (post-value) ones are. Require non-whitespace BEFORE `//`.
      if Trim(Copy(Infos[I].Text, 1, Infos[I].SlashSlashCol - 1)) = '' then Continue;
      { A `dl:ok` review marker is written by `drag-lint allow`, never by hand,
        and it MUST sit on the finding's own line -- that is what attributes it,
        so there is nowhere else to put it. Flagging it means every allow of a
        finding inside a multi-line argument list manufactures a NEW finding.
        Measured on YADF: 87 allows produced 8 of these, all self-inflicted.
        Only a comment that is ENTIRELY a marker is skipped. A HUMAN comment
        that merely also carries a marker is still a genuine reflow hazard and
        still fires -- the payload check, not Parse(), is what draws that line. }
      if StartsText(REVIEW_MARK, Trim(Copy(Infos[I].Text, Infos[I].SlashSlashCol + 2, MaxInt))) then Continue;
      // Also skip lines that close out of the multi-line construct -
      // YADF can't reflow into a comment that has no following sibling.
      if Infos[I].DepthExit = 0 then Continue;
      HasNext:= False;
      for J:= I + 1 to High(Infos) do
      begin
        if Trim(Infos[J].Text) <> '' then
        begin
          HasNext:= True;
          Break;
        end;
      end;
      if not HasNext then Continue;
      Finding:= Default(TLintFinding);
      Finding.RuleId  := 'inline-comment-in-multiline-args';
      Finding.Severity:= 'warning';
      Finding.Message:= '// comment inside multi-line argument/array list - reformatters ' + '(YADF, etc.) may reflow the next element into this comment. ' +
      'Move the comment above the line or to its own line.';
      Finding.FilePath:= AFilePath;
      Finding.StartLine:= I + 1;
      Finding.StartCol:= Infos[I].SlashSlashCol;
      Finding.EndLine:= I + 1;
      Finding.EndCol:= Length(Infos[I].Text) + 1;
      AFindings.Add(Finding);
    end; // if
  end; // for
end; // begin

{ Returns the `FieldByName` name node of a `<expr>.FieldByName(...)` call, or a null
  node when ANode is not such a call. The name node -- not the call -- is what a
  finding anchors on, so the caret lands on the offending lookup. }
function FieldByNameNameNode(const ANode: TTSNode; const ASource: TBytes): TTSNode;
var
  Entity: TTSNode;
  Rhs   : TTSNode;
begin
  Result:= Default(TTSNode);
  if ANode.IsNull or (ANode.NodeType <> 'exprCall') then Exit;
  Entity:= ANode.ChildByField('entity');
  if Entity.IsNull or (Entity.NodeType <> 'exprDot') then Exit;
  Rhs:= Entity.ChildByField('rhs');
  if Rhs.IsNull then Exit;
  if SameText(NodeText(Rhs, ASource), 'FieldByName') then Result:= Rhs;
end; // function

{ The literal field name of a FieldByName('x') call, unquoted; '' when the argument
  is not a plain literal (a variable, an expression, a const). }
function FieldByNameArgText(const ANode: TTSNode; const ASource: TBytes): string;
var
  Args: TTSNode;
  Arg0: TTSNode;
begin
  Result:= '';
  Args:= ANode.ChildByField('args');
  if Args.IsNull or (Args.NamedChildCount = 0) then Exit;
  Arg0:= Args.NamedChild(0);
  if Arg0.IsNull then Exit;
  Result:= Trim(NodeText(Arg0, ASource));
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then Result:= Copy(Result, 2, Length(Result) - 2);
end; // function

procedure CollectFieldByNameCalls(const ANode: TTSNode; const ASource: TBytes; ACalls: TList<TTSNode>);
var
  I: Integer;
begin
  if ANode.IsNull then Exit;
  if not FieldByNameNameNode(ANode, ASource).IsNull then ACalls.Add(ANode);
  for I:= 0 to ANode.NamedChildCount - 1 do CollectFieldByNameCalls(ANode.NamedChild(I), ASource, ACalls);
end; // procedure

{ One finding for the whole loop, naming the fields to hoist. }
procedure EmitFieldByNameLoopFinding(const ALoop: TTSNode; const ASource: TBytes; const AFilePath: string; AFindings: TList<TLintFinding>);
const
  MAX_NAMES_LISTED = 6;
var
  Calls  : TList<TTSNode>;
  Names  : TStringList   ;
  Finding: TLintFinding  ;
  Anchor : TTSNode       ;
  Nm     : string        ;
  Detail : string        ;
  Listed : TArray<string>;
  Shown  : Integer       ;
  I      : Integer       ;
begin
  Calls:= TList<TTSNode>.Create;
  Names:= TStringList.Create;
  try
    CollectFieldByNameCalls(ALoop, ASource, Calls);
    if Calls.Count = 0 then Exit;

    Names.Sorted    := True    ;
    Names.Duplicates:= dupIgnore;
    for I:= 0 to Calls.Count - 1 do
    begin
      Nm:= FieldByNameArgText(Calls[I], ASource);
      if Nm <> '' then Names.Add(Nm);
    end;

    Detail:= '';
    if Names.Count > 0 then
    begin
      Shown:= Min(Names.Count, MAX_NAMES_LISTED);
      SetLength(Listed, Shown);
      for I:= 0 to Shown - 1 do Listed[I]:= Names[I];
      Detail:= string.Join(', ', Listed); { not S := S + X in a loop -- see concat-in-loop }
      if Names.Count > MAX_NAMES_LISTED then Detail:= Detail + Format(', +%d more', [Names.Count - MAX_NAMES_LISTED]);
      Detail:= ' (' + Detail + ')';
    end;

    Anchor:= FieldByNameNameNode(Calls[0], ASource);
    Finding:= Default(TLintFinding);
    Finding.RuleId  := 'field-by-name-in-loop';
    Finding.Severity:= 'warning';
    Finding.Message := Format('FieldByName() called %d time(s) inside this loop%s -- cache the TField reference(s) ' + 'in locals before the loop and reuse them', [Calls.Count, Detail]);
    Finding.FilePath := AFilePath;
    Finding.StartLine:= Integer(Anchor.StartPoint.row   ) + 1;
    Finding.StartCol := Integer(Anchor.StartPoint.column) + 1;
    Finding.EndLine  := Integer(Anchor.EndPoint  .row   ) + 1;
    Finding.EndCol   := Integer(Anchor.EndPoint  .column) + 1;
    AFindings.Add(Finding);
  finally
    Names.Free;
    Calls.Free;
  end; // try
end; // procedure

{ v0.85: ONE finding per OUTERMOST loop, not one per call site.
  The old walk emitted a finding for every FieldByName token below a loop. Across
  this repo that turned 66 loops into 340 findings -- a single 8-line row-reader
  accounted for 8 of them. The remedy is per loop (hoist the lookups above it), so
  the finding has to be per loop as well, otherwise the count measures how wide the
  row-reader is rather than how many places need fixing.
  Nested loops are deliberately NOT descended into: they are inside the outermost
  loop's body, and hoisting happens above that loop. }
{ THE NORMALIZER behind the owner's 2026-08-25 ruling that "fits" means a
  NORMALIZED MESSAGE MATCH. 'Invoice not found' and 'Invoice was not found' must
  collapse to one key, or stage 3 generates EInvoiceNotFound AND
  EInvoiceWasNotFound and the collision the whole note is about is built in
  rather than avoided.

  Casing and punctuation go; a short stopword list goes. Deliberately NOT
  stemming: 'found'/'finding' surviving as different keys costs a duplicate
  suggestion, while over-stemming silently merges two genuinely different errors
  onto one class, and a wrong merge is the expensive direction here. }
function NormalizeExcMessage(const AMsg: string): string;
const
  STOPWORDS: array[0..10] of string =
    ('was', 'were', 'is', 'are', 'be', 'been', 'the', 'a', 'an', 'has', 'have');
var
  T    : string        ;
  I, K : Integer       ;
  Parts: TArray<string>;
  Keep : TArray<string>;
  Skip : Boolean       ;
begin
  T:= LowerCase(AMsg);
  for I:= 1 to Length(T) do
    if not CharInSet(T[I], ['a'..'z', '0'..'9']) then T[I]:= ' ';
  Parts:= T.Split([' '], TStringSplitOptions.ExcludeEmpty);
  SetLength(Keep, 0);
  for I:= 0 to High(Parts) do
  begin
    Skip:= False;
    for K:= Low(STOPWORDS) to High(STOPWORDS) do
      if Parts[I] = STOPWORDS[K] then begin Skip:= True; Break; end;
    if not Skip then Keep:= Keep + [Parts[I]];
  end;
  Result:= string.Join(' ', Keep);
end;

{ A literalString node's text still carries its quotes and Pascal's doubled-quote
  escape. Read it from the NODE, never from the source line: a regex over the
  line is the method that produced the 2026-08-17 measurement this feature's note
  had to retract -- it recovered 80 of 139 sites and then reported the 59 it
  could not parse as "sites with no literal", writing an extractor limitation up
  as a property of the code. }
function UnquotePascalString(const ALit: string): string;
begin
  Result:= ALit;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result:= Copy(Result, 2, Length(Result) - 2);
  Result:= StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

procedure WalkForFieldByNameInLoop(const ANode: TTSNode; const ASource: TBytes; const AFilePath: string; AFindings: TList<TLintFinding>);
var
  NT: string ;
  I : Integer;
begin
  if ANode.IsNull then Exit;
  NT:= ANode.NodeType;
  if (NT = 'while') or (NT = 'for') or (NT = 'repeat') then
  begin
    EmitFieldByNameLoopFinding(ANode, ASource, AFilePath, AFindings);
    Exit;
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do WalkForFieldByNameInLoop(ANode.NamedChild(I), ASource, AFilePath, AFindings);
end; // procedure

// v0.57: DFM files are parsed with the dedicated tree-sitter DFM grammar
// (tree_sitter_dfm), not the Pascal grammar. The Pascal grammar cannot represent
// the textual-DFM `object .. end` form or the Pascal set-literals used in property
// values ([biSystemMenu, biHelp], [], [akLeft, akTop, akRight]), so it emitted one
// spurious ERROR -> 'parser-error' per construct on every *valid* DFM. Under the
// DFM grammar a valid form parses clean; only a genuinely malformed DFM yields
// ERROR/MISSING nodes -- surfaced here as the same 'parser-error' rule id/message
// the .scm rule uses for Pascal, so a real DFM problem is still caught. Mirrors
// the ERROR/MISSING walk in TAstChecker.CheckSyntaxErrors (cap 100, no descent
// into an error node, skip clean subtrees via HasError).
procedure CollectDfmParseErrors(const ARoot: TTSNode; const AFilePath: string; AFindings: TList<TLintFinding>);

  procedure Visit(const N: TTSNode);
  var
    I: Integer     ;
    F: TLintFinding;
    P: TTSPoint    ;
  begin
    if N.IsNull or (AFindings.Count >= 100) then Exit;
    if N.IsError or N.IsMissing then
    begin
      P:= N.StartPoint;
      F:= Default(TLintFinding);
      F.RuleId  := 'parser-error';
      F.Severity:= 'error';
      F.Message := 'Syntax error: parser failed to recognize this construct';
      F.FilePath:= AFilePath;
      F.StartLine:= Integer(P.Row   ) + 1;
      F.StartCol := Integer(P.Column) + 1;
      F.EndLine  := F.StartLine;
      F.EndCol   := F.StartCol + 1;
      AFindings.Add(F);
      Exit; { do not descend into an error node }
    end; // if
    if not N.HasError then Exit; { clean subtree -> skip }
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Visit(ARoot);
end; // procedure

// v0.76 (#10 security): scan a parsed DFM tree for a credential-named property
// (Password/Pwd/Secret/ApiKey/...) assigned a non-empty string LITERAL. A secret
// checked into a form resource is an anti-pattern (it ships in the exe and lands
// in source control). Only a `string` value node fires -- an empty string, an
// event binding, or a numeric/set value does not. Uses the DFM grammar node
// types (see DRagLint.Parser.DFM: object -> property{name,value}; value 'string'
// is quoted_string/char_code atoms). Emitted as a 'warning' rule; low-FP.
function DfmDecodeStringValue(const ANode: TTSNode; const ASource: TBytes): string;
var
  i   : Integer;
  Atom: TTSNode;
  Raw : string ;
begin
  Result:= '';
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Atom:= ANode.NamedChild(i);
    if Atom.IsNull then Continue;
    if Atom.NodeType = 'quoted_string' then
    begin
      Raw:= NodeText(Atom, ASource);
      if (Length(Raw) >= 2) and (Raw[1] = '''') and (Raw[Length(Raw)] = '''') then
        Raw:= Copy(Raw, 2, Length(Raw) - 2);
      Result:= Result + StringReplace(Raw, '''''', '''', [rfReplaceAll]);
    end
    else if Atom.NodeType = 'char_code' then
      Result:= Result + ' ';
  end;
end; // function

function IsCredentialPropName(const AName: string): Boolean;
var
  Seg: string;
  P  : Integer;
begin
  // Match the final dotted segment so 'DB.Password' fires but 'PasswordHint'
  // (a caption) does not accidentally widen the net beyond the keyword set.
  Seg:= LowerCase(Trim(AName));
  P:= LastDelimiter('.', Seg);
  if P > 0 then Seg:= Copy(Seg, P + 1, MaxInt);
  Result:=
    (Seg = 'password') or (Seg = 'passwd') or (Seg = 'pwd') or
    (Seg = 'secret') or (Seg = 'apikey') or (Seg = 'privatekey') or
    (Seg = 'passphrase') or (Seg = 'connectionpassword');
end; // function

procedure CheckDfmCredentials(const ARoot: TTSNode; const ASource: TBytes; const AFilePath: string; AFindings: TList<TLintFinding>);

  procedure Visit(const N: TTSNode);
  var
    I        : Integer     ;
    Child    : TTSNode     ;
    NameNode : TTSNode     ;
    ValueNode: TTSNode     ;
    PropName : string      ;
    Secret   : string      ;
    F        : TLintFinding;
    P        : TTSPoint    ;
  begin
    if N.IsNull or (AFindings.Count >= 100) then Exit;
    if N.NodeType = 'property' then
    begin
      NameNode := N.ChildByField('name' );
      ValueNode:= N.ChildByField('value');
      if (not NameNode.IsNull) and (not ValueNode.IsNull) and (ValueNode.NodeType = 'string') then
      begin
        PropName:= NodeText(NameNode, ASource);
        if IsCredentialPropName(PropName) then
        begin
          Secret:= DfmDecodeStringValue(ValueNode, ASource);
          if Trim(Secret) <> '' then
          begin
            P:= N.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'dfm-hardcoded-credential';
            F.Severity:= 'warning';
            F.Message := Format('Hardcoded credential in DFM: property "%s" assigns a literal string; move secrets out of the form resource', [PropName]);
            F.FilePath:= AFilePath;
            F.StartLine:= Integer(P.Row   ) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine  := F.StartLine;
            F.EndCol   := F.StartCol + 1;
            AFindings.Add(F);
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Child:= N.NamedChild(I);
      if not Child.IsNull then Visit(Child);
    end;
  end; // procedure

begin
  Visit(ARoot);
end; // procedure

{ TLinter }

constructor TLinter.Create(const ARulesDir: string);
var
  ResolvedDir: string;
begin
  inherited Create;
  FLanguage:= tree_sitter_delphi13;
  if ARulesDir = '' then ResolvedDir:= TPath.Combine( TPath.GetDirectoryName(ParamStr(0)), 'rules')
  else ResolvedDir:= ARulesDir;
  FQueryRules:= TQueryRuleLoader.LoadAll(FLanguage, ResolvedDir);
end;

destructor TLinter.Destroy;
var
  R: TQueryRule;
begin
  for R in FQueryRules do R.Free;
  inherited;
end;

function TLinter.ExternalRuleCount: Integer;
begin
  Result:= Length(FQueryRules);
end;

function TLinter.DefaultDisabledRuleIds: TArray<string>;
var
  R: TQueryRule;
begin
  Result:= nil;
  for R in FQueryRules do
    if (not R.Enabled) and (R.RuleId <> '') then
      Result:= Result + [R.RuleId];
end;

{ True when an empty case branch reported at ALine carries an explanatory
  comment, which empty-case-branch's own message offers as the way to say "this
  no-op is deliberate".

  The comment usually sits on the STATEMENT line rather than the label line --

      #$00B0, #$2300, #$00F8, #$00D8:
        ; // Skip/Eliminate

  so both the label line and the one after it are inspected. An opening brace
  immediately followed by a dollar sign is a COMPILER DIRECTIVE, not a comment,
  and must not silence the rule. }
function EmptyBranchIsCommented(const ASource: TBytes; ALine: Integer): Boolean;
var
  Lines: TArray<string>;
  I    : Integer       ;
  S    : string        ;
  P    : Integer       ;
begin
  Result:= False;
  if ALine < 1 then Exit;
  Lines:= TEncoding.UTF8.GetString(ASource).Replace(#13#10, #10).Split([#10]);
  for I:= ALine - 1 to ALine do   { 0-based: the label line and the next one }
  begin
    if (I < 0) or (I > High(Lines)) then Continue;
    S:= Lines[I];
    if Pos('//', S) > 0 then Exit(True);
    if Pos('(*', S) > 0 then Exit(True);
    P:= Pos('{', S);
    if (P > 0) and not ((P < Length(S)) and (S[P + 1] = '$')) then Exit(True);
  end;
end;

function TLinter.CheckFileImpl( const AFilePath: string): TArray<TLintFinding>;
var
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
  Source  : TBytes             ;
  Findings: TList<TLintFinding>;
  IsDfm   : Boolean            ;
begin
  Findings:= TList<TLintFinding>.Create;
  Tree  := nil;
  Parser:= nil;
  try
    // v0.86 (Task 3): transcode ANSI/UTF-16 sources to valid UTF-8 before the
    // parse/slice pipeline (both assume UTF-8). This is the direct lint/lint-all
    // path; without it a valid CP1252 file (SOFTWID class) errored here.
    Source:= EnsureUtf8Bytes(TFile.ReadAllBytes(AFilePath));
    { Pick the grammar by extension: .dfm -> DFM grammar, everything else -> Pascal.
      Parsing a .dfm with the Pascal grammar produced a spurious parser-error per
      set-literal/root object (see CollectDfmParseErrors). }
    IsDfm:= SameText(ExtractFileExt(AFilePath), '.dfm');
    { SESSION 25 B2 follow-up: time the READ+PARSE alone, separately from
      executing the rule queries.

      Established by inspection: this routine builds its OWN TTSParser, so it
      does not share TAstParseCache with the built-in AST checks -- every file
      is parsed TWICE per lint-all. What that does NOT say is how much of the
      56.17 s this slot costs is the parse rather than the 114 tree-sitter
      queries, and routing this through the cache can only ever recover the
      parse half. Measure before doing the work; this counter is that
      measurement and nothing else. }
    Inc(GLintParseCount);
    var TP0: Int64:= TStopwatch.GetTimeStamp;
    Parser:= TTSParser.Create;
    if IsDfm then Parser.Language:= tree_sitter_dfm
    else Parser.Language:= FLanguage;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Source)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Source[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);
    Inc(GLintParseTicks, TStopwatch.GetTimeStamp - TP0);
    if IsDfm then
      { DFM: the Pascal *.scm rules and the Pascal-specific walks key off node types
        that don't exist in the DFM grammar (and the queries are compiled against the
        Pascal language), so the only meaningful diagnostic is a genuine grammar error. }
    begin
      CollectDfmParseErrors(Tree.RootNode, AFilePath, Findings);
      CheckDfmCredentials(Tree.RootNode, Source, AFilePath, Findings); // v0.76 #10
    end
    else
    begin
      WalkForFieldByNameInLoop(Tree.RootNode, Source, AFilePath, Findings);
      { Rides the parse above rather than adding one. Returns immediately when
        the project has not opted in. }
      if FExcUnit <> '' then HarvestExceptions(Tree.RootNode, Source, AFilePath);
      CheckInlineCommentInMultilineArgs(Source, AFilePath, Findings);
      // External *.scm rules
      var R: TQueryRule;
      { LITERAL PRE-FILTER -- see TQueryRule.RequiredText.
        A rule whose predicate is anchored to a literal cannot match a file whose
        text does not contain that literal, so running its query over the AST is
        provably wasted. Measured on ORM3: gettickcount-wraparound alone was
        17.48 s of the 52.82 s all 55 rules cost together, for ONE finding.
        The lowercased copy is built at most ONCE per file, and only when some
        rule actually declares a literal -- a corpus of rules that declare none
        pays nothing. LowerReady is a separate flag because an EMPTY file
        lowercases to '' and must not be mistaken for "not computed yet". }
      var LowerSrc  : string  := '';
      var LowerReady: Boolean := False;
      for R in FQueryRules do
      begin
        if R.RequiredText <> '' then
        begin
          if not LowerReady then
          begin
            LowerSrc  := LowerCase(TEncoding.UTF8.GetString(Source));
            LowerReady:= True;
          end;
          if not LowerSrc.Contains(R.RequiredText) then Continue;
        end;
        var QFindings:= R.Run(Tree.RootNode, Source, AFilePath);
        var F: TLintFinding;
        for F in QFindings do
        begin
          { empty-case-branch's own message says "or add a comment if
            intentional" -- but the .scm only anchors on the caseLabel being the
            branch's last child, so it fired whether or not the comment was
            there and the documented escape hatch did not exist. Honour it. }
          if SameText(F.RuleId, 'empty-case-branch') and EmptyBranchIsCommented(Source, F.StartLine) then Continue;
          Findings.Add(F);
        end;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end; // try
end; // function

{ Collects both halves of stage 1 in ONE walk: every `raise X.Create('lit')`.
  X = Exception is a SITE needing advice; anything else is a CANDIDATE whose
  literal is that class's known message.

  WHY CANDIDATES ARE NOT RESTRICTED TO THE CONFIGURED UNIT. A class declaration
  carries no message -- the only place a message exists is a raise site -- so the
  map has to be built from raise sites wherever they are, and a class raised
  anywhere in the project is a genuine candidate. The config key's job is to turn
  the feature on and to name where a NEW class should go; it is not a filter.

  The first literalString inside the argument list is taken deliberately: for
  `Create('Disk quota exceeded on ' + S)` that is the STATIC PREFIX, which is
  what a class name can be derived from. Ruling 2 (exactly where the literal ends
  and the runtime data begins) is still open and gates stage 3, not this. }
procedure TLinter.HarvestExceptions(const ANode: TTSNode; const ASource: TBytes; const AFilePath: string);

  function FirstLiteralString(const N: TTSNode): string;
  var
    I: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    if N.NodeType = 'literalString' then Exit(NodeText(N, ASource));
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Result:= FirstLiteralString(N.NamedChild(I));
      if Result <> '' then Exit;
    end;
  end;

var
  I                : Integer      ;
  Call, Dot, Lhs, Args: TTSNode   ;
  Cls, Msg         : string       ;
  Cand             : TDragExcCand ;
  Site             : TDragExcSite ;
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'raise' then
  begin
    Call:= ANode.ChildByField('exception');
    if (not Call.IsNull) and (Call.NodeType = 'exprCall') then
    begin
      Dot:= Call.ChildByField('entity');
      if (not Dot.IsNull) and (Dot.NodeType = 'exprDot') then
      begin
        Lhs:= Dot.ChildByField('lhs');
        if not Lhs.IsNull then
        begin
          Cls := NodeText(Lhs, ASource);
          Args:= Call.ChildByField('args');
          Msg := NormalizeExcMessage(UnquotePascalString(FirstLiteralString(Args)));
          if SameText(Cls, 'Exception') then
          begin
            { The position must match what the .scm rule reports, or the
              enrichment silently attaches to nothing: its @warn capture is the
              `raise` node, so this is that node's own start. }
            Site.FilePath:= AFilePath;
            Site.Line    := Integer(ANode.StartPoint.row   ) + 1;
            Site.Col     := Integer(ANode.StartPoint.column) + 1;
            Site.Msg     := Msg;
            FExcSites:= FExcSites + [Site];
          end
          else if Msg <> '' then
          begin
            Cand.ClsName:= Cls;
            Cand.Msg    := Msg;
            FExcCand:= FExcCand + [Cand];
          end;
        end;
      end;
    end;
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do
    HarvestExceptions(ANode.NamedChild(I), ASource, AFilePath);
end;

procedure TLinter.EnrichExceptionFindings(var AFindings: TArray<TLintFinding>);
var
  I, J, K: Integer;
  Key, Cls: string;
begin
  if FExcUnit = '' then Exit;
  for I:= 0 to High(AFindings) do
  begin
    if AFindings[I].RuleId <> 'raise-bare-exception' then Continue;
    Key:= '';
    for J:= 0 to High(FExcSites) do
      if (FExcSites[J].Line = AFindings[I].StartLine) and
         (FExcSites[J].Col  = AFindings[I].StartCol ) and
         SameText(FExcSites[J].FilePath, AFindings[I].FilePath) then
      begin
        Key:= FExcSites[J].Msg;
        Break;
      end;
    Cls:= '';
    if Key <> '' then
      for K:= 0 to High(FExcCand) do
        if FExcCand[K].Msg = Key then begin Cls:= FExcCand[K].ClsName; Break; end;
    if Cls <> '' then
      AFindings[I].Message:= AFindings[I].Message +
        Format(' %s already covers this message -- raise it instead.', [Cls])
    else
      AFindings[I].Message:= AFindings[I].Message +
        Format(' No existing exception class covers this message -- add one to %s.', [FExcUnit]);
  end;
end;

function TLinter.LintFile( const AFilePath: string): TArray<TLintFinding>;
begin
  Result:= CheckFileImpl(AFilePath);
end;

function TLinter.LintFolder(const APath: string; ARecursive: Boolean): TArray<TLintFinding>;
var
  Mode    : TSearchOption       ;
  Files   : TArray<string>      ;
  F       : string              ;
  All     : TList<TLintFinding> ;
  PartArr : TArray<TLintFinding>;
  P       : TLintFinding        ;
  Patterns: TArray<string>      ;
  Pattern : string              ;
begin
  if ARecursive then Mode:= TSearchOption.soAllDirectories
  else Mode:= TSearchOption.soTopDirectoryOnly;
  Patterns:= ['*.pas', '*.dpr', '*.dpk'];
  All:= TList<TLintFinding>.Create;
  try
    for Pattern in Patterns do
    begin
      Files:= TDirectory.GetFiles(APath, Pattern, Mode);
      for F in Files do
      begin
        try
          PartArr:= CheckFileImpl(F);
          for P in PartArr do All.Add(P);
        except
          on E: Exception do Writeln(Format('  SKIP %s: %s: %s', [F, E.ClassName, E.Message]));
        end;
      end;
    end;
    Result:= All.ToArray;
  finally
    All.Free;
  end; // try
end; // function

end.
