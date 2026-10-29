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
  System.Generics.Collections,
  DRagLint.Preprocess.Types;

/// <summary>The Delphi 13 target platform names PlatformBuiltins knows.</summary>
/// <returns>The platform names, Win32 and Win64 first.</returns>
/// <remarks>Pure. Lets a caller walk every platform table.</remarks>
function KnownPlatforms: TArray<string>;

/// <summary>Returns the built-in compiler defines for the given target
/// platform, ALL LOWERCASED, for Delphi 13 / RAD Studio 37 (VER370). 'Win32' and
/// 'Win64' are EXACTLY what dcc32 / dcc64 report as defined (e.g. Win64 has
/// cpux64, cpu64bits, win64, mswindows, assembler, weakref, nativecode, dcc;
/// Win32 has cpux86, cpu386, cpu32bits, win32, underscoreimportname). Win64x,
/// Linux64, OSX64, OSXARM64, Android,
/// Android64, iOSDevice64 and iOSSimARM64 each get their own POSIX / CPU / OS
/// set (UNVERIFIED: no cross compiler is installed). Platform
/// match is case-insensitive; an unknown platform falls back to the Win64
/// set.</summary>
/// <param name="APlatform">A Delphi 13 target platform name listed above
/// (case-insensitive). Empty or unknown defaults to Win64.</param>
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
/// just PlatformBuiltins(APlatform) -- it never raises. Lane INC2: a valued
/// define (DEBUG2=3) defines DEBUG2 and adds debug2 -&gt; 3 to NumericDefines,
/// after CompilerNumerics; Switches are CompilerDefaultSwitches then
/// DprojEffectiveSwitches.</summary>
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
/// <para>Calls: DRagLint.Preprocess.Profile.DprojEffectiveDefines, DRagLint.Preprocess.Profile.PlatformBuiltins, DRagLint.Preprocess.Profile.PlatformGroupSuffix, LowerCase</para>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Preprocess.Profile.pas), DRagLint.Lint.PlatformDivergent.CollectDivergences (DRagLint.Lint.PlatformDivergent.pas), DRagLint.Lint.PlatformDivergent.NameSet (DRagLint.Lint.PlatformDivergent.pas), DRagLint.Preprocess.Profile.DprojEffectiveDefines (DRagLint.Preprocess.Profile.pas), DRagLint.Preprocess.Profile.ProfileFromDproj (DRagLint.Preprocess.Profile.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.Lint.PlatformDivergent, DRagLint.Preprocess.Profile, DRagLint.Project.Facts</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDprojDefine = record
    /// <summary>The symbol as spelled in the .dproj (first spelling wins), without
    /// any '=VALUE' part.</summary>
    Name : string;
    /// <summary>Lane INC2: the text after '=' of a valued define (DEBUG2=3 -> '3');
    /// '' for a plain symbol. The last group that sets the symbol wins.</summary>
    Value: string;
    /// <summary>The group alias that added it to the current set: 'Base',
    /// 'Base_Win32', 'Cfg_1', 'Cfg_3_Win64', ...</summary>
    Group: string;
    /// <summary>Every group alias that sets it since the last replacing group,
    /// in application order; Groups[0] = Group.</summary>
    Groups: TArray<string>;
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
/// <remarks>
/// Pure: reads only AContent. Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.PlatformDivergent.CollectDivergences (DRagLint.Lint.PlatformDivergent.pas), DRagLint.Preprocess.Profile.ProfileFromDproj (DRagLint.Preprocess.Profile.pas), DRagLint.Project.Facts.ReadProjectFacts (DRagLint.Project.Facts.pas)</para>
/// <para>Calls: ContainsText, DRagLint.Preprocess.Profile.DprojGroupChain, DRagLint.Preprocess.Profile.TryDccDefineInGroup, IndexText, LowerCase, StartsStr, Trim</para>
/// <para>Returns: Order.ToArray</para>
/// <seealso cref="DRagLint.Preprocess.Profile.DprojGroupChain"/>
/// <seealso cref="DRagLint.Preprocess.Profile.TryDccDefineInGroup"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DprojEffectiveDefines(const AContent, APlatform, AConfig: string): TArray<TDprojDefine>;

/// <summary>The build-config names a .dproj declares, from its
/// '$(Config)'=='Name' or '$(Cfg_N)'!='' PropertyGroups, in document order.
/// 'Base' is not included.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <returns>Config names as spelled; empty when none is declared.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.PlatformDivergent.TPlatformDivergentCheck.CheckFiles (DRagLint.Lint.PlatformDivergent.pas)</para>
/// <para>Calls: DRagLint.Preprocess.Profile.ReadConfigSelectors</para>
/// <para>Returns: Names.ToArray</para>
/// <seealso cref="DRagLint.Preprocess.Profile.ReadConfigSelectors"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DprojConfigNames(const AContent: string): TArray<string>;

/// <summary>The PropertyGroup aliases MSBuild applies for one config +
/// platform, in order: Base, Base_&lt;P&gt;, then each config of AConfig's
/// CfgParent chain from the root down, each followed by its _&lt;P&gt;
/// group -- the order DprojEffectiveDefines applies DCC_Define in.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <param name="APlatform">The platform group suffix, used verbatim.</param>
/// <param name="AConfig">A config name or 'Base'; mapped as in
/// DprojEffectiveDefines.</param>
/// <returns>Aliases such as ['Base', 'Base_Win64', 'Cfg_2', 'Cfg_2_Win64'].
/// The last 'Cfg_N' entry (or 'Base') is the config's own key.</returns>
/// <remarks>
/// Pure: reads only AContent. Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Preprocess.Profile.DprojEffectiveDefines (DRagLint.Preprocess.Profile.pas), DRagLint.Project.Facts.ReadProjectFacts (DRagLint.Project.Facts.pas)</para>
/// <para>Calls: DRagLint.Preprocess.Profile.ConfigChain</para>
/// <seealso cref="DRagLint.Preprocess.Profile.ConfigChain"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DprojGroupChain(const AContent, APlatform, AConfig: string): TArray<string>;

/// <summary>The platforms a .dproj enables:
/// &lt;Platform value="P"&gt;True&lt;/Platform&gt; entries, in document
/// order.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <returns>Platform names as spelled ('Win32', 'Win64', ...).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.PlatformDivergent.ComparedPlatforms (DRagLint.Lint.PlatformDivergent.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DprojEnabledPlatforms(const AContent: string): TArray<string>;

/// <summary>Lane INC2: splits one define token the way a DCC_Define list or a
/// dcc -D option spells it: 'NAME' or 'NAME=VALUE'. Both halves are trimmed.</summary>
/// <param name="AToken">One token, e.g. 'DEBUG2=3' or 'FEATX'.</param>
/// <param name="AName">Receives the symbol ('' for a token such as '=3').</param>
/// <param name="AValue">Receives the text after the first '=', '' when none.</param>
/// <returns>True when the token carries a non-empty value.</returns>
/// <remarks>Pure. Never raises.</remarks>
function SplitDefineToken(const AToken: string; out AName, AValue: string): Boolean;

/// <summary>Lane INC2: the compiler's own numeric constants an {$IF} can test
/// for Delphi 13 / RAD Studio 37: CompilerVersion and RTLVersion, both 37
/// (the integer part; the evaluator is integer-only).</summary>
/// <returns>Lowercased name / value pairs.</returns>
/// <remarks>Pure.</remarks>
function CompilerNumerics: TArray<TPair<string, Integer>>;

/// <summary>Lane INC2: dcc's switch states with no .dproj option and no source
/// directive, for {$IFOPT}: B- C+ D+ G+ H+ I+ J- L+ M- O+ P+ Q- R- T- U- V+ W-
/// X+ Y+.</summary>
/// <returns>Lowercased letter / on pairs.</returns>
/// <remarks>Pure.</remarks>
function CompilerDefaultSwitches: TArray<TPair<string, Boolean>>;

/// <summary>Lane INC2: the switch states a .dproj sets for one config +
/// platform: each DCC_ switch property (DCC_RangeChecking -> R,
/// DCC_Optimize -> O, DCC_DebugInformation -> D, ...) as the LAST group of
/// DprojGroupChain that sets it leaves it; 'false' and '0' are off, any other
/// value on.</summary>
/// <param name="AContent">The .dproj text.</param>
/// <param name="APlatform">The platform group suffix, used verbatim.</param>
/// <param name="AConfig">A config name or 'Base'; mapped as in
/// DprojEffectiveDefines.</param>
/// <returns>Lowercased letter / on pairs, only for properties the .dproj
/// sets.</returns>
/// <remarks>Pure: reads only AContent. Never raises.</remarks>
function DprojEffectiveSwitches(const AContent, APlatform, AConfig: string): TArray<TPair<string, Boolean>>;

/// <summary>Lane INC2: the profile of a build with no project: the platform
/// built-in symbols, CompilerNumerics and CompilerDefaultSwitches.</summary>
/// <param name="APlatform">As for PlatformBuiltins.</param>
/// <returns>The profile.</returns>
/// <remarks>Pure.</remarks>
function BuiltinsProfile(const APlatform: string): TDefineProfile;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions;

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

function KnownPlatforms: TArray<string>;
begin
  Result := TArray<string>.Create('Win32', 'Win64', 'Win64x', 'Linux64', 'OSX64',
    'OSXARM64', 'Android', 'Android64', 'iOSDevice64', 'iOSSimARM64');
end;

function PlatformBuiltins(const APlatform: string): TArray<string>;
const
  // VERIFIED rows (Win32, Win64): produced by the installed Delphi 13 compilers
  // (Studio\37.0\bin\dcc32.exe / dcc64.exe) on 2026-10-28 with a probe program
  // that emits {$IFDEF X}{$MESSAGE HINT} for ~70 candidate symbols; the rows
  // below are EXACTLY the symbols the compiler reported, nothing more. The
  // compiler does NOT define COMPILER_VERSION_37 (removed from the old set).
  WIN32_SET = 'cpu32bits,cpux86,cpu386,mswindows,win32,assembler,weakref,'
    + 'underscoreimportname,unicode,conditionalexpressions,ver370,nativecode,dcc';
  WIN64_SET = 'cpux64,cpu64bits,mswindows,win64,assembler,weakref,'
    + 'unicode,conditionalexpressions,ver370,nativecode,dcc';
  // UNVERIFIED rows (no cross compiler is installed under Studio\37.0\bin; only
  // dcc32 / dcc64 exist): best recollection of the Embarcadero DocWiki
  // "Conditional compilation (Delphi)" table plus the compiler-wide symbols the
  // probe showed on both Windows compilers (unicode, conditionalexpressions,
  // ver370, nativecode, dcc, weakref). Re-verify when a cross compiler is
  // available.
  // UNVERIFIED Win64x (LLVM-based Windows 64): taken to equal Win64.
  WIN64X_SET = WIN64_SET;
  // UNVERIFIED Linux64: LINUX, LINUX64, POSIX, POSIX64, CPUX64, CPU64BITS,
  // EXTERNALLINKER.
  LINUX64_SET = 'linux,linux64,posix,posix64,cpux64,cpu64bits,externallinker,assembler,'
    + 'weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
  // UNVERIFIED macOS: MACOS, MACOS64, OSX, OSX64, POSIX, POSIX64, CPU64BITS,
  // CPUX64 (Intel) or CPUARM + CPUARM64 (Apple silicon); EXTERNALLINKER.
  OSX64_SET = 'macos,macos64,osx,osx64,posix,posix64,cpux64,cpu64bits,externallinker,assembler,'
    + 'weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
  OSXARM64_SET = 'macos,macos64,osx,osx64,posix,posix64,cpuarm,cpuarm64,cpu64bits,externallinker,'
    + 'weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
  // UNVERIFIED Android: ANDROID + ANDROID32 / ANDROID64, POSIX + POSIX32 /
  // POSIX64, CPUARM (+ CPUARM32 / CPUARM64), CPU32BITS / CPU64BITS; no LINUX.
  ANDROID_SET = 'android,android32,posix,posix32,cpuarm,cpuarm32,cpu32bits,externallinker,'
    + 'weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
  ANDROID64_SET = 'android,android64,posix,posix64,cpuarm,cpuarm64,cpu64bits,externallinker,'
    + 'weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
  // UNVERIFIED iOS: IOS, IOS64, IOSDEVICE, IOSDEVICE64 (device) or IOSSIMULATOR
  // (simulator), plus MACOS, MACOS64, POSIX, POSIX64, CPUARM, CPUARM64,
  // CPU64BITS.
  IOSDEV64_SET = 'ios,ios64,iosdevice,iosdevice64,macos,macos64,posix,posix64,cpuarm,cpuarm64,'
    + 'cpu64bits,externallinker,weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
  IOSSIM64_SET = 'ios,ios64,iossimulator,macos,macos64,posix,posix64,cpuarm,cpuarm64,'
    + 'cpu64bits,externallinker,weakref,unicode,conditionalexpressions,ver370,nativecode,dcc';
var
  Spec: string;
begin
  if SameText(APlatform, 'Win32') then Spec := WIN32_SET
  else if SameText(APlatform, 'Win64x') then Spec := WIN64X_SET
  else if SameText(APlatform, 'Linux64') then Spec := LINUX64_SET
  else if SameText(APlatform, 'OSX64') then Spec := OSX64_SET
  else if SameText(APlatform, 'OSXARM64') then Spec := OSXARM64_SET
  else if SameText(APlatform, 'Android') then Spec := ANDROID_SET
  else if SameText(APlatform, 'Android64') then Spec := ANDROID64_SET
  else if SameText(APlatform, 'iOSDevice64') then Spec := IOSDEV64_SET
  else if SameText(APlatform, 'iOSSimARM64') then Spec := IOSSIM64_SET
  else
    // Win64 is the default (also for unknown/empty platforms).
    Spec := WIN64_SET;
  Result := SplitString(Spec, ',');
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
  // Every platform with built-ins above has its own group suffix (Base_Linux64);
  // anything else keeps the Win64 default.
  if MatchText(APlatform, ['Win32', 'Win64x', 'Linux64', 'OSX64', 'OSXARM64',
    'Android', 'Android64', 'iOSDevice64', 'iOSSimARM64']) then
    Result := APlatform
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
function TryPropertyInGroup(const AContent, AConditionNeedle, AProperty: string;
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
      DM := TRegEx.Match(M.Groups[2].Value, '<' + AProperty + '>(.*?)</' + AProperty + '>',
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

// The DCC_Define of that group (lane INC2: TryPropertyInGroup generalises it).
function TryDccDefineInGroup(const AContent, AConditionNeedle: string;
  out AValue: string): Boolean;
begin
  Result := TryPropertyInGroup(AContent, AConditionNeedle, 'DCC_Define', AValue);
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

function DprojGroupChain(const AContent, APlatform, AConfig: string): TArray<string>;
var
  Key: string;
begin
  Result := [BASE_KEY, BASE_KEY + '_' + APlatform];
  for Key in ConfigChain(AContent, AConfig) do
    Result := Result + [Key, Key + '_' + APlatform];
end;

function DprojEffectiveDefines(const AContent, APlatform, AConfig: string): TArray<TDprojDefine>;
var
  Aliases: TArray<string>;
  Alias  : string;
  Value  : string;
  Part   : string;
  Sym    : string;
  Val    : string;
  Def    : TDprojDefine;
  Order  : TList<TDprojDefine>;
  Seen   : TDictionary<string, Integer>;
  Idx    : Integer;
begin
  // MSBuild applies, in order: Base, Base_<P>, then each config of the chain
  // from the root ancestor down, each followed by its own _<P> group. The two
  // platform groups were missed until 2026-09-23 (Micronite2027's EUREKALOG);
  // REPLACE semantics and the name -> Cfg_N mapping until 2026-10-25 (X5).
  Aliases := DprojGroupChain(AContent, APlatform, AConfig);
  Order := TList<TDprojDefine>.Create;
  Seen  := TDictionary<string, Integer>.Create;
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
        if (Sym = '') or StartsStr('$(', Sym) then Continue;
        // Lane INC2: 'DEBUG2=3' defines DEBUG2 and carries the value 3.
        SplitDefineToken(Trim(Part), Sym, Val);
        if Sym = '' then Continue;
        if Seen.TryGetValue(LowerCase(Sym), Idx) then
        begin
          Def := Order[Idx];
          if IndexText(Alias, Def.Groups) < 0 then Def.Groups := Def.Groups + [Alias];
          if Val <> '' then Def.Value := Val;
          Order[Idx] := Def;
          Continue;
        end;
        Seen.Add(LowerCase(Sym), Order.Count);
        Def.Name   := Sym;
        Def.Value  := Val;
        Def.Group  := Alias;
        Def.Groups := [Alias];
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

function SplitDefineToken(const AToken: string; out AName, AValue: string): Boolean;
var
  Eq: Integer;
begin
  Eq := Pos('=', AToken);
  if Eq = 0 then
  begin
    AName  := Trim(AToken);
    AValue := '';
  end
  else
  begin
    AName  := Trim(Copy(AToken, 1, Eq - 1));
    AValue := Trim(Copy(AToken, Eq + 1, MaxInt));
  end;
  Result := AValue <> '';
end;

const
  // Delphi 13 = RAD Studio 37: CompilerVersion 37.0, RTLVersion 37.0.
  COMPILER_VERSION_37 = 37;
  // dcc's default switch states (letter + sign), no option and no directive.
  DEFAULT_SWITCHES: array[0..18] of string = (
    'b-', 'c+', 'd+', 'g+', 'h+', 'i+', 'j-', 'l+', 'm-', 'o+',
    'p+', 'q-', 'r-', 't-', 'u-', 'v+', 'w-', 'x+', 'y+');
  // The .dproj property that sets each switch, and its letter. Parallel arrays.
  SWITCH_PROPERTIES: array[0..18] of string = (
    'DCC_FullBooleanEvaluations', 'DCC_AssertionsAtRuntime', 'DCC_DebugInformation',
    'DCC_ImportedDataReferences', 'DCC_LongStrings', 'DCC_IOChecking',
    'DCC_WriteableConstants', 'DCC_LocalDebugSymbols', 'DCC_RunTimeTypeInfo',
    'DCC_Optimize', 'DCC_OpenStringParams', 'DCC_IntegerOverflowCheck',
    'DCC_RangeChecking', 'DCC_TypedAtParameter', 'DCC_PentiumSafeDivide',
    'DCC_StrictVarStrings', 'DCC_GenerateStackFrames', 'DCC_ExtendedSyntax',
    'DCC_SymbolReferenceInfo');
  SWITCH_PROPERTY_LETTERS: array[0..18] of string = (
    'b', 'c', 'd', 'g', 'h', 'i', 'j', 'l', 'm', 'o',
    'p', 'q', 'r', 't', 'u', 'v', 'w', 'x', 'y');

function CompilerNumerics: TArray<TPair<string, Integer>>;
begin
  Result := [TPair<string, Integer>.Create('compilerversion', COMPILER_VERSION_37),
             TPair<string, Integer>.Create('rtlversion', COMPILER_VERSION_37)];
end;

function CompilerDefaultSwitches: TArray<TPair<string, Boolean>>;
var
  S: string;
begin
  Result := nil;
  for S in DEFAULT_SWITCHES do
    Result := Result + [TPair<string, Boolean>.Create(S[1], S[2] = '+')];
end;

function DprojEffectiveSwitches(const AContent, APlatform, AConfig: string): TArray<TPair<string, Boolean>>;
var
  Aliases: TArray<string>;
  Alias  : string;
  Value  : string;
  Last   : string;
  Found  : Boolean;
  K      : Integer;
begin
  Result := nil;
  Aliases := DprojGroupChain(AContent, APlatform, AConfig);
  for K := Low(SWITCH_PROPERTIES) to High(SWITCH_PROPERTIES) do
  begin
    Found := False;
    Last  := '';
    for Alias in Aliases do
      if TryPropertyInGroup(AContent, '$(' + Alias + ')', SWITCH_PROPERTIES[K], Value) then
      begin
        Found := True;
        Last  := Trim(Value);
      end;
    if Found then
      Result := Result + [TPair<string, Boolean>.Create(SWITCH_PROPERTY_LETTERS[K],
        not (SameText(Last, 'false') or (Last = '0')))];
  end;
end;

function BuiltinsProfile(const APlatform: string): TDefineProfile;
begin
  Result.Defines        := PlatformBuiltins(APlatform);
  Result.NumericDefines := CompilerNumerics;
  Result.Switches       := CompilerDefaultSwitches;
end;

function ProfileFromDproj(const ADprojPath, APlatform, AConfig: string): TDefineProfile;
var
  Seen   : TDictionary<string, Byte>;
  Order  : TList<string>;
  Content: string;
  Sym    : string;
  Def    : TDprojDefine;
  Num    : Integer;
begin
  Result.Defines := nil;
  // Lane INC2: the compiler's own values first; the .dproj's override them.
  Result.NumericDefines := CompilerNumerics;
  Result.Switches       := CompilerDefaultSwitches;

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
        // Lane INC2: DEBUG2=3 -> {$IF DEBUG2 = 3}. A non-integer value only defines.
        if (Def.Value <> '') and TryStrToInt(Def.Value, Num) then
          Result.NumericDefines := Result.NumericDefines + [TPair<string, Integer>.Create(Sym, Num)];
      end;
      Result.Switches := Result.Switches +
        DprojEffectiveSwitches(Content, PlatformGroupSuffix(APlatform), AConfig);
    end;

    Result.Defines := Order.ToArray;
  finally
    Order.Free;
    Seen.Free;
  end;
end;

end.
