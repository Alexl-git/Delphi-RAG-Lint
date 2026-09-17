unit DRagLint.Convert.GlyphVacuum;

{ drag-lint glyph-vacuum: walk .dfm/.fmx files under one or more roots, extract
  every streamed graphic, decode it (DRagLint.Convert.GlyphStrip), pair it with
  its count property and write a reviewable table + gallery.
  Spec: docs\superpowers\specs\2026-09-17-glyph-vacuum-design.md }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.Core.Interfaces;

type
  /// <summary>Inputs of one vacuum run.</summary>
  /// <remarks>Stores may be empty: the qualification columns (class_unit,
  /// count_default, count_effective's default half, runtime_refs) then stay
  /// empty rather than guessed. Append merges into an existing OutDir keyed on
  /// (dfm_path, object_path, property); a re-scan is idempotent.</remarks>
  TGlyphVacuumOptions = record
    Roots : TArray<string>;
    OutDir: string;
    Append: Boolean;
    Stores: TArray<ISymbolStore>;
  end;

  /// <summary>The counts the CLI prints as its one summary line.</summary>
  TGlyphVacuumSummary = record
    DfmFiles        : Integer;
    Graphics        : Integer;
    DistinctPayloads: Integer;
    Skipped         : Integer;
  end;

  /// <summary>One row of instances.tsv: one (component, graphic property).</summary>
  /// <remarks>Column order in the file is the field order here; a new column
  /// is appended at the end so an older instances.tsv still parses under
  /// --append. Every value is written verbatim with tabs/newlines replaced by
  /// spaces.</remarks>
  TGlyphRow = record
    DfmPath        : string;
    PasUnit        : string;
    Surface        : string;
    FormClass      : string;
    ObjectPath     : string;
    ComponentName  : string;
    ComponentClass : string;
    ClassUnit      : string;
    Inherited_     : string;
    Prop           : string;
    Kind           : string;
    Wrapper        : string;
    Format         : string;
    Bytes          : Integer;
    Width          : Integer;
    Height         : Integer;
    Bpp            : Integer;
    PaletteEntries : Integer;
    CountProp      : string;
    CountValue     : string;
    CountDefault   : string;
    CountEffective : string;
    InferredN      : string;
    Agree          : string;
    PayloadSha     : string;
    ImageFile      : string;
  end;

/// <summary>Run the vacuum. Creates OutDir, writes instances.tsv, classes.tsv,
/// skipped.tsv, gallery.html and images\.</summary>
/// <param name="AOpts">Roots, output directory, append flag, optional stores.</param>
/// <param name="ASummary">Counts for the CLI summary line.</param>
/// <param name="AError">Set when the result is False (a root missing, OutDir not
/// creatable).</param>
/// <returns>True when the walk completed; a tree with no graphics is True with
/// Graphics = 0.</returns>
function RunGlyphVacuum(const AOpts: TGlyphVacuumOptions;
  out ASummary: TGlyphVacuumSummary; out AError: string): Boolean;

implementation

uses
  System.IOUtils,
  System.Hash,
  System.StrUtils,
  System.Generics.Defaults,
  DRagLint.Core.Model,
  DRagLint.Convert.DfmReemit,
  DRagLint.Convert.GlyphStrip,
  DRagLint.Convert.PropTree;

const
  InstancesHeader =
    'dfm_path' + #9 + 'pas_unit' + #9 + 'surface' + #9 + 'form_class' + #9 +
    'object_path' + #9 + 'component_name' + #9 + 'component_class' + #9 +
    'class_unit' + #9 + 'inherited' + #9 + 'property' + #9 + 'kind' + #9 +
    'wrapper' + #9 + 'format' + #9 + 'bytes' + #9 + 'width' + #9 + 'height' + #9 +
    'bpp' + #9 + 'palette_entries' + #9 + 'count_prop' + #9 + 'count_value' + #9 +
    'count_default' + #9 + 'count_effective' + #9 + 'inferred_n' + #9 + 'agree' + #9 +
    'payload_sha' + #9 + 'image_file';

function Cell(const S: string): string;
begin
  Result:= StringReplace(StringReplace(S, #9, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Result:= StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

function RowLine(const R: TGlyphRow): string;
begin
  Result:= String.Join(#9, [
    Cell(R.DfmPath), Cell(R.PasUnit), R.Surface, Cell(R.FormClass), Cell(R.ObjectPath),
    Cell(R.ComponentName), Cell(R.ComponentClass), Cell(R.ClassUnit), R.Inherited_,
    Cell(R.Prop), R.Kind, Cell(R.Wrapper), R.Format, IntToStr(R.Bytes), IntToStr(R.Width),
    IntToStr(R.Height), IntToStr(R.Bpp), IntToStr(R.PaletteEntries), Cell(R.CountProp),
    Cell(R.CountValue), Cell(R.CountDefault), R.CountEffective, R.InferredN, R.Agree,
    R.PayloadSha, R.ImageFile]);
end;

// UTF-8 without a BOM: TFile.WriteAllText(.., TEncoding.UTF8) would prepend one,
// and a BOM in column 1 of a TSV header is a column called '?dfm_path'.
procedure WriteUtf8NoBom(const APath, AText: string);
begin
  TFile.WriteAllBytes(APath, TEncoding.UTF8.GetBytes(AText));
end;

function ImageExt(const AFormat: string): string;
begin
  if AFormat = '' then Result:= '.bin' else Result:= '.' + AFormat;
end;

// SHA-256 of the RAW payload bytes. THashSHA2 has no GetHashString(TBytes)
// overload (string/RawByteString/TStream/file only), so this hashes via the
// instance Update/HashAsString path rather than routing bytes through a string
// encoding, which would change the digest.
function Sha256Hex(const ABytes: TBytes): string;
var
  Hasher: THashSHA2;
begin
  Hasher:= THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  Hasher.Update(ABytes);
  Result:= LowerCase(Hasher.HashAsString);
end;

// The image bytes only (the wrapper preamble stripped), so a browser and a
// paint program open the file as the image it is.
procedure SaveImage(const AOutDir: string; const APayload: TBytes; const AG: TStreamedGraphic; const AFile: string);
var
  Img : TBytes;
  Path: string;
begin
  Path:= TPath.Combine(AOutDir, AFile);
  if TFile.Exists(Path) then Exit; { keyed on sha: same bytes, same file }
  if AG.Ok and (AG.ImageLength > 0) then
  begin
    SetLength(Img, AG.ImageLength);
    Move(APayload[AG.ImageOffset], Img[0], AG.ImageLength);
  end
  else
    Img:= APayload;
  TFile.WriteAllBytes(Path, Img);
end;

type
  // Per-class qualification, resolved through the stores at most once per run.
  TClassFacts = record
    Resolved   : Boolean;   // a store declared the class
    QName      : string;    // Unit.TClass
    UnitName   : string;
    Tree       : TPropTree;
    RuntimeRefs: Integer;   // -1 = no store
  end;

  TVacuumState = record
    Rows       : TList<TGlyphRow>;
    Shas       : TDictionary<string, Boolean>;
    OutDir     : string;
    ImgDir     : string;
    Summary    : TGlyphVacuumSummary;
    Stores     : TArray<ISymbolStore>;
    Facts      : TDictionary<string, TClassFacts>;
    RefsCounted: TDictionary<string, Boolean>;
  end;

const
  CountPropNames: array[0..3] of string = ('NumGlyphs', 'GlyphCount', 'NumStates', 'ImageCount');

function IsCountPropName(const AName: string): Boolean;
var S: string;
begin
  Result:= False;
  for S in CountPropNames do
    if SameText(S, AName) then Exit(True);
end;

// The first scalar sibling on the same object whose name is a known count
// property. Empty when there is none -- the caller must not invent a value.
procedure FindCountProp(const AObject: TDfmNode; out AName, AValue: string);
var C: TDfmNode;
begin
  AName := '';
  AValue:= '';
  for C in AObject.Children do
    if (C.Kind = dnkScalar) and IsCountPropName(C.Name) then
    begin
      AName := C.Name;
      AValue:= Trim(C.ValueText);
      Exit;
    end;
end;

// count_effective/inferred_n/agree/kind, derived from what's already on the
// row. count_default (the --db half) is Task 3's; here it is always ''.
procedure FillDerived(var R: TGlyphRow; const AObjectClass: string; AInCollection: Boolean);
var
  Eff, Inf: Integer;
begin
  if R.CountValue <> '' then R.CountEffective:= R.CountValue
  else R.CountEffective:= R.CountDefault;
  if (R.Height > 0) and (R.Width mod R.Height = 0) then R.InferredN:= IntToStr(R.Width div R.Height)
  else R.InferredN:= '';
  Eff:= StrToIntDef(R.CountEffective, 0);
  Inf:= StrToIntDef(R.InferredN, 0);
  if (R.CountEffective <> '') and (R.InferredN <> '') then
  begin
    if Eff = Inf then R.Agree:= 'Y' else R.Agree:= 'N';
  end
  else
    R.Agree:= '';
  if AInCollection or (SameText(R.Prop, 'Bitmap') and ContainsText(AObjectClass, 'ImageList')) then
    R.Kind:= 'container'
  else if (Eff > 1) or (Inf > 1) then
    R.Kind:= 'strip'
  else
    R.Kind:= 'single';
end;

// Resolve a bare .dfm class name once per run through the stores, in order:
// the first store declaring a class of that name wins. No store, or no such
// class, leaves the qualification columns EMPTY -- never guessed from the name.
function FactsFor(const ABareClass: string; const AStores: TArray<ISymbolStore>;
  var AState: TVacuumState): TClassFacts;
var
  S   : ISymbolStore;
  Syms: TArray<TSymbol>;
  Sym : TSymbol;
  Opts: TPropTreeOptions;
  P   : Integer;
begin
  if AState.Facts.TryGetValue(LowerCase(ABareClass), Result) then Exit;
  Result:= Default(TClassFacts);
  Result.RuntimeRefs:= -1;
  for S in AStores do
  begin
    Syms:= S.FindSymbolsByExactName(ABareClass);
    for Sym in Syms do
      if Sym.Kind = skClass then
      begin
        Result.Resolved:= True;
        Result.QName   := Sym.QualifiedName;
        P:= LastDelimiter('.', Sym.QualifiedName);
        Result.UnitName:= Copy(Sym.QualifiedName, 1, P - 1);
        Opts:= Default(TPropTreeOptions);
        Result.Tree:= BuildPropTree(S, Sym.QualifiedName, Opts);
        Result.RuntimeRefs:= 0;
        Break;
      end;
    if Result.Resolved then Break;
  end;
  AState.Facts.Add(LowerCase(ABareClass), Result);
end;

// Resolved .pas references to <declaring-class>.<prop> (reads and writes; a
// `Picture.Assign(..)` is a read of Picture followed by a call). Over-counts
// assignments, which is the safe direction for a sizing number. An inherited
// property is not redeclared on AQName, so its symbol lives under the class
// that DOES declare it -- ATree's own node for AProp names that class via
// DeclaredIn; fall back to AQName when the tree has no node for AProp (a
// property the tree does not know).
function CountRuntimeRefs(const AStores: TArray<ISymbolStore>; const AQName, AProp: string;
  const ATree: TPropTree): Integer;
var
  S    : ISymbolStore;
  Syms : TArray<TSymbol>;
  Sym  : TSymbol;
  Refs : TArray<TReference>;
  Ref  : TReference;
  N    : TPropNode;
  Owner: string;
begin
  Result:= 0;
  Owner:= AQName;
  for N in ATree.Nodes do
    if SameText(N.Path, AProp) then
    begin
      Owner:= N.DeclaredIn;
      Break;
    end;
  for S in AStores do
  begin
    Syms:= S.FindSymbolsByQualifiedName(Owner + '.' + AProp);
    for Sym in Syms do
    begin
      Refs:= S.FindReferencesTo(Sym.Id);
      for Ref in Refs do
        if EndsText('.pas', S.GetFilePath(Ref.FileId)) then Inc(Result);
    end;
  end;
end;

// The graphic property a leaf path names: the first segment before a '.' or a
// collection index '[' -- 'Picture.Data' -> 'Picture', 'ImageInfo[0].Image.Data'
// -> 'ImageInfo' (the collection property, not the item's own nested leaf).
function GraphicPropName(const AProp: string): string;
var PDot, PBrack, P: Integer;
begin
  PDot  := Pos('.', AProp);
  PBrack:= Pos('[', AProp);
  if PDot = 0 then P:= PBrack
  else if PBrack = 0 then P:= PDot
  else if PDot < PBrack then P:= PDot
  else P:= PBrack;
  if P = 0 then Result:= AProp else Result:= Copy(AProp, 1, P - 1);
end;

// Builds and files one row for one decoded payload -- the binary-leaf path and
// the collection-item path (HarvestCollection) both funnel through here so the
// derived columns are computed exactly once, the same way, everywhere.
procedure AddRow(const AObject: TDfmNode; const ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath, AProp: string;  // dl:ok too-many-parameters@1d66
  const APayload: TBytes; AInCollection: Boolean; var AState: TVacuumState);
var
  G     : TStreamedGraphic;
  R     : TGlyphRow;
  Facts : TClassFacts;
  Def   : string;
  Name  : string;
  Prop  : string;
  RefKey: string;
begin
  G:= ParseStreamedGraphic(APayload);
  R:= Default(TGlyphRow);
  R.DfmPath       := ADfmPath;
  R.PasUnit       := APasUnit;
  R.Surface       := ASurface;
  R.FormClass     := AFormClass;
  R.ObjectPath    := AObjectPath;
  R.ComponentName := AObject.Name;
  R.ComponentClass:= AObject.ClassName_;
  if SameText(AObject.Keyword, 'inherited') or SameText(AObject.Keyword, 'inline') then R.Inherited_:= 'Y';
  R.Prop          := AProp;
  R.Wrapper       := G.Wrapper;
  R.Format        := G.Format;
  R.Bytes         := Length(APayload);
  R.Width         := G.Width;
  R.Height        := G.Height;
  R.Bpp           := G.BitCount;
  R.PaletteEntries:= G.PaletteEntries;
  FindCountProp(AObject, R.CountProp, R.CountValue);
  Facts:= FactsFor(AObject.ClassName_, AState.Stores, AState);
  if Facts.Resolved then
  begin
    R.ClassUnit:= Facts.UnitName;
    if R.CountProp <> '' then
    begin
      // the object streamed a known count property explicitly: look up ITS default.
      if LeafDefaultOf(Facts.Tree, R.CountProp, Def) then R.CountDefault:= Def;
    end
    else
      // no count property streamed (its value equals the class's own default,
      // so the .dfm omits it) -- the class may still declare one; the first
      // known name with a usable default stands in for it.
      for Name in CountPropNames do
        if LeafDefaultOf(Facts.Tree, Name, Def) then
        begin
          R.CountProp   := Name;
          R.CountDefault:= Def;
          Break;
        end;
    Prop  := GraphicPropName(AProp);
    RefKey:= LowerCase(Facts.QName) + '.' + LowerCase(Prop);
    if not AState.RefsCounted.ContainsKey(RefKey) then
    begin
      Facts.RuntimeRefs:= Facts.RuntimeRefs + CountRuntimeRefs(AState.Stores, Facts.QName, Prop, Facts.Tree);
      AState.RefsCounted.Add(RefKey, True);
      AState.Facts.AddOrSetValue(LowerCase(AObject.ClassName_), Facts);
    end;
  end;
  FillDerived(R, AObject.ClassName_, AInCollection);
  R.PayloadSha    := Sha256Hex(APayload);
  R.ImageFile     := 'images\' + R.PayloadSha + ImageExt(G.Format);
  SaveImage(AState.OutDir, APayload, G, R.ImageFile);
  AState.Shas.AddOrSetValue(R.PayloadSha, True);
  AState.Rows.Add(R);
  Inc(AState.Summary.Graphics);
end;

// A collection value is verbatim `< item ... end item ... end>` text; the
// re-emit parser does not descend into it. Every `<Name> = {hex}` inside becomes
// one row named <CollectionProp>[i].<Name>, i counting `item` keywords from 0.
procedure HarvestCollection(const AObject: TDfmNode; const ACollProp: TDfmNode;  // dl:ok too-many-parameters@b1c3
  const ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath: string; var AState: TVacuumState);
var
  Text   : string;
  P, Q   : Integer;
  ItemIx : Integer;
  Name   : string;
  Line   : string;
  Payload: TBytes;
begin
  Text  := ACollProp.ValueText;
  ItemIx:= -1;
  P     := 1;
  while P <= Length(Text) do
  begin
    Q:= P;
    while (Q <= Length(Text)) and (Text[Q] <> #10) do Inc(Q);
    Line:= Trim(Copy(Text, P, Q - P));
    if SameText(Line, 'item') then Inc(ItemIx)
    else if EndsText('= {', Line) or (Pos(' = {', Line) > 0) then
    begin
      Name:= Trim(Copy(Line, 1, Pos('=', Line) - 1));
      // the hex runs from after the opening brace to the closing brace
      P:= Q;
      Q:= PosEx('}', Text, P);
      if Q = 0 then Break;
      Payload:= DecodeDfmHex(Copy(Text, P, Q - P));
      if Length(Payload) > 0 then
        AddRow(AObject, ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath,
          Format('%s[%d].%s', [ACollProp.Name, ItemIx, Name]), Payload, True, AState);
    end;
    P:= Q + 1;
  end;
end;

// Walks ANode's own children: recurses into nested dnkSubObject children
// (their own name joins AObjectPath, dotted), harvests every dnkBinary
// (streamed graphic) child in place, and expands every dnkCollection child's
// items. AObjectPath is ANode's OWN dotted path ('' for the form itself, which
// never appears in an emitted object_path).
procedure HarvestObject(const ANode: TDfmNode; const ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath: string;
  var AState: TVacuumState);
var
  Child    : TDfmNode;
  ChildPath: string;
  Payload  : TBytes;
begin
  for Child in ANode.Children do
  begin
    if Child.Kind = dnkSubObject then
    begin
      if AObjectPath = '' then ChildPath:= Child.Name else ChildPath:= AObjectPath + '.' + Child.Name;
      HarvestObject(Child, ADfmPath, APasUnit, ASurface, AFormClass, ChildPath, AState);
      Continue;
    end;
    if Child.Kind = dnkCollection then
    begin
      HarvestCollection(ANode, Child, ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath, AState);
      Continue;
    end;
    if Child.Kind <> dnkBinary then Continue;
    Payload:= DecodeDfmHex(Child.ValueText);
    if Length(Payload) = 0 then Continue;
    AddRow(ANode, ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath, Child.Name, Payload, False, AState);
  end;
end;

procedure HarvestFile(const APath: string; var AState: TVacuumState);
var
  Text   : string;
  Root   : TDfmNode;
  PasUnit: string;
  Surface: string;
begin
  Inc(AState.Summary.DfmFiles);
  Text:= TFile.ReadAllText(APath);
  if SameText(TPath.GetExtension(APath), '.fmx') then Surface:= 'fmx' else Surface:= 'dfm';
  PasUnit:= TPath.ChangeExtension(TPath.GetFileName(APath), '.pas');
  if not TFile.Exists(TPath.Combine(TPath.GetDirectoryName(APath), PasUnit)) then PasUnit:= '';
  Root:= nil;
  if not ParseDfmBlock(Text, Root) then
  begin
    Inc(AState.Summary.Skipped);
    Exit;
  end;
  try
    { The form itself never appears in an object_path: it is already carried
      as FormClass/dfm_path, so the walk starts at ITS children with an empty
      path prefix -- see HarvestObject's own remark. }
    HarvestObject(Root, APath, PasUnit, Surface, Root.ClassName_, '', AState);
  finally
    Root.Free;
  end;
end;

type
  // Per-class accumulator for classes.tsv, keyed on LowerCase(component_class).
  // Five owned dictionaries: a record read out of a TDictionary is a COPY, so
  // every mutation is written back with Aggs[Key]:= A.
  TClassAgg = record
    ClassName_ : string;
    ClassUnit  : string;
    Instances  : Integer;
    Props      : TDictionary<string, Integer>;
    CountProps : TDictionary<string, Integer>;
    CountDef   : string;
    NDist      : TDictionary<string, Integer>;
    InfDist    : TDictionary<string, Integer>;
    Disagree   : Integer;
    Formats    : TDictionary<string, Integer>;
    Shas       : TDictionary<string, Integer>;
    RuntimeRefs: Integer;
  end;

// value:count pairs, sorted by value descending (numeric keys first, then
// name ascending), the empty value last as '?:count'.
function DistText(const AD: TDictionary<string, Integer>): string;
var
  Keys : TArray<string>;
  K    : string;
  Parts: TArray<string>;
begin
  Keys:= AD.Keys.ToArray;
  TArray.Sort<string>(Keys, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      if (L = '') and (R = '') then Exit(0);
      if L = '' then Exit(1);
      if R = '' then Exit(-1);
      Result:= StrToIntDef(R, -1) - StrToIntDef(L, -1);
      if Result = 0 then Result:= CompareText(L, R);
    end));
  Parts:= nil;
  for K in Keys do
    if K = '' then Parts:= Parts + ['?:' + IntToStr(AD[K])]
    else Parts:= Parts + [K + ':' + IntToStr(AD[K])];
  Result:= String.Join(';', Parts);
end;

// The dictionary's keys alone, sorted with CompareText and joined -- for the
// columns that list distinct names (graphic_props/count_props), not counts.
function KeysText(const AD: TDictionary<string, Integer>): string;
var
  Keys: TArray<string>;
begin
  Keys:= AD.Keys.ToArray;
  TArray.Sort<string>(Keys, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result:= CompareText(L, R);
    end));
  Result:= String.Join(';', Keys);
end;

procedure Bump(const AD: TDictionary<string, Integer>; const AKey: string);
var V: Integer;
begin
  if AD.TryGetValue(AKey, V) then AD[AKey]:= V + 1 else AD.Add(AKey, 1);
end;

function ClassRowLine(const A: TClassAgg): string;
var Runtime: string;
begin
  if A.RuntimeRefs = -1 then Runtime:= '' else Runtime:= IntToStr(A.RuntimeRefs);
  Result:= String.Join(#9, [
    Cell(A.ClassName_), Cell(A.ClassUnit), IntToStr(A.Instances), Cell(KeysText(A.Props)),
    Cell(KeysText(A.CountProps)), Cell(A.CountDef), DistText(A.NDist), DistText(A.InfDist),
    IntToStr(A.Disagree), DistText(A.Formats), IntToStr(A.Shas.Count), Runtime]);
end;

// One row per distinct component_class (case-insensitive), sorted by class
// name. Stores may be empty: class_unit/count_default/runtime_refs then stay
// empty, matching instances.tsv's own qualification columns.
procedure WriteClassesTsv(const AOutDir: string; const ARows: TList<TGlyphRow>; var AState: TVacuumState);
const
  Header = 'component_class' + #9 + 'class_unit' + #9 + 'instances' + #9 + 'graphic_props' + #9 +
           'count_props' + #9 + 'count_default' + #9 + 'n_distribution' + #9 + 'inferred_distribution' + #9 +
           'disagreements' + #9 + 'formats' + #9 + 'distinct_payloads' + #9 + 'runtime_refs';
var
  Aggs : TDictionary<string, TClassAgg>;
  Keys : TArray<string>;
  K    : string;
  A    : TClassAgg;
  R    : TGlyphRow;
  SB   : TStringBuilder;
begin
  Aggs:= TDictionary<string, TClassAgg>.Create;
  try
    for R in ARows do
    begin
      K:= LowerCase(R.ComponentClass);
      if not Aggs.TryGetValue(K, A) then
      begin
        A:= Default(TClassAgg);
        A.ClassName_:= R.ComponentClass;
        A.ClassUnit := R.ClassUnit;
        A.Props     := TDictionary<string, Integer>.Create;
        A.CountProps:= TDictionary<string, Integer>.Create;
        A.NDist     := TDictionary<string, Integer>.Create;
        A.InfDist   := TDictionary<string, Integer>.Create;
        A.Formats   := TDictionary<string, Integer>.Create;
        A.Shas      := TDictionary<string, Integer>.Create;
      end;
      Inc(A.Instances);
      Bump(A.Props, R.Prop);
      if R.CountProp <> '' then Bump(A.CountProps, R.CountProp);
      if R.CountDefault <> '' then A.CountDef:= R.CountDefault;
      Bump(A.NDist, R.CountEffective);
      Bump(A.InfDist, R.InferredN);
      if R.Agree = 'N' then Inc(A.Disagree);
      Bump(A.Formats, R.Format);
      A.Shas.AddOrSetValue(R.PayloadSha, 1);
      A.RuntimeRefs:= FactsFor(R.ComponentClass, AState.Stores, AState).RuntimeRefs;
      Aggs.AddOrSetValue(K, A);
    end;

    Keys:= Aggs.Keys.ToArray;
    TArray.Sort<string>(Keys, TComparer<string>.Construct(
      function(const AL, ARr: string): Integer
      begin
        Result:= CompareText(Aggs[AL].ClassName_, Aggs[ARr].ClassName_);
      end));

    SB:= TStringBuilder.Create;
    try
      SB.Append(Header).Append(#13#10);
      for K in Keys do SB.Append(ClassRowLine(Aggs[K])).Append(#13#10);
      WriteUtf8NoBom(TPath.Combine(AOutDir, 'classes.tsv'), SB.ToString);
    finally
      SB.Free;
    end;
  finally
    for K in Aggs.Keys do
    begin
      A:= Aggs[K];
      A.Props.Free;
      A.CountProps.Free;
      A.NDist.Free;
      A.InfDist.Free;
      A.Formats.Free;
      A.Shas.Free;
    end;
    Aggs.Free;
  end;
end;

function RunGlyphVacuum(const AOpts: TGlyphVacuumOptions;
  out ASummary: TGlyphVacuumSummary; out AError: string): Boolean;
var
  State: TVacuumState;
  Root : string;
  F    : string;
  SB   : TStringBuilder;
  R    : TGlyphRow;
begin
  Result  := False;
  AError  := '';
  ASummary:= Default(TGlyphVacuumSummary);
  for Root in AOpts.Roots do
    if not TDirectory.Exists(Root) then
    begin
      AError:= 'root does not exist: ' + Root;
      Exit;
    end;
  State:= Default(TVacuumState);
  State.OutDir:= AOpts.OutDir;
  State.ImgDir:= TPath.Combine(AOpts.OutDir, 'images');
  State.Stores:= AOpts.Stores;
  try
    TDirectory.CreateDirectory(State.ImgDir);
  except
    on E: Exception do
    begin
      AError:= 'cannot create --out: ' + E.Message;
      Exit;
    end;
  end;
  State.Rows       := TList<TGlyphRow>.Create;
  State.Shas       := TDictionary<string, Boolean>.Create;
  State.Facts      := TDictionary<string, TClassFacts>.Create;
  State.RefsCounted:= TDictionary<string, Boolean>.Create;
  SB:= TStringBuilder.Create;
  try
    for Root in AOpts.Roots do
    begin
      for F in TDirectory.GetFiles(Root, '*.dfm', TSearchOption.soAllDirectories) do HarvestFile(F, State);
      for F in TDirectory.GetFiles(Root, '*.fmx', TSearchOption.soAllDirectories) do HarvestFile(F, State);
    end;
    SB.Append(InstancesHeader).Append(#13#10);
    for R in State.Rows do SB.Append(RowLine(R)).Append(#13#10);
    WriteUtf8NoBom(TPath.Combine(AOpts.OutDir, 'instances.tsv'), SB.ToString);
    WriteClassesTsv(AOpts.OutDir, State.Rows, State);
    State.Summary.DistinctPayloads:= State.Shas.Count;
    ASummary:= State.Summary;
    Result  := True;
  finally
    SB.Free;
    State.RefsCounted.Free;
    State.Facts.Free;
    State.Shas.Free;
    State.Rows.Free;
  end;
end;

end.
