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
  ;

type
  TAstChecker = class
    strict private
      class function LoadBuiltinAllowlist          : TDictionary<string, Boolean>;
      class function IsKeyword(const AName: string): Boolean                     ;
    public
      class function Check(const AStore: ISymbolStore; const AFile: string)          : TArray<TLintFinding>;
      class function CheckUndeclared(const AStore: ISymbolStore; const AFile: string): TArray<TLintFinding>;
      class function CheckUnbalancedBeginEnd( const AFile: string)                   : TArray<TLintFinding>;
      { Tree-sitter ERROR / MISSING nodes -> located 'syntax-error' findings.
      Live syntax diagnostics (Error-Insight-style) without a compiler. }
      class function CheckSyntaxErrors(const AFile: string): TArray<TLintFinding>;
      { v0.46: unused local variables (the compiler's H2164). For each defProc,
      a local declared in its var section that occurs exactly once in the whole
      routine subtree (i.e. only its declaration) is flagged. Counting over the
      subtree is intentionally false-positive-SAFE: a name used anywhere (incl.
      a nested routine = closure, or via with/property) raises the count and
      suppresses the finding. No compiler / no DB needed. }
      class function CheckUnusedLocals(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a 'raise' statement located inside a 'finally' block.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>One finding per raise found within a finally body (capped at 100); nil/empty if none.</returns>
      /// <remarks>A raise in a finally masks the exception currently propagating out of the protected
      /// section. The walk does not descend into nested try blocks, so each try's finally is attributed
      /// to that try. Pure tree-sitter AST; no DB or compiler required. Never raises.</remarks>
      class function CheckRaiseInFinally(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags the first statement that follows an unconditional Exit / raise / Break /
      /// Continue / Halt within the same statement list (unreachable code).</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>One 'code-after-exit' finding per statement list with dead code (capped); empty if none.</returns>
      /// <remarks>Only direct siblings are considered, so a terminator nested inside an if/case does not
      /// mark code after the if/case as dead. Pure tree-sitter AST; no DB. Never raises.</remarks>
      class function CheckCodeAfterExit(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a constructor or destructor whose body never calls 'inherited'.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>Findings tagged 'missing-inherited-ctor' / 'missing-inherited-dtor'; empty if none.</returns>
      /// <remarks>A missing inherited Create skips ancestor initialization; a missing inherited Destroy
      /// skips ancestor cleanup (resource leak). Class constructors/destructors and asm-bodied routines
      /// are skipped. The search ignores 'inherited' inside nested routines. Pure AST; no DB. Never raises.</remarks>
      class function CheckMissingInherited(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags Exit / Break / Continue / Halt inside a finally block.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>One 'control-flow-in-finally' finding per offending statement (capped); empty if none.</returns>
      /// <remarks>An Exit/Break/Continue/Halt in a finally silently discards any exception currently
      /// propagating out of the protected section. Walks each finally body, not descending into nested
      /// try blocks. Companion to CheckRaiseInFinally. Pure AST; no DB. Never raises.</remarks>
      class function CheckControlFlowInFinally(const AFile: string): TArray<TLintFinding>;
      /// <summary>Routine size/complexity metrics: too many parameters, too many locals,
      /// method too long, and excessive nesting depth.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <param name="AMaxParams">Parameter count above which 'too-many-parameters' fires.</param>
      /// <param name="AMaxLocals">Local-variable count above which 'too-many-locals' fires.</param>
      /// <param name="AMaxLines">Body line span above which 'method-too-long' fires.</param>
      /// <param name="AMaxNesting">Control-structure nesting depth above which 'deep-nesting' fires.</param>
      /// <returns>Findings tagged with the four metric rule ids; empty if all within limits.</returns>
      /// <remarks>One AST walk per routine. Pure AST; no DB. Never raises.</remarks>
      class function CheckRoutineMetrics(const AFile: string; AMaxParams, AMaxLocals, AMaxLines, AMaxNesting: Integer): TArray<TLintFinding>;
      /// <summary>Type-aware checks using a lightweight per-file name-to-type map:
      /// floating-point equality comparison, and FreeAndNil on an interface-typed variable.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>Findings 'float-equality-comparison' / 'freeandnil-on-interface'; empty if none.</returns>
      /// <remarks>The type map is flat (declared types of vars/params/fields, no scope resolution),
      /// so rare same-name shadowing may mis-type; the rules are heuristic. Interface detection uses the
      /// Delphi I-prefix convention. Pure AST; no DB. Never raises.</remarks>
      class function CheckTypeAware(const AFile: string): TArray<TLintFinding>;
      /// <summary>FireDAC misuse: 'Open' on a data-modifying statement, or 'ExecSQL' on a SELECT.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'firedac-open-execsql-mismatch' findings; empty if none.</returns>
      /// <remarks>Per routine, correlates a literal 'X.SQL.Text := ''...''' (classified SELECT vs
      /// INSERT/UPDATE/DELETE/MERGE) with a later 'X.Open' / 'X.ExecSQL' on the same variable, in
      /// program order. Only fires when the SQL is a recognizable literal, so false positives are rare.
      /// Pure AST; no DB. Never raises.</remarks>
      class function CheckFireDacSqlMismatch(const AFile: string): TArray<TLintFinding>;
      /// <summary>A locally-created object that is freed without try-finally protection (leaks if
      /// code between creation and Free raises).</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'unprotected-object-free' findings; empty if none.</returns>
      /// <remarks>Per routine, in program order: records 'X := ...Create...' constructions, then flags a
      /// later 'X.Free' / 'FreeAndNil(X)' on the same variable that is NOT lexically inside a finally
      /// block. Requiring same-routine construction filters destructor field-frees. Pure AST; no DB. Never raises.</remarks>
      class function CheckUnprotectedFree(const AFile: string): TArray<TLintFinding>;
      /// <summary>Detects interface reference cycles across the given files: class A holds an
      /// interface implemented by class B, and B holds an interface implemented by A (mutual).</summary>
      /// <param name="AFiles">Source files to parse (project-wide); typically the indexed file set.</param>
      /// <returns>'interface-reference-cycle' findings (one per mutual pair); empty if none.</returns>
      /// <remarks>Under ARC these mutual strong interface references leak; fix by marking one side
      /// [weak] or [unsafe]. Interface detection uses the I-prefix convention; only mutual (2-cycle)
      /// pairs are reported. Pure AST across all files; no DB. Never raises.</remarks>
      class function CheckInterfaceCycles(const AFiles: TArray<string>): TArray<TLintFinding>;
      /// <summary>Use of an object after 'X.Free' (dangling reference) within the same block.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'use-after-free' findings; empty if none.</returns>
      /// <remarks>Block-scoped (siblings only, to keep false positives low): after a raw 'X.Free' it
      /// flags a later 'X.&lt;member&gt;' access (incl. a second X.Free) until X is reassigned. FreeAndNil(X)
      /// clears tracking (it nils X). Pure AST; no DB. Never raises.</remarks>
      class function CheckUseAfterFree(const AFile: string): TArray<TLintFinding>;
      /// <summary>UI (VCL/FMX) access inside a TThread.Execute that is not on the main thread.</summary>
      /// <param name="AFile">Path to the .pas/.inc source file to scan; must exist.</param>
      /// <returns>'ui-access-in-thread' findings; empty if none.</returns>
      /// <remarks>Heuristic, tuned for low false positives: only inside a method named 'Execute' whose
      /// class (declared in the same file) has a base type whose name contains 'Thread', and only for
      /// strong UI members (assignment to '.Caption'; calls to '.SetFocus'/'.Repaint'/'.BringToFront').
      /// Access inside a nested anonymous method (a likely Synchronize/Queue body) is skipped. Pure AST;
      /// no DB. Never raises.</remarks>
      class function CheckUiThread(const AFile: string): TArray<TLintFinding>;
      /// <summary>Warns when a form unit declares a unit-level global variable whose type
      /// matches a class declared in the same file. Such globals leak the first form instance
      /// if the form is ever shown more than once.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per offending variable declaration.</returns>
      /// <remarks>Skipped entirely when no sibling .dfm file exists beside AFile. Pure AST;
      /// no DB. Never raises.</remarks>
      class function CheckGlobalFormVars(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags WinExec/ShellExecute/CreateProcess called with a non-literal
      /// command/executable argument -- a runtime-built command path is a command-injection
      /// risk (CWE-78).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per launcher call whose command argument is not a string literal.</returns>
      /// <remarks>Severity error. Per-callee command-arg index: WinExec=0, ShellExecute=2,
      /// CreateProcess=1. Pure AST; no DB. Never raises.</remarks>
      class function CheckShellExec(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a file API (AssignFile/FileOpen/CreateFile/TFile.Open) whose path
      /// argument is a string concatenation -- a user-controlled segment can escape the
      /// intended directory (path traversal, CWE-22).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per call whose path argument is a binary '+' expression.</returns>
      /// <remarks>Severity warning. Path-arg index: AssignFile=1, FileOpen/CreateFile=0,
      /// TFile.Open=0. Pure AST; no DB. Never raises.</remarks>
      class function CheckPathTraversal(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a for/while/repeat loop whose body's first statement is an
      /// unconditional Exit, Break, or raise -- the loop can never reach a second
      /// iteration.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per loop whose first body statement is Exit/Break/raise.</returns>
      /// <remarks>Severity warning. Only the direct first statement is inspected, so an
      /// Exit nested in an if is not flagged. Pure AST; no DB. Never raises.</remarks>
      class function CheckLoopAtMostOnce(const AFile: string): TArray<TLintFinding>;
      /// <summary>Checks a Format('literal', [literals]) call for two faults: the conversion
      /// specifier count not matching the argument count (format-argument-count), and a literal
      /// argument whose type is incompatible with its specifier family (format-specifier-type-mismatch).</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>Findings tagged 'format-argument-count' and/or 'format-specifier-type-mismatch'.</returns>
      /// <remarks>Severity error. Requires a literalString format + exprBrackets argument array;
      /// skips silently otherwise. Variable arguments are not type-checked. Pure AST; no DB.</remarks>
      class function CheckFormatCall(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a try..except whose handler neither re-raises nor logs nor calls
      /// Application.HandleException/ShowException -- the exception is silently swallowed.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per swallowing except clause, pinned to the 'except' keyword.</returns>
      /// <remarks>Severity warning. A handler counts as handling if it contains a raise, or an
      /// identifier/call whose text contains handleexception/showexception/log/report. try-finally
      /// is ignored. Pure AST; no DB. Never raises.</remarks>
      class function CheckSwallowedExcept(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a dataset opened (X.Open or X.Active := True) in a routine with no
      /// matching X.Close / X.Active := False in a finally block -- leaks a server cursor
      /// on an exception path.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per opened-but-not-finally-closed dataset variable.</returns>
      /// <remarks>Severity warning. Per-routine flow analysis (mirrors CheckUnprotectedFree).
      /// Pure AST; no DB. Never raises.</remarks>
      class function CheckDatasetOpen(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a critical section acquired (X.Enter or X.Acquire) in a routine with
      /// no matching X.Leave / X.Release in a finally block -- a lock leaked on an exception
      /// path deadlocks.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per acquired-but-not-finally-released lock variable.</returns>
      /// <remarks>Severity error. Per-routine flow analysis (mirrors CheckDatasetOpen).
      /// Pure AST; no DB. Never raises.</remarks>
      class function CheckCriticalSection(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a routine with more than 5 Exit statements -- hard to reason about
      /// control flow; consolidate exits or use guard clauses consistently.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per routine exceeding the Exit-count threshold, at its header.</returns>
      /// <remarks>Severity info. Threshold = 5 (const). Pure AST; no DB. Never raises.</remarks>
      class function CheckTooManyExitPoints(const AFile: string): TArray<TLintFinding>;
      /// <summary>Flags a routine whose cyclomatic complexity exceeds 15. Decision points:
      /// if/ifElse/while/for/repeat, each case branch, and each and/or operator; base 1.</summary>
      /// <param name="AFile">Path to the .pas source file to analyse.</param>
      /// <returns>One finding per routine over the complexity threshold, at its header.</returns>
      /// <remarks>Severity info. Threshold = 15 (const). Node kinds: kAnd/kOr/caseCase verified
      /// against the grammar. Pure AST; no DB. Never raises.</remarks>
      class function CheckCyclomaticComplexity(const AFile: string): TArray<TLintFinding>;
  end;

implementation

function tree_sitter_delphi13: PTSLanguage; cdecl;
external 'tree-sitter-delphi13';

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
  I        : Integer                     ;
  LineNum  : Integer                     ;
  ColNum   : Integer                     ;
begin
  if AStore = nil then Exit(nil);
  if not TFile.Exists(AFile) then Exit(nil);

  SrcBytes:= TFile.ReadAllBytes(AFile);
  Source:= TEncoding.Default.GetString(SrcBytes);

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
  if not TFile.Exists(AFile) then Exit;

  SrcBytes:= TFile.ReadAllBytes(AFile);
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
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
  Findings: TList<TLintFinding>;

  procedure Visit(const N: TTSNode);
  var
    I: Integer     ;
    F: TLintFinding;
    P: TTSPoint    ;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.IsError or N.IsMissing then
    begin
      P:= N.StartPoint;
      F:= Default(TLintFinding);
      F.RuleId  := 'syntax-error';
      F.Severity:= 'error';
      if N.IsMissing then F.Message:= 'Syntax error: missing token'
      else F.Message:= 'Syntax error near here';
      F.FilePath:= AFile;
      F.StartLine:= Integer(P.Row   ) + 1;
      F.StartCol := Integer(P.Column) + 1;
      F.EndLine:= F.StartLine;
      F.EndCol:= F.StartCol + 1;
      Findings.Add(F);
      Exit; { do not descend into an error node }
    end; // if
    if not N.HasError then Exit; { clean subtree -> skip }
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end; // procedure

begin
  Result:= nil;
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Src)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Src[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // begin

class function TAstChecker.CheckUnusedLocals( const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Src)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Src[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then VisitProcs(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // begin

class function TAstChecker.CheckRaiseInFinally(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckCodeAfterExit(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckMissingInherited(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckControlFlowInFinally(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckRoutineMetrics(const AFile: string; AMaxParams, AMaxLocals, AMaxLines, AMaxNesting: Integer): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  function MaxNest(const N: TTSNode; ADepth: Integer): Integer;
  var
    I, D, M: Integer;
    Inc1   : Integer;
  begin
    Result:= ADepth;
    if N.IsNull then Exit;
    Inc1:= 0;
    if (N.NodeType = 'if') or (N.NodeType = 'ifElse') or (N.NodeType = 'while') or (N.NodeType = 'for') or (N.NodeType = 'repeat') or (N.NodeType = 'case') or
      (N.NodeType = 'with') or (N.NodeType = 'try') then Inc1:= 1;
    M:= ADepth;
    for I:= 0 to N.ChildCount - 1 do
    begin
      D:= MaxNest(N.Child(I), ADepth + Inc1);
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckTypeAware(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes                    ;
  Parser  : TTSParser                 ;
  Tree    : TTSTree                   ;
  Findings: TList<TLintFinding>       ;
  TypeMap : TDictionary<string,string>;

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
            TypeMap.AddOrSetValue(LowerCase(NodeStr(NameId)), TTxt);
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectDecls(N.NamedChild(I));
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
      if TypeMap.TryGetValue(LowerCase(NodeStr(N)), T) then Result:= IsFloatType(T);
    end
    else if N.NodeType = 'literalNumber' then
    begin
      Txt:= NodeStr(N);
      Result:= (Pos('.', Txt) > 0) and (Pos('$', Txt) = 0);
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
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'exprBinary' then
    begin
      Op:= N.ChildByField('operator');
      if (not Op.IsNull) and ((Op.NodeType = 'kEq') or (Op.NodeType = 'kNeq')) then
      begin
        L:= N.ChildByField('lhs');
        R:= N.ChildByField('rhs');
        if OperandIsFloat(L) or OperandIsFloat(R) then
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
          if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) and IsInterfaceType(T) then
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
            if (A0.NodeType = 'identifier') and TypeMap.TryGetValue(LowerCase(NodeStr(A0)), T) and IsPointerType(T) then
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
    end;
    for I:= 0 to N.ChildCount - 1 do CheckExpr(N.Child(I));
  end;

begin
  Result:= nil;
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  TypeMap := TDictionary<string,string>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then
    begin
      CollectDecls(Tree.RootNode);
      CheckExpr(Tree.RootNode);
    end;
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    TypeMap.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckFireDacSqlMismatch(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then VisitProcs(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckUnprotectedFree(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
    else if (not AInFinally) and IsFree(N, V) and AConstructed.ContainsKey(V) then
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
        if C.NodeType = 'kFinally' then Lf:= True;
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
        Con:= TDictionary<string, Boolean>.Create;
        try
          WalkBody(Body, False, Con);
        finally
          Con.Free;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do VisitProcs(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then VisitProcs(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
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
    Parser: TTSParser;
    Tree  : TTSTree  ;

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
    Src:= TFile.ReadAllBytes(APath);
    Parser:= nil;
    Tree  := nil;
    try
      Parser:= TTSParser.Create;
      Parser.Language:= tree_sitter_delphi13;
      Tree:= Parser.Parse(
        function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
        var
          Remaining: Integer;
        begin
          Remaining:= Length(Src) - Integer(AByteIndex);
          if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
          SetLength(Result, Remaining);
          Move(Src[AByteIndex], Result[0], Remaining);
          ABytesRead:= Remaining;
        end, TTSInputEncoding.TSInputEncodingUTF8);
      if Tree <> nil then Walk(Tree.RootNode);
    finally
      Tree.Free;
      Parser.Free;
    end;
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
      if (LowerCase(ExtractFileExt(Path)) = '.pas') or (LowerCase(ExtractFileExt(Path)) = '.inc') then ExtractFile(Path);

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
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckUiThread(const AFile: string): TArray<TLintFinding>;
var
  Src      : TBytes                    ;
  Parser   : TTSParser                 ;
  Tree     : TTSTree                   ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings := TList<TLintFinding>.Create;
  ClassBase:= TDictionary<string,string>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then
    begin
      CollectClasses(Tree.RootNode);
      VisitProcs(Tree.RootNode);
    end;
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    ClassBase.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckGlobalFormVars(const AFile: string): TArray<TLintFinding>;
var
  Src           : TBytes;
  Parser        : TTSParser;
  Tree          : TTSTree;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  FormClassNames:= TDictionary<string, Boolean>.Create;
  Parser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    try
      if Tree <> nil then
      begin
        CollectClassNames(Tree.RootNode);
        if FormClassNames.Count > 0 then
          CheckGlobalVarDecls(Tree.RootNode);
      end;
      Result:= Findings.ToArray;
    finally
      Tree.Free;
    end;
  finally
    FormClassNames.Free;
    Findings.Free;
    Parser.Free;
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
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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

  function CmdArgIndex(const ACallee: string; out AIdx: Integer): Boolean;
  begin
    Result:= True;
    AIdx  := -1;
    if SameText(ACallee, 'WinExec') then AIdx:= 0
    else if SameText(ACallee, 'ShellExecute') then AIdx:= 2
    else if SameText(ACallee, 'CreateProcess') then AIdx:= 1
    else Result:= False;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, Idx      : Integer ;
    Ent, Args, A: TTSNode ;
    P           : TTSPoint;
    F           : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and CmdArgIndex(NodeStr(Ent), Idx) then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount > Idx) then
        begin
          A:= Args.NamedChild(Idx);
          if A.NodeType <> 'literalString' then
          begin
            P:= Ent.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'unsafe-shellexecute';
            F.Severity:= 'error';
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
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure

begin
  Result:= nil;
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckPathTraversal(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckLoopAtMostOnce(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
    B    : TTSNode;
    Found: Boolean;
  begin
    Result:= ABody;
    B:= ABody;
    if B.IsNull then Exit;
    if B.NodeType = 'block' then
    begin
      Found:= False;
      for I:= 0 to B.NamedChildCount - 1 do
        if B.NamedChild(I).NodeType = 'statement' then
        begin B:= B.NamedChild(I); Found:= True; Break; end;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckFormatCall(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
    I, J                     : Integer ;
    Ent, Args, Fmt, Arr, Elem: TTSNode ;
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
            Kinds:= SpecKinds(NodeStr(Fmt), IsComplex);
            { count check -- skipped for indexed/star formats we cannot count reliably }
            if (not IsComplex) and (Length(Kinds) <> Arr.NamedChildCount) then
            begin
              P:= Ent.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'format-argument-count';
              F.Severity:= 'error';
              F.Message := Format('Format string has %d specifier(s) but %d argument(s) were supplied.', [Length(Kinds), Arr.NamedChildCount]);
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
              if J >= Arr.NamedChildCount then Break;
              Elem:= Arr.NamedChild(J);
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckSwallowedExcept(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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

  { True if the subtree contains a raise, or an identifier/call whose text names a
    handler (HandleException/ShowException) or a logging/reporting routine. }
  function HandlesException(const N: TTSNode): Boolean;
  var
    I: Integer;
    T: string ;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'raise' then Exit(True);
    if (N.NodeType = 'identifier') or (N.NodeType = 'exprCall') or (N.NodeType = 'exprDot') then
    begin
      T:= LowerCase(NodeStr(N));
      if (Pos('handleexception', T) > 0) or (Pos('showexception', T) > 0)
         or (Pos('log', T) > 0) or (Pos('report', T) > 0) then Exit(True);
    end;
    for I:= 0 to N.ChildCount - 1 do
      if HandlesException(N.Child(I)) then Exit(True);
  end;

  procedure Visit(const N: TTSNode);
  var
    I        : Integer ;
    HasExcept: Boolean ;
    Handled  : Boolean ;
    C        : TTSNode ;
    ExceptPt : TTSPoint;
    F        : TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.NodeType = 'try' then
    begin
      HasExcept:= False;
      Handled  := False;
      ExceptPt := Default(TTSPoint);
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        if C.NodeType = 'kExcept' then
        begin
          HasExcept:= True;
          ExceptPt := C.StartPoint;
        end
        else if HasExcept and (C.NodeType <> 'kEnd') and (C.NodeType <> 'kFinally') then
        begin
          if HandlesException(C) then Handled:= True;
        end;
      end;
      if HasExcept and (not Handled) then
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckDatasetOpen(const AFile: string): TArray<TLintFinding>;
var
  Src            : TBytes                     ;
  Parser         : TTSParser                  ;
  Tree           : TTSTree                    ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then VisitProcs(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckCriticalSection(const AFile: string): TArray<TLintFinding>;
var
  Src             : TBytes                       ;
  Parser          : TTSParser                    ;
  Tree            : TTSTree                      ;
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then VisitProcs(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckTooManyExitPoints(const AFile: string): TArray<TLintFinding>;
const
  MAX_EXITS = 5;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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
    I: Integer;
    T: string ;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Exit; { nested routine counted separately }
    if N.NodeType = 'identifier' then T:= NodeStr(N)
    else if N.NodeType = 'exprCall' then T:= NodeStr(N.ChildByField('entity'))
    else T:= '';
    if SameText(T, 'Exit') then Inc(Result);
    for I:= 0 to N.ChildCount - 1 do Result:= Result + CountExits(N.Child(I));
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
      if NExit > MAX_EXITS then
      begin
        Hdr:= N.ChildByField('header');
        if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'too-many-exit-points';
        F.Severity:= 'info';
        F.Message := Format('Routine has %d Exit statements (max %d) -- consolidate exits or use guard clauses.', [NExit, MAX_EXITS]);
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

class function TAstChecker.CheckCyclomaticComplexity(const AFile: string): TArray<TLintFinding>;
const
  MAX_CC = 15;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
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

  function CountDecisions(const N: TTSNode): Integer;
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
    for I:= 0 to N.ChildCount - 1 do Result:= Result + CountDecisions(N.Child(I));
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
      CC:= 1 + CountDecisions(Body);
      if CC > MAX_CC then
      begin
        Hdr:= N.ChildByField('header');
        if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'cyclomatic-complexity';
        F.Severity:= 'info';
        F.Message := Format('Routine has cyclomatic complexity %d (max %d) -- consider extracting sub-routines.', [CC, MAX_CC]);
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
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end; // function

initialization

finalization
GKeywordSet.Free;
GKeywordSet:= nil;

end.
