unit DRagLint.Lint.PlatformDivergent;

// Rule platform-divergent-define: a conditional symbol that one enabled Windows
// platform's build defines and another's does not -- for the same config --
// AND that the project's code tests with an {$IFDEF}, {$IFNDEF} or defined().
// The two platform builds then compile different code, usually by accident (a
// define added to Base_Win32 in the Project Options dialog and never to
// Base_Win64). Spec: docs\superpowers\specs\2026-10-25-three-lint-rules-design.md,
// rule 1; owner rulings 2026-10-25 (effective sets, default ON).
//
// WHAT IS COMPARED. For each config C in Base + every config the .dproj
// declares, and each ordered pair of enabled platforms (P1, P2) out of Win32 /
// Win64, the EFFECTIVE define sets eff(C, P1) and eff(C, P2) from
// DprojEffectiveDefines -- the same reader the indexer preprocesses with, so a
// define moved from Base_Win32 up to Base is not a divergence, and a
// Cfg_N_<P> group that REPLACES (no $(DCC_Define)) is one. A symbol is
// divergent when it is in eff(C, P1) and not in eff(C, P2).
//
// WHEN IT FIRES (each clause is a control in
// tests\autotest\run_platform_divergent_define.ps1):
//   1. the symbol is divergent for at least one config;
//   2. it is TESTED in a file of the run (lexer and include resolution shared
//      with ifdef-undefined-symbol);
//   3. that file -- or a {$I} file it includes -- does not $DEFINE or $UNDEF
//      it itself (the platform split is then moot for that unit);
//   4. it is not compiler-predefined (WIN32, CPUX86, ... differ by design) and
//      not on the platform_divergent_allow list.
// ONE finding per symbol, at its first test site in run order; the message
// names the first config, both platforms and the group that set it, and every
// config it diverges in.
//
// CONSERVATIVE EXITS: no .dproj, fewer than two of Win32 / Win64 enabled, or a
// file whose include cannot be resolved -> no finding.
//
// WHY src\lint AND NOT src\preprocess: the extractor-version guard hashes
// src\preprocess; this rule changes no extraction.
//
// Encoding note: directive text appears only in // comments and strings.

interface

uses
  System.SysUtils,
  DRagLint.Core.Model;

const
  /// <summary>The rule id reported by TPlatformDivergentCheck.</summary>
  PLATFORM_DIVERGENT_RULE_ID = 'platform-divergent-define';

type
  /// <summary>Finds conditional symbols whose effective definition differs
  /// between the Win32 and Win64 builds of one config, at a site the code
  /// tests them.</summary>
  /// <remarks>
  /// Stateless; every method is a static class function and safe to
  /// call from any thread. Reads files, never writes them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPlatformDivergentCheck = class
  public
    /// <summary>Checks AFiles against the platform split of ADprojPath, under
    /// the definition in the unit header.</summary>
    /// <param name="AFiles">Source files of the run, in report order. Unreadable
    /// files, and files with an unresolvable include, are skipped.</param>
    /// <param name="ADprojPath">The owning project's .dproj. Empty or missing
    /// returns no findings -- without it the build's defines are unknown.</param>
    /// <param name="AAllow">Symbols whose split is deliberate (the
    /// platform_divergent_allow config list); compared case-insensitively.</param>
    /// <param name="AExtraIncludeDirs">Directories searched for {$I} files
    /// after the file's own folder -- for a file analysed from a temporary
    /// snapshot, pass the real file's folder.</param>
    /// <returns>At most one warning per divergent symbol, anchored at its first
    /// test site.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ProjectSearchDirs, DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ScanFileTests, DRagLint.Lint.PlatformDivergent.CollectDivergences, DRagLint.Lint.PlatformDivergent.ComparedPlatforms, DRagLint.Lint.PlatformDivergent.MakeFinding, DRagLint.Lint.PlatformDivergent.TryReadDproj, DRagLint.Preprocess.Profile.DprojConfigNames, IndexText, LowerCase, Trim</para>
    /// <para>Returns: nil; Findings.ToArray</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 67 lines (full implementation)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ProjectSearchDirs"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ScanFileTests"/>
    /// <seealso cref="DRagLint.Lint.PlatformDivergent.CollectDivergences"/>
    /// <seealso cref="DRagLint.Lint.PlatformDivergent.ComparedPlatforms"/>
    /// <seealso cref="DRagLint.Lint.PlatformDivergent.MakeFinding"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFiles(const AFiles: TArray<string>; const ADprojPath: string;
      const AAllow: TArray<string>;
      const AExtraIncludeDirs: TArray<string> = nil): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  DRagLint.Preprocess.Profile,
  DRagLint.Lint.IfdefUndefined;

const
  // The platforms compared: the Windows targets whose built-ins the engine
  // models (PlatformBuiltins). Mobile / POSIX splits are by design.
  COMPARED_PLATFORMS: array[0..1] of string = ('Win32', 'Win64');
  // The root config, compared like any declared one.
  BASE_CONFIG = 'Base';

type
  // The first divergence seen for one symbol, plus every config it shows in.
  TDivergence = record
    Symbol : string; // as spelled in the .dproj
    Config : string; // the first config it diverges in
    Has    : string; // the platform that defines it there
    Group  : string; // the group alias that set it there
    Lacks  : string; // the platform that does not
    Configs: string; // every config it diverges in, comma-separated
  end;

  // Lowercased symbol -> its divergence.
  TDivergenceMap = TDictionary<string, TDivergence>;

// The compared platforms the .dproj enables, spelled as COMPARED_PLATFORMS.
function ComparedPlatforms(const AContent: string): TArray<string>;
var
  Enabled: string;
  Plat   : string;
begin
  Result:= nil;
  for Plat in COMPARED_PLATFORMS do
    for Enabled in DprojEnabledPlatforms(AContent) do
      if SameText(Enabled, Plat) then
      begin
        Result:= Result + [Plat];
        Break;
      end;
end;

// Lowercased names of one effective set.
function NameSet(const ADefs: TArray<TDprojDefine>): TDictionary<string, Byte>;
var
  Def: TDprojDefine;
begin
  Result:= TDictionary<string, Byte>.Create;
  for Def in ADefs do Result.AddOrSetValue(LowerCase(Def.Name), 0);
end;

// Records every symbol of eff(AConfig, AHas) missing from eff(AConfig, ALacks)
// into ADivs, skipping compiler built-ins and the allow list. ASeenPairs keys
// '<symbol>|<config>' so a config is listed once per symbol.
procedure CollectDivergences(const AContent, AConfig, AHas, ALacks: string;
  AAllow: TDictionary<string, Byte>; ADivs: TDivergenceMap;
  ASeenPairs: TDictionary<string, Byte>);
var
  Other: TDictionary<string, Byte>;
  Def  : TDprojDefine;
  Key  : string;
  Div1 : TDivergence;
begin
  Other:= NameSet(DprojEffectiveDefines(AContent, ALacks, AConfig));
  try
    for Def in DprojEffectiveDefines(AContent, AHas, AConfig) do
    begin
      Key:= LowerCase(Def.Name);
      if Other.ContainsKey(Key) or AAllow.ContainsKey(Key)
        or TIfdefUndefinedCheck.IsCompilerPredefined(Key) then Continue;
      if not ADivs.TryGetValue(Key, Div1) then
      begin
        Div1:= Default(TDivergence);
        Div1.Symbol:= Def.Name;
        Div1.Config:= AConfig;
        Div1.Has   := AHas;
        Div1.Group := Def.Group;
        Div1.Lacks := ALacks;
      end;
      if not ASeenPairs.ContainsKey(Key + '|' + LowerCase(AConfig)) then
      begin
        ASeenPairs.Add(Key + '|' + LowerCase(AConfig), 0);
        Div1.Configs:= if Div1.Configs = '' then AConfig else Div1.Configs + ', ' + AConfig;
      end;
      ADivs.AddOrSetValue(Key, Div1);
    end;
  finally
    Other.Free;
  end;
end;

// Reads the .dproj, or returns False (missing, locked, undecodable).
function TryReadDproj(const APath: string; out AText: string): Boolean;
begin
  Result:= True;
  AText:= '';
  try
    AText:= TFile.ReadAllText(APath);
  except
    on E: EInOutError    do Result:= False;
    on E: EStreamError   do Result:= False;
    on E: EEncodingError do Result:= False;
  end;
end;

function MakeFinding(const AFilePath: string; const ATest: TConditionalTest;
  const ADiv: TDivergence): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId    := PLATFORM_DIVERGENT_RULE_ID;
  Result.Severity  := 'warning';
  Result.FilePath  := AFilePath;
  Result.StartLine := ATest.Line;
  Result.StartCol  := ATest.Col;
  Result.EndLine   := ATest.Line;
  Result.EndCol    := ATest.Col;
  Result.SymbolName:= ATest.Symbol;
  Result.Message   := Format(
    'Conditional symbol ''%s'' is defined for %s|%s (by %s) but not for %s|%s -- ' +
    'the two platform builds compile different code here (diverges in: %s). ' +
    'Define it for both platforms, or list it in platform_divergent_allow if the ' +
    'split is deliberate',
    [ADiv.Symbol, ADiv.Config, ADiv.Has, ADiv.Group, ADiv.Config, ADiv.Lacks, ADiv.Configs]);
end;

class function TPlatformDivergentCheck.CheckFiles(const AFiles: TArray<string>;
  const ADprojPath: string; const AAllow: TArray<string>;
  const AExtraIncludeDirs: TArray<string>): TArray<TLintFinding>;
var
  Content   : string;
  Platforms : TArray<string>;
  Allow     : TDictionary<string, Byte>;
  SeenPairs : TDictionary<string, Byte>;
  Reported  : TDictionary<string, Byte>;
  Divs      : TDivergenceMap;
  Findings  : TList<TLintFinding>;
  Config    : string;
  Has       : string;
  Lacks     : string;
  Sym       : string;
  FilePath  : string;
  SearchDirs: TArray<string>;
  Tests     : TArray<TConditionalTest>;
  Locals    : TArray<string>;
  Test      : TConditionalTest;
  Div1      : TDivergence;
  Configs   : TArray<string>;
begin
  Result:= nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath)
    or not TryReadDproj(ADprojPath, Content) then Exit;
  Platforms:= ComparedPlatforms(Content);
  if Length(Platforms) < 2 then Exit;

  Allow    := TDictionary<string, Byte>.Create;
  SeenPairs:= TDictionary<string, Byte>.Create;
  Reported := TDictionary<string, Byte>.Create;
  Divs     := TDivergenceMap.Create;
  Findings := TList<TLintFinding>.Create;
  try
    for Sym in AAllow do
      if Trim(Sym) <> '' then Allow.AddOrSetValue(LowerCase(Trim(Sym)), 0);
    Configs:= [BASE_CONFIG] + DprojConfigNames(Content);
    for Config in Configs do
      for Has in Platforms do
        for Lacks in Platforms do
          if Has <> Lacks then
            CollectDivergences(Content, Config, Has, Lacks, Allow, Divs, SeenPairs);
    if Divs.Count = 0 then Exit;

    SearchDirs:= AExtraIncludeDirs + TIfdefUndefinedCheck.ProjectSearchDirs(ADprojPath);
    for FilePath in AFiles do
    begin
      if not TIfdefUndefinedCheck.ScanFileTests(FilePath, SearchDirs, Tests, Locals) then Continue;
      for Test in Tests do
      begin
        Sym:= LowerCase(Test.Symbol);
        if Reported.ContainsKey(Sym) or not Divs.TryGetValue(Sym, Div1) then Continue;
        // The unit sets the symbol itself: the platform split is moot here.
        if IndexText(Sym, Locals) >= 0 then Continue;
        Reported.Add(Sym, 0);
        Findings.Add(MakeFinding(FilePath, Test, Div1));
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Divs.Free;
    Reported.Free;
    SeenPairs.Free;
    Allow.Free;
  end;
end;

end.
