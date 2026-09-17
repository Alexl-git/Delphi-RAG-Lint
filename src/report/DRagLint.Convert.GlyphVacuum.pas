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
  System.Math,
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
    Skipped    : TList<TPair<string, string>>; // (dfm_path, reason); see skipped.tsv
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

const
  FilerSignature = 'TPF0';
  SignatureScan  = 64;

// A binary .dfm starts with the filer signature (sometimes after a small
// resource header). Convert it in memory; the file is never written.
//
// Uses ObjectBinaryToText, NOT ObjectResourceToText, despite the latter's name
// looking like the fit: System.Classes.pas (RAD Studio 37.0) shows
// ObjectResourceToText calling Input.ReadResHeader FIRST -- it expects a
// compiled .RES-style header BEFORE the signature -- and only then forwards to
// ObjectBinaryToText. ObjectBinaryToText itself calls Reader.ReadSignature,
// which reads and validates the 4-byte 'TPF0' marker from the stream's CURRENT
// position -- that is the one that matches "positioned at the signature".
// Calling ObjectResourceToText directly on a TPF0-positioned stream makes
// ReadResHeader treat 'TPF0' as a resource header and raise EInvalidImage
// ('Invalid stream format'); confirmed against the hand-built fixture.
function BinaryDfmToText(const ABytes: TBytes; out AText: string): Boolean;
var
  Sig  : Integer;
  I    : Integer;
  InS  : TBytesStream;
  OutS : TStringStream;
begin
  Result:= False;
  AText := '';
  Sig   := -1;
  for I:= 0 to Min(SignatureScan, Length(ABytes) - Length(FilerSignature)) do
    if (ABytes[I] = Ord('T')) and (ABytes[I + 1] = Ord('P')) and (ABytes[I + 2] = Ord('F')) and
       (ABytes[I + Length(FilerSignature) - 1] = Ord('0')) then
    begin
      Sig:= I;
      Break;
    end;
  if Sig < 0 then Exit;
  InS := TBytesStream.Create(ABytes);
  OutS:= TStringStream.Create('', TEncoding.UTF8);
  try
    InS.Position:= Sig;
    ObjectBinaryToText(InS, OutS);
    AText := OutS.DataString;
    Result:= True;
  finally
    OutS.Free;
    InS.Free;
  end;
end;

// Records one file the walk could not turn into rows -- never dropped
// silently. AReason is the parse/read failure text verbatim; Summary.Skipped
// and skipped.tsv are the only places a caller learns this file was seen.
procedure Skip(const APath, AReason: string; var AState: TVacuumState);
begin
  AState.Skipped.Add(TPair<string, string>.Create(APath, AReason));
  Inc(AState.Summary.Skipped);
end;

procedure HarvestFile(const APath: string; var AState: TVacuumState);
var
  Bytes  : TBytes;
  Text   : string;
  Root   : TDfmNode;
  PasUnit: string;
  Surface: string;
begin
  Inc(AState.Summary.DfmFiles);
  try
    Bytes:= TFile.ReadAllBytes(APath);
    // FilerSignature (TPF0) means the file is a compiled binary .dfm --
    // convert it in memory; otherwise it is already a text .dfm (ANSI).
    if not BinaryDfmToText(Bytes, Text) then
      Text:= TEncoding.Default.GetString(Bytes);
    if SameText(TPath.GetExtension(APath), '.fmx') then Surface:= 'fmx' else Surface:= 'dfm';
    PasUnit:= TPath.ChangeExtension(TPath.GetFileName(APath), '.pas');
    if not TFile.Exists(TPath.Combine(TPath.GetDirectoryName(APath), PasUnit)) then PasUnit:= '';
    Root:= nil;
    if not ParseDfmBlock(Text, Root) then
    begin
      Skip(APath, 'not a parseable text .dfm', AState);
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
  except
    // A locked or unreadable .dfm (or a conversion/parse that raised rather
    // than returning False) must not abort the whole walk -- list it and
    // continue with the next file (Task 1 review finding, deferred here).
    on E: Exception do
      Skip(APath, E.Message, AState);
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
        // Register immediately: if anything below raises, the outer `finally`
        // walks Aggs to free these six dictionaries -- they must already be
        // reachable from it, not stranded in a local that never got written back.
        Aggs.Add(K, A);
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

const
  GalleryHead =
    '<!DOCTYPE html><html><head><meta charset="utf-8"><title>glyph-vacuum gallery</title>' +
    '<style>body{font-family:Segoe UI,Arial,sans-serif;margin:16px}h2{border-bottom:1px solid #999}' +
    '.card{display:inline-block;vertical-align:top;margin:8px;padding:8px;border:1px solid #ccc}' +
    '.box{position:relative;display:inline-block;background:#eee}.box img{display:block;image-rendering:pixelated}' +
    '.sep{position:absolute;top:0;bottom:0;width:0;border-left:1px dashed #e00}' +
    '.cap{font-size:12px;margin-top:4px}.paths{font-size:11px;color:#555}</style></head><body>';
  GalleryTail = '</body></html>';
  GalleryMaxPaths = 3;

// & first, then < and >, so an already-escaped '&amp;' never becomes '&amp;amp;'.
function Esc(const S: string): string;
begin
  Result:= StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result:= StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result:= StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

type
  // One card per distinct payload_sha within a class: Rep is the first row
  // seen for that sha (its geometry/caption fields), Count is every row
  // sharing the sha, Paths the first GalleryMaxPaths object_paths.
  TGalleryCard = record
    Rep  : TGlyphRow;
    Count: Integer;
    Paths: TArray<string>;
  end;

  // Per-class card set, keyed on payload_sha. A record read out of a
  // TDictionary is a COPY (Task 4's lesson): every card mutation is written
  // back with Cards.AddOrSetValue; the Cards dictionary itself is a class
  // reference, so no write-back is needed for it once the class row exists.
  TGalleryClass = record
    ClassName_: string;
    Cards     : TDictionary<string, TGalleryCard>;
  end;

// One <h2> per component_class (CompareText order), one .card per distinct
// payload_sha within that class -- see the unit banner's Spec for the layout.
procedure WriteGalleryHtml(const AOutDir: string; const ARows: TList<TGlyphRow>);
var
  Classes: TDictionary<string, TGalleryClass>;
  Keys   : TArray<string>;
  Shas   : TArray<string>;
  K, Sha : string;
  GC     : TGalleryClass;
  Card   : TGalleryCard;
  R      : TGlyphRow;
  SB     : TStringBuilder;
  N, I   : Integer;
begin
  Classes:= TDictionary<string, TGalleryClass>.Create;
  try
    for R in ARows do
    begin
      K:= LowerCase(R.ComponentClass);
      if not Classes.TryGetValue(K, GC) then
      begin
        GC:= Default(TGalleryClass);
        GC.ClassName_:= R.ComponentClass;
        GC.Cards     := TDictionary<string, TGalleryCard>.Create;
        Classes.Add(K, GC);
      end;
      if not GC.Cards.TryGetValue(R.PayloadSha, Card) then
      begin
        Card:= Default(TGalleryCard);
        Card.Rep:= R;
      end;
      Inc(Card.Count);
      if Length(Card.Paths) < GalleryMaxPaths then Card.Paths:= Card.Paths + [R.ObjectPath];
      GC.Cards.AddOrSetValue(R.PayloadSha, Card);
    end;

    Keys:= Classes.Keys.ToArray;
    TArray.Sort<string>(Keys, TComparer<string>.Construct(
      function(const AL, ARr: string): Integer
      begin
        Result:= CompareText(Classes[AL].ClassName_, Classes[ARr].ClassName_);
      end));

    SB:= TStringBuilder.Create;
    try
      SB.Append(GalleryHead);
      for K in Keys do
      begin
        GC:= Classes[K];
        SB.AppendFormat('<h2>%s</h2>', [Esc(GC.ClassName_)]);
        Shas:= GC.Cards.Keys.ToArray;
        for Sha in Shas do
        begin
          Card:= GC.Cards[Sha];
          R   := Card.Rep;
          if R.Width > 0 then
            SB.AppendFormat('<div class="card"><div class="box" style="width:%dpx;height:%dpx">',
              [R.Width, R.Height])
          else
            SB.Append('<div class="card"><div class="box" style="width:auto;height:auto">');
          SB.AppendFormat('<img src="%s" alt="">', [StringReplace(R.ImageFile, '\', '/', [rfReplaceAll])]);
          N:= StrToIntDef(R.CountEffective, 0);
          if (N > 1) and (R.Width > 0) and (R.Width mod N = 0) then
            for I:= 1 to N - 1 do
              SB.AppendFormat('<div class="sep" style="left:%dpx"></div>', [I * (R.Width div N)]);
          SB.Append('</div>');
          SB.AppendFormat('<div class="cap">%s | N=%s inferred=%s agree=%s | %dx%dx%d %s | shared by %d instance(s)</div>',
            [Esc(R.Prop), R.CountEffective, R.InferredN, R.Agree, R.Width, R.Height, R.Bpp, R.Format, Card.Count]);
          SB.AppendFormat('<div class="paths">%s</div></div>', [Esc(String.Join(', ', Card.Paths))]);
        end;
      end;
      SB.Append(GalleryTail);
      WriteUtf8NoBom(TPath.Combine(AOutDir, 'gallery.html'), SB.ToString);
    finally
      SB.Free;
    end;
  finally
    for K in Classes.Keys do Classes[K].Cards.Free;
    Classes.Free;
  end;
end;

// dfm_path <TAB> reason, one line per file HarvestFile could not turn into
// rows. Always written -- header only when nothing was skipped -- so its
// absence is never mistaken for "everything parsed".
procedure WriteSkippedTsv(const AOutDir: string; const ASkipped: TList<TPair<string, string>>);
const
  Header = 'dfm_path' + #9 + 'reason';
var
  SB: TStringBuilder;
  P : TPair<string, string>;
begin
  SB:= TStringBuilder.Create;
  try
    SB.Append(Header).Append(#13#10);
    for P in ASkipped do
      SB.Append(Cell(P.Key)).Append(#9).Append(Cell(P.Value)).Append(#13#10);
    WriteUtf8NoBom(TPath.Combine(AOutDir, 'skipped.tsv'), SB.ToString);
  finally
    SB.Free;
  end;
end;

// (dfm_path, object_path, property), case-insensitive: the merge key for
// --append. Two rows with the same key are the same instance across runs.
function RowKey(const R: TGlyphRow): string;
begin
  Result:= LowerCase(R.DfmPath) + '|' + LowerCase(R.ObjectPath) + '|' + LowerCase(R.Prop);
end;

// Read an existing instances.tsv by COLUMN NAME so a file written by an older
// build (fewer columns) still loads; unknown columns are ignored, missing ones
// read as ''.
procedure LoadExistingRows(const APath: string; const AInto: TDictionary<string, TGlyphRow>);
var
  Lines: TArray<string>;
  Hdr  : TArray<string>;
  Cols : TDictionary<string, Integer>;
  I, K : Integer;
  F    : TArray<string>;
  R    : TGlyphRow;
  function Col(const AName: string): string;
  var Ix: Integer;
  begin
    if Cols.TryGetValue(AName, Ix) and (Ix < Length(F)) then Result:= F[Ix] else Result:= '';
  end;
begin
  if not TFile.Exists(APath) then Exit;
  Lines:= TFile.ReadAllLines(APath, TEncoding.UTF8);
  if Length(Lines) = 0 then Exit;
  Hdr := Lines[0].Split([#9]);
  Cols:= TDictionary<string, Integer>.Create;
  try
    for K:= 0 to High(Hdr) do Cols.AddOrSetValue(Hdr[K], K);
    for I:= 1 to High(Lines) do
    begin
      if Trim(Lines[I]) = '' then Continue;
      F:= Lines[I].Split([#9]);
      R:= Default(TGlyphRow);
      R.DfmPath:= Col('dfm_path');
      R.PasUnit:= Col('pas_unit');
      R.Surface:= Col('surface');
      R.FormClass:= Col('form_class');
      R.ObjectPath:= Col('object_path');
      R.ComponentName:= Col('component_name');
      R.ComponentClass:= Col('component_class');
      R.ClassUnit:= Col('class_unit');
      R.Inherited_:= Col('inherited');
      R.Prop:= Col('property');
      R.Kind:= Col('kind');
      R.Wrapper:= Col('wrapper');
      R.Format:= Col('format');
      R.Bytes:= StrToIntDef(Col('bytes'), 0);
      R.Width:= StrToIntDef(Col('width'), 0);
      R.Height:= StrToIntDef(Col('height'), 0);
      R.Bpp:= StrToIntDef(Col('bpp'), 0);
      R.PaletteEntries:= StrToIntDef(Col('palette_entries'), 0);
      R.CountProp:= Col('count_prop');
      R.CountValue:= Col('count_value');
      R.CountDefault:= Col('count_default');
      R.CountEffective:= Col('count_effective');
      R.InferredN:= Col('inferred_n');
      R.Agree:= Col('agree');
      R.PayloadSha:= Col('payload_sha');
      R.ImageFile:= Col('image_file');
      AInto.AddOrSetValue(RowKey(R), R);
    end;
  finally
    Cols.Free;
  end;
end;

// Total order for the WRITE set (merged or not) so a --append run's
// instances.tsv/classes.tsv/gallery.html do not depend on walk order.
function CompareRowsForWrite(const L, R: TGlyphRow): Integer;
begin
  Result:= CompareText(L.DfmPath, R.DfmPath);
  if Result = 0 then Result:= CompareText(L.ObjectPath, R.ObjectPath);
  if Result = 0 then Result:= CompareText(L.Prop, R.Prop);
end;

function RunGlyphVacuum(const AOpts: TGlyphVacuumOptions;
  out ASummary: TGlyphVacuumSummary; out AError: string): Boolean;
var
  State    : TVacuumState;
  Root     : string;
  F        : string;
  SB       : TStringBuilder;
  R        : TGlyphRow;
  Merged   : TDictionary<string, TGlyphRow>;
  WriteRows: TList<TGlyphRow>;
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
  State.Skipped    := TList<TPair<string, string>>.Create;
  SB:= TStringBuilder.Create;
  try
    for Root in AOpts.Roots do
    begin
      for F in TDirectory.GetFiles(Root, '*.dfm', TSearchOption.soAllDirectories) do HarvestFile(F, State);
      for F in TDirectory.GetFiles(Root, '*.fmx', TSearchOption.soAllDirectories) do HarvestFile(F, State);
    end;
    if AOpts.Append then
    begin
      Merged:= TDictionary<string, TGlyphRow>.Create;
      try
        LoadExistingRows(TPath.Combine(AOpts.OutDir, 'instances.tsv'), Merged);
        for R in State.Rows do Merged.AddOrSetValue(RowKey(R), R);
        WriteRows:= TList<TGlyphRow>.Create(Merged.Values);
      finally
        Merged.Free;
      end;
      WriteRows.Sort(TComparer<TGlyphRow>.Construct(
        function(const L, Rr: TGlyphRow): Integer
        begin
          Result:= CompareRowsForWrite(L, Rr);
        end));
    end
    else
      WriteRows:= TList<TGlyphRow>.Create(State.Rows);
    try
      SB.Append(InstancesHeader).Append(#13#10);
      for R in WriteRows do SB.Append(RowLine(R)).Append(#13#10);
      WriteUtf8NoBom(TPath.Combine(AOpts.OutDir, 'instances.tsv'), SB.ToString);
      WriteClassesTsv(AOpts.OutDir, WriteRows, State);
      WriteGalleryHtml(AOpts.OutDir, WriteRows);
      WriteSkippedTsv(AOpts.OutDir, State.Skipped);
    finally
      WriteRows.Free;
    end;
    State.Summary.DistinctPayloads:= State.Shas.Count;
    ASummary:= State.Summary;
    Result  := True;
  finally
    SB.Free;
    State.Skipped.Free;
    State.RefsCounted.Free;
    State.Facts.Free;
    State.Shas.Free;
    State.Rows.Free;
  end;
end;

end.
