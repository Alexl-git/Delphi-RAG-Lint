unit DRagLint.Report.MapFile;

{ drag-lint 1.56 -- lane SBOM-2: the linker .map reader behind `sbom --map`.
  Reads the "Detailed map of segments" section of a Delphi linker map (DCC_MapFile=3, dcc -GD): one line per
  unit and segment,

    0001:00000000 0000B7A4 C=CODE     S=.text    G=(none)   M=System   ACBP=A9

  The unit name is the M= token; the second token is the segment length in hex. A unit is LINKED when at
  least one of its segments has a length above zero. The other map sections (segment list, publics,
  line numbers, bound resources) are not read. Pure: one file in, one list out. }

interface

uses
  System.Classes;

const
  /// <summary>The heading of the section this reader needs; a map without it is refused.</summary>
  MAP_DETAIL_HEADING = 'Detailed map of segments';

/// <summary>Reads the units a detailed linker map links.</summary>
/// <param name="pPath">The .map file. Read-only; any bytes are accepted (the file is decoded as ANSI).</param>
/// <param name="pUnits">Receives the linked unit names, one per line, no duplicates, compared without case.
/// Cleared first. The caller owns it.</param>
/// <param name="pError">Empty on success; else why the map cannot be used: the file is missing, has no
/// "Detailed map of segments" section (it was linked without DCC_MapFile=3), or names no linked unit.</param>
/// <returns>True when the map has a detailed section that names at least one linked unit.</returns>
/// <remarks>Not thread-safe on one pUnits. A unit whose segments are all empty is NOT listed.</remarks>
function ReadLinkerMap(const pPath: string; const pUnits: TStrings; out pError: string): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils;

const
  CUnitToken = 'M=';
  CPublicsMarker = 'Publics by';
  CLineNumbersMarker = 'Line numbers for';
  CMinTokens = 3; // address, length, ... M=unit
  CLengthTokenIndex = 1;
  CHexPrefix = '$';

{ The unit named by one segment line and the segment length; '' when the line names no unit. }
function UnitOfSegmentLine(const pLine: string; out pLength: Int64): string;
var
  LTokens: TArray<string>;
  LToken: string;
begin
  Result:= '';
  pLength:= 0;
  LTokens:= pLine.Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(LTokens) < CMinTokens then
    Exit;
  pLength:= StrToInt64Def(CHexPrefix + LTokens[CLengthTokenIndex], 0);
  for LToken in LTokens do
    if LToken.StartsWith(CUnitToken) then
      Exit(LToken.Substring(Length(CUnitToken)));
end;

function ReadLinkerMap(const pPath: string; const pUnits: TStrings; out pError: string): Boolean;
var
  LLines: TArray<string>;
  LLine, LUnit: string;
  LLength: Int64;
  LInDetail: Boolean;
begin
  pError:= '';
  pUnits.Clear;
  if not FileExists(pPath) then
  begin
    pError:= 'map file not found: ' + pPath;
    Exit(False);
  end;
  LLines:= TFile.ReadAllLines(pPath, TEncoding.ANSI);
  LInDetail:= False;
  for LLine in LLines do
  begin
    if not LInDetail then
    begin
      LInDetail:= LLine.Trim = MAP_DETAIL_HEADING;
      Continue;
    end;
    if LLine.Contains(CPublicsMarker) or LLine.StartsWith(CLineNumbersMarker) then
      Break;
    LUnit:= UnitOfSegmentLine(LLine, LLength);
    if (LUnit <> '') and (LLength > 0) and (pUnits.IndexOf(LUnit) < 0) then
      pUnits.Add(LUnit);
  end;
  if not LInDetail then
    pError:= pPath + ' is not a detailed linker map: it has no "' + MAP_DETAIL_HEADING +
      '" section (link with DCC_MapFile=3 / dcc -GD)'
  else if pUnits.Count = 0 then
    pError:= pPath + ' names no linked unit in its "' + MAP_DETAIL_HEADING + '" section';
  Result:= pError = '';
end;

end.
