unit DRagLint.V156.OOB1.Support;

{ Wave v156 lane OOB-1 -- helpers of DRagLint.V156.OOB1 (private to the lane).

  field-could-be-local (G-23): a PRIVATE field of a class that is referenced inside ONE routine of
  its own file only, and whose first reference in that routine is a write. The state never outlives
  a call, so a local variable does the same job. Silent when it cannot prove that: a reference
  outside any routine body (property accessor, initialization), a second routine, a second file,
  a first reference that reads (a cache), a qualified access of the same name elsewhere in the
  file (another class of the unit may reach the private field), an attribute on the field, an
  anonymous method in the routine, a published or non-private field.

  repeated-string-literal (G-25): the same string literal of 9 or more characters typed at 5 or
  more sites of the project (kind `literal` of source `pas`; units whose file name holds `test`
  are neither counted nor reported). One finding per literal text, at its first site. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Evaluates field-could-be-local and repeated-string-literal over one project index.</summary>
  /// <remarks>Stateless; class methods only. Reads the store, never writes it.</remarks>
  TOOB1Checks = class
  public
    /// <summary>Private fields of one file that live inside a single routine.</summary>
    /// <param name="AStore">Project index; nil returns nil.</param>
    /// <param name="AFileId">files.id of APath in AStore; 0 returns nil.</param>
    /// <param name="APath">The file path stamped on each finding.</param>
    /// <param name="ARuleId">Rule id to stamp on each finding.</param>
    /// <returns>One hint per field, at its declaration; nil when none.</returns>
    class function FieldsCouldBeLocal(const AStore: ISymbolStore; AFileId: Int64;
      const APath, ARuleId: string): TArray<TLintFinding>; static;
    /// <summary>String literals typed at 5 or more sites of the project.</summary>
    /// <param name="AStore">Project index; nil returns nil.</param>
    /// <param name="ARuleId">Rule id to stamp on each finding.</param>
    /// <returns>One hint per repeated text, at its first site (file path, then line); nil when none.</returns>
    /// <remarks>Cost: one GetLiteralsByKind per indexed file. Meant for lint-all only.</remarks>
    class function RepeatedLiterals(const AStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.IOUtils
  , System.RegularExpressions
  ;

const
  MIN_LITERAL_LEN = 9;
  MIN_LITERAL_SITES = 5;

function IsPrivateField(const ASym: TSymbol): Boolean;
begin
  var Mods: string:= Trim(LowerCase(ASym.Modifiers));
  Result:= (ASym.Kind = skField) and ((Mods = 'private') or (Mods = 'strict private'));
end;

function RoutineHasAnonymous(const APath: string; AFromLine, AToLine: Integer): Boolean;
begin
  Result:= True;  { unreadable source: not provable, stay silent }
  if not TFile.Exists(APath) then Exit;
  try
    var Lines: TArray<string>:= TFile.ReadAllLines(APath);
    var Body: TStringBuilder:= TStringBuilder.Create;
    try
      for var I: Integer:= AFromLine to AToLine do
        if (I >= 1) and (I <= Length(Lines)) then Body.AppendLine(Lines[I - 1]);
      Result:= TRegEx.IsMatch(Body.ToString, '\b(procedure|function)\s*\(', [roIgnoreCase]);
    finally
      Body.Free;
    end;
  except
    Result:= True;  // dl:ok try-except-swallowed -- REVIEWED v156 OOB-1: an unreadable file proves nothing; the rule stays silent
  end;
end;

class function TOOB1Checks.FieldsCouldBeLocal(const AStore: ISymbolStore; AFileId: Int64;
  const APath, ARuleId: string): TArray<TLintFinding>;
begin
  Result:= nil;
  if (AStore = nil) or (AFileId = 0) then Exit;
  var Refs: TArray<TReference>:= AStore.GetReferencesFromFile(AFileId);
  var Syms: TArray<TSymbol>:= AStore.FindSymbolsByFile(APath);
  var ById: TDictionary<Int64, TSymbol>:= TDictionary<Int64, TSymbol>.Create;
  var Attr: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  var Elsewhere: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var S: TSymbol in Syms do ById.AddOrSetValue(S.Id, S);
    if AStore.HasAttributes then
      for var A: TAttributeRow in AStore.GetAttributes(AFileId) do Attr.AddOrSetValue(A.SymbolId, True);
    for var R: TReference in Refs do
      if (R.ReceiverText <> '') and not ById.ContainsKey(R.SymbolId) then
        Elsewhere.AddOrSetValue(LowerCase(R.NameText), True);
    for var Fld: TSymbol in Syms do
    begin
      if not IsPrivateField(Fld) then Continue;
      var Cls: TSymbol;
      if not ById.TryGetValue(Fld.ParentId, Cls) or (Cls.Kind <> skClass) then Continue;
      if Attr.ContainsKey(Fld.Id) or Elsewhere.ContainsKey(LowerCase(Fld.Name)) then Continue;
      var Routine: Int64:= 0;
      var FirstLine: Integer:= MaxInt;
      var FirstCol: Integer:= MaxInt;
      var FirstKind: string:= '';
      var Count: Integer:= 0;
      var ReadCount: Integer:= 0;
      var Ok: Boolean:= True;
      for var R: TReference in Refs do
      begin
        if R.SymbolId <> Fld.Id then Continue;
        Inc(Count);
        if R.Kind <> 'write' then Inc(ReadCount);
        if (R.EnclosingSymbolId = 0) or ((Routine <> 0) and (R.EnclosingSymbolId <> Routine)) then
        begin
          Ok:= False;
          Break;
        end;
        Routine:= R.EnclosingSymbolId;
        if (R.StartLine < FirstLine) or ((R.StartLine = FirstLine) and (R.StartCol < FirstCol)) then
        begin
          FirstLine:= R.StartLine;
          FirstCol:= R.StartCol;
          FirstKind:= R.Kind;
        end;
      end;
      { a field that is never read is a write-only field, not a local-in-waiting (v156 FP-1) }
      if not Ok or (Count = 0) or (ReadCount = 0) or (FirstKind <> 'write') then Continue;
      var Rtn: TSymbol;
      if not ById.TryGetValue(Routine, Rtn) then Continue;
      var ToLine: Integer:= Rtn.ImplEndLine;
      if ToLine < Rtn.ImplStartLine then ToLine:= Rtn.EndLine;
      if RoutineHasAnonymous(APath, Rtn.ImplStartLine, ToLine) then Continue;
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId    := ARuleId;
      F.Severity  := 'hint';
      F.FileId    := AFileId;
      F.FilePath  := APath;
      F.StartLine := Fld.StartLine;
      F.StartCol  := Fld.StartCol;
      F.EndLine   := Fld.EndLine;
      F.EndCol    := Fld.EndCol;
      F.SymbolName:= Fld.Name;
      F.Message   := Format('Private field %s.%s is only used inside %s and written before it is read -- it could be a local variable',
        [Cls.Name, Fld.Name, Rtn.Name]);
      Result:= Result + [F];
    end;
  finally
    Elsewhere.Free;
    Attr.Free;
    ById.Free;
  end;
end;

class function TOOB1Checks.RepeatedLiterals(const AStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>;
type
  TSite = record
    FileId: Int64;
    Path  : string;
    Line  : Integer;
    Col   : Integer;
  end;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Counts: TDictionary<string, Integer>:= TDictionary<string, Integer>.Create;
  var First : TDictionary<string, TSite>:= TDictionary<string, TSite>.Create;
  try
    for var FileId: Int64 in AStore.GetAllFileIds do
    begin
      var Path: string:= AStore.GetFilePath(FileId);
      if Pos('test', LowerCase(ExtractFileName(Path))) > 0 then Continue;
      for var L: TStringLiteral in AStore.GetLiteralsByKind(FileId, 'literal') do
      begin
        if (L.Source <> 'pas') or (Length(L.Text) < MIN_LITERAL_LEN) then Continue;
        var N: Integer;
        if not Counts.TryGetValue(L.Text, N) then N:= 0;
        Counts.AddOrSetValue(L.Text, N + 1);
        var Site: TSite;
        Site.FileId:= FileId;
        Site.Path:= Path;
        Site.Line:= L.StartLine;
        Site.Col:= L.StartCol;
        var Old: TSite;
        var Cmp: Integer;
        if First.TryGetValue(L.Text, Old) then
        begin
          Cmp:= CompareText(Site.Path, Old.Path);
          if Cmp = 0 then Cmp:= (Site.Line - Old.Line) * 1000 + (Site.Col - Old.Col);
        end
        else Cmp:= -1;
        if Cmp < 0 then First.AddOrSetValue(L.Text, Site);
      end;
    end;
    for var Pair in Counts do
    begin
      if Pair.Value < MIN_LITERAL_SITES then Continue;
      var S: TSite:= First[Pair.Key];
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId    := ARuleId;
      F.Severity  := 'hint';
      F.FileId    := S.FileId;
      F.FilePath  := S.Path;
      F.StartLine := S.Line;
      F.StartCol  := S.Col;
      F.EndLine   := S.Line;
      F.EndCol    := S.Col + Length(Pair.Key) + 2;
      F.Message   := Format('The text ''%s'' is typed %d times in the project -- declare it once as a constant', [Pair.Key, Pair.Value]);
      Result:= Result + [F];
    end;
  finally
    First.Free;
    Counts.Free;
  end;
end;

end.
