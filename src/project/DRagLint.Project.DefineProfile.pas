unit DRagLint.Project.DefineProfile;

// Per-file define profiles: which .dproj owns a source file, what that
// project's ACTIVE build is (config + platform), and the TDefineProfile the
// preprocessor must use for it. OUTSIDE the extractor hash surface on purpose
// (run_extractor_version_guard.ps1): the index side consumes this through
// CLI.ResolveIndexProfile and bills a profile change through the cfg=/defs=
// fingerprint limbs, never through DRAGLINT_EXTRACTOR_VERSION.
//
// PRECEDENCE (decisions D1 / D2 / D4 of plans\2026-10-26-lsp-c10-a7-per-file-
// defines.md) lives in ResolveActiveBuild and DprojForFileWith ONLY; nothing else in
// the tree re-implements an order. D1 (owner ruling 2026-10-26): the .dproj
// (active-config marker + ProfileFromDproj) FIRST, then <base>.delphilsp.json, then
// the platform built-ins. To flip D1, change the ONE condition marked "D1" in
// ResolveActiveBuild. Intended use: an auto-discovered --project (the owning .dproj
// found through DB membership); an explicit --project still wins (D3).
//
// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM. Comments use
// // exclusively.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Preprocess.Types;

type
  /// <summary>Where a resolved profile's define SET came from.</summary>
  TDefineSource = (dsBuiltins, dsDproj, dsDelphiLsp);

  /// <summary>One project's active build as the resolver saw it.</summary>
  TActiveBuild = record
    /// <summary>The owning .dproj; '' = no owning project (built-ins).</summary>
    Dproj   : string;
    /// <summary>'Win32' or 'Win64' (resolved, never '').</summary>
    Platform: string;
    /// <summary>'Debug', 'Release', a custom name, or '' for built-ins.</summary>
    Config  : string;
    /// <summary>Where the define set came from.</summary>
    Source  : TDefineSource;
    /// <summary>Lowercased, deduped defines, platform built-ins included.</summary>
    Profile : TDefineProfile;
    /// <summary>8 lowercase hex of SHA1 over the sorted lowercased Defines joined
    /// by ';' -- lane INC2: then '#' and the sorted effective 'name=value' numerics and
    /// '$x+' / '$x-' switch states -- so a value or switch change re-parses; '' for
    /// built-ins.</summary>
    Digest  : string;
    /// <summary>Human-readable remarks, e.g. 'config marker absent -> Release'.</summary>
    Notes   : TArray<string>;
  end;

/// <summary>Reads the IDE's last active selection from a .dproj:
/// &lt;Config Condition="'$(Config)'==''"&gt;X&lt;/Config&gt; and the Platform twin.</summary>
/// <param name="ADproj">Path of the .dproj.</param>
/// <param name="APlatform">Receives the Platform marker, '' when absent.</param>
/// <param name="AConfig">Receives the Config marker, '' when absent.</param>
/// <returns>True when at least one marker was found.</returns>
/// <remarks>Pure over the file text; never raises (unreadable -> False).</remarks>
function ReadDprojActiveSelection(const ADproj: string; out APlatform, AConfig: string): Boolean;

/// <summary>Reads &lt;base&gt;.delphilsp.json beside ADproj: the -D tokens of
/// settings.dccOptions (split on spaces outside double quotes; each -D value split
/// on ';', empties dropped, lowercased) and the platform from settings.dllname
/// ('dcc32*' -> Win32, 'dcc64*' -> Win64). Lane INC2: a valued token (-DDEBUG2=3)
/// defines its NAME and adds the integer value to ANumeric; a -$X+ / -$X- switch
/// option lands in ASwitches.</summary>
/// <param name="ADproj">Path of the .dproj; the JSON is its sibling.</param>
/// <param name="APlatform">Receives 'Win32' or 'Win64'.</param>
/// <param name="ADefines">Receives the lowercased -D symbols (deduped, without values).</param>
/// <param name="ANumeric">Receives lowercased name / integer value of each valued -D token.</param>
/// <param name="ASwitches">Receives lowercased letter / on of each -$ switch option, in order.</param>
/// <returns>True when the file exists, parses and names a dcc32/dcc64 dllname;
/// False otherwise (ADefines nil).</returns>
/// <remarks>Never raises.</remarks>
function ReadDelphiLspDefines(const ADproj: string; out APlatform: string; out ADefines: TArray<string>;
  out ANumeric: TArray<TPair<string, Integer>>; out ASwitches: TArray<TPair<string, Boolean>>): Boolean;

/// <summary>The active build of one project. Platform = APlatformOverride, else
/// the .dproj marker, else delphilsp.json dllname, else 'Win64'. Config =
/// AConfigOverride, else the .dproj marker, else 'Release'. Defines (D1, .dproj
/// FIRST) = ProfileFromDproj(ADproj, platform, config) whenever the .dproj is
/// readable and carries a Config marker; only when it is unreadable or has no
/// Config marker AND AUseDelphiLsp AND delphilsp.json is usable with a matching
/// platform are its -D tokens used instead. PlatformBuiltins are always unioned in.</summary>
/// <param name="ADproj">'' -> built-ins only (Source = dsBuiltins).</param>
/// <param name="APlatformOverride">'' = none.</param>
/// <param name="AConfigOverride">'' = none.</param>
/// <param name="AUseDelphiLsp">True = delphilsp.json may serve when the .dproj cannot (D1).</param>
/// <returns>The resolved build.</returns>
/// <remarks>Never raises. Pure apart from reading the two files.</remarks>
function ResolveActiveBuild(const ADproj, APlatformOverride, AConfigOverride: string;
  AUseDelphiLsp: Boolean): TActiveBuild;

type
  /// <summary>Process-wide memo: file -> .dproj and .dproj -> TActiveBuild,
  /// invalidated by the last-write time + size of the .dproj AND of its
  /// delphilsp.json (an absent file is a stamp of its own), re-checked on EVERY
  /// build lookup (no timer).</summary>
  /// <remarks>Thread-safe: one critical section guards both maps (the merge proxy
  /// lints on a worker thread). The fallback is the profile installed with
  /// Configure, byte-identical to the pre-C10 behaviour, so a loose file never
  /// changes treatment. The file -> .dproj memo is dropped by Forget / Clear; a
  /// .dproj created later for an already-looked-up file is seen after Forget.</remarks>
  TProjectProfileCache = class
  public
    /// <summary>Installs the lookup context and drops every memo.</summary>
    /// <param name="ADbPaths">DBs for ownership probes; may be empty.</param>
    /// <param name="AActiveProject">The explicit --project or ''.</param>
    /// <param name="APlatformOverride">An explicit --platform or ''.</param>
    /// <param name="AConfigOverride">An explicit config or ''.</param>
    /// <param name="AFallback">Profile for files no .dproj owns.</param>
    /// <param name="AUseDelphiLsp">D1: delphilsp.json is consulted only after the .dproj.</param>
    class procedure Configure(const ADbPaths: TArray<string>; const AActiveProject, APlatformOverride,
      AConfigOverride: string; const AFallback: TDefineProfile; AUseDelphiLsp: Boolean);
    /// <summary>The active build for AFile; Dproj = '' means the fallback.</summary>
    /// <param name="AFile">Source path.</param>
    /// <returns>The build (never raises).</returns>
    class function BuildForFile(const AFile: string): TActiveBuild;
    /// <summary>= BuildForFile(AFile).Profile.</summary>
    /// <param name="AFile">Source path.</param>
    /// <returns>The define profile.</returns>
    class function ProfileForFile(const AFile: string): TDefineProfile;
    /// <summary>Drops the file -> .dproj memo for AFile.</summary>
    /// <param name="AFile">Source path.</param>
    class procedure Forget(const AFile: string);
    /// <summary>Drops every memo (the context stays).</summary>
    class procedure Clear;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Hash,
  System.RegularExpressions,
  System.SyncObjs,
  DRagLint.Preprocess.Profile,
  DRagLint.Index.Manifest,
  DRagLint.Project.OwnRoots,
  DRagLint.Storage.FileMembership;

const
  DEFAULT_CONFIG   = 'Release';
  DEFAULT_PLATFORM = 'Win64';
  DIGEST_LEN       = 8;
  CONFIG_MARKER    = '<Config\s+Condition="''\$\(Config\)''==''''"\s*>\s*([^<]+?)\s*</Config>';
  PLATFORM_MARKER  = '<Platform\s+Condition="''\$\(Platform\)''==''''"\s*>\s*([^<]+?)\s*</Platform>';
  DEFINE_SWITCH    = '-D';
  DEFINE_SWITCH_LEN = 2;
  SWITCH_OPTION    = '-$'; // a dcc switch option: -$R+
  SWITCH_OPTION_LEN = 4;

function NormPlatform(const APlatform: string): string;
begin
  if SameText(APlatform, 'Win32') then Result := 'Win32' else Result := DEFAULT_PLATFORM;
end;

function ReadTextSafe(const APath: string): string;
begin
  Result := '';
  try
    if (APath <> '') and TFile.Exists(APath) then Result := TFile.ReadAllText(APath);
  except // dl:ok bare-except@86a2 -- REVIEWED 2026-10-26 fail-open by contract: a resolver fault falls back to the pre-C10 profile, never raises
    Result := '';
  end;
end;

function FirstGroup(const AText, APattern: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(AText, APattern, [roIgnoreCase]);
  if M.Success then Result := Trim(M.Groups[1].Value) else Result := '';
end;

function ReadDprojActiveSelection(const ADproj: string; out APlatform, AConfig: string): Boolean;
var
  Text: string;
begin
  Text := ReadTextSafe(ADproj);
  APlatform := FirstGroup(Text, PLATFORM_MARKER);
  AConfig   := FirstGroup(Text, CONFIG_MARKER);
  Result := (APlatform <> '') or (AConfig <> '');
end;

// dccOptions -> tokens, split on spaces outside double quotes.
function SplitOptions(const AOptions: string): TArray<string>;
var
  Cur  : string;
  InQ  : Boolean;
  Ch   : Char;
  List : TList<string>;
begin
  List := TList<string>.Create;
  try
    Cur := '';
    InQ := False;
    for Ch in AOptions do
      if Ch = '"' then
      begin
        InQ := not InQ;
        Cur := Cur + Ch; // dl:ok concat-in-loop@32c6 -- REVIEWED 2026-10-26 dccOptions tokens are short (<256 chars)
      end
      else if (Ch = ' ') and not InQ then
      begin
        if Cur <> '' then List.Add(Cur);
        Cur := '';
      end
      else
        Cur := Cur + Ch; // dl:ok concat-in-loop@32c6 -- REVIEWED 2026-10-26 dccOptions tokens are short (<256 chars)
    if Cur <> '' then List.Add(Cur);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ReadDelphiLspDefines(const ADproj: string; out APlatform: string; out ADefines: TArray<string>;
  out ANumeric: TArray<TPair<string, Integer>>; out ASwitches: TArray<TPair<string, Boolean>>): Boolean;
var
  Json    : TJSONValue;
  Settings: TJSONValue;
  DllName : string;
  Options : string;
  Tok     : string;
  Part    : string;
  Sym     : string;
  Val     : string;
  Num     : Integer;
  Seen    : TDictionary<string, Byte>;
  List    : TList<string>;
begin
  Result := False;
  APlatform := '';
  ADefines := nil;
  ANumeric := nil;
  ASwitches := nil;
  try
    Json := TJSONObject.ParseJSONValue(ReadTextSafe(ChangeFileExt(ADproj, '.delphilsp.json')));
    if Json = nil then Exit;
    try
      Settings := Json.FindValue('settings');
      if Settings = nil then Exit;
      if not Settings.TryGetValue<string>('dllname', DllName) then Exit;
      DllName := LowerCase(ExtractFileName(DllName));
      if DllName.StartsWith('dcc32') then APlatform := 'Win32'
      else if DllName.StartsWith('dcc64') then APlatform := 'Win64'
      else Exit;
      if not Settings.TryGetValue<string>('dccOptions', Options) then Options := '';
      Seen := TDictionary<string, Byte>.Create;
      List := TList<string>.Create;
      try
        for Tok in SplitOptions(Options) do
        begin
          // Lane INC2: -$R+ / -$O- set a compiler switch.
          if (Length(Tok) = SWITCH_OPTION_LEN) and Tok.StartsWith(SWITCH_OPTION) and CharInSet(Tok[SWITCH_OPTION_LEN], ['+', '-']) then
          begin
            ASwitches := ASwitches + [TPair<string, Boolean>.Create(LowerCase(Tok[SWITCH_OPTION_LEN - 1]), Tok[SWITCH_OPTION_LEN] = '+')];
            Continue;
          end;
          if not Tok.StartsWith(DEFINE_SWITCH) then Continue;
          for Part in Copy(Tok, DEFINE_SWITCH_LEN + 1, MaxInt).Split([';']) do
          begin
            // Lane INC2: -DDEBUG2=3 defines DEBUG2 with the value 3.
            if SplitDefineToken(Part, Sym, Val) and TryStrToInt(Val, Num) then
              ANumeric := ANumeric + [TPair<string, Integer>.Create(LowerCase(Sym), Num)];
            Sym := LowerCase(Sym);
            if (Sym = '') or Seen.ContainsKey(Sym) then Continue;
            Seen.Add(Sym, 0);
            List.Add(Sym);
          end;
        end;
        ADefines := List.ToArray;
      finally
        List.Free;
        Seen.Free;
      end;
      Result := True;
    finally
      Json.Free;
    end;
  except // dl:ok bare-except@e286 -- REVIEWED 2026-10-26 fail-open by contract: a resolver fault falls back to the pre-C10 profile, never raises
    Result := False;
    APlatform := '';
    ADefines := nil;
    ANumeric := nil;
    ASwitches := nil;
  end;
end;

// The digest the indexer fingerprint bills (cfg=/defs= limb). Lane INC2: the
// EFFECTIVE values (last pair per name wins) and switch states are part of it,
// so DEBUG2=3 -> DEBUG2=4 or a DCC_RangeChecking flip re-parses the project.
function DigestOf(const AProfile: TDefineProfile): string;
var
  Sorted : TArray<string>;
  Nums   : TDictionary<string, Integer>;
  Sws    : TDictionary<string, Boolean>;
  Extra  : TArray<string>;
  N      : TPair<string, Integer>;
  S      : TPair<string, Boolean>;
begin
  Sorted := Copy(AProfile.Defines, 0, Length(AProfile.Defines));
  TArray.Sort<string>(Sorted);
  Extra := nil;
  Nums := TDictionary<string, Integer>.Create;
  Sws  := TDictionary<string, Boolean>.Create;
  try
    for N in AProfile.NumericDefines do Nums.AddOrSetValue(LowerCase(N.Key), N.Value);
    for S in AProfile.Switches do Sws.AddOrSetValue(LowerCase(S.Key), S.Value);
    for N in Nums do Extra := Extra + [Format('%s=%d', [N.Key, N.Value])];
    for S in Sws do Extra := Extra + ['$' + S.Key + (if S.Value then '+' else '-')];
  finally
    Sws.Free;
    Nums.Free;
  end;
  TArray.Sort<string>(Extra);
  if Length(Extra) > 0 then Sorted := Sorted + ['#'] + Extra;
  Result := Copy(THashSHA1.GetHashString(string.Join(';', Sorted)), 1, DIGEST_LEN).ToLower;
end;

// Builtins union Extra, lowercased, deduped, in first-seen order.
function UnionWithBuiltins(const APlatform: string; const AExtra: TArray<string>): TArray<string>;
var
  Seen: TDictionary<string, Byte>;
  List: TList<string>;
  Sym : string;
begin
  Seen := TDictionary<string, Byte>.Create;
  List := TList<string>.Create;
  try
    for Sym in PlatformBuiltins(APlatform) do
      if not Seen.ContainsKey(Sym) then
      begin
        Seen.Add(Sym, 0);
        List.Add(Sym);
      end;
    for Sym in AExtra do
      if not Seen.ContainsKey(LowerCase(Sym)) then
      begin
        Seen.Add(LowerCase(Sym), 0);
        List.Add(LowerCase(Sym));
      end;
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

function ResolveActiveBuild(const ADproj, APlatformOverride, AConfigOverride: string;
  AUseDelphiLsp: Boolean): TActiveBuild;
var
  MarkPlat, MarkCfg: string;
  LspPlat : string;
  LspDefs : TArray<string>;
  LspNums : TArray<TPair<string, Integer>>;
  LspSws  : TArray<TPair<string, Boolean>>;
  HaveLsp : Boolean;
  Notes   : TList<string>;
begin
  Result := Default(TActiveBuild);
  Result.Profile.NumericDefines := nil;
  if ADproj = '' then
  begin
    Result.Platform := NormPlatform(APlatformOverride);
    Result.Source   := dsBuiltins;
    Result.Profile := BuiltinsProfile(Result.Platform);
    Exit;
  end;
  Notes := TList<string>.Create;
  try
    Result.Dproj := ADproj;
    ReadDprojActiveSelection(ADproj, MarkPlat, MarkCfg);
    HaveLsp := ReadDelphiLspDefines(ADproj, LspPlat, LspDefs, LspNums, LspSws);
    if not HaveLsp then Notes.Add('delphilsp.json absent or unreadable');

    // Platform: override, else .dproj marker, else JSON dllname, else Win64 (D4 + D1).
    if APlatformOverride <> '' then Result.Platform := NormPlatform(APlatformOverride)
    else if MarkPlat <> '' then Result.Platform := NormPlatform(MarkPlat)
    else if HaveLsp then Result.Platform := LspPlat
    else
    begin
      Result.Platform := DEFAULT_PLATFORM;
      Notes.Add('platform marker absent -> ' + DEFAULT_PLATFORM);
    end;

    // Config: override, else .dproj marker, else Release.
    if AConfigOverride <> '' then Result.Config := AConfigOverride
    else if MarkCfg <> '' then Result.Config := MarkCfg
    else
    begin
      Result.Config := DEFAULT_CONFIG;
      Notes.Add('config marker absent -> ' + DEFAULT_CONFIG);
    end;

    // D1: the .dproj FIRST; delphilsp.json only when the .dproj is unreadable or has no
    // Config marker (flip this one condition to change the order). A JSON written for
    // another platform than the one resolved is not used.
    if AUseDelphiLsp and HaveLsp and (MarkCfg = '') and SameText(LspPlat, Result.Platform) then
    begin
      Result.Source := dsDelphiLsp;
      Result.Config := ''; // the IDE's effective set, not a named config
      Result.Profile.Defines := UnionWithBuiltins(Result.Platform, LspDefs);
      // Lane INC2: the compiler's values first, the JSON's -D values / -$ switches over them.
      Result.Profile.NumericDefines := CompilerNumerics + LspNums;
      Result.Profile.Switches := CompilerDefaultSwitches + LspSws;
    end
    else
    begin
      Result.Source := dsDproj;
      Result.Profile := ProfileFromDproj(ADproj, Result.Platform, Result.Config);
    end;
    Result.Digest := DigestOf(Result.Profile);
    Result.Notes  := Notes.ToArray;
  finally
    Notes.Free;
  end;
end;

// Single *.dproj directly in ADir, else ''.
function SoleDprojIn(const ADir: string): string;
var
  Files: TArray<string>;
begin
  Result := '';
  try
    if (ADir = '') or not TDirectory.Exists(ADir) then Exit;
    Files := TDirectory.GetFiles(ADir, '*.dproj');
    if Length(Files) = 1 then Result := Files[0];
  except // dl:ok bare-except@86a2 -- REVIEWED 2026-10-26 fail-open by contract: a resolver fault falls back to the pre-C10 profile, never raises
    Result := '';
  end;
end;

// The .dproj that owns AFile, or ''. Order: AActiveProject when it is a .dproj and
// (ADbPaths is empty or one of them contains the file); then, for each DB in ADbPaths
// that contains AFile, the manifest section's project, else <AnchorDirForDb(db)>\<dbbase>.dproj
// when that file exists (a DB a manifest section claims but without a project, i.e. a
// library, yields nothing); then (D2) the single *.dproj in AFile's own folder. Never raises.
// (C14: the public DprojForFile wrapper had no caller and was removed.)
function DprojForFileWith(const AFile: string; const ADbPaths: TArray<string>;
  const AActiveProject: string; const AManifest: TIndexManifest; AHaveManifest: Boolean): string;
var
  Db      : string;
  I       : Integer;
  Proj    : string;
  Claimed : Boolean;
  Anchor  : string;
  AnyHit  : Boolean;
begin
  Result := '';
  try
    if AFile = '' then Exit;
    if SameText(ExtractFileExt(AActiveProject), '.dproj') and TFile.Exists(AActiveProject) then
    begin
      AnyHit := Length(ADbPaths) = 0;
      for Db in ADbPaths do
        if DbContainsFile(Db, AFile) then AnyHit := True;
      if AnyHit then Exit(ExpandFileName(AActiveProject));
    end;
    for Db in ADbPaths do
    begin
      if not DbContainsFile(Db, AFile) then Continue;
      Claimed := False;
      if AHaveManifest then
        for I := 0 to High(AManifest.Sections) do
          if SameText(ExpandSectionDb(AManifest, AManifest.Sections[I]), ExpandFileName(Db)) then
          begin
            Claimed := True;
            Proj := SectionProjectFile(AManifest, AManifest.Sections[I]);
            if (Proj <> '') and TFile.Exists(Proj) then Exit(ExpandFileName(Proj));
          end;
      if not Claimed then
      begin
        Anchor := AnchorDirForDb(Db);
        if Anchor <> '' then
        begin
          Proj := TPath.Combine(Anchor, ChangeFileExt(ExtractFileName(Db), '.dproj'));
          if TFile.Exists(Proj) then Exit(ExpandFileName(Proj));
        end;
      end;
    end;
    Result := SoleDprojIn(ExtractFilePath(ExpandFileName(AFile)));
  except // dl:ok bare-except@86a2 -- REVIEWED 2026-10-26 fail-open by contract: a resolver fault falls back to the pre-C10 profile, never raises
    Result := '';
  end;
end;

function LoadManifestSafe(out AManifest: TIndexManifest): Boolean;
begin
  AManifest := Default(TIndexManifest);
  try
    AManifest := TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    Result := True;
  except // dl:ok bare-except@79dc -- REVIEWED 2026-10-26 fail-open by contract: a resolver fault falls back to the pre-C10 profile, never raises
    Result := False;
  end;
end;

{ TProjectProfileCache }

type
  TBuildEntry = record
    Stamp: string;
    Build: TActiveBuild;
  end;

var
  GLock       : TCriticalSection;
  GFileToProj : TDictionary<string, string>;
  GBuilds     : TDictionary<string, TBuildEntry>;
  GDbs        : TArray<string>;
  GActive     : string;
  GPlatform   : string;
  GConfig     : string;
  GFallback   : TDefineProfile;
  GPreferLsp  : Boolean;
  GManifest   : TIndexManifest;
  GHaveManifest: Boolean;

function StampOf(const APath: string): string;
var
  SR: TSearchRec;
begin
  if FindFirst(APath, faAnyFile, SR) = 0 then
  try
    Result := FormatDateTime('yyyymmddhhnnsszzz', SR.TimeStamp) + ':' + IntToStr(SR.Size); // ms resolution; SR.Time is the deprecated 2 s DOS stamp
  finally
    FindClose(SR);
  end
  else
    Result := 'absent';
end;

function FallbackBuild: TActiveBuild;
begin
  Result := Default(TActiveBuild);
  Result.Platform := NormPlatform(GPlatform);
  Result.Source   := dsBuiltins;
  Result.Profile  := GFallback;
end;

class procedure TProjectProfileCache.Clear;
begin
  GLock.Enter;
  try
    GFileToProj.Clear;
    GBuilds.Clear;
  finally
    GLock.Leave;
  end;
end;

class procedure TProjectProfileCache.Configure(const ADbPaths: TArray<string>; const AActiveProject,
  APlatformOverride, AConfigOverride: string; const AFallback: TDefineProfile; AUseDelphiLsp: Boolean);
begin
  GLock.Enter;
  try
    GDbs       := Copy(ADbPaths, 0, Length(ADbPaths));
    GActive    := AActiveProject;
    GPlatform  := APlatformOverride;
    GConfig    := AConfigOverride;
    GFallback  := AFallback;
    GPreferLsp := AUseDelphiLsp;
    GHaveManifest := (Length(GDbs) > 0) and LoadManifestSafe(GManifest);
    GFileToProj.Clear;
    GBuilds.Clear;
  finally
    GLock.Leave;
  end;
end;

class function TProjectProfileCache.BuildForFile(const AFile: string): TActiveBuild;
var
  Key  : string;
  Proj : string;
  Stamp: string;
  Entry: TBuildEntry;
begin
  GLock.Enter;
  try
    try
      Key := LowerCase(ExpandFileName(AFile));
      if not GFileToProj.TryGetValue(Key, Proj) then
      begin
        Proj := DprojForFileWith(AFile, GDbs, GActive, GManifest, GHaveManifest);
        GFileToProj.Add(Key, Proj);
      end;
      if Proj = '' then Exit(FallbackBuild);
      Stamp := StampOf(Proj) + '|' + StampOf(ChangeFileExt(Proj, '.delphilsp.json'));
      if not (GBuilds.TryGetValue(LowerCase(Proj), Entry) and (Entry.Stamp = Stamp)) then
      begin
        Entry.Stamp := Stamp;
        Entry.Build := ResolveActiveBuild(Proj, GPlatform, GConfig, GPreferLsp);
        GBuilds.AddOrSetValue(LowerCase(Proj), Entry);
      end;
      Result := Entry.Build;
    except // dl:ok bare-except@398e -- REVIEWED 2026-10-26 fail-open by contract: a resolver fault falls back to the pre-C10 profile, never raises
      Result := FallbackBuild; // fail-open: a resolver fault never changes the C8 treatment
    end;
  finally
    GLock.Leave;
  end;
end;

class function TProjectProfileCache.ProfileForFile(const AFile: string): TDefineProfile;
begin
  Result := BuildForFile(AFile).Profile;
end;

class procedure TProjectProfileCache.Forget(const AFile: string);
begin
  GLock.Enter;
  try
    GFileToProj.Remove(LowerCase(ExpandFileName(AFile)));
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock       := TCriticalSection.Create;
  GFileToProj := TDictionary<string, string>.Create;
  GBuilds     := TDictionary<string, TBuildEntry>.Create;

finalization
  GBuilds.Free;
  GFileToProj.Free;
  GLock.Free;

end.
