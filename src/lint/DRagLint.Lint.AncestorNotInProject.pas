unit DRagLint.Lint.AncestorNotInProject;

{ ancestor-not-in-project (1.42 lane enum; owner ruling 2026-11-03, C8CHAIN Q-B,
  docs\INBOX-2026-11-03-converter-to-engine-ancestor-not-in-project-rule.md).

  A form / frame / data module whose DIRECT ancestor class is declared in no unit
  of the project index and not in the platform library compiles only where the
  ancestor's unit happens to be on the search path. The project index is the
  compile closure of the .dproj / .dpr, so "not in the project index" is exactly
  "its unit is not a project member" -- the sibling of unit-not-in-dpr, judged
  from the class side instead of the uses side. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id: a form / frame / data module whose ancestor's unit is not in the project.</summary>
  ANCESTOR_NOT_IN_PROJECT_RULE = 'ancestor-not-in-project';

/// <summary>Finds every form / frame / data module class whose direct ancestor
/// is declared neither in the project index nor in the platform library.</summary>
/// <param name="AStore">The project index (the compile closure of the project);
/// nil yields no findings.</param>
/// <param name="ALibStore">The platform library index. nil yields NO findings:
/// without it a VCL / vendor base (TForm, TcxFrame, ...) cannot be told from a
/// project base whose unit is missing, and the rule stays silent rather than
/// report every form.</param>
/// <returns>One error per offending class, anchored at its declaration line;
/// the message names the class, the ancestor and the unit to add (the
/// qualifying unit of a dotted ancestor, otherwise the used units that resolve
/// in neither index).</returns>
/// <remarks>A class counts as a form / frame / data module when it is the ROOT
/// class of the text .dfm / .fmx beside its unit (first line
/// <c>object|inherited|inline Name: TClass</c>); a binary .dfm is skipped. The
/// ancestor is the first heritage entry, generic arguments stripped. Exempt:
/// an ancestor name declared as a type in either index, or a dotted ancestor
/// whose unit is a unit of either index. Never raises.</remarks>
function CollectAncestorNotInProject(const AStore, ALibStore: ISymbolStore): TArray<TLintFinding>;

implementation

uses
  System.StrUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  ;

type
  TSymbolKindSet = set of TSymbolKind;

const
  DFM_EXTENSIONS: array[0..1] of string = ('.dfm', '.fmx');
  { How many lines are read looking for the root object line of a text form file. }
  MAX_HEAD_LINES = 8;
  BINARY_DFM_MARK = #$FF;

{ The root class of a text form file, '' when absent, binary or unreadable. }
function FormRootClass(const APath: string): string;
var
  Reader: TStreamReader;
  Line  : string;
  N     : Integer;
  P     : Integer;
begin
  Result:= '';
  try
    Reader:= TStreamReader.Create(APath, TEncoding.ANSI, False);
    try
      N:= 0;
      while (not Reader.EndOfStream) and (N < MAX_HEAD_LINES) do
      begin
        Inc(N);
        Line:= Trim(Reader.ReadLine);
        if Line = '' then Continue;
        if Line.StartsWith(BINARY_DFM_MARK) then Exit;
        if not (StartsText('object ', Line) or StartsText('inherited ', Line)
                or StartsText('inline ', Line)) then Exit;
        P:= Pos(':', Line);
        if P = 0 then Exit;
        Line:= Trim(Copy(Line, P + 1, MaxInt));
        P:= Pos(' ', Line);
        if P > 0 then Line:= Copy(Line, 1, P - 1);
        P:= Pos('[', Line);
        if P > 0 then Line:= Copy(Line, 1, P - 1);
        Exit(Trim(Line));
      end;
    finally
      Reader.Free;
    end;
  except
    on EFOpenError do Result:= '';
    on EStreamError do Result:= '';
  end;
end;

{ The first heritage entry of a class, generic arguments and parentheses stripped. }
function FirstAncestor(const AHeritage: string): string;
var
  P: Integer;
begin
  Result:= Trim(AHeritage);
  if Result.StartsWith('(') then Result:= Copy(Result, 2, MaxInt);
  P:= Pos(',', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= Pos(')', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  Result:= Trim(Result);
end;

function HasKind(const AStore: ISymbolStore; const AName: string; const AKinds: TSymbolKindSet): Boolean;
begin
  Result:= False;
  if (AStore = nil) or (AName = '') then Exit;
  for var S in AStore.FindSymbolsByExactName(AName) do
    if S.Kind in AKinds then Exit(True);
end;

function CollectAncestorNotInProject(const AStore, ALibStore: ISymbolStore): TArray<TLintFinding>;
const
  TYPE_KINDS: TSymbolKindSet = [skClass, skInterface, skRecord, skTypeAlias];
  UNIT_KINDS: TSymbolKindSet = [skUnit];
var
  Findings: TList<TLintFinding>;
  RootOf  : TDictionary<Int64, string>; { file id -> root class of its form file ('' = none) }

  function RootClassOfFile(AFileId: Int64): string;
  begin
    if RootOf.TryGetValue(AFileId, Result) then Exit;
    Result:= '';
    var Pas:= AStore.GetFilePath(AFileId);
    if SameText(ExtractFileExt(Pas), '.pas') then
      for var Ext in DFM_EXTENSIONS do
        if TFile.Exists(ChangeFileExt(Pas, Ext)) then
        begin
          Result:= FormRootClass(ChangeFileExt(Pas, Ext));
          Break;
        end;
    RootOf.Add(AFileId, Result);
  end;

  function KnownUnit(const AUnit: string): Boolean;
  begin
    Result:= HasKind(AStore, AUnit, UNIT_KINDS) or HasKind(ALibStore, AUnit, UNIT_KINDS);
  end;

  { The used units of AFileId that resolve in neither index -- where a bare
    ancestor must come from. }
  function UnknownUses(AFileId: Int64): string;
  begin
    Result:= '';
    for var U in AStore.GetUnitUsesForFile(AFileId) do
      if (U.InPath = '') and not KnownUnit(U.UnitName) then
        Result:= Result + (if Result = '' then '' else ', ') + U.UnitName;
  end;

begin
  Result:= nil;
  if (AStore = nil) or (ALibStore = nil) then Exit;
  Findings:= TList<TLintFinding>.Create;
  RootOf  := TDictionary<Int64, string>.Create;
  try
    for var C in AStore.FindSymbolsByKind('class', False, MaxInt) do
    begin
      if not SameText(RootClassOfFile(C.FileId), C.Name) then Continue;
      var Full:= AStore.GetSymbolById(C.Id);
      var Anc := FirstAncestor(Full.Heritage);
      if Anc = '' then Continue;
      var UnitPart:= '';
      var Bare    := Anc;
      var Dot     := LastDelimiter('.', Anc);
      if Dot > 0 then
      begin
        UnitPart:= Copy(Anc, 1, Dot - 1);
        Bare    := Copy(Anc, Dot + 1, MaxInt);
      end;
      if HasKind(AStore, Bare, TYPE_KINDS) or HasKind(ALibStore, Bare, TYPE_KINDS) then Continue;
      if (UnitPart <> '') and KnownUnit(UnitPart) then Continue;
      var Hint:= UnitPart;
      if Hint = '' then Hint:= UnknownUses(C.FileId);
      if Hint = '' then Hint:= '(no candidate in the uses clause)';

      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId   := ANCESTOR_NOT_IN_PROJECT_RULE;
      F.Severity := 'error';
      F.FilePath := AStore.GetFilePath(C.FileId);
      F.StartLine:= C.StartLine;
      F.StartCol := C.StartCol;
      F.EndLine  := C.StartLine;
      F.EndCol   := C.StartCol;
      F.Message  := Format('%s (the root class of its form file) inherits from %s, which is ' +
                           'declared in no unit of this project and not in the platform ' +
                           'library -- add its unit to the project (.dproj / .dpr): %s. The ' +
                           'project fails to compile wherever that unit is not on the search path',
                           [C.Name, Bare, Hint]);
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    RootOf  .Free;
    Findings.Free;
  end;
end;

end.
