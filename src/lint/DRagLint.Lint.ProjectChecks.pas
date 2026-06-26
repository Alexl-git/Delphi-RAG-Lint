unit DRagLint.Lint.ProjectChecks;

// v0.9: project-level lint rules. Operate on a .dproj + sibling .dpr/.dpk,
// not on per-file ASTs. The first rule (`unit-not-in-dpr`) is from a known
// real-world hazard: Delphi compiles a unit if either the .dproj DCCReference
// list OR the search path resolves it, so a unit can be "in the build" without
// being listed in both places - and that silently breaks future re-IDE-opens.

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System  .Generics.Collections
  , System  .Generics.Defaults
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  ;

type
  TProjectChecks = class
    public
      // Compare .dproj <DCCReference Include="..."/> entries vs the matching
      // .dpr/.dpk's `uses` clause. Returns findings for every unit that is
      // present on one side but not the other.
      class function CheckUnitsInDpr( const ADprojPath: string): TArray<TLintFinding>;
      /// <summary>Checks that every unit used by the indexed project is either in
      /// the platform library DB or formally registered in the project (.dpr + .dproj).</summary>
      /// <param name="AStore">Open project symbol store.</param>
      /// <param name="ALibDbPath">Path to the platform library SQLite DB. Pass '' to skip.</param>
      /// <param name="AProjectDprojPath">Path to the .dproj file. Pass '' to skip .dpr/.dproj cross-check.</param>
      /// <returns>One warning per unit that is used but cannot be confirmed as a library or project member.</returns>
      class function CheckUnitMembership(const AStore: ISymbolStore;
        const ALibDbPath: string; const AProjectDprojPath: string): TArray<TLintFinding>;
  end;

implementation

uses
  FireDAC.Comp.Client
  ;

function NormalizeUnitName(const APathOrName: string): string;
var
  Base: string;
begin
  Base:= ExtractFileName(APathOrName);
  Base:= ChangeFileExt(Base, '');
  Result:= LowerCase(Base);
end;

function ReadDCCReferences(const ADprojPath: string): TArray<string>;
var
  Content: string       ;
  RE     : TRegEx       ;
  M      : TMatch       ;
  List   : TList<string>;
  Inc    : string       ;
begin
  if not TFile.Exists(ADprojPath) then Exit(nil);
  Content:= TFile.ReadAllText(ADprojPath);
  RE:= TRegEx.Create('<DCCReference\s+Include="([^"]+)"', [roIgnoreCase, roSingleLine]);
  List:= TList<string>.Create;
  try
    M:= RE.Match(Content);
    while M.Success do
    begin
      Inc:= M.Groups[1].Value;
      // Only track .pas/.dpr/.dpk units; skip .rc, .res, .dfm, etc.
      if SameText(ExtractFileExt(Inc), '.pas') or SameText(ExtractFileExt(Inc), '.dpk') then List.Add(Inc);
      M:= M.NextMatch;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function FindSiblingProgramFile(const ADprojPath: string): string;
var
  Base     : string;
  Dir      : string;
  Candidate: string;
begin
  Dir:= ExtractFilePath(ADprojPath);
  Base:= ChangeFileExt(ExtractFileName(ADprojPath), '');
  Candidate:= TPath.Combine(Dir, Base + '.dpr');
  if TFile.Exists(Candidate) then Exit(Candidate);
  Candidate:= TPath.Combine(Dir, Base + '.dpk');
  if TFile.Exists(Candidate) then Exit(Candidate);
  Result:= '';
end;

function ExtractUsesNames(const AProgramPath: string; out AUsesStartLine: Integer): TArray<string>;
// Pulls every unit name from every `uses` clause in a .dpr/.dpk. A
// .dpk has two: `requires` (other packages) and `contains` (.pas units).
// We treat both as inputs for membership comparison since both feed the
// compile set.
var
  Content  : string       ;
  RE       : TRegEx       ;
  UnitRE   : TRegEx       ;
  M        : TMatch       ;
  U        : TMatch       ;
  Clause   : string       ;
  List     : TList<string>;
  Idx      : Integer      ;
  LineCount: Integer      ;
  Pos      : Integer      ;
begin
  AUsesStartLine:= 1;
  if not TFile.Exists(AProgramPath) then Exit(nil);
  Content:= TFile.ReadAllText(AProgramPath);
  // Match `uses ... ;` and `contains ... ;` and `requires ... ;`
  RE:= TRegEx.Create( '\b(uses|contains|requires)\b\s*(.*?);', [roIgnoreCase, roSingleLine]);
  // Inside the clause, a unit reference looks like `Name` or `Name in ''...''`
  UnitRE:= TRegEx.Create('([A-Za-z_][A-Za-z0-9_\.]*)\s*(?:in\s+''[^'']*'')?', [roIgnoreCase]);
  List:= TList<string>.Create;
  try
    M:= RE.Match(Content);
    while M.Success do
    begin
      Clause:= M.Groups[2].Value;
      // Track line of first uses clause for the finding's location.
      if List.Count = 0 then
      begin
        LineCount:= 1;
        Pos:= M.Index;
        for Idx:= 1 to Pos do
          if (Idx <= Length(Content)) and (Content[Idx] = #10) then Inc(LineCount);
        AUsesStartLine:= LineCount;
      end;
      U:= UnitRE.Match(Clause);
      while U.Success do
      begin
        if (U.Groups[1].Value <> '') and (not SameText(U.Groups[1].Value, 'in')) then List.Add(U.Groups[1].Value);
        U:= U.NextMatch;
      end;
      M:= M.NextMatch;
    end; // while
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

class function TProjectChecks.CheckUnitsInDpr( const ADprojPath: string): TArray<TLintFinding>;
var
  DCCRefs    : TArray<string>             ;
  ProgramUses: TArray<string>             ;
  ProgramPath: string                     ;
  DCCSet     : TDictionary<string, string>;
  UsesSet    : TDictionary<string, string>;
  Pair       : TPair<string, string>      ;
  Finding    : TLintFinding               ;
  Findings   : TList<TLintFinding>        ;
  UsesLine   : Integer                    ;
  RefPath    : string                     ;
  Name       : string                     ;
begin
  Findings:= TList<TLintFinding>.Create;
  DCCSet := TDictionary<string, string>.Create;
  UsesSet:= TDictionary<string, string>.Create;
  try
    DCCRefs    := ReadDCCReferences     (ADprojPath);
    ProgramPath:= FindSiblingProgramFile(ADprojPath);
    if ProgramPath = '' then
    begin
      Finding:= Default(TLintFinding);
      Finding.RuleId  := 'unit-not-in-dpr';
      Finding.Severity:= 'warning';
      Finding.Message:= 'No sibling .dpr or .dpk found for ' + ExtractFileName(ADprojPath);
      Finding.FilePath := ADprojPath;
      Finding.StartLine:= 1;
      Finding.StartCol := 1;
      Findings.Add(Finding);
      Exit(Findings.ToArray);
    end;
    ProgramUses:= ExtractUsesNames(ProgramPath, UsesLine);

    for RefPath in DCCRefs     do DCCSet .AddOrSetValue(NormalizeUnitName(RefPath), RefPath);
    for Name    in ProgramUses do UsesSet.AddOrSetValue(LowerCase        (Name   ), Name   );

    // In .dproj but not in .dpr/.dpk uses -> most dangerous case.
    for Pair in DCCSet do
    begin
      if not UsesSet.ContainsKey(Pair.Key) then
      begin
        Finding:= Default(TLintFinding);
        Finding.RuleId  := 'unit-not-in-dpr';
        Finding.Severity:= 'warning';
        Finding.Message:= Format(
          'Unit "%s" is in the .dproj DCCReference list but missing from ' + 'the %s uses clause. Add it so re-IDE-opens keep it in the build.',
          [Pair.Value, ExtractFileName(ProgramPath)]);
        Finding.FilePath := ProgramPath;
        Finding.StartLine:= UsesLine;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end;
    end; // for

    // In .dpr/.dpk uses but not in .dproj DCCReference -> typically compiles
    // via search path, but IDE-managed dependency tracking misses it.
    for Pair in UsesSet do
    begin
      if not DCCSet.ContainsKey(Pair.Key) then
      begin
        // Skip RTL/VCL/FMX/standard-library names - they live in BDS Lib paths
        // and are never expected in DCCReference.
        if StartsText('System.', Pair.Value) or StartsText('Vcl.', Pair.Value) or StartsText('Fmx.', Pair.Value) or StartsText('Data.', Pair.Value) or
        StartsText('Winapi.', Pair.Value) or StartsText('FireDAC.', Pair.Value) or StartsText('IdContext', Pair.Value) or StartsText('REST.', Pair.Value) or
        SameText(Pair.Value, 'Forms') or SameText(Pair.Value, 'SysUtils') or SameText(Pair.Value, 'Classes') or SameText(Pair.Value, 'Windows') or
        SameText(Pair.Value, 'Messages') or SameText(Pair.Value, 'Variants') or SameText(Pair.Value, 'Graphics') or SameText(Pair.Value, 'Controls') or
        SameText(Pair.Value, 'Dialogs') or SameText(Pair.Value, 'Menus') or SameText(Pair.Value, 'StdCtrls') then Continue;
        Finding:= Default(TLintFinding);
        Finding.RuleId  := 'unit-not-in-dpr';
        Finding.Severity:= 'info';
        Finding.Message:= Format(
          'Unit "%s" is in %s uses clause but missing from .dproj ' + 'DCCReference list. Compiles via search path today; IDE may not ' + 'track it as a build input.',
          [Pair.Value, ExtractFileName(ProgramPath)]);
        Finding.FilePath := ADprojPath;
        Finding.StartLine:= 1;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end; // if
    end; // for

    Result:= Findings.ToArray;
  finally
    DCCSet.Free;
    UsesSet.Free;
    Findings.Free;
  end; // try
end; // function

class function TProjectChecks.CheckUnitMembership(const AStore: ISymbolStore;
  const ALibDbPath: string; const AProjectDprojPath: string): TArray<TLintFinding>;
var
  AllFileIds: TArray<Int64>;
  UsesArr   : TArray<TUnitUse>;
  Seen      : TDictionary<string, string>; { norm -> original UnitName }
  Findings  : TList<TLintFinding>;
  FileId    : Int64;
  U         : TUnitUse;
  UnitNorm  : string;
  UnitOrig  : string;
  DprojDir  : string;
  DprPath   : string;
  DCCRefs   : TArray<string>;
  DprUses   : TArray<string>;
  DummyLine : Integer;
  DCCSet    : TDictionary<string, Boolean>;
  DprSet    : TDictionary<string, Boolean>;
  Ref, RefNorm: string;
  OnDisk, InDpr, InDproj: Boolean;
  F         : TLintFinding;
  LibConn   : TFDConnection;
  LibQ      : TFDQuery;

  { Normalize a unit name or file path to a bare lower-case unit name segment.
    'System.SysUtils' -> 'sysutils';  'uMyUnit.pas' -> 'umyunit'. }
  function NormUnit(const AName: string): string;
  var DotPos: Integer;
  begin
    Result:= LowerCase(ChangeFileExt(ExtractFileName(AName), ''));
    DotPos:= LastDelimiter('.', Result);
    if DotPos > 0 then Result:= Copy(Result, DotPos + 1, MaxInt);
  end;

  function IsInLibDb(const ANorm: string): Boolean;
  begin
    Result:= False;
    if not Assigned(LibQ) then Exit;
    LibQ.Close;
    LibQ.Params[0].Value:= ANorm;
    LibQ.Open;
    Result:= not LibQ.IsEmpty;
  end;

begin
  Result:= nil;
  Findings:= TList<TLintFinding>.Create;
  Seen    := TDictionary<string, string>.Create;
  DCCSet  := TDictionary<string, Boolean>.Create;
  DprSet  := TDictionary<string, Boolean>.Create;
  LibConn := nil;
  LibQ    := nil;
  try
    { Open library DB read-only if provided }
    if (ALibDbPath <> '') and TFile.Exists(ALibDbPath) then
    begin
      LibConn:= TFDConnection.Create(nil);
      LibConn.DriverName:= 'SQLite';
      LibConn.Params.Values['Database']:= ALibDbPath;
      LibConn.Params.Values['OpenMode']:= 'ReadOnly';
      LibConn.Connected:= True;
      LibQ:= TFDQuery.Create(nil);
      LibQ.Connection:= LibConn;
      LibQ.SQL.Text:= 'SELECT 1 FROM symbols WHERE unit_name_norm=:N LIMIT 1';
      LibQ.Prepare;
    end;

    { Collect all unique used unit norms from the project DB }
    AllFileIds:= AStore.GetAllFileIds;
    for FileId in AllFileIds do
    begin
      UsesArr:= AStore.GetUnitUsesForFile(FileId);
      for U in UsesArr do
      begin
        UnitNorm:= NormUnit(U.UnitName);
        if (UnitNorm <> '') and not Seen.ContainsKey(UnitNorm) then
          Seen.Add(UnitNorm, U.UnitName);
      end;
    end;

    { Build project membership sets from .dproj + .dpr }
    DprojDir:= '';
    DprPath := '';
    DCCRefs := nil;
    DprUses := nil;
    if (AProjectDprojPath <> '') and TFile.Exists(AProjectDprojPath) then
    begin
      DprojDir:= ExtractFilePath(AProjectDprojPath);
      var DprFiles:= TDirectory.GetFiles(DprojDir, '*.dpr');
      if Length(DprFiles) > 0 then DprPath:= DprFiles[0];
      DCCRefs:= ReadDCCReferences(AProjectDprojPath);
      if DprPath <> '' then
        DprUses:= ExtractUsesNames(DprPath, DummyLine);
      for Ref in DCCRefs do
        DCCSet.AddOrSetValue(NormUnit(Ref), True);
      for Ref in DprUses do
        DprSet.AddOrSetValue(NormUnit(Ref), True);
    end;

    { Check each used unit }
    for UnitNorm in Seen.Keys do
    begin
      UnitOrig:= Seen[UnitNorm];
      { Skip known built-ins never present in any index }
      if SameText(UnitNorm, 'system') or SameText(UnitNorm, 'sysinit') then Continue;
      { 1. Library DB check }
      if IsInLibDb(UnitNorm) then Continue;
      { 2. Project membership check (.dpr + .dproj + disk) }
      if DprojDir <> '' then
      begin
        OnDisk := TFile.Exists(TPath.Combine(DprojDir, UnitOrig + '.pas'));
        InDpr  := DprSet.ContainsKey(UnitNorm);
        InDproj:= DCCSet.ContainsKey(UnitNorm);
        if OnDisk and InDpr and InDproj then Continue;
      end;
      F:= Default(TLintFinding);
      F.RuleId  := 'unit-not-in-project';
      F.Severity:= 'warning';
      F.Message := Format(
        'Unit ''%s'' is used but not in the platform library and not fully ' +
        'registered in the project (.dpr + .dproj).', [UnitOrig]);
      F.FilePath := AProjectDprojPath;
      F.StartLine:= 0;
      F.StartCol := 0;
      F.EndLine  := 0;
      F.EndCol   := 0;
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    LibQ.Free;
    LibConn.Free;
    DprSet.Free;
    DCCSet.Free;
    Seen.Free;
    Findings.Free;
  end;
end; // function

end.
