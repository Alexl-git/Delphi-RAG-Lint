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
// ProfileFromDproj parses the .dproj MSBuild XML through DprojEffectiveDefines:
// the DCC_Define of the Base PropertyGroup, the Base_<Platform> group, then each
// config of the selected config's chain (the NAME mapped to its Cfg_N key by the
// .dproj's own '$(Config)'=='Name' selector groups, CfgParent walked root
// first) followed by its Cfg_N_<Platform> group -- applied IN ORDER: a value
// carrying the $(DCC_Define) recursion token appends, one without it REPLACES
// the set so far (X5, 2026-10-25). The result is lowercased and unioned with
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
/// <para>Called from: DRagLint.CLI.DoPpProfile (DRagLint.CLI.pas), DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas), DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.IsCompilerPredefined (DRagLint.Lint.IfdefUndefined.pas), DRagLint.Preprocess.Profile.ProfileFromDproj (DRagLint.Preprocess.Profile.pas), DRagLint.Project.Facts.ReadProjectFacts (DRagLint.Project.Facts.pas)</para>
/// <para>Calls: SameText</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlatformBuiltins(const APlatform: string): TArray<string>;

/// <summary>Resolves the active TDefineProfile for a specific project + config:
/// PlatformBuiltins(APlatform) UNION DprojEffectiveDefines(content,
/// PlatformGroupSuffix(APlatform), AConfig) -- Base, Base_&lt;Platform&gt;, then
/// the config chain (each Cfg_N and its Cfg_N_&lt;Platform&gt; group), applied in
/// order, where a DCC_Define without $(DCC_Define) REPLACES the inherited set.
/// Symbols are lowercased and deduped. A missing or unparseable .dproj returns
/// just PlatformBuiltins(APlatform) -- it never raises. NumericDefines is left
/// empty (Task 7 scope is Defines only).</summary>
/// <param name="ADprojPath">Path to the .dproj; missing/unreadable -> builtins
/// only.</param>
/// <param name="APlatform">Target platform for the built-ins (default caller
/// passes 'Win64').</param>
/// <param name="AConfig">A config name declared by the .dproj (case-insensitive),
/// or 'Base'; '' means 'Release'. See DprojEffectiveDefines for the
/// fallback when the name is not declared.</param>
/// <returns>The resolved define profile (Defines populated, deduped,
/// lowercased).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoPpProfile (DRagLint.CLI.pas), DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas), DRagLint.Refactor.MultiProjectRename.ClosureUnits (DRagLint.Refactor.MultiProjectRename.pas)</para>
/// <para>Calls: DRagLint.Preprocess.Profile.DprojEffectiveDefines, DRagLint.Preprocess.Profile.PlatformBuiltins, DRagLint.Preprocess.Profile.PlatformGroupSuffix</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Preprocess.Profile.DprojEffectiveDefines"/>
/// <seealso cref="DRagLint.Preprocess.Profile.PlatformBuiltins"/>
/// <seealso cref="DRagLint.Preprocess.Profile.PlatformGroupSuffix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProfileFromDproj(const ADprojPath, APlatform, AConfig: string): TDefineProfile;

type
  /// <summary>One symbol of an effective DCC_Define set and the PropertyGroup
  /// alias that last put it there.</summary>
  TDprojDefine = record
    /// <summary>The symbol as spelled in the .dproj (first spelling wins).</summary>
    Name : string;
    /// <summary>The group alias that added it to the current set: 'Base',
    /// 'Base_Win32', 'Cfg_1', 'Cfg_3_Win64', ...</summary>
    Group: string;
  end;

/// <summary>The EFFECTIVE DCC_Define set of one config + platform, computed the
/// way MSBuild applies a RAD Studio .dproj: groups Base, Base_&lt;P&gt;, then
/// every config of the chain from the root ancestor down to AConfig, each
/// followed by its _&lt;P&gt; group. A DCC_Define that contains the
/// $(DCC_Define) recursion token APPENDS; one without it REPLACES the set
/// inherited so far. Platform built-ins are NOT included.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <param name="APlatform">The platform group suffix, used verbatim ('Win32',
/// 'Win64').</param>
/// <param name="AConfig">A config NAME ('Debug', 'Release', a custom name) or
/// 'Base'. Mapped to its Cfg_N key through the .dproj's own
/// '$(Config)'=='Name' groups, walking CfgParent; '' means 'Release'; a name
/// the .dproj does not declare falls back to Debug -&gt; Cfg_1, anything
/// else -&gt; Cfg_2.</param>
/// <returns>The effective symbols in first-seen order, deduplicated
/// case-insensitively; other $(...) macro references are dropped.</returns>
/// <remarks>Pure: reads only AContent. Never raises.</remarks>
function DprojEffectiveDefines(const AContent, APlatform, AConfig: string): TArray<TDprojDefine>;

/// <summary>The build-config names a .dproj declares, from its
/// '$(Config)'=='Name' or '$(Cfg_N)'!='' PropertyGroups, in document order.
/// 'Base' is not included.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <returns>Config names as spelled; empty when none is declared.</returns>
function DprojConfigNames(const AContent: string): TArray<string>;

/// <summary>The platforms a .dproj enables:
/// &lt;Platform value="P"&gt;True&lt;/Platform&gt; entries, in document
/// order.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <returns>Platform names as spelled ('Win32', 'Win64', ...).</returns>
function DprojEnabledPlatforms(const AContent: string): TArray<string>;

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
  // The group alias of the root config, and the config name that selects only
  // the Base groups.
  BASE_KEY = 'Base';
  // The config an empty config name means (the indexer passes '').
  DEFAULT_CONFIG = 'Release';
  // Longest CfgParent chain followed (a cycle guard).
  MAX_CFG_DEPTH = 16;
  // One <PropertyGroup ...>...</PropertyGroup>: group 1 = attributes, 2 = body.
  GROUP_PATTERN = '<PropertyGroup\b([^>]*)>(.*?)</PropertyGroup>';
  // A config selector: '$(Config)'=='Name' or '$(Cfg_N)'!=''.
  SELECTOR_PATTERN = '''\$\(Config\)''\s*==\s*''([^'']+)''\s+or\s+''\$\(([A-Za-z0-9_]+)\)''\s*!=\s*''''';
  CFGPARENT_PATTERN = '<CfgParent>\s*([A-Za-z0-9_]+)\s*</CfgParent>';
  // <Platform value="Win64">True</Platform> in the BorlandProject section.
  PLATFORM_ENABLED_PATTERN = '<Platform\s+value="([^"]+)"\s*>\s*True\s*</Platform>';

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

// Map a config name to its RAD Studio Cfg_N alias the way the IDE templates
// lay it out: Release -> Cfg_2, Debug -> Cfg_1. Only the FALLBACK now, for a
// config name the .dproj itself does not declare (see ConfigChain).
function CfgAliasFor(const AConfig: string): string;
begin
  if SameText(AConfig, 'Debug') then
    Result := 'Cfg_1'
  else
    Result := 'Cfg_2';
end;

// The platform suffix RAD Studio uses in its per-platform group aliases
// (Base_Win32, Cfg_1_Win64). Mirrors PlatformBuiltins: Win32 is Win32, and
// anything else -- including empty/unknown -- is the Win64 default.
function PlatformGroupSuffix(const APlatform: string): string;
begin
  if SameText(APlatform, 'Win32') then
    Result := 'Win32'
  else
    Result := 'Win64';
end;

// Find the DCC_Define of the first PropertyGroup whose Condition contains
// AConditionNeedle (e.g. '$(Base)' or '$(Cfg_1_Win64)') and that HAS a
// DCC_Define. True when one was found -- an empty <DCC_Define></DCC_Define>
// is found, with AValue '' (it replaces the set). A needle never matches the
// wrong group: '$(Base_Win64)' does not contain '$(Base)', and '$(Cfg_10)'
// does not contain '$(Cfg_1)'. The config-selector groups carry no
// DCC_Define, so they are passed over.
function TryDccDefineInGroup(const AContent, AConditionNeedle: string;
  out AValue: string): Boolean;
var
  M : TMatch;
  DM: TMatch;
begin
  Result := False;
  AValue := '';
  M := TRegEx.Match(AContent, GROUP_PATTERN, [roIgnoreCase, roSingleLine]);
  while M.Success do
  begin
    if ContainsText(M.Groups[1].Value, AConditionNeedle) then
    begin
      DM := TRegEx.Match(M.Groups[2].Value, '<DCC_Define>(.*?)</DCC_Define>',
        [roIgnoreCase, roSingleLine]);
      if DM.Success then
      begin
        AValue := DM.Groups[1].Value;
        Exit(True);
      end;
    end;
    M := M.NextMatch;
  end;
end;

// Read the config-selector groups -- Condition
// "'$(Config)'=='Name' or '$(Cfg_N)'!=''" -- into AKeyOfName (lowercased name
// -> Cfg_N key) and AParentOfKey (lowercased key -> its CfgParent key). ANames,
// when not nil, receives each declared name once, in document order. 'Base'
// is skipped: it selects no Cfg_N.
procedure ReadConfigSelectors(const AContent: string;
  AKeyOfName, AParentOfKey: TDictionary<string, string>; ANames: TList<string>);
var
  M   : TMatch;
  S   : TMatch;
  P   : TMatch;
  Name: string;
  Key : string;
begin
  M := TRegEx.Match(AContent, GROUP_PATTERN, [roIgnoreCase, roSingleLine]);
  while M.Success do
  begin
    S := TRegEx.Match(M.Groups[1].Value, SELECTOR_PATTERN, [roIgnoreCase]);
    if S.Success and not SameText(S.Groups[1].Value, BASE_KEY) then
    begin
      Name := S.Groups[1].Value;
      Key  := S.Groups[2].Value;
      if not AKeyOfName.ContainsKey(LowerCase(Name)) then
      begin
        AKeyOfName.Add(LowerCase(Name), Key);
        if ANames <> nil then ANames.Add(Name);
      end;
      P := TRegEx.Match(M.Groups[2].Value, CFGPARENT_PATTERN, [roIgnoreCase]);
      if P.Success then AParentOfKey.AddOrSetValue(LowerCase(Key), P.Groups[1].Value);
    end;
    M := M.NextMatch;
  end;
end;

// The Cfg_N keys of AConfig's inheritance chain, ROOT FIRST, Base excluded:
// Profiling (Cfg_3, CfgParent Cfg_2) -> [Cfg_2, Cfg_3]. 'Base' -> []. '' is
// 'Release'. A name the .dproj does not declare falls back to CfgAliasFor.
// The walk stops at Base, at a key with no known parent, or after
// MAX_CFG_DEPTH steps (a cycle guard).
function ConfigChain(const AContent, AConfig: string): TArray<string>;
var
  KeyOfName  : TDictionary<string, string>;
  ParentOfKey: TDictionary<string, string>;
  Name       : string;
  Key        : string;
  Depth      : Integer;
begin
  Result := nil;
  if SameText(AConfig, BASE_KEY) then Exit;
  Name := if AConfig = '' then DEFAULT_CONFIG else AConfig;
  KeyOfName   := TDictionary<string, string>.Create;
  ParentOfKey := TDictionary<string, string>.Create;
  try
    ReadConfigSelectors(AContent, KeyOfName, ParentOfKey, nil);
    if not KeyOfName.TryGetValue(LowerCase(Name), Key) then
      Key := CfgAliasFor(Name);
    Depth := 0;
    while (Key <> '') and not SameText(Key, BASE_KEY) and (Depth < MAX_CFG_DEPTH) do
    begin
      Result := [Key] + Result;
      if not ParentOfKey.TryGetValue(LowerCase(Key), Key) then Key := '';
      Inc(Depth);
    end;
  finally
    ParentOfKey.Free;
    KeyOfName.Free;
  end;
end;

function DprojEffectiveDefines(const AContent, APlatform, AConfig: string): TArray<TDprojDefine>;
var
  Aliases: TArray<string>;
  Alias  : string;
  Key    : string;
  Value  : string;
  Part   : string;
  Sym    : string;
  Def    : TDprojDefine;
  Order  : TList<TDprojDefine>;
  Seen   : TDictionary<string, Byte>;
begin
  // MSBuild applies, in order: Base, Base_<P>, then each config of the chain
  // from the root ancestor down, each followed by its own _<P> group. The two
  // platform groups were missed until 2026-09-23 (Micronite2027's EUREKALOG);
  // REPLACE semantics and the name -> Cfg_N mapping until 2026-10-25 (X5).
  Aliases := [BASE_KEY, BASE_KEY + '_' + APlatform];
  for Key in ConfigChain(AContent, AConfig) do
    Aliases := Aliases + [Key, Key + '_' + APlatform];

  Order := TList<TDprojDefine>.Create;
  Seen  := TDictionary<string, Byte>.Create;
  try
    for Alias in Aliases do
    begin
      if not TryDccDefineInGroup(AContent, '$(' + Alias + ')', Value) then Continue;
      // No recursion token: this group's value IS the set from here on.
      if not ContainsText(Value, RECURSION_TOKEN) then
      begin
        Order.Clear;
        Seen.Clear;
      end;
      for Part in Value.Split([';']) do
      begin
        Sym := Trim(Part);
        // Drop blanks and MSBuild property references, the recursion token
        // included -- a macro cannot be expanded here.
        if (Sym = '') or StartsStr('$(', Sym) or Seen.ContainsKey(LowerCase(Sym)) then Continue;
        Seen.Add(LowerCase(Sym), 0);
        Def.Name  := Sym;
        Def.Group := Alias;
        Order.Add(Def);
      end;
    end;
    Result := Order.ToArray;
  finally
    Seen.Free;
    Order.Free;
  end;
end;

function DprojConfigNames(const AContent: string): TArray<string>;
var
  KeyOfName  : TDictionary<string, string>;
  ParentOfKey: TDictionary<string, string>;
  Names      : TList<string>;
begin
  KeyOfName   := TDictionary<string, string>.Create;
  ParentOfKey := TDictionary<string, string>.Create;
  Names       := TList<string>.Create;
  try
    ReadConfigSelectors(AContent, KeyOfName, ParentOfKey, Names);
    Result := Names.ToArray;
  finally
    Names.Free;
    ParentOfKey.Free;
    KeyOfName.Free;
  end;
end;

function DprojEnabledPlatforms(const AContent: string): TArray<string>;
var
  M: TMatch;
begin
  Result := nil;
  M := TRegEx.Match(AContent, PLATFORM_ENABLED_PATTERN, [roIgnoreCase]);
  while M.Success do
  begin
    Result := Result + [M.Groups[1].Value];
    M := M.NextMatch;
  end;
end;

function ProfileFromDproj(const ADprojPath, APlatform, AConfig: string): TDefineProfile;
var
  Seen   : TDictionary<string, Byte>;
  Order  : TList<string>;
  Content: string;
  Sym    : string;
  Def    : TDprojDefine;
begin
  Result.Defines := nil;
  Result.NumericDefines := nil;

  Seen  := TDictionary<string, Byte>.Create;
  Order := TList<string>.Create;
  try
    // Platform built-ins are always present: the compiler sets them, so no
    // DCC_Define -- not even a replacing one -- can remove them.
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
      for Def in DprojEffectiveDefines(Content, PlatformGroupSuffix(APlatform), AConfig) do
      begin
        Sym := LowerCase(Def.Name);
        if not Seen.ContainsKey(Sym) then
        begin
          Seen.Add(Sym, 0);
          Order.Add(Sym);
        end;
      end;
    end;

    Result.Defines := Order.ToArray;
  finally
    Order.Free;
    Seen.Free;
  end;
end;

end.
