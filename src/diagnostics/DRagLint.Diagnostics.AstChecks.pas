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

initialization

finalization
GKeywordSet.Free;
GKeywordSet:= nil;

end.
