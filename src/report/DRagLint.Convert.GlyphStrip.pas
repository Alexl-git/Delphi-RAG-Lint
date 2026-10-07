unit DRagLint.Convert.GlyphStrip;

{ Pure reader for graphics streamed into a .dfm. No I/O, no VCL. The G[I/N]
  stitcher (docs\superpowers\specs\2026-09-17-glyph-strip-G-grammar-design.md)
  joins this unit later; the vacuum verb is its first consumer. }

interface

uses
  System.SysUtils;

type
  /// <summary>What a streamed graphic payload turned out to be, decoded from
  /// its bytes -- never inferred from the property name.</summary>
  /// <remarks>
  /// A .dfm `Picture.Data` blob is a streamed TPicture: one length
  /// byte, that many class-name bytes, then that graphic class's own framing --
  /// an Int32 size before the image for TBitmap / TJPEGImage, none for TIcon /
  /// TPngImage / TGIFImage / TWICImage (TGraphicDataFraming; one source of truth
  /// with UnwrapGraphicData since 1.26.2). ImageOffset / ImageLength locate the
  /// TRUE image; both are 0 when the wrapper names a class whose framing is not
  /// known, or whose bytes do not hold a recognised image -- the offset is then
  /// not guessed, and Format comes from the class name alone. A bare image (no preamble) is recognised by its magic bytes at
  /// offset 0 -- or, when it starts with '&lt;?xml'/'&lt;svg' (an optional UTF-8
  /// BOM and whitespace skipped), as SVG text -- and reported with an empty
  /// Wrapper. A TBitmap-typed property streams as [Int32 LE length][image bytes]
  /// with no class name at all; that length-prefixed shape is also reported with
  /// an empty Wrapper. Width/Height/BitCount/PaletteEntries are filled for BMP
  /// only; every other format, including SVG, leaves them 0.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.GlyphStrip.pas), DRagLint.Convert.GlyphStrip.ParseStreamedGraphic (DRagLint.Convert.GlyphStrip.pas), DRagLint.Convert.GlyphStrip.ReadDibHeader (DRagLint.Convert.GlyphStrip.pas), DRagLint.Convert.GlyphVacuum.AddRow (DRagLint.Convert.GlyphVacuum.pas), DRagLint.Convert.GlyphVacuum.SaveImage (DRagLint.Convert.GlyphVacuum.pas)</para>
  /// <para>Used in units: DRagLint.Convert.GlyphStrip, DRagLint.Convert.GlyphVacuum</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TStreamedGraphic = record
    Ok            : Boolean;
    Wrapper       : string;
    Format        : string;
    ImageOffset   : Integer;
    ImageLength   : Integer;
    Width         : Integer;
    Height        : Integer;
    BitCount      : Integer;
    PaletteEntries: Integer;
  end;

/// <summary>Decode a .dfm binary-property value (`{ 4A0B... }`, any whitespace,
/// either case) into bytes. Non-hex characters are skipped; an odd trailing
/// nibble is dropped.</summary>
/// <param name="AValueText">The verbatim value text as TDfmNode.ValueText holds it.</param>
/// <returns>The decoded bytes; empty for an empty or non-hex value.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Convert.DfmReemit.ReemitBlock.TranscodeKeptBytes (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.GlyphVacuum.HarvestCollection (DRagLint.Convert.GlyphVacuum.pas), DRagLint.Convert.GlyphVacuum.HarvestObject (DRagLint.Convert.GlyphVacuum.pas)</para>
/// <para>Calls: Byte, CharInSet, Copy, StrToIntDef, UpCase</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DecodeDfmHex(const AValueText: string): TBytes;

/// <summary>Image format from the magic bytes at <paramref name="AOffset"/>.</summary>
/// <param name="ABytes">The payload bytes to sniff.</param>
/// <param name="AOffset">Byte offset within <paramref name="ABytes"/> to read the magic number from.</param>
/// <returns>'bmp' | 'ico' | 'wmf' | 'emf' | 'png' | 'jpg' | 'gif' | 'svg' | '' (unrecognised).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Convert.GlyphStrip.IsLengthPrefixedImage (DRagLint.Convert.GlyphStrip.pas), DRagLint.Convert.GlyphStrip.UnwrapGraphicData (DRagLint.Convert.GlyphStrip.pas)</para>
/// <para>Calls: DRagLint.Convert.GlyphStrip.IsEmfSignature, DRagLint.Convert.GlyphStrip.LooksLikeSvg, DRagLint.Convert.GlyphStrip.StartsWith</para>
/// <para>Returns: ''</para>
/// <seealso cref="DRagLint.Convert.GlyphStrip.IsEmfSignature"/>
/// <seealso cref="DRagLint.Convert.GlyphStrip.LooksLikeSvg"/>
/// <seealso cref="DRagLint.Convert.GlyphStrip.StartsWith"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SniffImageFormat(const ABytes: TBytes; AOffset: Integer): string;

/// <summary>Decode a streamed graphic payload: wrapper preamble first (the
/// writer's own declaration), magic bytes as the fallback, then the BMP DIB
/// header when the image is a BMP.</summary>
/// <param name="APayload">The whole property value, decoded from hex.</param>
/// <returns>Ok=False when neither a preamble nor a magic is recognised; every
/// numeric field 0 and Format '' in that case.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Convert.GlyphVacuum.AddRow (DRagLint.Convert.GlyphVacuum.pas)</para>
/// <para>Calls: Default, DRagLint.Convert.GlyphStrip.FormatDeclaredBy, DRagLint.Convert.GlyphStrip.ReadDibHeader, DRagLint.Convert.GlyphStrip.ReadPictureClassName, DRagLint.Convert.GlyphStrip.UnwrapGraphicData</para>
/// <para>Returns: Default(TStreamedGraphic)</para>
/// <seealso cref="DRagLint.Convert.GlyphStrip.FormatDeclaredBy"/>
/// <seealso cref="DRagLint.Convert.GlyphStrip.ReadDibHeader"/>
/// <seealso cref="DRagLint.Convert.GlyphStrip.ReadPictureClassName"/>
/// <seealso cref="DRagLint.Convert.GlyphStrip.UnwrapGraphicData"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseStreamedGraphic(const APayload: TBytes): TStreamedGraphic;

type
  /// <summary>The FILER FRAMING a graphic property's binary <c>Data</c> uses:
  /// what surrounds the image file when the property is streamed into a .dfm.
  /// It differs per graphic class, so a payload is carried between two
  /// properties by unwrapping one framing and wrapping the other -- never by
  /// copying the bytes.</summary>
  /// <remarks>
  /// Read from the sources (RAD Studio 37 Vcl.Graphics / Vcl.Imaging.*,
  /// DevExpress RS37 dxSmartImage / dxGDIPlusClasses), not inferred:
  /// <para>gdfGraphic -- TGraphic.WriteData / ReadData: the bare image file
  /// (SaveToStream / LoadFromStream). TIcon, TPngImage, TGIFImage and TWICImage
  /// do not override it; nor do TdxSmartImage / TdxSmartGlyph, whose Data is
  /// therefore the bare file too.</para>
  /// <para>gdfSized -- [Int32 LE size][image]: TBitmap.WriteData, TJPEGImage.WriteData.</para>
  /// <para>gdfSizedInclusive -- [Int32 LE size, counting itself][image]: TMetafile.</para>
  /// <para>gdfPicture -- TPicture.WriteData: one length byte, the graphic's class
  /// name, then THAT class's own framing.</para>
  /// <para>gdfUnknown -- not known; never guessed.</para>
  /// </remarks>
  TGraphicDataFraming = (gdfUnknown, gdfGraphic, gdfSized, gdfSizedInclusive, gdfPicture);

/// <summary>The filer framing of a VCL graphic class's <c>Data</c>.</summary>
/// <param name="AClassName">A class name, bare or unit-qualified (Vcl.Graphics.TBitmap).</param>
/// <returns>The framing for TPicture, TBitmap, TJPEGImage, TMetafile, TIcon,
/// TPngImage, TGIFImage, TWICImage; gdfUnknown for any other class.</returns>
/// <remarks>VCL classes ONLY. A third-party class's framing is declared by the
/// cast library (`dfmdata`, see ParseDataFraming), because the engine has no
/// way to know whether a class it never read overrides ReadData.</remarks>
function GraphicClassFraming(const AClassName: string): TGraphicDataFraming;

/// <summary>A castlib `dfmdata` keyword as a framing.</summary>
/// <param name="AKeyword">'graphic' | 'bitmap' | 'metafile' | 'picture', any case.</param>
/// <returns>The framing; gdfUnknown for any other text.</returns>
function ParseDataFraming(const AKeyword: string): TGraphicDataFraming;

/// <summary>Strip a streamed graphic payload down to the bare image file.</summary>
/// <param name="APayload">The property value, decoded from hex.</param>
/// <param name="AImage">The image file bytes on success; empty otherwise.</param>
/// <param name="AFormat">The image format sniffed from AImage ('bmp', 'png', ...).</param>
/// <param name="AWrapper">The TPicture wrapper's class name; '' when there was none.</param>
/// <param name="AReason">Why the payload could not be unwrapped; '' on success.</param>
/// <returns>True when AImage is a recognised image file.</returns>
/// <remarks>Accepts three shapes: a bare image file; [Int32 size][image]
/// (a TBitmap-typed property); and a TPicture stream, whose class name decides
/// the inner framing (GraphicClassFraming). REFUSES -- never guesses -- an
/// unknown class name, a size field that disagrees with the bytes that follow,
/// and inner bytes that are not a recognised image.</remarks>
function UnwrapGraphicData(const APayload: TBytes; out AImage: TBytes;
  out AFormat, AWrapper, AReason: string): Boolean;

/// <summary>Frame a bare image file for a property of the given filer framing.</summary>
/// <param name="AImage">The image file bytes.</param>
/// <param name="AFormat">Its format as UnwrapGraphicData reported it.</param>
/// <param name="AFraming">The TARGET property's framing.</param>
/// <param name="AData">The bytes to stream on success.</param>
/// <param name="AReason">Why it could not be framed; '' on success.</param>
/// <returns>False for gdfUnknown, and for gdfPicture when no VCL graphic class
/// holds AFormat.</returns>
function WrapGraphicData(const AImage: TBytes; const AFormat: string;
  AFraming: TGraphicDataFraming; out AData: TBytes; out AReason: string): Boolean;

/// <summary>Bytes as a .dfm binary property value, the way Delphi writes one:
/// '{', then 32 bytes (64 hex digits) per line, the closing '}' on the last.</summary>
/// <param name="ABytes">The bytes to encode.</param>
/// <param name="AIndent">The whitespace each hex line starts with.</param>
/// <returns>The value text, CRLF line breaks; '{}' for no bytes.</returns>
function EncodeDfmHex(const ABytes: TBytes; const AIndent: string): string;

implementation

const
  MaxClassNameLen   = 63;
  PreambleSizeBytes = 4;
  BmpFileHeaderLen  = 14;
  BitmapCoreHeader  = 12;
  BitmapInfoHeader  = 40;
  MaxPaletteBits    = 8;
  // little-endian integer assembly: byte-N contributes N*8 bits of shift
  Byte1Shift   = 8;
  Byte2Shift   = 16;
  Byte3Shift   = 24;
  Int16ByteLen = 2;
  Int32ByteLen = 4;
  Byte1Index   = 1;
  Byte2Index   = 2;
  Byte3Index   = 3;
  // BITMAPCOREHEADER field offsets, counted from the DIB header's own start
  CoreWidthOffset   = 4;
  CoreHeightOffset  = 6;
  CoreBitCountOffset= 10;
  // BITMAPINFOHEADER field offsets
  InfoWidthOffset   = 4;
  InfoHeightOffset  = 8;
  InfoBitCountOffset= 14;
  InfoClrUsedOffset = 32;
  // the printable-ASCII range a Delphi filer class name is written in
  MinPrintableAscii = 32;
  MaxPrintableAscii = 126;
  // streamed-graphic magic bytes, sniffed at the payload's image offset
  PngMagic: array[0..3] of Byte = ($89, $50, $4E, $47);
  BmpMagic: array[0..1] of Byte = ($42, $4D);
  JpgMagic: array[0..2] of Byte = ($FF, $D8, $FF);
  GifMagic: array[0..3] of Byte = ($47, $49, $46, $38);
  IcoMagic: array[0..3] of Byte = ($00, $00, $01, $00);
  WmfMagic: array[0..3] of Byte = ($D7, $CD, $C6, $9A); { placeable WMF }
  // ENHMETAHEADER.iType alone (01 00 00 00) is a 10-byte non-image value too;
  // the real signature is the 4 bytes ' EMF' at a fixed offset into the header.
  EmfSigOffset  = 40;
  EmfSignature: array[0..3] of Byte = ($20, $45, $4D, $46); { ' EMF' }
  // a UTF-8 BOM and leading whitespace are skipped before the SVG text probe
  Utf8Bom: array[0..2] of Byte = ($EF, $BB, $BF);
  XmlDeclPrefix = '<?xml';
  SvgTagPrefix  = '<svg';
  // TBitmap-typed properties (e.g. TBitBtn.Glyph.Data) stream with no class
  // name at all: a 4-byte LE length, then the image -- so a payload needs room
  // for the length field plus the widest magic signature checked at its start.
  MinLengthPrefixedPayload = PreambleSizeBytes + Int32ByteLen;

function DecodeDfmHex(const AValueText: string): TBytes;
var
  C     : Char;
  Hex   : string;
  I     : Integer;
begin
  Hex:= '';
  for C in AValueText do
    if CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']) then Hex:= Hex + UpCase(C);
  SetLength(Result, Length(Hex) div 2);
  for I:= 0 to High(Result) do
    Result[I]:= Byte(StrToIntDef('$' + Copy(Hex, (I * 2) + 1, 2), 0));
end;

function StartsWith(const ABytes: TBytes; AOffset: Integer; const ASig: array of Byte): Boolean;
var K: Integer;
begin
  Result:= False;
  if (AOffset < 0) or (AOffset + Length(ASig) > Length(ABytes)) then Exit;
  for K:= 0 to High(ASig) do
    if ABytes[AOffset + K] <> ASig[K] then Exit;
  Result:= True;
end;

// The ENHMETAHEADER signature lives 40 bytes into the header, not at offset 0
// -- iType alone (01 00 00 00) is a common short non-image value.
function IsEmfSignature(const ABytes: TBytes; AOffset: Integer): Boolean;
begin
  Result:= StartsWith(ABytes, AOffset + EmfSigOffset, EmfSignature);
end;

// SVG glyphs (TdxSmartGlyph) stream as raw XML text, no binary preamble at
// all: skip an optional UTF-8 BOM, then ASCII whitespace, then compare the
// next few bytes case-insensitively to '<?xml' or '<svg'.
function LooksLikeSvg(const ABytes: TBytes; AOffset: Integer): Boolean;
var
  P    : Integer;
  Probe: string;
begin
  Result:= False;
  P:= AOffset;
  if StartsWith(ABytes, P, Utf8Bom) then Inc(P, Length(Utf8Bom));
  while (P < Length(ABytes)) and CharInSet(Chr(ABytes[P]), [' ', #9, #13, #10]) do Inc(P);
  if P + Length(XmlDeclPrefix) <= Length(ABytes) then
  begin
    Probe:= TEncoding.ASCII.GetString(ABytes, P, Length(XmlDeclPrefix));
    if SameText(Probe, XmlDeclPrefix) then Exit(True);
  end;
  if P + Length(SvgTagPrefix) <= Length(ABytes) then
  begin
    Probe:= TEncoding.ASCII.GetString(ABytes, P, Length(SvgTagPrefix));
    if SameText(Probe, SvgTagPrefix) then Exit(True);
  end;
end;

// Flat magic-byte dispatch table -- each Exit is one signature, independent
// of the others; folding these into a loop over an array of (sig, format)
// pairs would need a dynamic-array typed constant per entry for zero
// behavioural gain on a routine this small.
function SniffImageFormat(const ABytes: TBytes; AOffset: Integer): string;  // dl:ok too-many-exit-points@0ee8
begin
  Result:= '';
  if StartsWith(ABytes, AOffset, PngMagic) then Exit('png');
  if StartsWith(ABytes, AOffset, BmpMagic) then Exit('bmp');
  if StartsWith(ABytes, AOffset, JpgMagic) then Exit('jpg');
  if StartsWith(ABytes, AOffset, GifMagic) then Exit('gif');
  if StartsWith(ABytes, AOffset, IcoMagic) then Exit('ico');
  if StartsWith(ABytes, AOffset, WmfMagic) then Exit('wmf');
  if IsEmfSignature(ABytes, AOffset) then Exit('emf');
  if LooksLikeSvg(ABytes, AOffset) then Exit('svg');
end;

function ReadInt32LE(const ABytes: TBytes; AOffset: Integer): Integer;
begin
  Result:= 0;
  if AOffset + Int32ByteLen > Length(ABytes) then Exit;
  Result:= Integer(ABytes[AOffset]) or (Integer(ABytes[AOffset + Byte1Index]) shl Byte1Shift) or
           (Integer(ABytes[AOffset + Byte2Index]) shl Byte2Shift) or (Integer(ABytes[AOffset + Byte3Index]) shl Byte3Shift);
end;

function ReadInt16LE(const ABytes: TBytes; AOffset: Integer): Integer;
begin
  Result:= 0;
  if AOffset + Int16ByteLen > Length(ABytes) then Exit;
  Result:= Integer(ABytes[AOffset]) or (Integer(ABytes[AOffset + Byte1Index]) shl Byte1Shift);
end;

// Fill Width/Height/BitCount/PaletteEntries from the DIB header that follows the
// 14-byte BITMAPFILEHEADER. Both the 12-byte core header and the 40+-byte info
// header are read; anything else leaves the fields at 0.
procedure ReadDibHeader(const ABytes: TBytes; AImageOffset: Integer; var AG: TStreamedGraphic);
var
  Dib     : Integer;
  HdrSize : Integer;
  ClrUsed : Integer;
begin
  Dib    := AImageOffset + BmpFileHeaderLen;
  HdrSize:= ReadInt32LE(ABytes, Dib);
  if HdrSize = BitmapCoreHeader then
  begin
    AG.Width   := ReadInt16LE(ABytes, Dib + CoreWidthOffset);
    AG.Height  := ReadInt16LE(ABytes, Dib + CoreHeightOffset);
    AG.BitCount:= ReadInt16LE(ABytes, Dib + CoreBitCountOffset);
    ClrUsed    := 0;
  end
  else if HdrSize >= BitmapInfoHeader then
  begin
    AG.Width   := ReadInt32LE(ABytes, Dib + InfoWidthOffset);
    AG.Height  := Abs(ReadInt32LE(ABytes, Dib + InfoHeightOffset));
    AG.BitCount:= ReadInt16LE(ABytes, Dib + InfoBitCountOffset);
    ClrUsed    := ReadInt32LE(ABytes, Dib + InfoClrUsedOffset);
  end
  else
    Exit;
  if ClrUsed <> 0 then
    AG.PaletteEntries:= ClrUsed
  else if (AG.BitCount > 0) and (AG.BitCount <= MaxPaletteBits) then
    AG.PaletteEntries:= 1 shl AG.BitCount
  else
    AG.PaletteEntries:= 0;
end;

function BareClassName(const AClassName: string): string;
begin
  Result:= Trim(AClassName);
  if Result.LastIndexOf('.') >= 0 then Result:= Result.Substring(Result.LastIndexOf('.') + 1);
end;

function GraphicClassFraming(const AClassName: string): TGraphicDataFraming;
var
  Cls: string;
begin
  Cls:= BareClassName(AClassName);
  if SameText(Cls, 'TPicture') then
    Result:= gdfPicture
  else if SameText(Cls, 'TBitmap') or SameText(Cls, 'TJPEGImage') then
    Result:= gdfSized
  else if SameText(Cls, 'TMetafile') then
    Result:= gdfSizedInclusive
  else if SameText(Cls, 'TIcon') or SameText(Cls, 'TPngImage') or SameText(Cls, 'TGIFImage') or
          SameText(Cls, 'TWICImage') then
    Result:= gdfGraphic
  else
    Result:= gdfUnknown;
end;

function ParseDataFraming(const AKeyword: string): TGraphicDataFraming;
var
  K: string;
begin
  K:= Trim(AKeyword);
  if SameText(K, 'graphic') then
    Result:= gdfGraphic
  else if SameText(K, 'bitmap') then
    Result:= gdfSized
  else if SameText(K, 'metafile') then
    Result:= gdfSizedInclusive
  else if SameText(K, 'picture') then
    Result:= gdfPicture
  else
    Result:= gdfUnknown;
end;

// The VCL class TPicture.WriteData names for an image of this format, or ''.
function PictureClassForFormat(const AFormat: string): string;
begin
  if AFormat = 'bmp' then
    Result:= 'TBitmap'
  else if AFormat = 'png' then
    Result:= 'TPngImage'
  else if AFormat = 'ico' then
    Result:= 'TIcon'
  else if AFormat = 'jpg' then
    Result:= 'TJPEGImage'
  else if AFormat = 'gif' then
    Result:= 'TGIFImage'
  else if (AFormat = 'emf') or (AFormat = 'wmf') then
    Result:= 'TMetafile'
  else
    Result:= '';
end;

function Int32Bytes(AValue: Integer): TBytes;
begin
  SetLength(Result, Int32ByteLen);
  Result[0]         := Byte(AValue);
  Result[Byte1Index]:= Byte(AValue shr Byte1Shift);
  Result[Byte2Index]:= Byte(AValue shr Byte2Shift);
  Result[Byte3Index]:= Byte(AValue shr Byte3Shift);
end;

// [Int32 size][image]: how a TBitmap-typed property (TBitBtn.Glyph.Data) streams.
function IsLengthPrefixedImage(const APayload: TBytes): Boolean;
begin
  Result:= (Length(APayload) >= MinLengthPrefixedPayload) and
           (ReadInt32LE(APayload, 0) = Length(APayload) - PreambleSizeBytes) and
           (SniffImageFormat(APayload, PreambleSizeBytes) <> '');
end;

// The TPicture preamble's class name: one length byte, then that many printable
// ASCII bytes. False when APayload does not open with one.
function ReadPictureClassName(const APayload: TBytes; out AWrapper: string): Boolean;
var
  N: Integer;
begin
  AWrapper:= '';
  N:= if Length(APayload) > 0 then APayload[0] else 0;
  Result:= (N >= 1) and (N <= MaxClassNameLen) and (Length(APayload) >= 1 + N);
  for var I: Integer:= 1 to N do
    if Result and ((APayload[I] < MinPrintableAscii) or (APayload[I] > MaxPrintableAscii)) then
      Result:= False;
  if Result then AWrapper:= TEncoding.ASCII.GetString(APayload, 1, N);
end;

// The image inside a TPicture stream whose class name AWrapper was read: that
// class's own framing decides. AReason is '' on success.
procedure UnwrapPictureInner(const APayload: TBytes; const AWrapper: string;
  out AImage: TBytes; out AReason: string);
var
  Rest   : Integer;
  Size   : Integer;
  Framing: TGraphicDataFraming;
begin
  AImage := nil;
  AReason:= '';
  Rest   := 1 + Length(AWrapper);
  Framing:= GraphicClassFraming(AWrapper);
  case Framing of
    gdfGraphic:
      AImage:= Copy(APayload, Rest, MaxInt);
    gdfSized, gdfSizedInclusive:
      if Length(APayload) < Rest + PreambleSizeBytes then
        AReason:= Format('the %s payload is cut short before its size field', [AWrapper])
      else
      begin
        Size:= ReadInt32LE(APayload, Rest);
        if Framing = gdfSizedInclusive then Dec(Size, PreambleSizeBytes);
        if Size <> Length(APayload) - Rest - PreambleSizeBytes then
          AReason:= Format('the %s size field says %d byte(s) but %d follow',
            [AWrapper, Size, Length(APayload) - Rest - PreambleSizeBytes])
        else
          AImage:= Copy(APayload, Rest + PreambleSizeBytes, MaxInt);
      end;
  else
    AReason:= Format('unknown graphic class %s in the TPicture wrapper -- its filer format is not known', [AWrapper]);
  end;
end;

function UnwrapGraphicData(const APayload: TBytes; out AImage: TBytes;
  out AFormat, AWrapper, AReason: string): Boolean;
begin
  AImage  := nil;
  AFormat := '';
  AWrapper:= '';
  AReason := '';
  if Length(APayload) = 0 then
    AReason:= 'the payload is empty'
  else if SniffImageFormat(APayload, 0) <> '' then
    AImage:= Copy(APayload)                                  { already a bare image file }
  else if IsLengthPrefixedImage(APayload) then
    AImage:= Copy(APayload, PreambleSizeBytes, MaxInt)
  else if ReadPictureClassName(APayload, AWrapper) then
    UnwrapPictureInner(APayload, AWrapper, AImage, AReason)
  else
    AReason:= 'the payload is not a TPicture or TGraphic stream (no image signature, no class-name preamble)';
  if AReason = '' then
  begin
    AFormat:= SniffImageFormat(AImage, 0);
    if AFormat = '' then
    begin
      AReason:= Format('the %s payload is not a recognised image', [AWrapper]);
      AImage := nil;
    end;
  end;
  Result:= AReason = '';
end;

// The image format a TPicture class name DECLARES, for a wrapper whose bytes
// could not be unwrapped: the writer's declaration is all there is.
function FormatDeclaredBy(const AClassName: string): string;
var
  Cls: string;
begin
  Cls:= BareClassName(AClassName);
  if SameText(Cls, 'TBitmap') then
    Result:= 'bmp'
  else if SameText(Cls, 'TIcon') then
    Result:= 'ico'
  else if SameText(Cls, 'TMetafile') then
    Result:= 'wmf'
  else if SameText(Cls, 'TPngImage') or SameText(Cls, 'TPNGObject') then
    Result:= 'png'
  else if SameText(Cls, 'TJPEGImage') then
    Result:= 'jpg'
  else
    Result:= '';
end;

// ONE SOURCE OF TRUTH WITH UnwrapGraphicData (1.26.2). This used to assume an
// Int32 size after ANY wrapper class, so a TPngImage / TIcon / TGIFImage /
// TWICImage picture -- which write none -- got an ImageOffset 4 bytes into the
// image, and glyph-vacuum saved a truncated file.
function ParseStreamedGraphic(const APayload: TBytes): TStreamedGraphic;
var
  Image: TBytes;
  Fmt  : string;
  Cls  : string;
  Why  : string;
begin
  Result:= Default(TStreamedGraphic);
  if UnwrapGraphicData(APayload, Image, Fmt, Cls, Why) then
  begin
    Result.Ok         := True;
    Result.Wrapper    := Cls;
    Result.Format     := Fmt;
    Result.ImageLength:= Length(Image);
    Result.ImageOffset:= Length(APayload) - Length(Image); { the image is always the payload's tail }
  end
  else if ReadPictureClassName(APayload, Cls) then
  begin
    Result.Ok     := True;
    Result.Wrapper:= Cls;
    Result.Format := FormatDeclaredBy(Cls);
  end;
  if (Result.Format = 'bmp') and (Result.ImageLength > 0) then ReadDibHeader(APayload, Result.ImageOffset, Result);
end;

function WrapGraphicData(const AImage: TBytes; const AFormat: string;
  AFraming: TGraphicDataFraming; out AData: TBytes; out AReason: string): Boolean;
var
  Cls  : string;
  Inner: TBytes;
begin
  AData  := nil;
  AReason:= '';
  Result := True;
  case AFraming of
    gdfGraphic       : AData:= Copy(AImage);
    gdfSized         : AData:= Int32Bytes(Length(AImage)) + AImage;
    gdfSizedInclusive: AData:= Int32Bytes(Length(AImage) + PreambleSizeBytes) + AImage;
    gdfPicture:
    begin
      Cls:= PictureClassForFormat(AFormat);
      Result:= (Cls <> '') and WrapGraphicData(AImage, AFormat, GraphicClassFraming(Cls), Inner, AReason);
      if Result then
        AData:= TBytes.Create(Byte(Length(Cls))) + TEncoding.ASCII.GetBytes(Cls) + Inner
      else if AReason = '' then
        AReason:= Format('no VCL graphic class holds a %s image in a TPicture', [AFormat]);
    end;
  else
    AReason:= 'the target filer format is not known';
    Result := False;
  end;
end;

function EncodeDfmHex(const ABytes: TBytes; const AIndent: string): string;
const
  BytesPerLine = 32;
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    SB.Append('{');
    for var I: Integer:= 0 to High(ABytes) do
    begin
      if I mod BytesPerLine = 0 then SB.Append(#13#10).Append(AIndent);
      SB.Append(IntToHex(ABytes[I], 2));
    end;
    SB.Append('}');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
