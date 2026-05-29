unit DRagLint.Diagnostics.AstChecks;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions,
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
  end;

implementation

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

class function TAstChecker.Check(const AStore: ISymbolStore;
  const AFile: string): TArray<TLintFinding>;
var
  All: TList<TLintFinding>;
  Part: TArray<TLintFinding>;
  F: TLintFinding;
begin
  All := TList<TLintFinding>.Create;
  try
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
