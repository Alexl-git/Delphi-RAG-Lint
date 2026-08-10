unit DRagLint.Preprocess.Profile;

// PP-Task-7: the define-profile resolver. Derives the active TDefineProfile
// (the set of defines the in-process preprocessor treats as "on") from either
// a RAD Studio .dproj project file (indexing a specific project/config) or the
// platform built-ins (library scans / no project). Consumed by the indexer
// (Task 9) to pick per-config defines so {$IFDEF} resolution matches the build.
//
// PlatformBuiltins ports the JS defaults (defaults.js DEFAULT_DEFINES,
// cli.js:38-43) extended per platform. All symbols are lowercased.
//
// ProfileFromDproj parses the .dproj MSBuild XML: it collects the DCC_Define of
// the Base PropertyGroup plus the selected config's PropertyGroup (Release ->
// Cfg_2, Debug -> Cfg_1 -- the RAD Studio indirection), splits each on ';',
// drops the $(DCC_Define) MSBuild recursion token, lowercases, and unions with
// the platform built-ins (deduped). A missing / unparseable .dproj yields just
// the platform built-ins for APlatform (never raises).
//
// Encoding note: directive / MSBuild tokens like the recursion macro are STRING
// constants; comments in this unit use // exclusively (never a brace inside a
// { } block comment).

interface

uses
  System.SysUtils,
  DRagLint.Preprocess.Types;

/// <summary>Returns the built-in compiler defines for the given target
/// platform, ALL LOWERCASED, for Delphi 13 / RAD Studio 37 (CompilerVersion 37,
/// VER370). 'Win64' -> mswindows, win64, cpu64bits, cpux86_64, unicode,
/// conditionalexpressions, compiler_version_37, ver370. 'Win32' -> mswindows,
/// win32, cpux86, unicode, conditionalexpressions, compiler_version_37, ver370
/// (no win64/cpu64bits/cpux86_64). Platform match is case-insensitive; an
/// unknown platform falls back to the Win64 set.</summary>
/// <param name="APlatform">'Win64' or 'Win32' (case-insensitive). Empty or
/// unknown defaults to Win64.</param>
/// <returns>Lowercased built-in define names.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoPpProfile (DRagLint.CLI.pas), DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas), DRagLint.Preprocess.Profile.ProfileFromDproj (DRagLint.Preprocess.Profile.pas)
/// Calls: SameText
/// Owns returned: new (caller owns)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlatformBuiltins(const APlatform: string): TArray<string>;

/// <summary>Resolves the active TDefineProfile for a specific project + config:
/// PlatformBuiltins(APlatform) UNION the DCC_Define values from the .dproj's
/// Base PropertyGroup AND the selected AConfig PropertyGroup (Release -> Cfg_2,
/// Debug -> Cfg_1). Each DCC_Define is split on ';', the $(DCC_Define) recursion
/// token dropped, the rest lowercased; the union is deduped. A missing or
/// unparseable .dproj returns just PlatformBuiltins(APlatform) -- it never
/// raises. NumericDefines is left empty (Task 7 scope is Defines only).</summary>
/// <param name="ADprojPath">Path to the .dproj; missing/unreadable -> builtins
/// only.</param>
/// <param name="APlatform">Target platform for the built-ins (default caller
/// passes 'Win64').</param>
/// <param name="AConfig">'Release' or 'Debug' (case-insensitive; anything else
/// treated as Release).</param>
/// <returns>The resolved define profile (Defines populated, deduped,
/// lowercased).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoPpProfile (DRagLint.CLI.pas), DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas)
/// Calls: DRagLint.Preprocess.Profile.AddDccDefines, DRagLint.Preprocess.Profile.CfgAliasFor, DRagLint.Preprocess.Profile.DccDefineInGroup, DRagLint.Preprocess.Profile.PlatformBuiltins
/// Touches: file system
/// <seealso cref="DRagLint.Preprocess.Profile.AddDccDefines"/>
/// <seealso cref="DRagLint.Preprocess.Profile.CfgAliasFor"/>
/// <seealso cref="DRagLint.Preprocess.Profile.DccDefineInGroup"/>
/// <seealso cref="DRagLint.Preprocess.Profile.PlatformBuiltins"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProfileFromDproj(const ADprojPath, APlatform, AConfig: string): TDefineProfile;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections;

// The MSBuild recursion token that terminates every DCC_Define list -- dropped
// when splitting a DCC_Define value into concrete symbols.
const
  RECURSION_TOKEN = '$(DCC_Define)';

function PlatformBuiltins(const APlatform: string): TArray<string>;
begin
  // Shared across every Windows platform for Delphi 13 / RAD Studio 37.
  if SameText(APlatform, 'Win32') then
    Result := TArray<string>.Create(
      'mswindows', 'win32', 'cpux86',
      'unicode', 'conditionalexpressions', 'compiler_version_37', 'ver370')
  else
    // Win64 is the default (also for unknown/empty platforms).
    Result := TArray<string>.Create(
      'mswindows', 'win64', 'cpu64bits', 'cpux86_64',
      'unicode', 'conditionalexpressions', 'compiler_version_37', 'ver370');
end;

// Map a config name to its RAD Studio Cfg_N alias: Release -> Cfg_2,
// Debug -> Cfg_1. Anything other than an explicit 'Debug' is treated as Release
// (the default build config).
function CfgAliasFor(const AConfig: string): string;
begin
  if SameText(AConfig, 'Debug') then
    Result := 'Cfg_1'
  else
    Result := 'Cfg_2';
end;

// Extract the DCC_Define value from the PropertyGroup whose Condition matches
// AConditionNeedle (e.g. the Base group or a Cfg_N group). Returns '' when no
// such group / DCC_Define is present. Scoped per-PropertyGroup so a config's
// DCC_Define is never confused with another config's.
function DccDefineInGroup(const AContent, AConditionNeedle: string): string;
var
  GroupRx: TRegEx;
  DefRx  : TRegEx;
  M      : TMatch;
  Cond   : string;
  Group  : string;
begin
  Result := '';
  // Match each <PropertyGroup Condition="...">...</PropertyGroup> block.
  GroupRx := TRegEx.Create('<PropertyGroup\b([^>]*)>(.*?)</PropertyGroup>',
    [roIgnoreCase, roSingleLine]);
  DefRx := TRegEx.Create('<DCC_Define>(.*?)</DCC_Define>',
    [roIgnoreCase, roSingleLine]);
  M := GroupRx.Match(AContent);
  while M.Success do
  begin
    Cond  := M.Groups[1].Value; // the attributes, incl. Condition="..."
    Group := M.Groups[2].Value; // the inner XML
    if ContainsText(Cond, AConditionNeedle) then
    begin
      var DM: TMatch := DefRx.Match(Group);
      if DM.Success then
      begin
        Result := DM.Groups[1].Value;
        Exit;
      end;
    end;
    M := M.NextMatch;
  end;
end;

// Split a DCC_Define value on ';', drop the $(DCC_Define) recursion token and
// blanks, lowercase each surviving symbol, and add it to ASet (dedup by key).
procedure AddDccDefines(const AValue: string; ASet: TDictionary<string, Byte>;
  AOrder: TList<string>);
var
  Parts: TArray<string>;
  P    : string;
  Sym  : string;
begin
  if AValue = '' then Exit;
  Parts := AValue.Split([';']);
  for P in Parts do
  begin
    Sym := LowerCase(Trim(P));
    if (Sym = '') or SameText(Trim(P), RECURSION_TOKEN) then Continue;
    if not ASet.ContainsKey(Sym) then
    begin
      ASet.Add(Sym, 0);
      AOrder.Add(Sym);
    end;
  end;
end;

function ProfileFromDproj(const ADprojPath, APlatform, AConfig: string): TDefineProfile;
var
  Seen   : TDictionary<string, Byte>;
  Order  : TList<string>;
  Content: string;
  Sym    : string;
  BaseDef: string;
  CfgDef : string;
begin
  Result.Defines := nil;
  Result.NumericDefines := nil;

  Seen  := TDictionary<string, Byte>.Create;
  Order := TList<string>.Create;
  try
    // Platform built-ins are always present (they seed the union / dedup set).
    for Sym in PlatformBuiltins(APlatform) do
      if not Seen.ContainsKey(Sym) then
      begin
        Seen.Add(Sym, 0);
        Order.Add(Sym);
      end;

    // Layer the .dproj-derived defines on top when the file is present + parses.
    if (ADprojPath <> '') and TFile.Exists(ADprojPath) then
    begin
      Content := '';
      try
        Content := TFile.ReadAllText(ADprojPath);
      except
        Content := ''; // unparseable/unreadable -> builtins only (no raise)
      end;
      if Content <> '' then
      begin
        // Base PropertyGroup: Condition mentions '$(Base)'.
        BaseDef := DccDefineInGroup(Content, '$(Base)');
        AddDccDefines(BaseDef, Seen, Order);
        // Selected config PropertyGroup: Condition mentions '$(Cfg_N)'.
        CfgDef := DccDefineInGroup(Content, '$(' + CfgAliasFor(AConfig) + ')');
        AddDccDefines(CfgDef, Seen, Order);
      end;
    end;

    Result.Defines := Order.ToArray;
  finally
    Order.Free;
    Seen.Free;
  end;
end;

end.
