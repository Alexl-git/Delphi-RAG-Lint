unit ConvRules.UnitStatus;

{ Classifies a used unit against a DESTINATION project, for one platform
  (spec section 4.2). Pure except the default file probe, which lists each
  folder once and caches it; tests inject their own probe. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , ConvRules.UsesHarvest
  ;

type
  /// <summary>Why a used unit is (or is not) resolvable by the destination.</summary>
  TUnitStatusKind = (uskUnknown, uskProject, uskLibrary, uskViaScope, uskMissing);

  /// <summary>A classification result.</summary>
  TUnitStatus = record
    /// <summary>The verdict.</summary>
    Kind    : TUnitStatusKind;
    /// <summary>uskProject: the file found ('' for a member without an `in`
    /// path); uskViaScope: the qualified name, e.g. 'Vcl.Forms'; else ''.</summary>
    Resolved: string;
  end;

  /// <summary>Answers "does this file exist?" for the resolver.</summary>
  TFileProbe = reference to function(const APath: string): Boolean;

  /// <summary>Resolves unit names the way the destination's compiler would.</summary>
  /// <remarks>Order, first match wins: destination member; APath.pas/.dcu in the
  /// project folder or a search-path folder (project); the name in the library
  /// list (library); each scope name prefixed, same checks (via scope); else
  /// MISSING. Case-insensitive throughout. Not thread-safe.</remarks>
  TUnitResolver = class
  private
    FMembers : TDictionary<string, string>;
    FLibrary : TDictionary<string, Boolean>;
    FDirFiles: TObjectDictionary<string, TDictionary<string, Boolean>>;
    FDirs    : TArray<string>;
    FScopes  : TArray<string>;
    FProbe   : TFileProbe;
    function FileInDir(const ADir, AFileName: string): Boolean;
    function ResolveProject(const AName: string; out APath: string): Boolean;
  public
    /// <summary>Builds the lookup tables.</summary>
    /// <param name="ASettings">Destination settings for the platform being classified.</param>
    /// <param name="AMembers">Destination .dpr members.</param>
    /// <param name="ALibrary">Library unit names for the platform; empty makes
    /// every library-only unit MISSING (the caller must say so).</param>
    /// <param name="AProbe">nil = read the disk, one listing per folder, cached.</param>
    constructor Create(const ASettings: TProjectSettings; const AMembers: TArray<TDprMember>; const ALibrary: TArray<string>; const AProbe: TFileProbe);
    /// <summary>Frees the lookup tables.</summary>
    destructor Destroy; override;
    /// <summary>Classify one unit name.</summary>
    /// <param name="AName">The name as written in a uses clause.</param>
    /// <returns>The status; never uskUnknown.</returns>
    function Classify(const AName: string): TUnitStatus;
  end;

const
  /// <summary>StatusText of a uskMissing status; the form bolds rows showing it.</summary>
  STATUS_MISSING_TEXT = 'MISSING';

/// <summary>The status for "no destination loaded".</summary>
/// <returns>Kind = uskUnknown, Resolved = ''.</returns>
function UnknownStatus: TUnitStatus;

/// <summary>The Status column text.</summary>
/// <param name="AStatus">A status.</param>
/// <returns>'no destination' | 'project' | 'library' | 'via scope -> X' | 'MISSING'.</returns>
function StatusText(const AStatus: TUnitStatus): string;

/// <summary>Whether a harvested unit is listed under the current check boxes.</summary>
/// <param name="AStatus">Its status.</param>
/// <param name="AFindMissing">Find missing is ticked.</param>
/// <param name="AIncludeUnqualified">Include unqualified names is ticked.</param>
/// <returns>uskUnknown: always True (no destination = list everything);
/// Find missing off: True; on: MISSING, plus via scope when AIncludeUnqualified.</returns>
function ShouldAdd(const AStatus: TUnitStatus; AFindMissing, AIncludeUnqualified: Boolean): Boolean;

implementation

uses
  System.IOUtils
  ;

const
  UNIT_EXTS: array[0..1] of string = ('.pas', '.dcu');

function UnknownStatus: TUnitStatus;
begin
  Result.Kind    := uskUnknown;
  Result.Resolved:= '';
end;

function StatusText(const AStatus: TUnitStatus): string;
begin
  case AStatus.Kind of
    uskProject : Result:= 'project';
    uskLibrary : Result:= 'library';
    uskViaScope: Result:= 'via scope -> ' + AStatus.Resolved;
    uskMissing : Result:= STATUS_MISSING_TEXT;
  else
    Result:= 'no destination';
  end;
end;

function ShouldAdd(const AStatus: TUnitStatus; AFindMissing, AIncludeUnqualified: Boolean): Boolean;
begin
  if (AStatus.Kind = uskUnknown) or not AFindMissing then
    Exit(True);
  Result:= (AStatus.Kind = uskMissing) or ((AStatus.Kind = uskViaScope) and AIncludeUnqualified);
end;

constructor TUnitResolver.Create(const ASettings: TProjectSettings; const AMembers: TArray<TDprMember>; const ALibrary: TArray<string>; const AProbe: TFileProbe);
var
  D: TDprMember;
  S: string;
begin
  inherited Create;
  FMembers := TDictionary<string, string>.Create;
  FLibrary := TDictionary<string, Boolean>.Create;
  FDirFiles:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  for D in AMembers do
    if not FMembers.ContainsKey(UpperCase(D.UnitName)) then
      FMembers.Add(UpperCase(D.UnitName), D.FilePath);
  for S in ALibrary do
    FLibrary.AddOrSetValue(UpperCase(S), True);
  FDirs  := [ASettings.ProjectDir] + ASettings.SearchPath;
  FScopes:= ASettings.Scopes;
  FProbe := AProbe;
end;

destructor TUnitResolver.Destroy;
begin
  FDirFiles.Free;
  FLibrary.Free;
  FMembers.Free;
  inherited Destroy;
end;

function TUnitResolver.FileInDir(const ADir, AFileName: string): Boolean;
var
  Files: TDictionary<string, Boolean>;
  F    : string;
begin
  if Assigned(FProbe) then
    Exit(FProbe(TPath.Combine(ADir, AFileName)));
  if not FDirFiles.TryGetValue(UpperCase(ADir), Files) then
  begin
    Files:= TDictionary<string, Boolean>.Create;
    FDirFiles.Add(UpperCase(ADir), Files);
    if TDirectory.Exists(ADir) then
      for F in TDirectory.GetFiles(ADir) do
        Files.AddOrSetValue(UpperCase(ExtractFileName(F)), True);
  end;
  Result:= Files.ContainsKey(UpperCase(AFileName));
end;

function TUnitResolver.ResolveProject(const AName: string; out APath: string): Boolean;
var
  Dir: string;
  Ext: string;
begin
  if FMembers.TryGetValue(UpperCase(AName), APath) then
    Exit(True);
  for Dir in FDirs do
    for Ext in UNIT_EXTS do
      if FileInDir(Dir, AName + Ext) then
      begin
        APath:= TPath.Combine(Dir, AName + Ext);
        Exit(True);
      end;
  APath:= '';
  Result:= False;
end;

function TUnitResolver.Classify(const AName: string): TUnitStatus;
var
  Path: string;
  S   : string;
  Q   : string;
begin
  Result.Resolved:= '';
  if ResolveProject(AName, Path) then
  begin
    Result.Kind    := uskProject;
    Result.Resolved:= Path;
    Exit;
  end;
  if FLibrary.ContainsKey(UpperCase(AName)) then
  begin
    Result.Kind:= uskLibrary;
    Exit;
  end;
  for S in FScopes do
  begin
    Q:= S + '.' + AName;
    if ResolveProject(Q, Path) or FLibrary.ContainsKey(UpperCase(Q)) then
    begin
      Result.Kind    := uskViaScope;
      Result.Resolved:= Q;
      Exit;
    end;
  end;
  Result.Kind:= uskMissing;
end;

end.
