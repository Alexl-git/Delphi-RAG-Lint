unit DRagLint.Lint.SharedScope;

{ SHARED-UNIT-SCOPE (1.41, owner ruling 2026-11-02: UNION). A unit compiled by several
  projects is judged by every project that lists it, not by the one DB a lint run opened.
  Spec: docs\superpowers\specs\2026-11-03-shared-unit-scope-design.md. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Interfaces;

type
  /// <summary>Opens (or returns an already-open) read-only store for a project named by
  /// a manifest section or by a shared unit's `dl:shared` header.</summary>
  /// <param name="AProjectName">The project / manifest section name; case-insensitive.</param>
  /// <returns>An open store, or nil when the name resolves to no configured index or the
  /// index cannot be opened. nil means "could not check", never "not used there".</returns>
  /// <remarks>The caller owns the returned store's lifetime for the whole run.</remarks>
  TSiblingStoreResolver = reference to function(const AProjectName: string): ISymbolStore;

  /// <summary>Lists every project section name of the manifest the run reads.</summary>
  /// <returns>Section names; empty when no manifest loads.</returns>
  TSiblingProjectLister = reference to function: TArray<string>;

  /// <summary>Does ASibling use the symbol under judgement?</summary>
  /// <param name="ASibling">An open store of a project that lists the unit.</param>
  /// <returns>True when the sibling's index shows a use.</returns>
  TSiblingUse = reference to function(const ASibling: ISymbolStore): Boolean;

  /// <summary>Verdict of TSharedScope.Judge.</summary>
  /// <remarks>svNotShared: no other project lists the unit -- judge from the own DB alone.
  /// svUsedElsewhere: a listing project uses it -- no finding. svUnusedEverywhere: every
  /// listing project was checked, fresh, and none uses it -- report. svUndecided: a listing
  /// project's index is missing, will not open or is stale -- do not report.</remarks>
  TSharedVerdict = (svNotShared, svUsedElsewhere, svUnusedEverywhere, svUndecided);

  /// <summary>Finds the projects that list a unit and asks each whether a symbol of it
  /// is used.</summary>
  /// <remarks>
  /// The listing set of a unit path P: every name on P's `dl:shared` header, plus every
  /// manifest section whose index holds a `files` row for P (a project index is its
  /// `.dproj` compile closure). The run's own store is excluded. A header-named project
  /// whose index is missing, will not open or is not fresh makes every verdict on P
  /// svUndecided; a manifest section that will not open is ignored (nothing says it lists
  /// P). LAZY: nothing is opened until the first Judge; the listing set, the self test and
  /// the freshness probe are cached per path / per project for the object's life.
  /// Not thread-safe; one per lint run.
  /// </remarks>
  TSharedScope = class
  private
    FStore   : ISymbolStore;
    FResolve : TSiblingStoreResolver;
    FLister  : TSiblingProjectLister;
    FNames   : TArray<string>;
    FNamesOk : Boolean;
    FListing : TDictionary<string, TArray<string>>;
    FWhyNot  : TDictionary<string, string>;
    FUsable  : TDictionary<string, Boolean>;
    function Open(const AName: string): ISymbolStore;
    function IsSelf(const ASibling: ISymbolStore): Boolean;
    function IsUsable(const AName: string; const ASibling: ISymbolStore): Boolean;
    procedure ResolvePath(const APath: string);
  public
    /// <summary>Binds the scope to the run's own store and the CLI's resolvers.</summary>
    /// <param name="AStore">The run's own project store.</param>
    /// <param name="AResolve">Opens a project's store by name; nil = no sibling can be opened.</param>
    /// <param name="ALister">Lists the manifest's section names; nil = header names only.</param>
    constructor Create(const AStore: ISymbolStore; const AResolve: TSiblingStoreResolver;
                       const ALister: TSiblingProjectLister);
    /// <summary>Frees the caches; the stores belong to the resolver's owner.</summary>
    destructor Destroy; override;
    /// <summary>Judges one symbol of the unit at AUnitPath across the projects that list it.</summary>
    /// <param name="AUnitPath">The unit's path as the own store records it.</param>
    /// <param name="AUsed">Asked once per listing project, until one answers True.</param>
    /// <param name="AProjects">Out: the listing projects (comma-separated) for a message;
    /// for svUndecided, why no verdict was reached.</param>
    /// <returns>The verdict; see TSharedVerdict.</returns>
    function Judge(const AUnitPath: string; const AUsed: TSiblingUse; out AProjects: string): TSharedVerdict;
  end;

implementation

uses
  DRagLint.Lint.SharedUnit,  { TSharedUnit.ProjectsOf -- the header-declared projects }
  DRagLint.Index.Freshness;  { ProbeIndexFreshness -- a stale sibling proves nothing }

const
  META_INDEXED_AT = 'indexed_at_unix';
  META_PROJECT_TAG = 'project_tag';

constructor TSharedScope.Create(const AStore: ISymbolStore; const AResolve: TSiblingStoreResolver;
  const ALister: TSiblingProjectLister);
begin
  inherited Create;
  FStore  := AStore;
  FResolve:= AResolve;
  FLister := ALister;
  FListing:= TDictionary<string, TArray<string>>.Create;
  FWhyNot := TDictionary<string, string>.Create;
  FUsable := TDictionary<string, Boolean>.Create;
end;

destructor TSharedScope.Destroy;
begin
  FUsable.Free;
  FWhyNot.Free;
  FListing.Free;
  inherited Destroy;
end;

function TSharedScope.Open(const AName: string): ISymbolStore;
begin
  Result:= nil;
  if (not Assigned(FResolve)) or (Trim(AName) = '') then Exit;
  try
    Result:= FResolve(Trim(AName));
  except  { a sibling index that will not open is "could not check" (nil), never an aborted lint run }
    on E: Exception do Result:= nil;
  end;
end;

{ The run's own DB, reopened through the manifest. Cheap meta first; a match is confirmed by
  every own file path being present in the sibling (two DBs built in one second share a stamp). }
function TSharedScope.IsSelf(const ASibling: ISymbolStore): Boolean;
var
  Ids: TArray<Int64>;
begin
  Result:= False;
  if (ASibling = nil) or (FStore = nil) then Exit;
  if (ASibling.GetMetaValue(META_INDEXED_AT) <> FStore.GetMetaValue(META_INDEXED_AT)) or
     (ASibling.GetMetaValue(META_PROJECT_TAG) <> FStore.GetMetaValue(META_PROJECT_TAG)) then Exit;
  Ids:= FStore.GetAllFileIds;
  if Length(Ids) <> Length(ASibling.GetAllFileIds) then Exit;
  for var Fid in Ids do
    if ASibling.FindFileIdByPath(FStore.GetFilePath(Fid)) <= 0 then Exit;
  Result:= True;
end;

function TSharedScope.IsUsable(const AName: string; const ASibling: ISymbolStore): Boolean;
begin
  if FUsable.TryGetValue(LowerCase(AName), Result) then Exit;
  Result:= ProbeIndexFreshness(ASibling, 1).Verdict = fvFresh;
  FUsable.Add(LowerCase(AName), Result);
end;

procedure TSharedScope.ResolvePath(const APath: string);
var
  Names: TList<string>;
  Seen : TDictionary<string, Boolean>;
  Why  : string;
  St   : ISymbolStore;
begin
  Names:= TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Why:= '';
    { 1. the header: a declared relationship, so an index that cannot answer blocks the verdict }
    for var N in TSharedUnit.ProjectsOf(APath) do
    begin
      if (Trim(N) = '') or Seen.ContainsKey(LowerCase(Trim(N))) then Continue;
      Seen.Add(LowerCase(Trim(N)), True);
      St:= Open(N);
      if St = nil then
      begin
        if Why = '' then Why:= Format('the index of %s (named on its dl:shared header) could not be opened', [Trim(N)]);
        Continue;
      end;
      if IsSelf(St) then Continue;
      Names.Add(Trim(N));
    end;
    { 2. the manifest: a section lists the unit when its index holds the file }
    if Assigned(FLister) and not FNamesOk then
    begin
      FNamesOk:= True;
      try
        FNames:= FLister();
      except  // dl:ok try-except-swallowed@5735 -- a manifest that will not load leaves the header as the only evidence, which is the pre-1.41 behaviour
        on E: Exception do FNames:= nil;
      end;
    end;
    for var N in FNames do
    begin
      if (Trim(N) = '') or Seen.ContainsKey(LowerCase(Trim(N))) then Continue;
      Seen.Add(LowerCase(Trim(N)), True);
      St:= Open(N);
      if (St = nil) or (St.FindFileIdByPath(APath) <= 0) or IsSelf(St) then Continue;
      Names.Add(Trim(N));
    end;
    FListing.AddOrSetValue(LowerCase(APath), Names.ToArray);
    FWhyNot.AddOrSetValue(LowerCase(APath), Why);
  finally
    Seen.Free;
    Names.Free;
  end;
end;

function TSharedScope.Judge(const AUnitPath: string; const AUsed: TSiblingUse; out AProjects: string): TSharedVerdict;
var
  Listing: TArray<string>;
  Why    : string;
  St     : ISymbolStore;
begin
  AProjects:= '';
  if AUnitPath = '' then Exit(svNotShared);
  if not FListing.ContainsKey(LowerCase(AUnitPath)) then ResolvePath(AUnitPath);
  Listing:= FListing[LowerCase(AUnitPath)];
  Why:= FWhyNot[LowerCase(AUnitPath)];
  if Why <> '' then
  begin
    AProjects:= Why;
    Exit(svUndecided);
  end;
  if Length(Listing) = 0 then Exit(svNotShared);
  AProjects:= string.Join(', ', Listing);
  for var N in Listing do
  begin
    St:= Open(N);
    if (St = nil) or not IsUsable(N, St) then
    begin
      AProjects:= Format('the index of %s is missing or not fresh', [N]);
      Exit(svUndecided);
    end;
    if AUsed(St) then Exit(svUsedElsewhere);
  end;
  Result:= svUnusedEverywhere;
end;

end.
