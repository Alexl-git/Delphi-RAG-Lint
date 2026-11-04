unit DRagLint.Project.TargetStudio;

{ WHICH STUDIO'S LIBRARY PATH A PROJECT IS READ AGAINST (GH #13, Jonathas Paiva's
  report). Since 1.39 the index preprocesses for the Delphi the .dproj targets, but
  the library path, platform list, IDE Environment Variables and $(BDS) stayed on
  37.0, so a 10.3 project lost every unit only 10.3's path names: 61 of them on the
  measured project, with fewer callers and no warning.

  ONE MAPPING. BdsKeyOfCompilerVersion inverts CompilerVersionOfStudioRoot by
  asking it, so the BDS offset stays in Preprocess.Profile alone.

  WHY THE TAIL IS NOT IN TClosureResolver. Reading the right key is not enough: the
  closure only ever used library paths to EXCLUDE, so a unit on a path and on no
  project search path stayed unreachable under any key. Searching the path belongs
  in TClosureResolver, but src\index is extractor-hashed and no bump is allowed in
  1.42 wave 2 (ledger NEXT-BUMP: GH13-CLOSURE-TAIL). So ResolveTargetClosure asks
  the same resolver a second question about a shadow project; there is one closure
  walk, one uses scanner and one preprocess path. }

interface

uses
  DRagLint.Index.Closure
  , DRagLint.Project.Resolver  // dl:ok uses-global-census@d4b1 -- REVIEWED 2026-11-04: DEFAULT_BDS_KEY belongs with the resolver this unit opens per key
  ;

type
  /// <summary>The Studio key one project's library paths come from, and how that
  /// choice was made.</summary>
  TTargetStudio = record
    /// <summary>The key the target asks for; '' when nothing names a target, or
    /// the target has no BDS key the mapping knows.</summary>
    RequestedBds: string;
    /// <summary>The key actually read; never ''.</summary>
    UsedBds: string;
    /// <summary>'Delphi 10.3' for a named target, else ''.</summary>
    TargetName: string;
    /// <summary>One line naming requested and used when the target could not be
    /// honoured; '' otherwise.</summary>
    Note: string;
    /// <summary>True when the key read is not the default Studio's.</summary>
    /// <returns>UsedBds differs from DEFAULT_BDS_KEY.</returns>
    function IsForeign: Boolean;
    /// <summary>A resolver over the key read.</summary>
    /// <returns>The caller owns it.</returns>
    function OpenResolver: TProjectResolver;
    /// <summary>The line `index` prints for a foreign key.</summary>
    /// <returns>'Library path: BDS 20.0 (target Delphi 10.3)'; '' on the default.</returns>
    function SummaryLine: string;
  end;

/// <summary>Records the run's --target-compiler for ResolveTargetStudio.</summary>
/// <param name="pTargetArg">The raw value; '' when absent.</param>
/// <remarks>Set once at start-up, before any verb. A --jobs child receives the same
/// flag on its command line, so its value matches its parent's.</remarks>
procedure SetRunTargetCompilerArg(const pTargetArg: string);

/// <summary>Chooses the Studio key for a project, with the precedence of the
/// defines: --target-compiler, then the .dproj's ProjectVersion, then the default.</summary>
/// <param name="pProjectFile">The project; only a .dproj carries a ProjectVersion.
/// '' or anything else takes the default unless --target-compiler names a version.</param>
/// <returns>The choice. Falls back to the default with a Note when the target's key
/// is not installed.</returns>
/// <remarks>An absent or unmappable ProjectVersion is SILENT, as the defines are: that
/// project has no target, so nothing was not honoured. Reads the .dproj and the
/// registry; never raises for a missing file.</remarks>
function ResolveTargetStudio(const pProjectFile: string): TTargetStudio;

/// <summary>A project's compile closure with the library tail searched after the
/// project's own folders, as dcc does.</summary>
/// <param name="pClosure">Configured with library roots and profile. Not owned.</param>
/// <param name="pProjectFile">The .dproj, .dpr or .dpk.</param>
/// <param name="pExclude">Exclude globs, as TClosureResolver.Resolve takes them.</param>
/// <param name="pTail">TProjectResolver.ClosureSearchTail; nil for the plain closure.</param>
/// <returns>TClosureResolver.Resolve's result, plus every unit (and its includes)
/// reachable through the tail, appended in discovery order.</returns>
/// <exception cref="Exception">As TClosureResolver.Resolve when the project file
/// does not exist.</exception>
/// <remarks>Nil tail: a plain Resolve, nothing else runs. Otherwise writes and removes
/// a shadow project under the temp folder; the project's own folder is untouched.</remarks>
function ResolveTargetClosure(pClosure: TClosureResolver; const pProjectFile: string;
  const pExclude, pTail: TArray<string>): TClosureResult;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , System.Classes
  , System.RegularExpressions
  , System.Generics.Collections
  , DRagLint.Lint.TargetCompiler  // dl:ok uses-global-census@d7c5 -- REVIEWED 2026-11-04: TARGET_COMPILER_AUTO is the token of the resolver call this unit makes
  , DRagLint.Preprocess.Profile
  ;

const
  { CompilerVersionOfStudioRoot reads a folder's leaf; any parent does. }
  PROBE_PARENT = 'x\';
  KEY_SUFFIX = '.0';
  FIRST_MAPPED_BDS = 14;

var
  GRunTargetArg: string;

function TTargetStudio.IsForeign: Boolean;
begin
  Result:= not SameText(UsedBds, DEFAULT_BDS_KEY);
end;

function TTargetStudio.OpenResolver: TProjectResolver;
begin
  Result:= TProjectResolver.CreateForStudio(UsedBds);
end;

function TTargetStudio.SummaryLine: string;
begin
  Result:= if IsForeign then Format('Library path: BDS %s (target %s)', [UsedBds, TargetName]) else '';
end;

{ The inverse of CompilerVersionOfStudioRoot: 33 -> '20.0'; '' when that mapping has none (XE5 and older). }
function BdsKeyOfCompilerVersion(pCompilerVersion: Integer): string;
begin
  for var Bds: Integer:= FIRST_MAPPED_BDS to pCompilerVersion do
    if CompilerVersionOfStudioRoot(PROBE_PARENT + IntToStr(Bds) + KEY_SUFFIX) = pCompilerVersion then
      Exit(IntToStr(Bds) + KEY_SUFFIX);
  Result:= '';
end;

procedure SetRunTargetCompilerArg(const pTargetArg: string);
begin
  GRunTargetArg:= Trim(pTargetArg);
end;

function ResolveTargetStudio(const pProjectFile: string): TTargetStudio;
var
  Tok    : string ;
  Version: Integer;
  Err    : string ;
begin
  Result:= Default(TTargetStudio);
  Result.UsedBds:= DEFAULT_BDS_KEY;
  Tok:= GRunTargetArg;
  if (Tok = '') and SameText(ExtractFileExt(pProjectFile), '.dproj') then Tok:= TARGET_COMPILER_AUTO;
  if Tok = '' then Exit;
  if not ResolveTargetCompiler(Tok, '', '', pProjectFile, Version, Err) then Exit;

  Result.TargetName:= CompilerDisplayName(Version);
  Result.RequestedBds:= BdsKeyOfCompilerVersion(Version);
  if Result.RequestedBds = '' then
    Result.Note:= Format('note: library path: target %s has no BDS key this engine can map; using BDS %s',
      [Result.TargetName, DEFAULT_BDS_KEY])
  else if IsBdsStudioInstalled(Result.RequestedBds) then Result.UsedBds:= Result.RequestedBds
  else if not SameText(Result.RequestedBds, DEFAULT_BDS_KEY) then
    Result.Note:= Format('note: library path: target %s wants BDS %s, which is not installed here; using BDS %s',
      [Result.TargetName, Result.RequestedBds, DEFAULT_BDS_KEY]);
end;

{ The project's main source with every relative `in '...'` made absolute, so a
  unit named that way is not found again under another folder by name. }
function ShadowMainSource(const pSource: string): string;
var
  BaseDir: string;
  Matches: TMatchCollection;
begin
  Result:= TFile.ReadAllText(pSource);
  BaseDir:= ExtractFilePath(pSource);
  Matches:= TRegEx.Matches(Result, '\bin\s+''([^'']+)''', [roIgnoreCase]);
  for var Idx: Integer:= Matches.Count - 1 downto 0 do
  begin
    var Group: TGroup:= Matches[Idx].Groups[1];
    if not TPath.IsPathRooted(Group.Value) then
      Result:= Copy(Result, 1, Group.Index - 1) + TPath.Combine(BaseDir, Group.Value) +
        Copy(Result, Group.Index + Group.Length, MaxInt);
  end;
end;

function ResolveTargetClosure(pClosure: TClosureResolver; const pProjectFile: string;
  const pExclude, pTail: TArray<string>): TClosureResult;
const
  SHADOW_NAME = 'shadow';
  MAIN_SOURCE_EXTS: array[0..1] of string = ('.dpr', '.dpk');
var
  ShadowDir: string;
  Dproj    : TStringBuilder;
  Shadow   : TClosureResult;
  Seen     : TDictionary<string, Boolean>;
begin
  Result:= pClosure.Resolve(pProjectFile, pExclude);
  if Length(pTail) = 0 then Exit;

  Result.SearchPaths:= Result.SearchPaths + pTail;
  ShadowDir:= TPath.Combine(TPath.GetTempPath, 'dl-closure-tail-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(ShadowDir);
  Dproj:= TStringBuilder.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    Dproj.Append('<Project><PropertyGroup><DCC_UnitSearchPath>')
      .Append(string.Join(';', Result.SearchPaths))
      .Append('</DCC_UnitSearchPath></PropertyGroup><ItemGroup>');
    for var F: string in Result.Files do
    begin
      Seen.AddOrSetValue(LowerCase(F), True);
      if SameText(ExtractFileExt(F), '.pas') then Dproj.Append('<DCCReference Include="').Append(F).Append('"/>');
    end;
    Dproj.Append('</ItemGroup></Project>');
    TFile.WriteAllText(TPath.Combine(ShadowDir, SHADOW_NAME + '.dproj'), Dproj.ToString);
    { The main source is seeded too: its own `uses` may name a library-only unit. }
    for var Ext: string in MAIN_SOURCE_EXTS do
    begin
      var MainSource: string:= ChangeFileExt(TPath.GetFullPath(pProjectFile), Ext);
      if TFile.Exists(MainSource) then
      begin
        TFile.WriteAllText(TPath.Combine(ShadowDir, SHADOW_NAME + Ext), ShadowMainSource(MainSource));
        Break;
      end;
    end;

    Shadow:= pClosure.Resolve(TPath.Combine(ShadowDir, SHADOW_NAME + '.dproj'), pExclude);
    for var I: Integer:= 0 to High(Shadow.Files) do
      if not Seen.ContainsKey(LowerCase(Shadow.Files[I])) then
      begin
        Result.Files:= Result.Files + [Shadow.Files[I]];
        Result.UsedBy:= Result.UsedBy + [Shadow.UsedBy[I]];
      end;
    for var W: string in Shadow.Warnings do
      if not MatchStr(W, Result.Warnings) then Result.Warnings:= Result.Warnings + [W];
  finally
    Seen.Free;
    Dproj.Free;
    TDirectory.Delete(ShadowDir, True);
  end;
end;

end.
