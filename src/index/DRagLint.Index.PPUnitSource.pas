unit DRagLint.Index.PPUnitSource;

// Lane INC3 (2026-10-27): the used-unit half of the IF-directive symbol table.
// The preprocessor resolves a name in the constants of its own active text
// first; for a name it does not declare it asks the installed IPPUnitSource
// about each unit of the uses clause. This is that source.
//
// HOW A UNIT IS ANSWERED
//   1. A PROJECT unit (a file the closure listed, or a unit symbol of a project
//      DB) is SCANNED: preprocessed under the project's profile with the same
//      source installed, and its interface declarations kept. This is the
//      per-unit pre-pass that makes index ORDER irrelevant -- a unit's
//      constants are known before the unit itself is indexed, and the scan
//      honours that unit's own IF branches (a constant inside an inactive
//      branch of the used unit does not count either). One scan per unit per
//      run; a uses cycle answers 'unknown' for the unit already in progress.
//   2. Any other unit is asked of the LIBRARY DBs: a const symbol's stored
//      signature ('= <expr>' since extractor 1.6.0) is evaluated in that
//      unit's scope; '<type> = <v>' is a typed constant (declared, not a true
//      constant); every other kind is declared. An unqualified uses name
//      (SysUtils) matches its namespaced unit (System.SysUtils).
//
// THREAD-SAFETY: every lookup runs under one re-entrant lock (a scan recurses
// into LookupInUnit on the same thread).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  DRagLint.Core.Interfaces,
  DRagLint.Preprocess.Types,
  DRagLint.Preprocess.Expr,
  DRagLint.Preprocess.Decls;

type
  /// <summary>The IPPUnitSource the index and lint runs install (see the unit
  /// header for how each unit is answered).</summary>
  /// <remarks>Thread-safe. Opens its DBs read-only, lazily, on first need.</remarks>
  TPPUnitSourceResolver = class(TInterfacedObject, IPPUnitSource)
  private type
    TAnswer = record
      Kind : TPPNameKind;
      Value: TPPValue;
    end;
  private
    FLock       : TCriticalSection;
    FProfile    : TDefineProfile;
    FSearchPaths: TArray<string>;
    FDefines    : TDictionary<string, Boolean>;
    FNumeric    : TDictionary<string, Integer>;
    FUnitFiles  : TDictionary<string, string>;
    FScanned    : TObjectDictionary<string, TDictionary<string, TPPDecl>>;
    FInProgress : TDictionary<string, Boolean>;
    FAnswers    : TDictionary<string, TAnswer>;
    FProjectDbs : TArray<string>;
    FLibraryDbs : TArray<string>;
    FProjStores : TArray<ISymbolStore>;
    FLibStores  : TArray<ISymbolStore>;
    FStoresOpen : Boolean;
    FDepth      : Integer;
    FUnknownAnswers: Integer;
    procedure OpenStores;
    function UnitFile(const AUnit: string): string;
    function Scan(const AKey, APath: string): TDictionary<string, TPPDecl>;
    function AskLibrary(const AUnit, AName: string): TAnswer;
    function EvalInUnit(const AUnitQName, AExpr: string; out AValue: TPPValue): Boolean;
  public
    /// <summary>Constructor: a source for one run.</summary>
    /// <param name="AProfile">The define profile project units are scanned under.</param>
    /// <param name="ASearchPaths">Include search paths for those scans.</param>
    /// <param name="AProjectDbs">Project DBs: their unit symbols locate project
    /// files to scan (missing files are skipped). May be empty.</param>
    /// <param name="ALibraryDbs">Library DBs answered from symbols. May be empty;
    /// paths that do not exist are ignored.</param>
    constructor Create(const AProfile: TDefineProfile; const ASearchPaths, AProjectDbs, ALibraryDbs: TArray<string>);
    /// <summary>Frees the caches and closes the DBs.</summary>
    destructor Destroy; override;
    /// <summary>Registers project source files (unit name = file base name);
    /// non-.pas paths are ignored. Clears every cached answer.</summary>
    /// <param name="APaths">Absolute paths, e.g. a closure's file list.</param>
    /// <param name="ASearchPaths">Include search paths for the scans (replaces the earlier ones).</param>
    procedure AddUnitFiles(const APaths, ASearchPaths: TArray<string>);
    /// <summary>See IPPUnitSource.LookupInUnit.</summary>
    /// <param name="AUnit">The unit as the uses clause spells it.</param>
    /// <param name="AName">The bare symbol name.</param>
    /// <param name="AValue">The value when pnkConst is returned.</param>
    /// <returns>How AUnit declares AName.</returns>
    function LookupInUnit(const AUnit, AName: string; out AValue: TPPValue): TPPNameKind;
    /// <summary>How many lookups answered pnkUnknown since the last AddUnitFiles
    /// -- zero means no IF needed a unit the source could not see, so a second
    /// closure pass would decide nothing differently.</summary>
    property UnknownAnswers: Integer read FUnknownAnswers;
  end;

/// <summary>Creates a TPPUnitSourceResolver and installs it as the
/// process-wide PPUnitSource (replacing any earlier one).</summary>
/// <param name="AProfile">See TPPUnitSourceResolver.Create.</param>
/// <param name="AProjectDbs">See TPPUnitSourceResolver.Create.</param>
/// <param name="ALibraryDbs">See TPPUnitSourceResolver.Create.</param>
/// <returns>The installed resolver; the installation owns it (do not free).</returns>
function InstallPPUnitSource(const AProfile: TDefineProfile; const AProjectDbs, ALibraryDbs: TArray<string>): TPPUnitSourceResolver;

implementation

uses
  System.IOUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Encoding,
  DRagLint.Storage.SQLite,
  DRagLint.Preprocess;

const
  // A library constant built from other constants nests its evaluation; this
  // bounds a pathological (or cyclic) chain.
  MAX_EVAL_DEPTH = 16;
  SYSTEM_UNIT = 'System';

constructor TPPUnitSourceResolver.Create(const AProfile: TDefineProfile; const ASearchPaths, AProjectDbs, ALibraryDbs: TArray<string>);
begin
  inherited Create;
  FLock       := TCriticalSection.Create;
  FProfile    := AProfile;
  FSearchPaths:= ASearchPaths;
  FProjectDbs := AProjectDbs;
  FLibraryDbs := ALibraryDbs;
  FDefines    := TDictionary<string, Boolean>.Create;
  FNumeric    := TDictionary<string, Integer>.Create;
  FUnitFiles  := TDictionary<string, string>.Create;
  FScanned    := TObjectDictionary<string, TDictionary<string, TPPDecl>>.Create([doOwnsValues]);
  FInProgress := TDictionary<string, Boolean>.Create;
  FAnswers    := TDictionary<string, TAnswer>.Create;
  for var D: string in AProfile.Defines do
    if D <> '' then FDefines.AddOrSetValue(LowerCase(D), True);
  for var P: TPair<string, Integer> in AProfile.NumericDefines do
    FNumeric.AddOrSetValue(LowerCase(P.Key), P.Value);
end;

destructor TPPUnitSourceResolver.Destroy;
begin
  FProjStores:= nil;
  FLibStores := nil;
  FAnswers.Free;
  FInProgress.Free;
  FScanned.Free;
  FUnitFiles.Free;
  FNumeric.Free;
  FDefines.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPPUnitSourceResolver.AddUnitFiles(const APaths, ASearchPaths: TArray<string>);
begin
  FLock.Enter;
  try
    FSearchPaths:= ASearchPaths;
    for var P: string in APaths do
      if SameText(ExtractFileExt(P), '.pas') then
        FUnitFiles.AddOrSetValue(LowerCase(TPath.GetFileNameWithoutExtension(P)), P);
    FAnswers.Clear;
    FScanned.Clear;
    FUnknownAnswers:= 0;
  finally
    FLock.Leave;
  end;
end;

procedure TPPUnitSourceResolver.OpenStores;

  function OpenAll(const ADbs: TArray<string>): TArray<ISymbolStore>;
  begin
    Result:= nil;
    for var Db: string in ADbs do
      if (Db <> '') and TFile.Exists(Db) then
        try
          Result:= Result + [TSQLiteSymbolStore.Create(Db, True) as ISymbolStore];
        except // dl:ok try-except-swallowed@5384 -- REVIEWED 2026-10-27 an unreadable DB answers nothing; the lookup falls through to pp-unresolved-if
          on E: Exception do Continue;
        end;
  end;

begin
  if FStoresOpen then Exit;
  FStoresOpen:= True;
  FProjStores:= OpenAll(FProjectDbs);
  FLibStores := OpenAll(FLibraryDbs);
end;

// The project source file of AUnit, or '' when it is not a project unit.
function TPPUnitSourceResolver.UnitFile(const AUnit: string): string;
var
  Key: string;
begin
  Key:= LowerCase(AUnit);
  if FUnitFiles.TryGetValue(Key, Result) then Exit;
  Result:= '';
  OpenStores;
  for var S: ISymbolStore in FProjStores do
  begin
    for var Sym: TSymbol in S.FindSymbolsByQualifiedName(AUnit) do
      if (Sym.Kind = skUnit) and SameText(Sym.QualifiedName, AUnit) then
      begin
        Result:= S.GetFilePath(Sym.FileId);
        if (Result <> '') and TFile.Exists(Result) then Break;
        Result:= '';
      end;
    if Result <> '' then Break;
  end;
  FUnitFiles.AddOrSetValue(Key, Result); // '' = negative cache
end;

function TPPUnitSourceResolver.Scan(const AKey, APath: string): TDictionary<string, TPPDecl>;
var
  Opts  : TPPOptions;
  Report: TPPReport;
begin
  if FScanned.TryGetValue(AKey, Result) then Exit;
  Result:= TDictionary<string, TPPDecl>.Create;
  FInProgress.AddOrSetValue(AKey, True);
  try
    try
      Opts:= TPPOptionsDefault;
      Opts.Profile    := FProfile;
      Opts.IncludeMode:= 'defines-only';
      Opts.BaseDir    := TPath.GetDirectoryName(APath);
      Opts.SearchPaths:= FSearchPaths;
      PreprocessReport(EnsureUtf8Bytes(TFile.ReadAllBytes(APath)), Opts, Report);
      for var D: TPPDecl in Report.Exported do
        Result.AddOrSetValue(LowerCase(D.Name), D);
    except // dl:ok try-except-swallowed@e22c -- REVIEWED 2026-10-27 an unreadable unit declares nothing we can see; its names surface as pp-unresolved-if
      on E: Exception do Result.Clear;
    end;
  finally
    FInProgress.Remove(AKey);
  end;
  FScanned.Add(AKey, Result);
end;

// Evaluates a library constant's expression in its own unit's scope: names
// resolve in AUnitQName, then System.
function TPPUnitSourceResolver.EvalInUnit(const AUnitQName, AExpr: string; out AValue: TPPValue): Boolean;
var
  Me: TPPUnitSourceResolver;
begin
  Me:= Self;
  Result:= TryEvalPPConst(AExpr, FDefines, FNumeric,
    function(const AName: string; out AV: TPPValue): TPPNameKind
    begin
      Result:= Me.LookupInUnit(AUnitQName, AName, AV);
      if (Result = pnkUnknown) and not SameText(AUnitQName, SYSTEM_UNIT) then
        Result:= Me.LookupInUnit(SYSTEM_UNIT, AName, AV);
    end, AValue);
end;

// FindSymbolsByExactName that answers nothing when the DB is busy or locked.
function SafeByName(const AStore: ISymbolStore; const AName: string): TArray<TSymbol>;
begin
  try
    Result:= AStore.FindSymbolsByExactName(AName);
  except
    on Exception do Result:= nil;
  end;
end;

function TPPUnitSourceResolver.AskLibrary(const AUnit, AName: string): TAnswer;
var
  Want, UnitQ, Sig: string;
  Hits            : TArray<TSymbol>;
  Hit             : TSymbol;
  Found           : Boolean;
begin
  Result:= Default(TAnswer);
  Hit:= Default(TSymbol);
  OpenStores;
  Want:= AUnit + '.' + AName;
  Found:= False;
  for var S: ISymbolStore in FLibStores do
  begin
    try
      Hits:= S.FindSymbolsByQualifiedName(Want);
    except
      on Exception do Hits:= nil;
    end;
    // An unqualified uses name (SysUtils) matches a namespaced unit.
    if (Length(Hits) = 0) and (not AUnit.Contains('.')) then
      for var X: TSymbol in SafeByName(S, AName) do
        if X.QualifiedName.ToLower.EndsWith('.' + Want.ToLower) then Hits:= Hits + [X];
    for var X: TSymbol in Hits do
      if (X.Section <> 'implementation') and X.QualifiedName.ToLower.EndsWith(Want.ToLower) then
      begin
        Hit:= X;
        Found:= True;
        Break;
      end;
    if Found then Break;
  end;
  if not Found then Exit;
  Result.Kind:= pnkDeclared;
  if Hit.Kind <> skConstDecl then Exit;
  { The stored signature is '= <expr>' or, for a literal value, '<inferred type> = <v>'
    -- and a TYPED constant is stored the same way ('Integer = 3'). Since EXT-E4
    (extractor 1.26.0-alpha) the parser marks a typed constant with the
    'typed' modifier, so it is refused here like dcc does (E2026). A DB indexed
    before that has no modifier and still yields the value. }
  if (' ' + LowerCase(Hit.Modifiers) + ' ').Contains(' typed ') then
  begin
    Result.Kind:= pnkTypedConst;
    Exit;
  end;
  Sig:= Trim(Hit.Signature);
  if not Sig.Contains('=') then Exit;
  Sig:= Copy(Sig, Pos('=', Sig), MaxInt);
  UnitQ:= Copy(Hit.QualifiedName, 1, Length(Hit.QualifiedName) - Length(AName) - 1);
  if FDepth >= MAX_EVAL_DEPTH then Exit;
  Inc(FDepth);
  try
    if EvalInUnit(UnitQ, Trim(Copy(Sig, 2, MaxInt)), Result.Value) then Result.Kind:= pnkConst;
  finally
    Dec(FDepth);
  end;
end;

function TPPUnitSourceResolver.LookupInUnit(const AUnit, AName: string; out AValue: TPPValue): TPPNameKind;
var
  Key, Path: string;
  Decls    : TDictionary<string, TPPDecl>;
  D        : TPPDecl;
  A        : TAnswer;
begin
  AValue:= Default(TPPValue);
  Result:= pnkUnknown;
  if (AUnit = '') or (AName = '') then Exit;
  FLock.Enter;
  try
    Key:= LowerCase(AUnit);
    Path:= UnitFile(AUnit);
    if Path <> '' then
    begin
      if FInProgress.ContainsKey(Key) then Exit; // a uses cycle: the unit is mid-scan
      Decls:= Scan(Key, Path);
      if not Decls.TryGetValue(LowerCase(AName), D) then Exit;
      if D.IsTypedConst then Result:= pnkTypedConst
      else if not (D.IsTrueConst and D.HasValue) then Result:= pnkDeclared
      else
      begin
        AValue:= D.Value;
        Result:= pnkConst;
      end;
      Exit;
    end;
    if not FAnswers.TryGetValue(Key + '.' + LowerCase(AName), A) then
    begin
      A:= AskLibrary(AUnit, AName);
      FAnswers.AddOrSetValue(Key + '.' + LowerCase(AName), A);
    end;
    AValue:= A.Value;
    Result:= A.Kind;
  finally
    if Result = pnkUnknown then Inc(FUnknownAnswers);
    FLock.Leave;
  end;
end;

function InstallPPUnitSource(const AProfile: TDefineProfile; const AProjectDbs, ALibraryDbs: TArray<string>): TPPUnitSourceResolver;
begin
  Result:= TPPUnitSourceResolver.Create(AProfile, nil, AProjectDbs, ALibraryDbs);
  PPSetUnitSource(Result);
end;

end.
