unit DRagLint.Lint.ProjectChecks;

// v0.9: project-level lint rules. Operate on a .dproj + sibling .dpr/.dpk,
// not on per-file ASTs. The first rule (`unit-not-in-dpr`) is from a known
// real-world hazard: Delphi compiles a unit if either the .dproj DCCReference
// list OR the search path resolves it, so a unit can be "in the build" without
// being listed in both places - and that silently breaks future re-IDE-opens.

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Generics.Defaults,
  DRagLint.Core.Model;

type
  TProjectChecks = class
  public
    // Compare .dproj <DCCReference Include="..."/> entries vs the matching
    // .dpr/.dpk's `uses` clause. Returns findings for every unit that is
    // present on one side but not the other.
    class function CheckUnitsInDpr(
      const ADprojPath: string): TArray<TLintFinding>;
  end;

implementation

function NormalizeUnitName(const APathOrName: string): string;
var
  Base: string;
begin
  Base := ExtractFileName(APathOrName);
  Base := ChangeFileExt(Base, '');
  Result := LowerCase(Base);
end;

function ReadDCCReferences(const ADprojPath: string): TArray<string>;
var
  Content: string;
  RE: TRegEx;
  M: TMatch;
  List: TList<string>;
  Inc: string;
begin
  if not TFile.Exists(ADprojPath) then
    Exit(nil);
  Content := TFile.ReadAllText(ADprojPath);
  RE := TRegEx.Create('<DCCReference\s+Include="([^"]+)"',
    [roIgnoreCase, roSingleLine]);
  List := TList<string>.Create;
  try
    M := RE.Match(Content);
    while M.Success do
    begin
      Inc := M.Groups[1].Value;
      // Only track .pas/.dpr/.dpk units; skip .rc, .res, .dfm, etc.
      if SameText(ExtractFileExt(Inc), '.pas') or
         SameText(ExtractFileExt(Inc), '.dpk') then
        List.Add(Inc);
      M := M.NextMatch;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FindSiblingProgramFile(const ADprojPath: string): string;
var
  Base, Dir, Candidate: string;
begin
  Dir := ExtractFilePath(ADprojPath);
  Base := ChangeFileExt(ExtractFileName(ADprojPath), '');
  Candidate := TPath.Combine(Dir, Base + '.dpr');
  if TFile.Exists(Candidate) then Exit(Candidate);
  Candidate := TPath.Combine(Dir, Base + '.dpk');
  if TFile.Exists(Candidate) then Exit(Candidate);
  Result := '';
end;

function ExtractUsesNames(const AProgramPath: string;
  out AUsesStartLine: Integer): TArray<string>;
// Pulls every unit name from every `uses` clause in a .dpr/.dpk. A
// .dpk has two: `requires` (other packages) and `contains` (.pas units).
// We treat both as inputs for membership comparison since both feed the
// compile set.
var
  Content: string;
  RE, UnitRE: TRegEx;
  M, U: TMatch;
  Clause: string;
  List: TList<string>;
  Idx, LineCount: Integer;
  Pos: Integer;
begin
  AUsesStartLine := 1;
  if not TFile.Exists(AProgramPath) then
    Exit(nil);
  Content := TFile.ReadAllText(AProgramPath);
  // Match `uses ... ;` and `contains ... ;` and `requires ... ;`
  RE := TRegEx.Create(
    '\b(uses|contains|requires)\b\s*(.*?);',
    [roIgnoreCase, roSingleLine]);
  // Inside the clause, a unit reference looks like `Name` or `Name in ''...''`
  UnitRE := TRegEx.Create('([A-Za-z_][A-Za-z0-9_\.]*)\s*(?:in\s+''[^'']*'')?',
    [roIgnoreCase]);
  List := TList<string>.Create;
  try
    M := RE.Match(Content);
    while M.Success do
    begin
      Clause := M.Groups[2].Value;
      // Track line of first uses clause for the finding's location.
      if List.Count = 0 then
      begin
        LineCount := 1;
        Pos := M.Index;
        for Idx := 1 to Pos do
          if (Idx <= Length(Content)) and (Content[Idx] = #10) then
            Inc(LineCount);
        AUsesStartLine := LineCount;
      end;
      U := UnitRE.Match(Clause);
      while U.Success do
      begin
        if (U.Groups[1].Value <> '') and
           (not SameText(U.Groups[1].Value, 'in')) then
          List.Add(U.Groups[1].Value);
        U := U.NextMatch;
      end;
      M := M.NextMatch;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TProjectChecks.CheckUnitsInDpr(
  const ADprojPath: string): TArray<TLintFinding>;
var
  DCCRefs, ProgramUses: TArray<string>;
  ProgramPath: string;
  DCCSet, UsesSet: TDictionary<string, string>;
  Pair: TPair<string, string>;
  Finding: TLintFinding;
  Findings: TList<TLintFinding>;
  UsesLine: Integer;
  RefPath: string;
  Name: string;
begin
  Findings := TList<TLintFinding>.Create;
  DCCSet := TDictionary<string, string>.Create;
  UsesSet := TDictionary<string, string>.Create;
  try
    DCCRefs := ReadDCCReferences(ADprojPath);
    ProgramPath := FindSiblingProgramFile(ADprojPath);
    if ProgramPath = '' then
    begin
      Finding := Default(TLintFinding);
      Finding.RuleId := 'unit-not-in-dpr';
      Finding.Severity := 'warning';
      Finding.Message := 'No sibling .dpr or .dpk found for ' +
        ExtractFileName(ADprojPath);
      Finding.FilePath := ADprojPath;
      Finding.StartLine := 1;
      Finding.StartCol := 1;
      Findings.Add(Finding);
      Exit(Findings.ToArray);
    end;
    ProgramUses := ExtractUsesNames(ProgramPath, UsesLine);

    for RefPath in DCCRefs do
      DCCSet.AddOrSetValue(NormalizeUnitName(RefPath), RefPath);
    for Name in ProgramUses do
      UsesSet.AddOrSetValue(LowerCase(Name), Name);

    // In .dproj but not in .dpr/.dpk uses -> most dangerous case.
    for Pair in DCCSet do
    begin
      if not UsesSet.ContainsKey(Pair.Key) then
      begin
        Finding := Default(TLintFinding);
        Finding.RuleId := 'unit-not-in-dpr';
        Finding.Severity := 'warning';
        Finding.Message := Format(
          'Unit "%s" is in the .dproj DCCReference list but missing from ' +
          'the %s uses clause. Add it so re-IDE-opens keep it in the build.',
          [Pair.Value, ExtractFileName(ProgramPath)]);
        Finding.FilePath := ProgramPath;
        Finding.StartLine := UsesLine;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end;
    end;

    // In .dpr/.dpk uses but not in .dproj DCCReference -> typically compiles
    // via search path, but IDE-managed dependency tracking misses it.
    for Pair in UsesSet do
    begin
      if not DCCSet.ContainsKey(Pair.Key) then
      begin
        // Skip RTL/VCL/FMX/standard-library names - they live in BDS Lib paths
        // and are never expected in DCCReference.
        if StartsText('System.', Pair.Value) or
           StartsText('Vcl.', Pair.Value) or
           StartsText('Fmx.', Pair.Value) or
           StartsText('Data.', Pair.Value) or
           StartsText('Winapi.', Pair.Value) or
           StartsText('FireDAC.', Pair.Value) or
           StartsText('IdContext', Pair.Value) or
           StartsText('REST.', Pair.Value) or
           SameText(Pair.Value, 'Forms') or
           SameText(Pair.Value, 'SysUtils') or
           SameText(Pair.Value, 'Classes') or
           SameText(Pair.Value, 'Windows') or
           SameText(Pair.Value, 'Messages') or
           SameText(Pair.Value, 'Variants') or
           SameText(Pair.Value, 'Graphics') or
           SameText(Pair.Value, 'Controls') or
           SameText(Pair.Value, 'Dialogs') or
           SameText(Pair.Value, 'Menus') or
           SameText(Pair.Value, 'StdCtrls') then
          Continue;
        Finding := Default(TLintFinding);
        Finding.RuleId := 'unit-not-in-dpr';
        Finding.Severity := 'info';
        Finding.Message := Format(
          'Unit "%s" is in %s uses clause but missing from .dproj ' +
          'DCCReference list. Compiles via search path today; IDE may not ' +
          'track it as a build input.',
          [Pair.Value, ExtractFileName(ProgramPath)]);
        Finding.FilePath := ADprojPath;
        Finding.StartLine := 1;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end;
    end;

    Result := Findings.ToArray;
  finally
    DCCSet.Free;
    UsesSet.Free;
    Findings.Free;
  end;
end;

end.
