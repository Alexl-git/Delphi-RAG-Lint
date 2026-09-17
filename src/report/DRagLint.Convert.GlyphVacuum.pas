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
  DRagLint.Convert.DfmReemit,
  DRagLint.Convert.GlyphStrip;

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
  TVacuumState = record
    Rows   : TList<TGlyphRow>;
    Shas   : TDictionary<string, Boolean>;
    OutDir : string;
    ImgDir : string;
    Summary: TGlyphVacuumSummary;
  end;

// Walks ANode's own children: recurses into nested dnkSubObject children
// (their own name joins AObjectPath, dotted) and harvests every dnkBinary
// (streamed graphic) child in place. AObjectPath is ANode's OWN dotted path
// ('' for the form itself, which never appears in an emitted object_path).
procedure HarvestObject(const ANode: TDfmNode; const ADfmPath, APasUnit, ASurface, AFormClass, AObjectPath: string;
  var AState: TVacuumState);
var
  Child    : TDfmNode;
  ChildPath: string;
  Payload  : TBytes;
  G        : TStreamedGraphic;
  R        : TGlyphRow;
begin
  for Child in ANode.Children do
  begin
    if Child.Kind = dnkSubObject then
    begin
      if AObjectPath = '' then ChildPath:= Child.Name else ChildPath:= AObjectPath + '.' + Child.Name;
      HarvestObject(Child, ADfmPath, APasUnit, ASurface, AFormClass, ChildPath, AState);
      Continue;
    end;
    if Child.Kind <> dnkBinary then Continue;
    Payload:= DecodeDfmHex(Child.ValueText);
    if Length(Payload) = 0 then Continue;
    G:= ParseStreamedGraphic(Payload);
    R:= Default(TGlyphRow);
    R.DfmPath       := ADfmPath;
    R.PasUnit       := APasUnit;
    R.Surface       := ASurface;
    R.FormClass     := AFormClass;
    R.ObjectPath    := AObjectPath;
    R.ComponentName := ANode.Name;
    R.ComponentClass:= ANode.ClassName_;
    R.Prop          := Child.Name;
    R.Kind          := 'single';
    R.Wrapper       := G.Wrapper;
    R.Format        := G.Format;
    R.Bytes         := Length(Payload);
    R.Width         := G.Width;
    R.Height        := G.Height;
    R.Bpp           := G.BitCount;
    R.PaletteEntries:= G.PaletteEntries;
    R.PayloadSha    := Sha256Hex(Payload);
    R.ImageFile     := 'images\' + R.PayloadSha + ImageExt(G.Format);
    SaveImage(AState.OutDir, Payload, G, R.ImageFile);
    AState.Shas.AddOrSetValue(R.PayloadSha, True);
    AState.Rows.Add(R);
    Inc(AState.Summary.Graphics);
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
  try
    TDirectory.CreateDirectory(State.ImgDir);
  except
    on E: Exception do
    begin
      AError:= 'cannot create --out: ' + E.Message;
      Exit;
    end;
  end;
  State.Rows:= TList<TGlyphRow>.Create;
  State.Shas:= TDictionary<string, Boolean>.Create;
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
    State.Summary.DistinctPayloads:= State.Shas.Count;
    ASummary:= State.Summary;
    Result  := True;
  finally
    SB.Free;
    State.Shas.Free;
    State.Rows.Free;
  end;
end;

end.
