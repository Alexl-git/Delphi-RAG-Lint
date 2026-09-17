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
  /// <remarks>A .dfm `Picture.Data` blob is a streamed TPicture: one length
  /// byte, that many class-name bytes, a little-endian Int32 image size, then
  /// the image. A bare image (no preamble) is recognised by its magic bytes at
  /// offset 0 and reported with an empty Wrapper. Width/Height/BitCount/
  /// PaletteEntries are filled for BMP only; every other format leaves them 0.</remarks>
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
function DecodeDfmHex(const AValueText: string): TBytes;

/// <summary>Image format from the magic bytes at <paramref name="AOffset"/>.</summary>
/// <param name="ABytes">The payload bytes to sniff.</param>
/// <param name="AOffset">Byte offset within <paramref name="ABytes"/> to read the magic number from.</param>
/// <returns>'bmp' | 'ico' | 'wmf' | 'emf' | 'png' | 'jpg' | 'gif' | '' (unrecognised).</returns>
function SniffImageFormat(const ABytes: TBytes; AOffset: Integer): string;

/// <summary>Decode a streamed graphic payload: wrapper preamble first (the
/// writer's own declaration), magic bytes as the fallback, then the BMP DIB
/// header when the image is a BMP.</summary>
/// <param name="APayload">The whole property value, decoded from hex.</param>
/// <returns>Ok=False when neither a preamble nor a magic is recognised; every
/// numeric field 0 and Format '' in that case.</returns>
function ParseStreamedGraphic(const APayload: TBytes): TStreamedGraphic;

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
  EmfMagic: array[0..3] of Byte = ($01, $00, $00, $00); { ENHMETAHEADER.iType }

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

// Flat magic-byte dispatch table -- each Exit is one signature, independent
// of the others; folding these into a loop over an array of (sig, format)
// pairs would need a dynamic-array typed constant per entry for zero
// behavioural gain on a routine this small.
function SniffImageFormat(const ABytes: TBytes; AOffset: Integer): string;  // dl:ok too-many-exit-points@fc29
begin
  Result:= '';
  if StartsWith(ABytes, AOffset, PngMagic) then Exit('png');
  if StartsWith(ABytes, AOffset, BmpMagic) then Exit('bmp');
  if StartsWith(ABytes, AOffset, JpgMagic) then Exit('jpg');
  if StartsWith(ABytes, AOffset, GifMagic) then Exit('gif');
  if StartsWith(ABytes, AOffset, IcoMagic) then Exit('ico');
  if StartsWith(ABytes, AOffset, WmfMagic) then Exit('wmf');
  if StartsWith(ABytes, AOffset, EmfMagic) then Exit('emf');
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

function ParseStreamedGraphic(const APayload: TBytes): TStreamedGraphic;
var
  N  : Integer;
  I  : Integer;
  Cls: string;
begin
  Result:= Default(TStreamedGraphic);
  if Length(APayload) = 0 then Exit;

  { A bare image, sniffed at offset 0. }
  Result.Format:= SniffImageFormat(APayload, 0);
  if Result.Format <> '' then
  begin
    Result.Ok         := True;
    Result.ImageOffset:= 0;
    Result.ImageLength:= Length(APayload);
  end
  else
  begin
    { The Delphi filer preamble: [len] class-name [Int32 size] image. }
    N:= APayload[0];
    if (N < 1) or (N > MaxClassNameLen) or (Length(APayload) < 1 + N + PreambleSizeBytes) then Exit;
    for I:= 1 to N do
      if (APayload[I] < MinPrintableAscii) or (APayload[I] > MaxPrintableAscii) then Exit; { not a class name }
    Cls:= TEncoding.ASCII.GetString(APayload, 1, N);
    Result.Wrapper    := Cls;
    Result.ImageOffset:= 1 + N + PreambleSizeBytes;
    Result.ImageLength:= Length(APayload) - Result.ImageOffset;
    Result.Format     := SniffImageFormat(APayload, Result.ImageOffset);
    if Result.Format = '' then
    begin
      { The writer's declaration decides when the magic does not. }
      if SameText(Cls, 'TBitmap')    then Result.Format:= 'bmp'
      else if SameText(Cls, 'TIcon') then Result.Format:= 'ico'
      else if SameText(Cls, 'TMetafile') then Result.Format:= 'wmf'
      else if SameText(Cls, 'TPngImage') or SameText(Cls, 'TPNGObject') then Result.Format:= 'png'
      else if SameText(Cls, 'TJPEGImage') then Result.Format:= 'jpg';
    end;
    Result.Ok:= True;
  end;

  if Result.Format = 'bmp' then ReadDibHeader(APayload, Result.ImageOffset, Result);
end;

end.
