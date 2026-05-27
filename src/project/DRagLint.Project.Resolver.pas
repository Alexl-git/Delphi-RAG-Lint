unit DRagLint.Project.Resolver;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Win.Registry,
  Winapi.Windows;

type
  // Resolves the set of folders that should be scanned for a Delphi project.
  // Inputs: a .dproj path. Outputs: deduplicated folder list combining:
  //   - the .dproj's own folder
  //   - DCC_UnitSearchPath entries from the .dproj
  //   - Library and Browsing paths from registry (Win32 + Win64, HKCU + HKLM)
  //   - folders containing each unit listed in the .dpr's `uses X in 'path'`
  //     clauses (one level deep)
  // All $(BDS) and similar macros are expanded.
  TProjectResolver = class
  strict private
    FBDS: string;
    function ExpandMacros(const APath: string): string;
    procedure AddFolderIfReal(AList: TList<string>; const APath: string);
    procedure AddSemicolonList(AList: TList<string>; const ASemicolonList: string;
      const ABaseDir: string);
    procedure ReadLibraryPaths(AList: TList<string>);
    procedure ReadDProj(const ADprojPath: string; AList: TList<string>);
    procedure ReadDprUsesPaths(const ADprPath: string; AList: TList<string>);
  public
    constructor Create;
    function Resolve(const ADprojPath: string): TArray<string>;
    // Library/Browsing paths from registry only — no .dproj required.
    // Useful for "index everything Delphi knows about" without a project.
    function ResolveLibraryPaths: TArray<string>;
  end;

implementation

const
  BDS_REG_PATH = '\Software\Embarcadero\BDS\37.0';

constructor TProjectResolver.Create;
begin
  inherited Create;
  // Default BDS install. Could be overridden by env var.
  FBDS := GetEnvironmentVariable('BDS');
  if FBDS = '' then
    FBDS := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
end;

function TProjectResolver.ExpandMacros(const APath: string): string;
begin
  Result := APath;
  Result := StringReplace(Result, '$(BDS)', FBDS, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDSCOMMONDIR)',
    TPath.Combine(FBDS, '..\Studio\Public\Documents'), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(Platform)', 'Win64',
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(Config)', 'Debug',
    [rfReplaceAll, rfIgnoreCase]);
end;

procedure TProjectResolver.AddFolderIfReal(AList: TList<string>;
  const APath: string);
var
  Normalized: string;
begin
  if APath.Trim = '' then
    Exit;
  Normalized := ExpandMacros(APath.Trim);
  try
    Normalized := TPath.GetFullPath(Normalized);
  except
    Exit;
  end;
  if not TDirectory.Exists(Normalized) then
    Exit;
  // Case-insensitive dedup.
  for var Existing in AList do
    if SameText(Existing, Normalized) then
      Exit;
  AList.Add(Normalized);
end;

procedure TProjectResolver.AddSemicolonList(AList: TList<string>;
  const ASemicolonList, ABaseDir: string);
var
  Parts: TArray<string>;
  P, Resolved: string;
begin
  if ASemicolonList.Trim = '' then
    Exit;
  Parts := ASemicolonList.Split([';']);
  for P in Parts do
  begin
    if P.Trim = '' then Continue;
    Resolved := ExpandMacros(P.Trim);
    if not TPath.IsPathRooted(Resolved) then
      Resolved := TPath.Combine(ABaseDir, Resolved);
    AddFolderIfReal(AList, Resolved);
  end;
end;

procedure ReadRegPathInto(const ARoot: HKEY; const AKey, AValue: string;
  ASamDesired: Cardinal; const AAdd: TProc<string>);
var
  Reg: TRegistry;
  RegValue: string;
begin
  Reg := TRegistry.Create(KEY_READ or ASamDesired);
  try
    Reg.RootKey := ARoot;
    if Reg.OpenKeyReadOnly(AKey) then
      try
        if Reg.ValueExists(AValue) then
        begin
          RegValue := Reg.ReadString(AValue);
          AAdd(RegValue);
        end;
      finally
        Reg.CloseKey;
      end;
  finally
    Reg.Free;
  end;
end;

procedure TProjectResolver.ReadLibraryPaths(AList: TList<string>);
const
  PLATFORMS: array[0..1] of string = ('Win32', 'Win64');
  VALUE_NAMES: array[0..1] of string = ('Search Path', 'Browsing Path');
var
  Plat, Val: string;
  HiveRoot: HKEY;
  Sam: Cardinal;
  RegBase: string;
begin
  // Probe HKCU + HKLM, both 32-bit + 64-bit registry views.
  for Plat in PLATFORMS do
    for Val in VALUE_NAMES do
    begin
      RegBase := BDS_REG_PATH + '\Library\' + Plat;
      for HiveRoot in [HKEY(HKEY_CURRENT_USER), HKEY(HKEY_LOCAL_MACHINE)] do
        for Sam in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] do
          ReadRegPathInto(HiveRoot, RegBase, Val, Sam,
            procedure (S: string)
            begin
              AddSemicolonList(AList, S, '');
            end);
    end;
end;

procedure TProjectResolver.ReadDProj(const ADprojPath: string;
  AList: TList<string>);
const
  // Tag names whose text content is a semicolon-separated path list.
  PATH_TAGS: array[0..3] of string = (
    'DCC_UnitSearchPath',
    'DCC_UnitAliases',
    'DCC_ObjPath',
    'DCC_DcuOutput'
  );
var
  Content, Tag, Pattern, Text: string;
  BaseDir: string;
  Matches: TMatchCollection;
  M: TMatch;
begin
  BaseDir := TPath.GetDirectoryName(ADprojPath);
  AddFolderIfReal(AList, BaseDir);

  // Skip XML DOM (MSXML COM init is not present in many Delphi installs).
  // We only need a few specific tags — plain regex over the file text.
  Content := TFile.ReadAllText(ADprojPath, TEncoding.UTF8);
  for Tag in PATH_TAGS do
  begin
    Pattern := Format('<%s>(.*?)</%s>', [Tag, Tag]);
    Matches := TRegEx.Matches(Content, Pattern, [roIgnoreCase, roSingleLine]);
    for M in Matches do
    begin
      Text := M.Groups[1].Value;
      AddSemicolonList(AList, Text, BaseDir);
    end;
  end;
end;

procedure TProjectResolver.ReadDprUsesPaths(const ADprPath: string;
  AList: TList<string>);
var
  Content: string;
  BaseDir: string;
  // Quick-and-dirty: find every `in '...'` literal, strip quotes, resolve.
  P, EndQ, StartQ: Integer;
  Quoted, Resolved, FolderOf: string;
begin
  if not TFile.Exists(ADprPath) then Exit;
  BaseDir := TPath.GetDirectoryName(ADprPath);
  Content := TFile.ReadAllText(ADprPath);
  P := 1;
  while True do
  begin
    P := Pos(' in ''', Content, P);
    if P = 0 then Break;
    StartQ := P + 4;  // points to opening quote
    EndQ := PosEx('''', Content, StartQ + 1);
    if EndQ = 0 then Break;
    Quoted := Copy(Content, StartQ + 1, EndQ - StartQ - 1);
    Resolved := Quoted;
    if not TPath.IsPathRooted(Resolved) then
      Resolved := TPath.Combine(BaseDir, Resolved);
    FolderOf := TPath.GetDirectoryName(Resolved);
    AddFolderIfReal(AList, FolderOf);
    P := EndQ + 1;
  end;
end;

function TProjectResolver.ResolveLibraryPaths: TArray<string>;
var
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    ReadLibraryPaths(List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TProjectResolver.Resolve(const ADprojPath: string): TArray<string>;
var
  List: TList<string>;
  DprPath, BaseDir, MainSource: string;
begin
  if not TFile.Exists(ADprojPath) then
    raise Exception.CreateFmt('.dproj not found: %s', [ADprojPath]);
  List := TList<string>.Create;
  try
    ReadDProj(ADprojPath, List);

    // Try to find the matching .dpr (same basename) next to the .dproj
    BaseDir := TPath.GetDirectoryName(ADprojPath);
    MainSource := TPath.ChangeExtension(ADprojPath, '.dpr');
    if TFile.Exists(MainSource) then
      DprPath := MainSource
    else
    begin
      // Sometimes the .dpk has the uses list (packages)
      MainSource := TPath.ChangeExtension(ADprojPath, '.dpk');
      if TFile.Exists(MainSource) then
        DprPath := MainSource
      else
        DprPath := '';
    end;
    if DprPath <> '' then
      ReadDprUsesPaths(DprPath, List);

    ReadLibraryPaths(List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
