unit DRagLint.Lint.IncludeCycleRules;

{ cycle-edge-in-include (wave 152c lane INCR).

  `drag-lint cycles --fix` edits uses clauses and declarations, and it never edits an include file
  (ruling N-06 A5: an include is shared text, a host-side edit cannot be proven to leave the other
  hosts alone). So a uses entry or a declaration that a uses cycle runs through, written in an $I
  include, is a cycle the tool cannot untangle -- and the one finding that names it is the
  "move it into the .pas" advice. Two shapes:

    U  a uses entry that comes from an include (unit_uses.origin_path <> '') whose target unit is in
       the SAME strongly-connected group as its host;
    D  a top-level declaration in an include of a group unit that another unit of the same group
       references (from its own file or from one of its includes).

  The groups are the ones circular-uses reports: ProjectRules builds them from
  CollectCircularUsesDetailed and hands them over, so there is ONE Tarjan pass in the engine.
  The facts are the 149 EX2 file_includes rows plus the N-06 unit_uses columns; an index that
  predates them (HasFileFacts False) yields nothing. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  CYCLE_EDGE_IN_INCLUDE_RULE = 'cycle-edge-in-include';

type
  /// <summary>One uses cycle (strongly-connected group of 2+ units) as circular-uses reports it.</summary>
  /// <remarks>Paths and Names are parallel arrays; Names are the unit names sorted the way
  /// circular-uses prints them.</remarks>
  TIncludeCycleGroup = record
    Paths: TArray<string>;
    Names: TArray<string>;
  end;

/// <summary>The cycle-edge-in-include project rule: a cycle edge written in an include file.</summary>
/// <param name="AStore">An open, migrated symbol store; nil yields nothing.</param>
/// <param name="AGroups">The uses cycles of the index (circular-uses groups).</param>
/// <returns>One hint per (host unit, target, include) for a uses entry, and one per (symbol, host
/// unit) for a declaration, anchored at the {$I} directive in the host's .pas.</returns>
/// <remarks>Silent for an empty group list and for an index without the file-fact tables.
/// Not thread-safe; reads the store only.</remarks>
function CollectCycleEdgeInInclude(const AStore: ISymbolStore;
  const AGroups: TArray<TIncludeCycleGroup>): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Math
  , System.TypInfo
  , System.Generics.Collections
  ;

const
  MAX_USERS_SHOWN = 3;
  KIND_PREFIX_LEN = 2; { the sk of an skRecord enum name }

type
  /// <summary>A group member: its file id and its unit name.</summary>
  TMember = record
    FileId: Int64;
    Name  : string;
  end;

  /// <summary>Per-run readers and caches; one instance per CollectCycleEdgeInInclude call.</summary>
  TIncludeCycleScan = class
  private
    FStore   : ISymbolStore;
    FSites   : TDictionary<Int64, TArray<TFileIncludeRow>>;
    FRefKeys : TDictionary<Int64, TDictionary<string, Boolean>>;
    FUses    : TDictionary<Int64, TDictionary<string, Boolean>>;
    FFindings: TList<TLintFinding>;
    function  SitesOf(AFileId: Int64): TArray<TFileIncludeRow>;
    function  AnchorOf(const ASites: TArray<TFileIncludeRow>; AIndex: Integer): Integer;
    function  IncludeFileIds(AFileId: Int64): TArray<Int64>;
    function  RefKeysOfFile(AFileId: Int64): TDictionary<string, Boolean>;
    function  UsesNamesOf(AFileId: Int64): TDictionary<string, Boolean>;
    function  GroupText(const AGroup: TIncludeCycleGroup): string;
    function  MembersOf(const AGroup: TIncludeCycleGroup): TArray<TMember>;
    function  ReferencedFrom(const AMember, AHost: TMember; const ASym: TSymbol; ADeclFileId: Int64): Boolean;
    function  AlsoIncludedBy(const AMembers: TArray<TMember>; AHost: Int64; const AIncPath: string): string;
    procedure Emit(const AHostPath: string; ALine, ACol: Integer; const AMessage: string);
    procedure ScanUses(const AGroup: TIncludeCycleGroup; const AMembers: TArray<TMember>; const AHost: TMember);
    procedure ScanDecls(const AGroup: TIncludeCycleGroup; const AMembers: TArray<TMember>; const AHost: TMember);
  public
    constructor Create(const AStore: ISymbolStore);
    destructor Destroy; override;
    function Run(const AGroups: TArray<TIncludeCycleGroup>): TArray<TLintFinding>;
  end;

{ TIncludeCycleScan }

constructor TIncludeCycleScan.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore   := AStore;
  FSites   := TDictionary<Int64, TArray<TFileIncludeRow>>.Create;
  FRefKeys := TObjectDictionary<Int64, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FUses    := TObjectDictionary<Int64, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FFindings:= TList<TLintFinding>.Create;
end;

destructor TIncludeCycleScan.Destroy;
begin
  FFindings.Free;
  FUses.Free;
  FRefKeys.Free;
  FSites.Free;
  inherited Destroy;
end;

function TIncludeCycleScan.SitesOf(AFileId: Int64): TArray<TFileIncludeRow>;
begin
  if not FSites.TryGetValue(AFileId, Result) then
  begin
    Result:= FStore.GetIncludeSites(AFileId);
    FSites.Add(AFileId, Result);
  end;
end;

{ The row index of the Depth-0 include that brings ASites[AIndex] into the host: the row itself
  for Depth 0, else the nearest earlier row one level up (rows keep source order). }
function TIncludeCycleScan.AnchorOf(const ASites: TArray<TFileIncludeRow>; AIndex: Integer): Integer;
var
  Want: Integer;
begin
  Result:= AIndex;
  Want  := ASites[AIndex].Depth;
  while (Result > 0) and (Want > 0) do
  begin
    Dec(Result);
    if ASites[Result].Depth = Want - 1 then Dec(Want);
  end;
end;

function TIncludeCycleScan.IncludeFileIds(AFileId: Int64): TArray<Int64>;
var
  Row: TFileIncludeRow;
  Fid: Int64;
begin
  Result:= nil;
  for Row in SitesOf(AFileId) do
  begin
    Fid:= FStore.FindFileIdByPath(Row.IncPath);
    if Fid > 0 then Result:= Result + [Fid];
  end;
end;

{ Every reference made from AFileId, keyed 'i<symbol id>' when the resolver bound it and 'n<lower name>'
  when it did not: the resolver does not bind a name to a symbol declared in an include of the used unit
  (symbols.file_id is the .inc, not the unit), so an unbound name is matched by text. }
function TIncludeCycleScan.RefKeysOfFile(AFileId: Int64): TDictionary<string, Boolean>;
var
  R: TReference;
begin
  if FRefKeys.TryGetValue(AFileId, Result) then Exit;
  Result:= TDictionary<string, Boolean>.Create;
  FRefKeys.Add(AFileId, Result);
  for R in FStore.GetReferencesFromFile(AFileId) do
    if R.SymbolId > 0 then Result.AddOrSetValue('i' + IntToStr(R.SymbolId), True)
    else Result.AddOrSetValue('n' + LowerCase(R.NameText), True);
end;

{ The lower-case names AFileId's uses clauses (include-borne entries too) list. }
function TIncludeCycleScan.UsesNamesOf(AFileId: Int64): TDictionary<string, Boolean>;
var
  U: TUnitUse;
begin
  if FUses.TryGetValue(AFileId, Result) then Exit;
  Result:= TDictionary<string, Boolean>.Create;
  FUses.Add(AFileId, Result);
  for U in FStore.GetUnitUsesForFile(AFileId) do Result.AddOrSetValue(LowerCase(U.UnitName), True);
end;

function TIncludeCycleScan.GroupText(const AGroup: TIncludeCycleGroup): string;
begin
  Result:= string.Join(' -> ', AGroup.Names);
end;

function TIncludeCycleScan.MembersOf(const AGroup: TIncludeCycleGroup): TArray<TMember>;
var
  I  : Integer;
  M  : TMember;
  Fid: Int64;
begin
  Result:= nil;
  for I:= 0 to High(AGroup.Paths) do
  begin
    Fid:= FStore.FindFileIdByPath(AGroup.Paths[I]);
    if Fid <= 0 then Continue;
    M.FileId:= Fid;
    M.Name  := AGroup.Names[I];
    Result  := Result + [M];
  end;
end;

{ True when AMember (a unit of the group other than the host) references the declaration ASym that
  AHost's include declares: a reference bound to the symbol, or an unbound reference of the same name
  from a unit that lists AHost in a uses clause. Looks at AMember's own file and at its includes other
  than the declaring one, so a shared include never "uses" itself. }
function TIncludeCycleScan.ReferencedFrom(const AMember, AHost: TMember; const ASym: TSymbol;
  ADeclFileId: Int64): Boolean;
var
  IdKey  : string;
  NameKey: string;
  ByName : Boolean;
  Fid    : Int64;
  Tmp    : Boolean;
  Files  : TArray<Int64>;
begin
  IdKey  := 'i' + IntToStr(ASym.Id);
  NameKey:= 'n' + LowerCase(ASym.Name);
  ByName := UsesNamesOf(AMember.FileId).ContainsKey(LowerCase(AHost.Name));
  Files  := [AMember.FileId];
  for Fid in IncludeFileIds(AMember.FileId) do
    if Fid <> ADeclFileId then Files:= Files + [Fid];
  Result:= False;
  for Fid in Files do
    if RefKeysOfFile(Fid).TryGetValue(IdKey, Tmp) or (ByName and RefKeysOfFile(Fid).TryGetValue(NameKey, Tmp)) then Exit(True);
end;
{ ' (also included by `X`[, `Y`])' for the other group units whose includes name AIncPath; '' when none. }
function TIncludeCycleScan.AlsoIncludedBy(const AMembers: TArray<TMember>; AHost: Int64;
  const AIncPath: string): string;
var
  M  : TMember;
  Row: TFileIncludeRow;
  Hit: Boolean;
  Names: TList<string>;
begin
  Result:= '';
  Names := TList<string>.Create;
  try
    for M in AMembers do
    begin
      if M.FileId = AHost then Continue;
      Hit:= False;
      for Row in SitesOf(M.FileId) do
        if SameText(Row.IncPath, AIncPath) then Hit:= True;
      if not Hit then Continue;
      Names.Add('`' + M.Name + '`');
    end;
    if Names.Count > 0 then Result:= ' (also included by ' + string.Join(', ', Names.ToArray) + ')';
  finally
    Names.Free;
  end;
end;

procedure TIncludeCycleScan.Emit(const AHostPath: string; ALine, ACol: Integer; const AMessage: string);
var
  F: TLintFinding;
begin
  F:= Default(TLintFinding);
  F.RuleId   := CYCLE_EDGE_IN_INCLUDE_RULE;
  F.Severity := 'hint';
  F.FilePath := AHostPath;
  F.StartLine:= ALine;
  F.StartCol := ACol;
  F.EndLine  := ALine;
  F.EndCol   := ACol;
  F.Message  := AMessage;
  FFindings.Add(F);
end;

{ Shape U: an include-borne uses entry whose target is in the host's own group. }
procedure TIncludeCycleScan.ScanUses(const AGroup: TIncludeCycleGroup; const AMembers: TArray<TMember>;
  const AHost: TMember);
var
  U    : TUnitUse;
  Seen : TDictionary<string, Boolean>;
  Sites: TArray<TFileIncludeRow>;
  Row  : TFileIncludeRow;
  Col  : Integer;
  M    : TMember;
  Hit  : Boolean;
  Key  : string;
  Low  : string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    Sites:= SitesOf(AHost.FileId);
    for U in FStore.GetUnitUsesForFile(AHost.FileId) do
    begin
      if U.OriginPath = '' then Continue;
      Low:= LowerCase(U.UnitName);
      Hit:= False;
      for M in AMembers do
        if (M.FileId <> AHost.FileId)
           and (SameText(M.Name, U.UnitName)
                or ((not U.UnitName.Contains('.')) and SameText(ExtractFileExt(M.Name), '.' + U.UnitName))) then Hit:= True;
      if not Hit then Continue;
      Key:= Low + '|' + LowerCase(U.OriginPath);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      Col:= 1;
      for Row in Sites do
        if Row.InUses and (Row.Depth = 0) and (Row.HostLine = U.IncludeLine) then Col:= Row.HostCol;
      Emit(FStore.GetFilePath(AHost.FileId), U.IncludeLine, Col,
        Format('`%s` uses `%s` through the include `%s` (line %d), and both units are in a uses cycle (%s)%s. ' +
          'drag-lint never edits an include file, so `cycles --fix` cannot move or remove this entry. ' +
          'Write `%s` in the uses clause of `%s.pas` itself -- replace the `{$I}` by its entries or take this one out of the include -- ' +
          'then run `drag-lint cycles --plan`.',
          [AHost.Name, U.UnitName, ExtractFileName(U.OriginPath), U.StartLine, GroupText(AGroup),
           AlsoIncludedBy(AMembers, AHost.FileId, U.OriginPath), U.UnitName, AHost.Name]));
    end;
  finally
    Seen.Free;
  end;
end;

{ Shape D: a top-level declaration of an include of the host that another unit of the group uses. }
procedure TIncludeCycleScan.ScanDecls(const AGroup: TIncludeCycleGroup; const AMembers: TArray<TMember>;
  const AHost: TMember);
var
  Sites : TArray<TFileIncludeRow>;
  I     : Integer;
  Anchor: Integer;
  IncFid: Int64;
  IncPath: string;
  S     : TSymbol;
  M     : TMember;
  Users : TList<string>;
  Shown : string;
  Kind  : string;
begin
  Sites:= SitesOf(AHost.FileId);
  for I:= 0 to High(Sites) do
  begin
    if Sites[I].InUses then Continue;
    IncFid:= FStore.FindFileIdByPath(Sites[I].IncPath);
    if IncFid <= 0 then Continue;
    IncPath:= FStore.GetFilePath(IncFid);
    Anchor := AnchorOf(Sites, I);
    for S in FStore.FindSymbolsByFile(IncPath) do
    begin
      if (S.Name = '') or (S.ParentId > 0) then Continue;
      if S.Kind in [skUnit, skProgram, skPackage, skInitialization, skFinalization] then Continue;
      Users:= TList<string>.Create;
      try
        for M in AMembers do
          if (M.FileId <> AHost.FileId) and ReferencedFrom(M, AHost, S, IncFid) then Users.Add('`' + M.Name + '`');
        if Users.Count = 0 then Continue;
        Shown:= string.Join(', ', Users.ToArray, 0, Min(Users.Count, MAX_USERS_SHOWN));
        if Users.Count > MAX_USERS_SHOWN then Shown:= Shown + Format(' +%d more', [Users.Count - MAX_USERS_SHOWN]);
        Kind:= LowerCase(Copy(GetEnumName(TypeInfo(TSymbolKind), Ord(S.Kind)), KIND_PREFIX_LEN + 1, MaxInt));
        Emit(FStore.GetFilePath(AHost.FileId), Sites[Anchor].HostLine, Sites[Anchor].HostCol,
          Format('`%s` (%s) is declared in the include `%s` (line %d) of `%s`, and %s of the same uses cycle (%s) use it%s. ' +
            'drag-lint never edits an include file, so `cycles --fix` cannot move it into a leaf unit. ' +
            'Move the declaration into `%s.pas` (or a unit of its own), then run `drag-lint cycles --plan`.',
            [S.Name, Kind, ExtractFileName(IncPath), S.StartLine, AHost.Name, Shown, GroupText(AGroup),
             AlsoIncludedBy(AMembers, AHost.FileId, IncPath), AHost.Name]));
      finally
        Users.Free;
      end;
    end;
  end;
end;

function TIncludeCycleScan.Run(const AGroups: TArray<TIncludeCycleGroup>): TArray<TLintFinding>;
var
  G      : TIncludeCycleGroup;
  Members: TArray<TMember>;
  H      : TMember;
begin
  for G in AGroups do
  begin
    Members:= MembersOf(G);
    for H in Members do
    begin
      ScanUses(G, Members, H);
      ScanDecls(G, Members, H);
    end;
  end;
  Result:= FFindings.ToArray;
end;

function CollectCycleEdgeInInclude(const AStore: ISymbolStore;
  const AGroups: TArray<TIncludeCycleGroup>): TArray<TLintFinding>;
var
  Scan: TIncludeCycleScan;
begin
  Result:= nil;
  if (AStore = nil) or (Length(AGroups) = 0) or not AStore.HasFileFacts then Exit;
  Scan:= TIncludeCycleScan.Create(AStore);
  try
    Result:= Scan.Run(AGroups);
  finally
    Scan.Free;
  end;
end;

end.
