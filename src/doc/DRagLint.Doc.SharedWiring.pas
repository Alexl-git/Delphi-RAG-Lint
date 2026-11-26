unit DRagLint.Doc.SharedWiring;

{ The `Registered as:` fact of a unit several projects compile (Q21, 1.54.1).

  THE PROBLEM. The fact is a join over THIS project's di_bindings. ORM3 SERVER
  registers every COMMON business object, CLIENT registers four of them, each
  has its own index, and each `document` run replaced the other's line.

  THE RULE is the one the inbound facts have (DRagLint.Doc.SharedFacts): the
  line is the union over the projects, each entry tagged with the projects that
  render it -- `[SrvApp]IFoo (transient)` -- and a run adds and removes only its
  own tag.

  WHY NOT AN INBOUND LABEL. The inbound rules judge an entry by the unit it
  names. A registration names an interface, which both projects hold, so the
  registering unit cannot be read off the entry. Evidence that another project
  documents the unit is therefore taken from the whole FILE, not from the
  block: the registrar of the other project names the class (`Used by:` /
  `Used in units:` of the class block), while the method blocks that repeat the
  line often hold no inbound fact at all.

  ONLY ON EVIDENCE. Without it -- no `dl:shared` marker, no tag, no unit this
  index does not hold anywhere in the file -- the fact is exactly what the index
  renders, untagged, as before.

  RUN BEFORE THE RENDER. The writer and the checker both replace Facts.Wiring by
  the reconciled entries, so the two cannot disagree and the byte compare of the
  rest of the block is untouched. }

interface

uses
  DRagLint.Core.Interfaces;

/// <summary>The wiring fact this project writes for a symbol, the parts other
/// projects contributed to the stored block put back.</summary>
/// <param name="AWiring">TDocFacts.Wiring as this index renders it: `di:` and
/// `ds:` entries joined by `; `, unescaped.</param>
/// <param name="AStoredBody">The stored managed block's body
/// (TSharedFacts.StoredBlockBody); empty when the symbol has none.</param>
/// <param name="AStore">The index the facts come from.</param>
/// <param name="AUnitPath">The declaring file; read for the `dl:shared` marker
/// and for evidence in its other blocks.</param>
/// <returns>AWiring unchanged when nothing shows that another project documents
/// the unit; else the same string with the `di:` entries reconciled.</returns>
/// <remarks>Per entry: rendered here -- kept, TSharedFacts.ProjectTag added;
/// stored only and tagged -- own tag removed, dropped when no tag is left;
/// stored only and untagged -- kept (its project cannot be told), unless this
/// project registers the same interface itself, which supersedes it. An entry of
/// a project that is gone stays until `doc-forget` reaps its tag. Without a
/// project tag (several `--db`) no tag is added or removed. Not thread-safe: one
/// file's evidence is cached.</remarks>
function ReconcileWiring(const AWiring, AStoredBody: string; const AStore: ISymbolStore;
  const AUnitPath: string): string;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Core.Encoding    { ReadSourceFileText }
  , DRagLint.Doc.Regions      // dl:unit DRagLint.Doc.Regions accepted -- AUTO_BEGIN/AUTO_END are the managed-block fence TDocRegions writes; every reader of a block must share them (B-33 item 1)
  , DRagLint.Doc.ProjectTags
  , DRagLint.Doc.SharedFacts
  , DRagLint.Lint.SharedUnit
  ;

const
  DI_PREFIX     = 'di:';
  WIRING_SEP    = '; ';
  PARA_OPEN     = '<para>';
  DOC_SLASHES   = '///';
  LIFETIME_OPEN = ' (';

type
  { One entry of the line: what it says and which projects said it. }
  TWiringEntry = record
    Bare: string;
    Tags: TArray<string>;
  end;

var
  { The last file asked about. Analyze and the writer walk a unit declaration by
    declaration, so one file is enough; the stamp drops it when the file changes. }
  FEvidenceKey: string  = '';
  FEvidence   : Boolean = False;

{ Does any managed block of AUnitPath show another project, or carry a tag on its
  own `Registered as:` line? }
function FileNamesOtherProject(const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  Text, Body: string;
  B, E      : Integer;
begin
  Result:= False;
  Text:= ReadSourceFileText(AUnitPath);
  B:= Pos(AUTO_BEGIN, Text);
  while (B > 0) and not Result do
  begin
    Inc(B, Length(AUTO_BEGIN));
    E:= PosEx(AUTO_END, Text, B);
    if E = 0 then Exit;
    Body  := Copy(Text, B, E - B).Replace(DOC_SLASHES, '');
    Result:= Body.Contains(PARA_OPEN + WIRING_LABEL + ' [') or TSharedFacts.BlockNamesOtherProject(Body, AStore);
    B:= PosEx(AUTO_BEGIN, Text, E);
  end;
end;

{ Is the unit documented by another project, as far as this index can tell? }
function SeenElsewhere(const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  Stamp: TDateTime;
  Key  : string;
begin
  if not FileAge(AUnitPath, Stamp) then Exit(False);
  Key:= Format('%p|%s|%x', [Pointer(AStore), AUnitPath, PInt64(@Stamp)^]);
  if Key <> FEvidenceKey then
  begin
    FEvidence   := TSharedUnit.IsShared(AUnitPath) or FileNamesOtherProject(AStore, AUnitPath);
    FEvidenceKey:= Key;
  end;
  Result:= FEvidence;
end;

{ The content of the stored line, unescaped, or ''. The renderer wraps every fact
  in its own para; an unwrapped (pre-2026-08-24) line has no reliable end and is
  left to the fresh render. }
function StoredWiring(const AStoredBody: string): string;
var
  P, E: Integer;
begin
  Result:= '';
  P:= Pos(PARA_OPEN + WIRING_LABEL, AStoredBody);
  if P = 0 then Exit;
  Inc(P, Length(PARA_OPEN + WIRING_LABEL));
  E:= PosEx('<', AStoredBody, P);
  if E = 0 then Exit;
  Result:= Copy(AStoredBody, P, E - P).Replace('&lt;', '<').Replace('&gt;', '>').Replace('&amp;', '&');
end;

{ The interface an entry registers: the entry without its ` (lifetime)`. }
function InterfaceOf(const ABare: string): string;
var
  P: Integer;
begin
  P:= ABare.LastIndexOf(LIFETIME_OPEN);
  Result:= if P > 0 then Copy(ABare, 1, P) else ABare;
end;

function IndexOfBare(const AList: TList<TWiringEntry>; const ABare: string): Integer;
begin
  for Result:= 0 to AList.Count - 1 do
    if SameText(AList[Result].Bare, ABare) then Exit;
  Result:= -1;
end;

function RegistersInterface(const AList: TList<TWiringEntry>; const ABare: string): Boolean;
var
  W: TWiringEntry;
begin
  Result:= False;
  for W in AList do
    if SameText(InterfaceOf(W.Bare), InterfaceOf(ABare)) then Exit(True);
end;

{ AEntries (spelled `[A,B]bare`) added to AList, a repeat merging its tags. }
procedure AddEntries(const AList: TList<TWiringEntry>; const AEntries: TArray<string>);
var
  E   : string;
  W   : TWiringEntry;
  Tags: TArray<string>;
  Bare: string;
  At  : Integer;
begin
  for E in AEntries do
  begin
    SplitTagged(E, Tags, Bare);
    At    := IndexOfBare(AList, Bare);
    W.Bare:= Bare;
    W.Tags:= if At >= 0 then AList[At].Tags + Tags else Tags;
    if At >= 0 then AList[At]:= W else AList.Add(W);
  end;
end;

{ The entries to write, sorted by name: AFresh under this project's tag, then what
  of AStored belongs to others. See ReconcileWiring's remarks for the rules. }
function MergedEntries(const AStored, AFresh: TList<TWiringEntry>; const AOwn: string): TArray<string>;
var
  W   : TWiringEntry;
  At  : Integer;
  Tags: TArray<string>;
begin
  Result:= nil;
  for W in AFresh do
  begin
    At  := IndexOfBare(AStored, W.Bare);
    Tags:= if At >= 0 then AStored[At].Tags else nil;
    if AOwn <> '' then Tags:= Tags + [AOwn];
    Result:= Result + [FormatTagged(Tags, W.Bare)];
  end;
  for W in AStored do
  begin
    if IndexOfBare(AFresh, W.Bare) >= 0 then Continue;
    if Length(W.Tags) = 0 then
    begin
      if (AOwn = '') or not RegistersInterface(AFresh, W.Bare) then Result:= Result + [W.Bare];
      Continue;
    end;
    Tags:= if AOwn = '' then W.Tags else WithoutTag(W.Tags, AOwn);
    if Length(Tags) > 0 then Result:= Result + [FormatTagged(Tags, W.Bare)];
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const X, Y: string): Integer
    begin
      Result:= TSharedFacts.CompareInboundEntries(X, Y);
    end));
end;

function ReconcileWiring(const AWiring, AStoredBody: string; const AStore: ISymbolStore;
  const AUnitPath: string): string;
var
  Content      : string;
  Part         : string;
  Others, Parts: TArray<string>;
  Stored, Fresh: TList<TWiringEntry>;
begin
  Result := AWiring;
  Content:= StoredWiring(AStoredBody);
  if (AStore = nil) or ((Content = '') and not AWiring.Contains(DI_PREFIX)) then Exit;
  if not SeenElsewhere(AStore, AUnitPath) then Exit;

  Others:= nil;
  Stored:= TList<TWiringEntry>.Create;
  Fresh := TList<TWiringEntry>.Create;
  try
    AddEntries(Stored, SplitWiringEntries(Content));
    for Part in AWiring.Split([WIRING_SEP]) do
      if StartsStr(DI_PREFIX, Part) then AddEntries(Fresh, [Copy(Part, Length(DI_PREFIX) + 1, MaxInt)])
      else if Part <> '' then Others:= Others + [Part];
    Parts:= nil;
    for Part in MergedEntries(Stored, Fresh, TSharedFacts.ProjectTag) do Parts:= Parts + [DI_PREFIX + Part];
    Result:= string.Join(WIRING_SEP, Parts + Others);
  finally
    Fresh.Free;
    Stored.Free;
  end;
end;

end.
