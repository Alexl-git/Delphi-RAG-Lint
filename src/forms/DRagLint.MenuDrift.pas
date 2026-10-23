unit DRagLint.MenuDrift;

/// <summary>menu-drift (spec docs\superpowers\specs\2026-10-23-code-built-menu-reader-design.md,
/// sections 7 and 8): compares the code-built menu tree (DRagLint.MenuTree)
/// with the ide-menu surfaces of the feature registry and classifies every
/// difference as missing, moved or unregistered, plus notes.</summary>
/// <remarks>Engine only; the CLI verb menu-drift is a thin wrapper. Keys come
/// from MenuCaptionKey / MenuPathKey, which equal featuregen's CaptionKey /
/// MenuKey. Not thread-safe.</remarks>

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.MenuTree
  ;

type
  /// <summary>One ide-menu surface of the registry.</summary>
  TRegistrySurface = record
    /// <summary>Id of the entry that owns the surface.</summary>
    EntryId: string;
    /// <summary>The path as written in the entry.</summary>
    Path   : string;
    /// <summary>MenuPathKey(Path).</summary>
    Key    : string;
  end;

  /// <summary>The registry side of the comparison: ide-menu surfaces and the
  /// exempted captions.</summary>
  TMenuRegistry = class
  private
    FSurfaces: TList<TRegistrySurface>;
    FExempt  : TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Reads pDir\entries\*.json (surfaces of type ide-menu), the family
    /// children of pDir\generated\manifest.json and pDir\exemptions.json (the keys of "captions").</summary>
    /// <param name="pDir">A features directory (the repo's features\, or a fixture's registry\).</param>
    /// <exception cref="EMenuDriftSetup">pDir\entries is missing or an entry is not valid JSON.</exception>
    procedure LoadFromDir(const pDir: string);
    /// <summary>Adds one surface (tests, or a loader).</summary>
    procedure AddSurface(const pEntryId, pPath: string);
    /// <summary>Adds the ide-menu surfaces of the family children in a generated
    /// manifest.json ("families": { name: [ child entries ] }) -- e.g. the
    /// chart-questions children, one per Reports item. A missing file adds nothing.</summary>
    /// <param name="pManifest">Path of features\generated\manifest.json.</param>
    procedure LoadFamilies(const pManifest: string);
    /// <summary>The ide-menu surfaces, in load order.</summary>
    property Surfaces: TList<TRegistrySurface> read FSurfaces;
    /// <summary>Exempted captions as written.</summary>
    property Exempt: TList<string> read FExempt;
  end;

  /// <summary>A registered path the live tree does not have (spec 7).</summary>
  TDriftMissing = record
    Path : string;
    Entry: string;
    /// <summary>'renamed? -> ''caption''' when a live leaf under the same parent shares >= 12 leading key characters; else ''.</summary>
    Hint : string;
  end;

  /// <summary>A registered path whose leaf caption lives under another parent.</summary>
  TDriftMoved = record
    Path : string;
    Entry: string;
    NowAt: string;
  end;

  /// <summary>A live leaf no registry surface covers.</summary>
  TDriftUnregistered = record
    Path    : string;
    Handler : string;
    Source  : string;
    Skeleton: string;
  end;

  /// <summary>The drift report (spec 7/8). Owns its lists.</summary>
  TMenuDriftReport = class
  private
    FMissing     : TList<TDriftMissing>;
    FMoved       : TList<TDriftMoved>;
    FUnregistered: TList<TDriftUnregistered>;
    FNotes       : TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    property Missing: TList<TDriftMissing> read FMissing;
    property Moved: TList<TDriftMoved> read FMoved;
    property Unregistered: TList<TDriftUnregistered> read FUnregistered;
    property Notes: TList<string> read FNotes;
    /// <summary>True when any missing, moved or unregistered finding exists (notes never count).</summary>
    function HasDrift: Boolean;
    /// <summary>'menu-drift: missing=N unregistered=N moved=N notes=N'.</summary>
    function SummaryLine: string;
    /// <summary>MISSING / MOVED / UNREGISTERED / NOTE lines, then the summary line.</summary>
    function ToText: string;
    /// <summary>menu-drift/1 JSON (spec 8).</summary>
    function ToJson: string;
  end;

  /// <summary>Raised when the registry cannot be read (the CLI maps it to exit 2).</summary>
  EMenuDriftSetup = class(Exception);

/// <summary>Classifies the drift between a live tree and a registry (spec 7).</summary>
/// <param name="pTree">The live tree; only non-external roots are compared.</param>
/// <param name="pRegistry">The registry side.</param>
/// <returns>A new report; the caller owns it.</returns>
/// <remarks>A registered path under a parent that holds a dynamic leaf is
/// never reported missing (the dynamic item may be it; its note says so).
/// Order inside a submenu is not compared.</remarks>
function ComputeMenuDrift(pTree: TMenuTree; pRegistry: TMenuRegistry): TMenuDriftReport;

implementation

uses
  System.IOUtils
  , System.JSON
  , System.RegularExpressions
  ;

const
  MIN_CAPTION_PREFIX = 12;  { FeatureGen.Check.pas MIN_CAPTION_PREFIX: the same prefix rule }
  PATH_SEP = ' > ';

{ ---- TMenuRegistry ---- }

constructor TMenuRegistry.Create;
begin
  inherited Create;
  FSurfaces:= TList<TRegistrySurface>.Create;
  FExempt  := TList<string>.Create;
end;

destructor TMenuRegistry.Destroy;
begin
  FExempt.Free;
  FSurfaces.Free;
  inherited Destroy;
end;

procedure TMenuRegistry.AddSurface(const pEntryId, pPath: string);
var
  S: TRegistrySurface;
begin
  S.EntryId:= pEntryId;
  S.Path   := pPath;
  S.Key    := MenuPathKey(pPath);
  FSurfaces.Add(S);
end;

procedure TMenuRegistry.LoadFromDir(const pDir: string);
var
  F, Id, Typ: string;
  V         : TJSONValue;
  Arr       : TJSONArray;
  Item      : TJSONValue;
  Caps      : TJSONObject;
  Pair      : TJSONPair;
begin
  if not TDirectory.Exists(TPath.Combine(pDir, 'entries')) then
    raise EMenuDriftSetup.CreateFmt('registry has no entries folder: %s', [TPath.Combine(pDir, 'entries')]);
  for F in TDirectory.GetFiles(TPath.Combine(pDir, 'entries'), '*.json') do
  begin
    V:= TJSONObject.ParseJSONValue(TFile.ReadAllText(F, TEncoding.UTF8));
    if not (V is TJSONObject) then
    begin
      V.Free;
      raise EMenuDriftSetup.CreateFmt('registry entry is not a JSON object: %s', [F]);
    end;
    try
      Id:= TJSONObject(V).GetValue<string>('id', TPath.GetFileNameWithoutExtension(F));
      if TJSONObject(V).TryGetValue<TJSONArray>('surfaces', Arr) then
        for Item in Arr do
          if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('type', Typ) and SameText(Typ, 'ide-menu') then
            AddSurface(Id, TJSONObject(Item).GetValue<string>('path', ''));
    finally
      V.Free;
    end;
  end;
  LoadFamilies(TPath.Combine(TPath.Combine(pDir, 'generated'), 'manifest.json'));
  F:= TPath.Combine(pDir, 'exemptions.json');
  if not TFile.Exists(F) then Exit;
  V:= TJSONObject.ParseJSONValue(TFile.ReadAllText(F, TEncoding.UTF8));
  try
    if (V is TJSONObject) and TJSONObject(V).TryGetValue<TJSONObject>('captions', Caps) then
      for Pair in Caps do FExempt.Add(Pair.JsonString.Value);
  finally
    V.Free;
  end;
end;

procedure TMenuRegistry.LoadFamilies(const pManifest: string);
var
  V       : TJSONValue;
  Fams    : TJSONObject;
  Fam     : TJSONPair;
  Child   : TJSONValue;
  Arr     : TJSONArray;
  Item    : TJSONValue;
  Id, Typ : string;
begin
  if not TFile.Exists(pManifest) then Exit;
  V:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pManifest, TEncoding.UTF8));
  try
    if not ((V is TJSONObject) and TJSONObject(V).TryGetValue<TJSONObject>('families', Fams)) then Exit;
    for Fam in Fams do
      if Fam.JsonValue is TJSONArray then
        for Child in TJSONArray(Fam.JsonValue) do
          if (Child is TJSONObject) and TJSONObject(Child).TryGetValue<TJSONArray>('surfaces', Arr) then
          begin
            Id:= TJSONObject(Child).GetValue<string>('id', Fam.JsonString.Value);
            for Item in Arr do
              if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('type', Typ) and SameText(Typ, 'ide-menu') then
                AddSurface(Id, TJSONObject(Item).GetValue<string>('path', ''));
          end;
  finally
    V.Free;
  end;
end;

{ ---- TMenuDriftReport ---- }

constructor TMenuDriftReport.Create;
begin
  inherited Create;
  FMissing     := TList<TDriftMissing>.Create;
  FMoved       := TList<TDriftMoved>.Create;
  FUnregistered:= TList<TDriftUnregistered>.Create;
  FNotes       := TList<string>.Create;
end;

destructor TMenuDriftReport.Destroy;
begin
  FNotes.Free;
  FUnregistered.Free;
  FMoved.Free;
  FMissing.Free;
  inherited Destroy;
end;

function TMenuDriftReport.HasDrift: Boolean;
begin
  Result:= (FMissing.Count > 0) or (FMoved.Count > 0) or (FUnregistered.Count > 0);
end;

function TMenuDriftReport.SummaryLine: string;
begin
  Result:= Format('menu-drift: missing=%d unregistered=%d moved=%d notes=%d',
    [FMissing.Count, FUnregistered.Count, FMoved.Count, FNotes.Count]);
end;

function TMenuDriftReport.ToText: string;
var
  SB: TStringBuilder;
  M : TDriftMissing;
  V : TDriftMoved;
  U : TDriftUnregistered;
  N : string;
begin
  SB:= TStringBuilder.Create;
  try
    for M in FMissing do
    begin
      SB.Append('MISSING ').Append(M.Path).Append('  (entry ').Append(M.Entry).Append(')');
      if M.Hint <> '' then SB.Append('  ').Append(M.Hint);
      SB.Append(sLineBreak);
    end;
    for V in FMoved do
      SB.Append('MOVED ').Append(V.Path).Append('  (entry ').Append(V.Entry).Append(')  now at ').Append(V.NowAt).Append(sLineBreak);
    for U in FUnregistered do
    begin
      SB.Append('UNREGISTERED ').Append(U.Path).Append('  -> ').Append(U.Handler).Append('  (').Append(U.Source).Append(')').Append(sLineBreak);
      SB.Append('  skeleton: ').Append(U.Skeleton).Append(sLineBreak);
    end;
    for N in FNotes do SB.Append('NOTE ').Append(N).Append(sLineBreak);
    SB.Append(SummaryLine).Append(sLineBreak);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMenuDriftReport.ToJson: string;
var
  O, Row, Sum: TJSONObject;
  Arr        : TJSONArray;
  M          : TDriftMissing;
  V          : TDriftMoved;
  U          : TDriftUnregistered;
  N          : string;
begin
  O:= TJSONObject.Create;
  try
    O.AddPair('schema', 'menu-drift/1');
    Arr:= TJSONArray.Create;
    for M in FMissing do
    begin
      Row:= TJSONObject.Create;
      Row.AddPair('path', M.Path);
      Row.AddPair('entry', M.Entry);
      Row.AddPair('hint', M.Hint);
      Arr.AddElement(Row);
    end;
    O.AddPair('missing', Arr);
    Arr:= TJSONArray.Create;
    for V in FMoved do
    begin
      Row:= TJSONObject.Create;
      Row.AddPair('path', V.Path);
      Row.AddPair('entry', V.Entry);
      Row.AddPair('nowAt', V.NowAt);
      Arr.AddElement(Row);
    end;
    O.AddPair('moved', Arr);
    Arr:= TJSONArray.Create;
    for U in FUnregistered do
    begin
      Row:= TJSONObject.Create;
      Row.AddPair('path', U.Path);
      Row.AddPair('handler', U.Handler);
      Row.AddPair('source', U.Source);
      Row.AddPair('skeleton', U.Skeleton);
      Arr.AddElement(Row);
    end;
    O.AddPair('unregistered', Arr);
    Arr:= TJSONArray.Create;
    for N in FNotes do Arr.Add(N);
    O.AddPair('notes', Arr);
    Sum:= TJSONObject.Create;
    Sum.AddPair('missing', TJSONNumber.Create(FMissing.Count));
    Sum.AddPair('unregistered', TJSONNumber.Create(FUnregistered.Count));
    Sum.AddPair('moved', TJSONNumber.Create(FMoved.Count));
    Sum.AddPair('notes', TJSONNumber.Create(FNotes.Count));
    O.AddPair('summary', Sum);
    Result:= O.Format(2);
  finally
    O.Free;
  end;
end;

{ ---- ComputeMenuDrift ---- }

function ParentKey(const pPathKey: string): string;
var
  I: Integer;
begin
  I:= pPathKey.LastIndexOf(PATH_SEP);
  Result:= if I >= 0 then pPathKey.Substring(0, I) else '';
end;

function LeafKey(const pPathKey: string): string;
var
  I: Integer;
begin
  I:= pPathKey.LastIndexOf(PATH_SEP);
  Result:= if I >= 0 then pPathKey.Substring(I + Length(PATH_SEP)) else pPathKey;
end;

{ FeatureGen.Check RegistryCaptionMatch: equal, or one a prefix of the other
  with the shorter at least MIN_CAPTION_PREFIX characters. }
function CaptionMatch(const pA, pB: string): Boolean;
var
  Short: Integer;
begin
  if (pA = '') or (pB = '') then Exit(False);
  if pA = pB then Exit(True);
  Short:= if Length(pA) < Length(pB) then Length(pA) else Length(pB);
  Result:= (Short >= MIN_CAPTION_PREFIX) and (pA.StartsWith(pB) or pB.StartsWith(pA));
end;

function CommonPrefix(const pA, pB: string): Integer;
begin
  Result:= 0;
  while (Result < Length(pA)) and (Result < Length(pB)) and (pA.Chars[Result] = pB.Chars[Result]) do Inc(Result);
end;

function JsonText(const pS: string): string;
var
  S: TJSONString;
begin
  S:= TJSONString.Create(pS);
  try
    Result:= S.ToJSON;
  finally
    S.Free;
  end;
end;

{ stale-looking exemption (spec 7 note row): an exempted caption that the
  kind model now sees as a container / header / root -- it no longer needs exempting }
procedure CollectContainers(pNode: TMenuNode; const pPrefix: string; pAcc: TList<string>);
var
  C   : TMenuNode;
  Path: string;
begin
  Path:= if pPrefix = '' then pNode.DisplayCaption else pPrefix + PATH_SEP + pNode.DisplayCaption;
  if pNode.Kind in [mnkRoot, mnkSubmenu] then pAcc.Add(MenuPathKey(Path));
  for C in pNode.Children do CollectContainers(C, Path, pAcc);
end;

procedure CollectStructural(pNode: TMenuNode; pAcc: TDictionary<string, TMenuNodeKind>);
var
  C: TMenuNode;
begin
  if pNode.Kind in [mnkRoot, mnkSubmenu, mnkHeader] then pAcc.AddOrSetValue(pNode.CaptionKey, pNode.Kind);
  for C in pNode.Children do CollectStructural(C, pAcc);
end;

function ComputeMenuDrift(pTree: TMenuTree; pRegistry: TMenuRegistry): TMenuDriftReport;
var
  Live      : TList<TMenuLeaf>;
  L         : TMenuLeaf;
  LiveKeys  : TDictionary<string, Integer>;
  RegKeys   : TDictionary<string, Integer>;
  DynParents: TList<string>;
  MovedTo   : TList<string>;
  Containers: TList<string>;
  Struct    : TDictionary<string, TMenuNodeKind>;
  R         : TRegistrySurface;
  I, Best, P: Integer;
  K, PK, LK : string;
  Miss      : TDriftMissing;
  Mov       : TDriftMoved;
  Unr       : TDriftUnregistered;
  Covered   : Boolean;
  Exempt    : Boolean;
  E         : string;
  N         : TMenuNode;
  Kind      : TMenuNodeKind;
begin
  Result:= TMenuDriftReport.Create;
  Live      := TList<TMenuLeaf>.Create;
  LiveKeys  := TDictionary<string, Integer>.Create;
  RegKeys   := TDictionary<string, Integer>.Create;
  DynParents:= TList<string>.Create;
  MovedTo   := TList<string>.Create;
  Containers:= TList<string>.Create;
  Struct    := TDictionary<string, TMenuNodeKind>.Create;
  try
    for L in pTree.Leaves do
    begin
      if L.External then Continue;
      if L.Kind = mnkDynamic then
      begin
        DynParents.Add(MenuPathKey(L.ParentPath));
        Continue;
      end;
      Live.Add(L);
      LiveKeys.AddOrSetValue(MenuPathKey(L.Path), Live.Count - 1);
    end;
    for I:= 0 to pRegistry.Surfaces.Count - 1 do RegKeys.AddOrSetValue(pRegistry.Surfaces[I].Key, I);
    for N in pTree.Roots do CollectContainers(N, '', Containers);

    { missing / moved }
    for R in pRegistry.Surfaces do
    begin
      { a path naming a live submenu is that submenu's own surface (drag-lint > Reports) }
      if (R.Key = '') or LiveKeys.ContainsKey(R.Key) or Containers.Contains(R.Key) then Continue;
      PK:= ParentKey(R.Key);
      LK:= LeafKey(R.Key);
      if DynParents.Contains(PK) then Continue;  { the dynamic item may be it; its note says so }
      Best:= -1;
      for I:= 0 to Live.Count - 1 do
        if MenuCaptionKey(Live[I].Caption) = LK then
        begin
          Best:= I;
          Break;
        end;
      if Best >= 0 then
      begin
        Mov.Path := R.Path;
        Mov.Entry:= R.EntryId;
        Mov.NowAt:= Live[Best].Path;
        Result.Moved.Add(Mov);
        MovedTo.Add(MenuPathKey(Live[Best].Path));
        Continue;
      end;
      Miss.Path := R.Path;
      Miss.Entry:= R.EntryId;
      Miss.Hint := '';
      Best:= -1;
      P:= MIN_CAPTION_PREFIX - 1;
      for I:= 0 to Live.Count - 1 do
      begin
        K:= MenuPathKey(Live[I].Path);
        if (ParentKey(K) <> PK) or RegKeys.ContainsKey(K) then Continue;
        if CommonPrefix(LeafKey(K), LK) > P then
        begin
          P:= CommonPrefix(LeafKey(K), LK);
          Best:= I;
        end;
      end;
      if Best >= 0 then Miss.Hint:= 'renamed? -> ' + QuotedStr(Live[Best].Caption.Replace('&&', '&'));
      Result.Missing.Add(Miss);
    end;

    { unregistered }
    for L in Live do
    begin
      K:= MenuPathKey(L.Path);
      if RegKeys.ContainsKey(K) or MovedTo.Contains(K) then Continue;
      Covered:= False;
      for R in pRegistry.Surfaces do
        if (ParentKey(R.Key) = ParentKey(K)) and CaptionMatch(LeafKey(R.Key), LeafKey(K)) then
        begin
          Covered:= True;
          Break;
        end;
      if Covered then Continue;
      Exempt:= False;
      for E in pRegistry.Exempt do
        if MenuCaptionKey(E) = MenuCaptionKey(L.Caption) then
        begin
          Exempt:= True;
          Break;
        end;
      if Exempt then Continue;
      Unr.Path    := L.Path;
      Unr.Handler := L.Handler;
      Unr.Source  := L.Source;
      Unr.Skeleton:= '{ "type": "ide-menu", "path": ' + JsonText(L.Path) + ' }';
      Result.Unregistered.Add(Unr);
    end;

    { notes: the tree's own (dynamic captions, unparented items), then stale-looking exemptions }
    for E in pTree.Notes do Result.Notes.Add(E);
    for N in pTree.Roots do CollectStructural(N, Struct);
    for E in pRegistry.Exempt do
      if Struct.TryGetValue(MenuCaptionKey(E), Kind) then
        Result.Notes.Add(Format('exemption %s is a %s in the live tree -- the kind model no longer needs it exempted',
          [QuotedStr(E), MenuKindName(Kind)]));
  finally
    Struct.Free;
    Containers.Free;
    MovedTo.Free;
    DynParents.Free;
    RegKeys.Free;
    LiveKeys.Free;
    Live.Free;
  end;
end;

end.
