unit DRagLint.Core.StudioEnv;

{ THE ONE PLACE THIS REPO IS ALLOWED TO NAME A RAD STUDIO PATH.

  WHY THIS UNIT EXISTS
  --------------------
  Eight sites across four units named the Studio installation, and they did not
  agree on how to find it. Three separate strategies were in the tree at once:
    * env only            -- CLI.pas, check-unit: $BDS or a literal
    * registry then fixed -- LSP.Proxy.pas: RootDir or a literal
    * literal only        -- CompileCheck.pas, and the $(BDS) macro expansion
  Four of the eight stored a path they could have COMPOSED -- bin\rsvars.bat is
  the root plus a known suffix, and storing it separately means a machine with
  Studio somewhere else got the right root and the wrong rsvars.

  So: one accessor, and every caller composes from it with TPath.Combine. A
  second Studio literal anywhere in this repo is a defect, and
  hardcoded-absolute-path is what catches it.

  WHICH STUDIO: THE PROJECT'S, NOT A PINNED ONE (2026-10-07)
  -----------------------------------------------------------
  Until 2026-10-07 every Studio path and registry key was pinned to 37.0
  (Delphi 13), and $BDS was the only way to point elsewhere. A Delphi 10.3
  project was therefore analysed with Delphi 13's Library path and IDE
  variables unless someone remembered an environment variable -- configuration
  living outside the project, which the owner ruled out.

  The Studio is now a TARGET, a BDS version such as '20.0', that the CLI sets
  once per run with SetBds before any project work:
    1. --delphi <bds>, when given;
    2. the project's own configuration, when it names one;
    3. the .dproj's <ProjectVersion>, through BdsOfProjectVersion (a value
       that fits two Delphis takes the only one installed, and says so);
    4. no project at all: the newest Studio installed on this machine.
  A project whose version cannot be mapped is an ERROR in the CLI, never a
  guess. $BDS is NOT read any more, by this unit or any other.

  RESOLUTION OF THE ROOT, AND WHY THE FALLBACK IS EXISTENCE-CHECKED
  ----------------------------------------------------------------
    1. HKCU\Software\Embarcadero\BDS\<bds>, value RootDir -- what the IDE itself
       writes at install time. Not existence-checked: it is an explicit
       statement by the installer.
    2. <Program Files (x86)>\Embarcadero\Studio\<bds>, ONLY IF THAT DIRECTORY
       EXISTS. The owner's ruling of 2026-09-02: an unconditional fallback turns
       "Studio is not installed" into a wrong path handed to dcc, which then
       fails with a message about units rather than about Studio. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when the target RAD Studio installation cannot be
  /// resolved.</summary>
  /// <remarks>The message names the target version and every source tried,
  /// so the person reading it can act on it.</remarks>
  EStudioNotFound = class(Exception);

  /// <summary>Resolves the TARGET RAD Studio installation and everything
  /// composed from it: root, registry key, rsvars.bat.</summary>
  /// <remarks>
  /// The target is process-wide state set once per run (SetBds). Everything
  /// else re-reads the registry on every call: cheap, never called in a loop,
  /// and a cached root would go stale across an install with no way to notice.
  /// </remarks>
  TStudioEnv = class
  strict private
    const
      /// <summary>Parent of every per-version registry key.</summary>
      REG_BDS = 'Software\Embarcadero\BDS';
      REG_VALUE = 'RootDir';
      /// <summary>The ONE Studio path literal in this repository: the parent of
      /// the per-version folders, used only as the existence-checked fallback.
      /// Every other Studio path is composed from TStudioEnv.Root.</summary>
      FALLBACK_PARENT = 'C:\Program Files (x86)\Embarcadero\Studio\'; // dl:ok hardcoded-absolute-path@a8ad -- the single fallback the owner ruled to keep, 2026-09-02; existence-checked before use, and the only Studio literal in the repo
      /// <summary>Target when nothing is installed and nothing was set: the one
      /// Studio this product was built against.</summary>
      DEFAULT_BDS = '37.0';
    class var
      FBds: string;
    /// <summary>HKCU RootDir of one BDS version, or '' if the key, the value or
    /// the read fails. Never raises.</summary>
    class function ReadRegistryRoot(const ABds: string): string; static;
    /// <summary>Trims and drops a trailing delimiter, so callers that
    /// concatenate cannot produce a doubled separator.</summary>
    class function NormalizeRoot(const ARoot: string): string; static;
    /// <summary>The rsvars.bat of a given root -- composed, never stored.</summary>
    class function RsvarsOf(const ARoot: string): string; static;
  public
    /// <summary>Sets the target BDS version for this run ('20.0', '37.0', ...).
    /// '' returns to the default: the newest installed.</summary>
    class procedure SetBds(const ABds: string); static;
    /// <summary>The target BDS version: the one set, else the newest installed,
    /// else '37.0'.</summary>
    class function Bds: string; static;
    /// <summary>The target's registry key, without a leading delimiter:
    /// Software\Embarcadero\BDS\&lt;bds&gt;. Library, Environment Variables and
    /// platforms live under it.</summary>
    class function RegBase: string; static;
    /// <summary>Every BDS version installed for this user (a key under
    /// HKCU\Software\Embarcadero\BDS with a RootDir), oldest first.</summary>
    class function InstalledBds: TArray<string>; static;
    /// <summary>Every BDS version a .dproj's &lt;ProjectVersion&gt; can belong to;
    /// empty when the value is not in the verified table.</summary>
    /// <remarks>
    /// ONLY VERIFIED RANGES. Each entry was seen in real projects of that
    /// Delphi on the reference machine (2026-10-07): 18.5-18.8 in the 10.3
    /// trees, 20.1-20.2 in the Delphi 12 tree, 20.4 in the Delphi 13 trees.
    /// 20.3 appears in BOTH the 12 and the 13 trees, so it has TWO candidates.
    /// </remarks>
    class function BdsCandidatesOfProjectVersion(const AProjectVersion: string): TArray<string>; static;
    /// <summary>The ONE BDS version for a &lt;ProjectVersion&gt;, or '' with the
    /// reason in AWhy.</summary>
    /// <remarks>
    /// One candidate: that one. Several (20.3): the single one installed on this
    /// machine, and AWhy says so; if none or more than one is installed, ''. No
    /// candidate: ''. A wrong Studio is worse than asking for --delphi.
    /// </remarks>
    class function BdsOfProjectVersion(const AProjectVersion: string; out AWhy: string): string; static;
    /// <summary>The &lt;ProjectVersion&gt; of a .dproj, or '' when the file or
    /// the element is missing. A .dpr is read through its sibling .dproj.</summary>
    class function ProjectVersionOf(const AProjectFile: string): string; static;
    /// <summary>Resolves the target's Studio root without raising.</summary>
    /// <param name="ARoot">The root with no trailing delimiter, or '' when the
    /// function returns False.</param>
    /// <param name="ADiagnostic">A message naming the target and every source
    /// tried, or '' on success. Suitable for printing verbatim.</param>
    /// <returns>True when a root was resolved.</returns>
    class function TryRoot(out ARoot: string; out ADiagnostic: string): Boolean; static;
    /// <summary>The target's Studio root, or '' when none resolves -- for the
    /// callers that legitimately degrade (a $(BDS) expansion whose path then
    /// fails its own existence check).</summary>
    class function RootOrEmpty: string; static;
    /// <summary>The target's Studio root.</summary>
    /// <exception cref="EStudioNotFound">No source resolves; the message names
    /// them.</exception>
    class function Root: string; static;
    /// <summary>&lt;Root&gt;\bin\rsvars.bat, composed, existence NOT checked (the
    /// caller hands it to cmd.exe, whose own failure names the file).</summary>
    class function RsvarsBat: string; static;
    /// <summary>Checks the parts of the contract a test can control without a
    /// real install: the version table, normalisation, the registry key and
    /// rsvars composition. Reached through `drag-lint selftest studio-root`
    /// (tests\autotest\run_studio_root_guard.ps1). Not thread-safe: it sets and
    /// restores the target.</summary>
    class function SelfTest(out AFailure: string): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math,
  System.Win.Registry,
  Winapi.Windows;

{ Orders two BDS version keys ('9.0', '20.0', '37.0') numerically, part by part;
  a part that is not a number sorts as 0, so a stray key cannot raise. }
function CompareValueOfVersion(const A, B: string): Integer;
var
  PA, PB: TArray<string>;
  I, NA, NB: Integer;
begin
  PA:= A.Split(['.']);
  PB:= B.Split(['.']);
  for I:= 0 to Max(Length(PA), Length(PB)) - 1 do
  begin
    NA:= 0;
    NB:= 0;
    if I < Length(PA) then NA:= StrToIntDef(PA[I], 0);
    if I < Length(PB) then NB:= StrToIntDef(PB[I], 0);
    if NA <> NB then Exit(NA - NB);
  end;
  Result:= 0;
end; // function

{ TStudioEnv }

class function TStudioEnv.ReadRegistryRoot(const ABds: string): string;
var
  Reg: TRegistry;
begin
  Result:= '';
  if ABds = '' then Exit;
  Reg:= TRegistry.Create(KEY_READ);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(REG_BDS + '\' + ABds) and Reg.ValueExists(REG_VALUE) then
        Result:= Trim(Reg.ReadString(REG_VALUE));
    except
      { A missing or unreadable key is not exceptional -- it is the expected
        state without that IDE, and the caller still has the fallback to try. }
      on E: Exception do Result:= '';
    end;
  finally
    Reg.Free;
  end;
end; // function

class function TStudioEnv.NormalizeRoot(const ARoot: string): string;
begin
  Result:= ExcludeTrailingPathDelimiter(Trim(ARoot));
end; // function

class function TStudioEnv.RsvarsOf(const ARoot: string): string;
begin
  Result:= TPath.Combine(ARoot, 'bin\rsvars.bat');
end; // function

class procedure TStudioEnv.SetBds(const ABds: string);
begin
  FBds:= Trim(ABds);
end; // procedure

class function TStudioEnv.Bds: string;
var
  Installed: TArray<string>;
begin
  if FBds <> '' then Exit(FBds);
  Installed:= InstalledBds;
  if Length(Installed) > 0 then Exit(Installed[High(Installed)]);
  Result:= DEFAULT_BDS;
end; // function

class function TStudioEnv.RegBase: string;
begin
  Result:= REG_BDS + '\' + Bds;
end; // function

class function TStudioEnv.InstalledBds: TArray<string>;
var
  Reg  : TRegistry;
  Names: TStringList;
  List : TList<string>;
  N    : string;
begin
  Result:= nil;
  List:= TList<string>.Create;
  Names:= TStringList.Create;
  Reg:= TRegistry.Create(KEY_READ);
  try
    { No Embarcadero key at all is not an error: OpenKeyReadOnly returns False
      and nothing is installed. }
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_BDS) then
    begin
      Reg.GetKeyNames(Names);
      Reg.CloseKey;
    end;
    for N in Names do
      if ReadRegistryRoot(N) <> '' then List.Add(N);
    { Numeric order, so '9.0' sorts before '37.0'. }
    List.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result:= CompareValueOfVersion(A, B);
      end));
    Result:= List.ToArray;
  finally
    Reg.Free;
    Names.Free;
    List.Free;
  end;
end; // function

class function TStudioEnv.BdsCandidatesOfProjectVersion(const AProjectVersion: string): TArray<string>;
var
  V: string;
begin
  V:= Trim(AProjectVersion);
  if (V = '18.5') or (V = '18.6') or (V = '18.7') or (V = '18.8') then
    Result:= TArray<string>.Create('20.0')          { Delphi 10.3 Rio }
  else if (V = '20.1') or (V = '20.2') then
    Result:= TArray<string>.Create('23.0')          { Delphi 12 Athens }
  else if V = '20.3' then
    Result:= TArray<string>.Create('23.0', '37.0')  { Delphi 12.3 or 13: both seen }
  else if V = '20.4' then
    Result:= TArray<string>.Create('37.0')          { Delphi 13 Florence }
  else
    Result:= nil;
end; // function

class function TStudioEnv.BdsOfProjectVersion(const AProjectVersion: string; out AWhy: string): string;
var
  Cands    : TArray<string>;
  Installed: TArray<string>;
  HitCount : Integer;
  HitBds   : string;
  C, I     : string;
begin
  Result:= '';
  AWhy:= '';
  Cands:= BdsCandidatesOfProjectVersion(AProjectVersion);
  if Length(Cands) = 0 then
  begin
    AWhy:= 'ProjectVersion ' + Trim(AProjectVersion) + ' is not in the verified table';
    Exit;
  end;
  if Length(Cands) = 1 then Exit(Cands[0]);
  Installed:= InstalledBds;
  HitCount:= 0;
  HitBds:= '';
  for C in Cands do
    for I in Installed do
      if C = I then
      begin
        Inc(HitCount);
        HitBds:= C;
      end;
  if HitCount = 1 then
  begin
    AWhy:= 'ProjectVersion ' + Trim(AProjectVersion) + ' fits BDS ' + string.Join(' or ', Cands) +
           '; only ' + HitBds + ' is installed';
    Exit(HitBds);
  end;
  if HitCount = 0 then
    AWhy:= 'ProjectVersion ' + Trim(AProjectVersion) + ' fits BDS ' + string.Join(' or ', Cands) + ', and neither is installed'
  else
    AWhy:= 'ProjectVersion ' + Trim(AProjectVersion) + ' fits BDS ' + string.Join(' or ', Cands) + ', and both are installed';
end; // function

class function TStudioEnv.ProjectVersionOf(const AProjectFile: string): string;
var
  Dproj: string;
  M    : TMatch;
begin
  Result:= '';
  Dproj:= AProjectFile;
  if SameText(ExtractFileExt(Dproj), '.dpr') or SameText(ExtractFileExt(Dproj), '.dpk') then
    Dproj:= ChangeFileExt(Dproj, '.dproj');
  if not TFile.Exists(Dproj) then Exit;
  try
    M:= TRegEx.Match(TFile.ReadAllText(Dproj), '<ProjectVersion>\s*([^<\s]+)\s*</ProjectVersion>', [roIgnoreCase]);
    if M.Success then Result:= M.Groups[1].Value;
  except
    on E: Exception do Result:= ''; { unreadable .dproj: the caller reports "no version" }
  end;
end; // function

class function TStudioEnv.TryRoot(out ARoot: string; out ADiagnostic: string): Boolean;
var
  Target  : string;
  Fallback: string;
begin
  ADiagnostic:= '';
  Target:= Bds;
  ARoot:= NormalizeRoot(ReadRegistryRoot(Target));
  if ARoot = '' then
  begin
    Fallback:= TPath.Combine(FALLBACK_PARENT, Target);
    if TDirectory.Exists(Fallback) then ARoot:= Fallback;
  end;
  if ARoot <> '' then Exit(True);

  ADiagnostic:= 'RAD Studio ' + Target + ' not found. Looked at HKCU\' + REG_BDS + '\' +
                Target + '\' + REG_VALUE + ', then ' + TPath.Combine(FALLBACK_PARENT, Target) +
                ' (which does not exist). Install that Delphi, or name an installed one with ' +
                '--delphi <bds>.';
  Result:= False;
end; // function

class function TStudioEnv.RootOrEmpty: string;
var
  Diagnostic: string;
begin
  if not TryRoot(Result, Diagnostic) then Result:= '';
end; // function

class function TStudioEnv.Root: string;
var
  Diagnostic: string;
begin
  if not TryRoot(Result, Diagnostic) then raise EStudioNotFound.Create(Diagnostic);
end; // function

class function TStudioEnv.RsvarsBat: string;
begin
  Result:= RsvarsOf(Root);
end; // function

class function TStudioEnv.SelfTest(out AFailure: string): Boolean;
const
  { A path that cannot exist, so a machine's real Studio can never make a
    failing assertion pass by coincidence. }
  PROBE = 'C:\SelfTestStudio';  // dl:ok hardcoded-absolute-path@73e1 -- a deliberately non-existent probe root, so a real Studio install cannot make a failing assertion pass by coincidence
var
  Saved: string;
  Why  : string;

  function Expect(const ADesc, AActual, AExpected: string): Boolean;
  begin
    Result:= AActual = AExpected;
    if not Result then
      AFailure:= ADesc + ' -- got "' + AActual + '", expected "' + AExpected + '"';
  end;

begin
  AFailure:= '';
  if not Expect('ProjectVersion 18.8 is Delphi 10.3', string.Join(',', BdsCandidatesOfProjectVersion('18.8')), '20.0') then Exit(False);
  if not Expect('ProjectVersion 18.5 is Delphi 10.3', string.Join(',', BdsCandidatesOfProjectVersion(' 18.5 ')), '20.0') then Exit(False);
  if not Expect('ProjectVersion 20.4 is Delphi 13', string.Join(',', BdsCandidatesOfProjectVersion('20.4')), '37.0') then Exit(False);
  if not Expect('ProjectVersion 20.3 is Delphi 12.3 or 13', string.Join(',', BdsCandidatesOfProjectVersion('20.3')), '23.0,37.0') then Exit(False);
  if not Expect('an unknown ProjectVersion has no candidate', string.Join(',', BdsCandidatesOfProjectVersion('99.9')), '') then Exit(False);
  if not Expect('an unknown ProjectVersion maps to nothing', BdsOfProjectVersion('99.9', Why), '') then Exit(False);

  if not Expect('a trailing delimiter is stripped', NormalizeRoot(PROBE + '\'), PROBE) then Exit(False);
  if not Expect('surrounding whitespace is trimmed', NormalizeRoot('  ' + PROBE + '  '), PROBE) then Exit(False);
  if not Expect('rsvars.bat is composed from the root, not stored separately',
                RsvarsOf(PROBE), PROBE + '\bin\rsvars.bat') then Exit(False);

  Saved:= FBds;
  try
    SetBds(' 20.0 ');
    if not Expect('SetBds trims and wins', Bds, '20.0') then Exit(False);
    if not Expect('RegBase follows the target', RegBase, 'Software\Embarcadero\BDS\20.0') then Exit(False);
  finally
    FBds:= Saved;
  end;

  Result:= True;
end; // function

end.
