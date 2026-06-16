unit DRagLint.Diagnostics.AstChecks;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  TreeSitter, TreeSitterLib,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  TAstChecker = class
  strict private
    class function LoadBuiltinAllowlist: TDictionary<string, Boolean>;
    class function IsKeyword(const AName: string): Boolean;
  public
    class function Check(const AStore: ISymbolStore;
      const AFile: string): TArray<TLintFinding>;
    class function CheckUndeclared(const AStore: ISymbolStore;
      const AFile: string): TArray<TLintFinding>;
    class function CheckUnbalancedBeginEnd(
      const AFile: string): TArray<TLintFinding>;
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
  GKeywordSet := TDictionary<string, Boolean>.Create(256);
  KW := TStringList.Create;
  try
    KW.CommaText :=
      'and,array,as,asm,begin,case,class,const,' +
      'constructor,destructor,dispinterface,div,do,downto,' +
      'else,end,except,exports,file,finalization,finally,' +
      'for,function,goto,if,implementation,in,inherited,' +
      'initialization,inline,interface,is,label,library,' +
      'mod,nil,not,object,of,on,operator,or,out,' +
      'packed,procedure,program,property,protected,public,' +
      'published,raise,record,reintroduce,repeat,resourcestring,' +
      'set,shl,shr,string,then,threadvar,to,try,type,' +
      'unit,until,uses,var,while,with,xor,' +
      'absolute,abstract,assembler,automated,cdecl,contains,' +
      'default,deprecated,dynamic,experimental,export,external,' +
      'far,final,forward,helper,implements,index,message,' +
      'name,near,nodefault,overload,override,package,pascal,' +
      'platform,private,read,readonly,register,' +
      'requires,resident,result,safecall,sealed,self,static,' +
      'stdcall,strict,stored,true,false,virtual,winapi,' +
      'write,writeonly,integer,boolean,char,byte,' +
      'word,cardinal,int64,double,single,real';
    var I: Integer;
    for I := 0 to KW.Count - 1 do
      GKeywordSet.AddOrSetValue(KW[I], True);
  finally
    KW.Free;
  end;
end;

class function TAstChecker.IsKeyword(const AName: string): Boolean;
begin
  if GKeywordSet = nil then
    BuildKeywordSet;
  Result := GKeywordSet.ContainsKey(System.SysUtils.LowerCase(AName));
end;

class function TAstChecker.LoadBuiltinAllowlist: TDictionary<string, Boolean>;
var
  AllowPath: string;
  Lines: TArray<string>;
  Line: string;
  D: TDictionary<string, Boolean>;
begin
  D := TDictionary<string, Boolean>.Create(256);
  AllowPath := TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), 'rules\builtin-symbols.txt');
  if TFile.Exists(AllowPath) then
  begin
    Lines := TFile.ReadAllLines(AllowPath, TEncoding.ASCII);
    for Line in Lines do
    begin
      var Trimmed := Trim(Line);
      if Trimmed <> '' then
        D.AddOrSetValue(Trimmed, True);
    end;
  end;
  Result := D;
end;

class function TAstChecker.CheckUndeclared(const AStore: ISymbolStore;
  const AFile: string): TArray<TLintFinding>;
var
  Source: string;
  Findings: TList<TLintFinding>;
  Seen: TDictionary<string, Boolean>;
  Allowlist: TDictionary<string, Boolean>;
  Matches: TMatchCollection;
  M: TMatch;
  Name: string;
  Syms: TArray<TSymbol>;
  Finding: TLintFinding;
  LineStart: Integer;
  SrcBytes: TBytes;
  i: Integer;
  LineNum, ColNum: Integer;
begin
  if AStore = nil then
    Exit(nil);
  if not TFile.Exists(AFile) then
    Exit(nil);

  SrcBytes := TFile.ReadAllBytes(AFile);
  Source := TEncoding.Default.GetString(SrcBytes);

  Findings := TList<TLintFinding>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Allowlist := LoadBuiltinAllowlist;
  try
    Matches := TRegEx.Matches(Source,
      '\b([A-Z][A-Za-z0-9_]{2,})\b');
    for M in Matches do
    begin
      Name := M.Groups[1].Value;
      if Seen.ContainsKey(Name) then
        Continue;
      Seen.Add(Name, True);

      if IsKeyword(Name) then
        Continue;
      if Allowlist.ContainsKey(Name) then
        Continue;

      Syms := AStore.FindSymbolsByExactName(Name);
      if Length(Syms) > 0 then
        Continue;

      LineNum := 1;
      ColNum  := 1;
      LineStart := 1;
      for i := 1 to M.Index - 1 do
      begin
        if Source[i] = #10 then
        begin
          Inc(LineNum);
          LineStart := i + 1;
        end;
      end;
      ColNum := M.Index - LineStart + 1;

      Finding := Default(TLintFinding);
      Finding.RuleId    := 'undeclared-identifier';
      Finding.Severity  := 'warning';
      Finding.Message   := 'Identifier "' + Name +
        '" not found in symbol index (may be undeclared or from an unindexed unit)';
      Finding.FilePath  := AFile;
      Finding.StartLine := LineNum;
      Finding.StartCol  := ColNum;
      Finding.EndLine   := LineNum;
      Finding.EndCol    := ColNum + Length(Name);
      Findings.Add(Finding);
    end;
    Result := Findings.ToArray;
  finally
    Allowlist.Free;
    Seen.Free;
    Findings.Free;
  end;
end;

class function TAstChecker.CheckUnbalancedBeginEnd(
  const AFile: string): TArray<TLintFinding>;
var
  Source: string;
  SrcBytes: TBytes;
  i, Len: Integer;
  C: Char;
  Depth: Integer;
  InStr, InLineComment, InBraceCmt, InParenStarCmt: Boolean;
  WordStart: Integer;
  Word: string;
  LastUnmatchedLine, LastUnmatchedCol: Integer;
  LineNum, ColNum: Integer;
  LineStart: Integer;
  Finding: TLintFinding;
begin
  Result := nil;
  if not TFile.Exists(AFile) then
    Exit;

  SrcBytes := TFile.ReadAllBytes(AFile);
  Source := TEncoding.Default.GetString(SrcBytes);
  Len := Length(Source);

  Depth := 0;
  InStr := False;
  InLineComment := False;
  InBraceCmt := False;
  InParenStarCmt := False;
  LastUnmatchedLine := 1;
  LastUnmatchedCol  := 1;
  LineNum  := 1;
  LineStart := 1;
  i := 1;

  while i <= Len do
  begin
    C := Source[i];

    if C = #10 then
    begin
      Inc(LineNum);
      LineStart := i + 1;
      InLineComment := False;
      Inc(i);
      Continue;
    end;
    if C = #13 then
    begin
      Inc(i);
      Continue;
    end;

    if InLineComment then
    begin
      Inc(i);
      Continue;
    end;

    if InBraceCmt then
    begin
      if C = '}' then
        InBraceCmt := False;
      Inc(i);
      Continue;
    end;

    if InParenStarCmt then
    begin
      if (C = '*') and (i < Len) and (Source[i + 1] = ')') then
      begin
        InParenStarCmt := False;
        Inc(i, 2);
      end
      else
        Inc(i);
      Continue;
    end;

    if InStr then
    begin
      if C = '''' then
      begin
        if (i < Len) and (Source[i + 1] = '''') then
          Inc(i, 2)
        else
        begin
          InStr := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
      Continue;
    end;

    if C = '''' then
    begin
      InStr := True;
      Inc(i);
      Continue;
    end;

    if C = '{' then
    begin
      InBraceCmt := True;
      Inc(i);
      Continue;
    end;

    if (C = '(') and (i < Len) and (Source[i + 1] = '*') then
    begin
      InParenStarCmt := True;
      Inc(i, 2);
      Continue;
    end;

    if (C = '/') and (i < Len) and (Source[i + 1] = '/') then
    begin
      InLineComment := True;
      Inc(i, 2);
      Continue;
    end;

    if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) then
    begin
      WordStart := i;
      while (i <= Len) and
            CharInSet(Source[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(i);
      Word := Copy(Source, WordStart, i - WordStart);

      if (i <= Len) and not CharInSet(Source[i], [#0..#32, '(', ')', ',', ';', '.', '[', ']', ':', '=', '+', '-', '*', '/', '@', '^', '{', '}', #39]) then
      begin
        Continue;
      end;

      if SameText(Word, 'begin') then
      begin
        Inc(Depth);
        ColNum := WordStart - LineStart + 1;
        LastUnmatchedLine := LineNum;
        LastUnmatchedCol  := ColNum;
      end
      else if SameText(Word, 'end') then
      begin
        if Depth > 0 then
          Dec(Depth)
        else
        begin
          ColNum := WordStart - LineStart + 1;
          LastUnmatchedLine := LineNum;
          LastUnmatchedCol  := ColNum;
        end;
      end;
      Continue;
    end;

    Inc(i);
  end;

  if Depth <> 0 then
  begin
    Finding := Default(TLintFinding);
    Finding.RuleId    := 'unbalanced-begin-end';
    Finding.Severity  := 'warning';
    Finding.Message   := Format(
      'Unbalanced begin/end: depth %d at end of file ' +
      '(last unmatched keyword near line %d)',
      [Depth, LastUnmatchedLine]);
    Finding.FilePath  := AFile;
    Finding.StartLine := LastUnmatchedLine;
    Finding.StartCol  := LastUnmatchedCol;
    Finding.EndLine   := LastUnmatchedLine;
    Finding.EndCol    := LastUnmatchedCol + 5;
    Result := [Finding];
  end;
end;

class function TAstChecker.CheckSyntaxErrors(
  const AFile: string): TArray<TLintFinding>;
var
  Src: TBytes;
  Parser: TTSParser;
  Tree: TTSTree;
  Findings: TList<TLintFinding>;

  procedure Visit(const N: TTSNode);
  var
    i: Integer;
    F: TLintFinding;
    P: TTSPoint;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.IsError or N.IsMissing then
    begin
      P := N.StartPoint;
      F := Default(TLintFinding);
      F.RuleId   := 'syntax-error';
      F.Severity := 'error';
      if N.IsMissing then
        F.Message := 'Syntax error: missing token'
      else
        F.Message := 'Syntax error near here';
      F.FilePath  := AFile;
      F.StartLine := Integer(P.Row) + 1;
      F.StartCol  := Integer(P.Column) + 1;
      F.EndLine   := F.StartLine;
      F.EndCol    := F.StartCol + 1;
      Findings.Add(F);
      Exit;                 { do not descend into an error node }
    end;
    if not N.HasError then Exit;   { clean subtree -> skip }
    for i := 0 to N.ChildCount - 1 do
      Visit(N.Child(i));
  end;

begin
  Result := nil;
  if not TFile.Exists(AFile) then Exit;
  Src := TFile.ReadAllBytes(AFile);
  Findings := TList<TLintFinding>.Create;
  Parser := nil;
  Tree := nil;
  try
    Parser := TTSParser.Create;
    Parser.Language := tree_sitter_delphi13;
    Tree := Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint;
        var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining := Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then
        begin
          ABytesRead := 0;
          SetLength(Result, 0);
          Exit;
        end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead := Remaining;
      end,
      TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then
      Visit(Tree.RootNode);
    Result := Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end;

class function TAstChecker.CheckUnusedLocals(
  const AFile: string): TArray<TLintFinding>;
var
  Src: TBytes;
  Parser: TTSParser;
  Tree: TTSTree;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var S, E, L: Integer;
  begin
    Result := '';
    if N.IsNull then Exit;
    S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result := TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Count every identifier occurrence (lowercased) in the subtree. A declared
    local's own declaration counts as one; any use raises it above one. }
  procedure CountIdents(const N: TTSNode; AMap: TDictionary<string, Integer>);
  var
    I, C: Integer;
    T: string;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'identifier' then
    begin
      T := LowerCase(NodeStr(N));
      if T <> '' then
        if AMap.TryGetValue(T, C) then AMap[T] := C + 1 else AMap.Add(T, 1);
    end;
    for I := 0 to N.NamedChildCount - 1 do
      CountIdents(N.NamedChild(I), AMap);
  end;

  procedure CheckProc(const ADefProc: TTSNode);
  var
    Counts: TDictionary<string, Integer>;
    I, J, K, Cnt, TypeStart: Integer;
    Child, DV, TypeNode, NameId, Hdr, Nm, Body: TTSNode;
    RoutineName, DisplayName, LowerName: string;
    P: TTSPoint;
    F: TLintFinding;
  begin
    { skip asm routines -- identifiers in an asm block are not 'identifier'
      nodes, so a local used only in asm would be a false positive. }
    Body := ADefProc.ChildByField('body');
    if (not Body.IsNull) and (Body.NodeType = 'asm') then Exit;

    Counts := TDictionary<string, Integer>.Create;
    try
      CountIdents(ADefProc, Counts);

      RoutineName := '';
      Hdr := ADefProc.ChildByField('header');
      if not Hdr.IsNull then
      begin
        Nm := Hdr.ChildByField('name');
        if not Nm.IsNull then RoutineName := NodeStr(Nm);
      end;

      { direct declVars children = THIS routine's local var sections (a nested
        routine's declVars are grandchildren, handled when we recurse to it). }
      for I := 0 to ADefProc.NamedChildCount - 1 do
      begin
        Child := ADefProc.NamedChild(I);
        if Child.NodeType <> 'declVars' then Continue;
        for J := 0 to Child.NamedChildCount - 1 do
        begin
          DV := Child.NamedChild(J);
          if DV.NodeType <> 'declVar' then Continue;
          TypeNode := DV.ChildByField('type');
          if TypeNode.IsNull then TypeStart := MaxInt
          else TypeStart := Integer(TypeNode.StartByte);
          { name identifiers come before the type field (A, B: T) }
          for K := 0 to DV.NamedChildCount - 1 do
          begin
            NameId := DV.NamedChild(K);
            if NameId.NodeType <> 'identifier' then Continue;
            if Integer(NameId.StartByte) >= TypeStart then Continue;
            DisplayName := NodeStr(NameId);
            LowerName := LowerCase(DisplayName);
            if LowerName = '' then Continue;
            Cnt := 0;
            Counts.TryGetValue(LowerName, Cnt);
            if Cnt <= 1 then   { only the declaration occurrence -> unused }
            begin
              P := NameId.StartPoint;
              F := Default(TLintFinding);
              F.RuleId   := 'unused-local';
              F.Severity := 'hint';
              if RoutineName <> '' then
                F.Message := Format(
                  'H2164 Variable ''%s'' is declared but never used in ''%s''',
                  [DisplayName, RoutineName])
              else
                F.Message := Format(
                  'H2164 Variable ''%s'' is declared but never used',
                  [DisplayName]);
              F.FilePath  := AFile;
              F.StartLine := Integer(P.Row) + 1;
              F.StartCol  := Integer(P.Column) + 1;
              F.EndLine   := F.StartLine;
              F.EndCol    := F.StartCol + Length(DisplayName);
              Findings.Add(F);
            end;
          end;
        end;
      end;
    finally
      Counts.Free;
    end;
  end;

  procedure VisitProcs(const N: TTSNode);
  var I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
      CheckProc(N);
    for I := 0 to N.NamedChildCount - 1 do
      VisitProcs(N.NamedChild(I));
  end;

begin
  Result := nil;
  if not TFile.Exists(AFile) then Exit;
  Src := TFile.ReadAllBytes(AFile);
  Findings := TList<TLintFinding>.Create;
  Parser := nil;
  Tree := nil;
  try
    Parser := TTSParser.Create;
    Parser.Language := tree_sitter_delphi13;
    Tree := Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint;
        var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining := Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then
        begin
          ABytesRead := 0;
          SetLength(Result, 0);
          Exit;
        end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead := Remaining;
      end,
      TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then
      VisitProcs(Tree.RootNode);
    Result := Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end;

class function TAstChecker.Check(const AStore: ISymbolStore;
  const AFile: string): TArray<TLintFinding>;
var
  All: TList<TLintFinding>;
  Part: TArray<TLintFinding>;
  F: TLintFinding;
begin
  All := TList<TLintFinding>.Create;
  try
    Part := CheckSyntaxErrors(AFile);
    for F in Part do All.Add(F);

    Part := CheckUnbalancedBeginEnd(AFile);
    for F in Part do All.Add(F);

    if AStore <> nil then
    begin
      Part := CheckUndeclared(AStore, AFile);
      for F in Part do All.Add(F);
    end;

    Result := All.ToArray;
  finally
    All.Free;
  end;
end;


initialization

finalization
  GKeywordSet.Free;
  GKeywordSet := nil;

end.
