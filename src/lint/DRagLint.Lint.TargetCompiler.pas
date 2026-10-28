unit DRagLint.Lint.TargetCompiler;

{ The TARGET COMPILER of a lint run (two-way modernize / downgrade, lane D0,
  1.38): which Delphi compiler the linted code must still compile on.

  One number, the CompilerVersion (37 = Delphi 13 Florence), decides two things:
    * a MODERNIZE rule whose fix emits a construct newer than the target
      ("needs_compiler" in its sidecar / catalog entry) is not reported;
    * a COMPAT rule -- category "compat", the reverse fix that rewrites such a
      construct back to classic syntax -- is switched ON when the target is
      older than the construct ("compat_since").
  The default, 37, is today's behaviour: nothing is gated, no compat rule runs.

  This unit is a LEAF on purpose (System.* only): the CLI, the LSP and the
  project-context file (.dlcontext.json, field targetCompiler -- the LSP lane's
  DRagLint.Project.ContextFile) all feed the same resolver, and the query-rule
  engine and the autofix registry read the run's value through
  ActiveTargetCompiler without depending on the CLI. }

interface

uses
  System.SysUtils;

const
  /// <summary>The CompilerVersion a run targets when nothing names one: 37,
  /// Delphi 13 Florence -- the behaviour every release before 1.38 had.</summary>
  DEFAULT_TARGET_COMPILER = 37;
  /// <summary>Oldest CompilerVersion a token may name (14 = Delphi 6).</summary>
  MIN_TARGET_COMPILER = 14;
  /// <summary>Newest CompilerVersion a token may name (37 = Delphi 13).</summary>
  MAX_TARGET_COMPILER = 37;
  /// <summary>The token that derives the target from the owning .dproj's
  /// ProjectVersion (opt-in; never the default -- owner ruling Q2, 2026-10-28).</summary>
  TARGET_COMPILER_AUTO = 'auto';
  /// <summary>CompilerVersion of Delphi 10.3 Rio, the first to accept an inline
  /// `var` declaration and `for var` -- the ANeedsCompiler of every fixer that emits one.</summary>
  INLINE_VAR_SINCE = 33;

type
  /// <summary>The per-run rule gate a target compiler implies: which rule ids
  /// are silenced (their fix needs a newer compiler) and which compat rules are
  /// switched on (the target cannot take the construct they report).</summary>
  /// <remarks>A value type built once per run by Build; Drops / ForcesOn are
  /// pure lookups. Empty (Active = False) at the default target, so a default
  /// run takes no new code path at all.</remarks>
  TTargetRuleGate = record
    /// <summary>The CompilerVersion the gate was built for.</summary>
    Target  : Integer;
    /// <summary>Rule ids whose needs_compiler is newer than Target.</summary>
    Gated   : TArray<string>;
    /// <summary>Compat rule ids whose compat_since is newer than Target.</summary>
    CompatOn: TArray<string>;
    /// <summary>Builds the gate from parallel catalog arrays.</summary>
    /// <param name="pTarget">The run's CompilerVersion.</param>
    /// <param name="pIds">Rule ids, one per catalog row.</param>
    /// <param name="pNeeds">needs_compiler per row (0 = any compiler).</param>
    /// <param name="pCompatSince">compat_since per row (0 = not a compat rule).</param>
    /// <returns>The gate; Gated and CompatOn empty when no row is affected.</returns>
    /// <exception cref="EArgumentException">Raised when the three arrays differ in length.</exception>
    class function Build(pTarget: Integer; const pIds: TArray<string>;
      const pNeeds, pCompatSince: TArray<Integer>): TTargetRuleGate; static;
    /// <summary>True when the gate differs from the default run (Target is not
    /// DEFAULT_TARGET_COMPILER).</summary>
    /// <returns>Target is set (not 0) and is not DEFAULT_TARGET_COMPILER.</returns>
    function Active: Boolean;
    /// <summary>True when findings of pRuleId must not be reported under Target.</summary>
    /// <param name="pRuleId">Rule id; compared case-insensitively.</param>
    /// <returns>True for an id in Gated.</returns>
    function Drops(const pRuleId: string): Boolean;
    /// <summary>True when pRuleId is a compat rule the target switches on, so its
    /// off-by-default state is lifted for this run.</summary>
    /// <param name="pRuleId">Rule id; compared case-insensitively.</param>
    /// <returns>True for an id in CompatOn.</returns>
    function ForcesOn(const pRuleId: string): Boolean;
  end;

/// <summary>Parses one target-compiler token into a CompilerVersion.</summary>
/// <param name="pToken">A product version (13, 12, 12.2, 11, 10.4, 10.3, XE7,
/// 2009, 7, 6; an optional "Delphi" prefix and code names such as Athens are
/// accepted) or a CompilerVersion number 14..37. Case- and space-insensitive.
/// Not "auto" -- see ResolveTargetCompiler.</param>
/// <param name="pVersion">Out: the CompilerVersion; DEFAULT_TARGET_COMPILER on failure.</param>
/// <param name="pError">Out: '' on success, else a one-line message naming the
/// accepted tokens.</param>
/// <returns>True when pToken names a known compiler.</returns>
/// <remarks>Product numbers (6..13) and CompilerVersion numbers (14..37) do not
/// overlap, so a bare number is never ambiguous. Delphi 2007 (CompilerVersion
/// 18.5) maps to 18. Pure.</remarks>
function ParseCompilerToken(const pToken: string; out pVersion: Integer; out pError: string): Boolean;  // dl:ok unused-public-symbol@7528 -- public API: pinned by tests\rules-catalog, called by the LSP context lane

/// <summary>Maps a .dproj &lt;ProjectVersion&gt; to the CompilerVersion of the
/// IDE that saved it.</summary>
/// <param name="pProjectVersion">The element text, e.g. '20.4'.</param>
/// <param name="pVersion">Out: the CompilerVersion; 0 when unknown.</param>
/// <returns>True when the value is in the pinned table; an unknown value is
/// never guessed (the caller refuses).</returns>
/// <remarks>Only 20.4 -> 37 is measured on this machine (drag-lint.dproj, Studio
/// 37); the older rows follow the Embarcadero release history and are pinned by
/// tests\autotest\run_target_compiler_guard.ps1. Pure.</remarks>
function ProjectVersionToCompiler(const pProjectVersion: string; out pVersion: Integer): Boolean;  // dl:ok unused-public-symbol@4e5d -- public API: pinned by tests\rules-catalog, called by the LSP context lane

/// <summary>The product name of a CompilerVersion, for messages.</summary>
/// <param name="pVersion">A CompilerVersion.</param>
/// <returns>'Delphi 13', 'Delphi 10.4', 'Delphi XE7' ...; 'CompilerVersion N'
/// for a number outside the table.</returns>
function CompilerDisplayName(pVersion: Integer): string;

/// <summary>THE resolver of a run's target compiler. First non-empty source
/// wins: the command line, then the lint config (drag-lint-lint.json key
/// target_compiler, profile-overridable), then the project context file
/// (.dlcontext.json field targetCompiler), then DEFAULT_TARGET_COMPILER.</summary>
/// <param name="pCmdLine">--target-compiler value, or ''.</param>
/// <param name="pConfigValue">TLintConfig.TargetCompiler, or ''.</param>
/// <param name="pContextValue">The project context file's targetCompiler, or ''
/// (the LSP lane wires this; the CLI passes '' today).</param>
/// <param name="pDprojPath">The owning .dproj, used only when the winning token
/// is "auto"; '' when none is known.</param>
/// <param name="pVersion">Out: the CompilerVersion; DEFAULT_TARGET_COMPILER on failure.</param>
/// <param name="pError">Out: '' on success, else a one-line refusal.</param>
/// <returns>False when the winning token is unknown, or is "auto" without a
/// .dproj or with a ProjectVersion outside the pinned table -- the caller
/// refuses the run rather than guessing.</returns>
/// <remarks>The config beats the context file because the config is written by
/// a person and the context file by a tool. Pure apart from reading pDprojPath.</remarks>
function ResolveTargetCompiler(const pCmdLine, pConfigValue, pContextValue, pDprojPath: string;
  out pVersion: Integer; out pError: string): Boolean;

/// <summary>True when a rule (or fix entry) that needs compiler pNeedsCompiler
/// must be silenced under pTarget.</summary>
/// <param name="pNeedsCompiler">needs_compiler; 0 = any compiler.</param>
/// <param name="pTarget">The run's CompilerVersion.</param>
/// <returns>(pNeedsCompiler &gt; 0) and (pTarget &lt; pNeedsCompiler).</returns>
function IsGatedByTarget(pNeedsCompiler, pTarget: Integer): Boolean;

/// <summary>True when a compat rule whose construct needs compiler
/// pCompatSince is switched on under pTarget.</summary>
/// <param name="pCompatSince">compat_since; 0 = not a compat rule.</param>
/// <param name="pTarget">The run's CompilerVersion.</param>
/// <returns>(pCompatSince &gt; 0) and (pTarget &lt; pCompatSince).</returns>
function IsCompatOnForTarget(pCompatSince, pTarget: Integer): Boolean;  // dl:ok unused-public-symbol@402c -- public API: pinned by tests\rules-catalog, called by the LSP context lane

/// <summary>The target compiler of the current run.</summary>
/// <returns>The value SetActiveTargetCompiler stored; DEFAULT_TARGET_COMPILER
/// until then.</returns>
/// <remarks>Read by the query-rule engine (per-entry needs_compiler) and the
/// autofix registry (RegisterFixer's ANeedsCompiler). Process-wide: one run,
/// one target. A host that lints several projects in one process (the LSP)
/// sets it before each run.</remarks>
function ActiveTargetCompiler: Integer;

/// <summary>Sets the target compiler of the current run.</summary>
/// <param name="pVersion">A CompilerVersion; 0 or less restores the default.</param>
/// <remarks>Call once per run, before linting; not synchronised.</remarks>
procedure SetActiveTargetCompiler(pVersion: Integer);

implementation

uses
  System.StrUtils, System.IOUtils, System.RegularExpressions;

type
  TCompilerRow = record
    Version: Integer;
    Name   : string;   { display name after "Delphi " }
    Tokens : string;   { accepted product tokens, '|'-separated, upper case, no spaces }
  end;

const
  { Newest first. Tokens are matched after upper-casing and removing spaces and
    a leading DELPHI. }
  COMPILERS: array[0..22] of TCompilerRow = (
    (Version: 37; Name: '13';    Tokens: '13|13.0|13.1|FLORENCE'),
    (Version: 36; Name: '12';    Tokens: '12|12.0|12.1|12.2|12.3|ATHENS'),
    (Version: 35; Name: '11';    Tokens: '11|11.0|11.1|11.2|11.3|ALEXANDRIA'),
    (Version: 34; Name: '10.4';  Tokens: '10.4|10.4.1|10.4.2|SYDNEY'),
    (Version: 33; Name: '10.3';  Tokens: '10.3|10.3.1|10.3.2|10.3.3|RIO'),
    (Version: 32; Name: '10.2';  Tokens: '10.2|10.2.1|10.2.2|10.2.3|TOKYO'),
    (Version: 31; Name: '10.1';  Tokens: '10.1|BERLIN'),
    (Version: 30; Name: '10';    Tokens: '10|10.0|SEATTLE'),
    (Version: 29; Name: 'XE8';   Tokens: 'XE8'),
    (Version: 28; Name: 'XE7';   Tokens: 'XE7'),
    (Version: 27; Name: 'XE6';   Tokens: 'XE6'),
    (Version: 26; Name: 'XE5';   Tokens: 'XE5'),
    (Version: 25; Name: 'XE4';   Tokens: 'XE4'),
    (Version: 24; Name: 'XE3';   Tokens: 'XE3'),
    (Version: 23; Name: 'XE2';   Tokens: 'XE2'),
    (Version: 22; Name: 'XE';    Tokens: 'XE'),
    (Version: 21; Name: '2010';  Tokens: '2010'),
    (Version: 20; Name: '2009';  Tokens: '2009'),
    (Version: 18; Name: '2007';  Tokens: '2007|2006'),
    (Version: 17; Name: '2005';  Tokens: '2005'),
    (Version: 16; Name: '8';     Tokens: '8'),
    (Version: 15; Name: '7';     Tokens: '7'),
    (Version: 14; Name: '6';     Tokens: '6'));

type
  TProjectVersionRow = record
    ProjectVersion: string;
    Version       : Integer;
  end;

const
  { .dproj <ProjectVersion> -> CompilerVersion. 20.4 is measured (Studio 37);
    the rest follow the release history. An unlisted value refuses. }
  PROJECT_VERSIONS: array[0..17] of TProjectVersionRow = (
    (ProjectVersion: '20.4'; Version: 37),
    (ProjectVersion: '20.3'; Version: 36),
    (ProjectVersion: '20.2'; Version: 36),
    (ProjectVersion: '20.1'; Version: 36),
    (ProjectVersion: '19.5'; Version: 35),
    (ProjectVersion: '19.4'; Version: 35),
    (ProjectVersion: '19.3'; Version: 35),
    (ProjectVersion: '19.2'; Version: 34),
    (ProjectVersion: '19.1'; Version: 34),
    (ProjectVersion: '19.0'; Version: 34),
    (ProjectVersion: '18.8'; Version: 33),
    (ProjectVersion: '18.7'; Version: 33),
    (ProjectVersion: '18.6'; Version: 33),
    (ProjectVersion: '18.5'; Version: 33),
    (ProjectVersion: '18.4'; Version: 32),
    (ProjectVersion: '18.3'; Version: 32),
    (ProjectVersion: '18.2'; Version: 32),
    (ProjectVersion: '18.1'; Version: 31));

  ACCEPTED_TOKENS_HINT = 'accepted: 13, 12, 11, 10.4, 10.3, 10.2, 10.1, 10, XE8..XE2, XE, 2010, 2009, 2007, 2005, 7, 6, ' +
    'a CompilerVersion 14..37, or auto';

var
  GActiveTarget: Integer = DEFAULT_TARGET_COMPILER;

function NormaliseToken(const pToken: string): string;
begin
  Result:= UpperCase(StringReplace(Trim(pToken), ' ', '', [rfReplaceAll]));
  if StartsStr('DELPHI', Result) then Result:= Copy(Result, Length('DELPHI') + 1, MaxInt);
end;

function ParseCompilerToken(const pToken: string; out pVersion: Integer; out pError: string): Boolean;
var
  Tok: string;
  Row: TCompilerRow;
  N  : Integer;
begin
  pVersion:= DEFAULT_TARGET_COMPILER;
  pError  := '';
  Tok:= NormaliseToken(pToken);
  if Tok <> '' then
  begin
    for Row in COMPILERS do
      if MatchStr(Tok, SplitString(Row.Tokens, '|')) then
      begin
        pVersion:= Row.Version;
        Exit(True);
      end;
    if TryStrToInt(Tok, N) and (N >= MIN_TARGET_COMPILER) and (N <= MAX_TARGET_COMPILER) then
    begin
      pVersion:= N;
      Exit(True);
    end;
  end;
  pError:= Format('target-compiler: unknown version "%s" (%s)', [pToken, ACCEPTED_TOKENS_HINT]);
  Result:= False;
end;

function ProjectVersionToCompiler(const pProjectVersion: string; out pVersion: Integer): Boolean;
var
  Row: TProjectVersionRow;
begin
  pVersion:= 0;
  for Row in PROJECT_VERSIONS do
    if Row.ProjectVersion = Trim(pProjectVersion) then
    begin
      pVersion:= Row.Version;
      Exit(True);
    end;
  Result:= False;
end;

{ Reads the <ProjectVersion> element of a .dproj: the trimmed text, '' when the
  file is missing, unreadable or has none. A text scan -- the element is one line
  in every .dproj the IDE writes. Never raises. }
function ReadDprojProjectVersion(const pDproj: string): string;
var
  M: TMatch;
begin
  Result:= '';
  if (pDproj = '') or not TFile.Exists(pDproj) then Exit;
  try
    M:= TRegEx.Match(TFile.ReadAllText(pDproj), '<ProjectVersion>\s*([^<]*?)\s*</ProjectVersion>', [roIgnoreCase]);
    if M.Success then Result:= M.Groups[1].Value;
  except
    on E: Exception do Result:= '';  { unreadable .dproj: '' = unknown, the caller refuses }
  end;
end;

function CompilerDisplayName(pVersion: Integer): string;
var
  Row: TCompilerRow;
begin
  for Row in COMPILERS do
    if Row.Version = pVersion then Exit('Delphi ' + Row.Name);
  Result:= 'CompilerVersion ' + IntToStr(pVersion);
end;

function ResolveTargetCompiler(const pCmdLine, pConfigValue, pContextValue, pDprojPath: string;
  out pVersion: Integer; out pError: string): Boolean;
var
  Tok   : string;
  PV    : string;
  Source: string;
begin
  pVersion:= DEFAULT_TARGET_COMPILER;
  pError  := '';
  Tok:= pCmdLine;
  Source:= '--target-compiler';
  if Trim(Tok) = '' then
  begin
    Tok:= pConfigValue;
    Source:= 'config target_compiler';
  end;
  if Trim(Tok) = '' then
  begin
    Tok:= pContextValue;
    Source:= 'context targetCompiler';
  end;
  if Trim(Tok) = '' then Exit(True);
  if not SameText(Trim(Tok), TARGET_COMPILER_AUTO) then
  begin
    Result:= ParseCompilerToken(Tok, pVersion, pError);
    if not Result then pError:= pError + ' -- from ' + Source;
    Exit;
  end;
  if pDprojPath = '' then
  begin
    pError:= 'target-compiler: "auto" needs the owning .dproj -- pass --project <x.dproj>, or name a version';
    Exit(False);
  end;
  PV:= ReadDprojProjectVersion(pDprojPath);
  if not ProjectVersionToCompiler(PV, pVersion) then
  begin
    pVersion:= DEFAULT_TARGET_COMPILER;
    pError:= Format('target-compiler: "auto" cannot map ProjectVersion "%s" of %s to a compiler -- name a version instead',
      [PV, pDprojPath]);
    Exit(False);
  end;
  Result:= True;
end;

function IsGatedByTarget(pNeedsCompiler, pTarget: Integer): Boolean;
begin
  Result:= (pNeedsCompiler > 0) and (pTarget < pNeedsCompiler);
end;

function IsCompatOnForTarget(pCompatSince, pTarget: Integer): Boolean;
begin
  Result:= (pCompatSince > 0) and (pTarget < pCompatSince);
end;

function ActiveTargetCompiler: Integer;
begin
  Result:= GActiveTarget;
end;

procedure SetActiveTargetCompiler(pVersion: Integer);
begin
  GActiveTarget:= if pVersion > 0 then pVersion else DEFAULT_TARGET_COMPILER;
end;

{ TTargetRuleGate }

class function TTargetRuleGate.Build(pTarget: Integer; const pIds: TArray<string>;
  const pNeeds, pCompatSince: TArray<Integer>): TTargetRuleGate;
var
  I: Integer;
begin
  if (Length(pNeeds) <> Length(pIds)) or (Length(pCompatSince) <> Length(pIds)) then
    raise EArgumentException.Create('TTargetRuleGate.Build: the id / needs / compat_since arrays differ in length');
  Result:= Default(TTargetRuleGate);
  Result.Target:= pTarget;
  for I:= 0 to High(pIds) do
  begin
    if IsGatedByTarget(pNeeds[I], pTarget) then Result.Gated:= Result.Gated + [pIds[I]];
    if IsCompatOnForTarget(pCompatSince[I], pTarget) then Result.CompatOn:= Result.CompatOn + [pIds[I]];
  end;
end;

function TTargetRuleGate.Active: Boolean;
begin
  Result:= (Target <> 0) and (Target <> DEFAULT_TARGET_COMPILER);
end;

function TTargetRuleGate.Drops(const pRuleId: string): Boolean;
begin
  Result:= MatchText(pRuleId, Gated);
end;

function TTargetRuleGate.ForcesOn(const pRuleId: string): Boolean;
begin
  Result:= MatchText(pRuleId, CompatOn);
end;

end.
