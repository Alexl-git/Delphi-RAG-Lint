unit DRagLint.FieldRepo.HandlersRegions;

(* drag-lint 1.53.1 -- the numbered ORM regions of a unit (backport of the same unit of 1.54, only what
   DRagLint.FieldRepo.OrmGen needs; 1.54 replaces this file as a whole).

     {$REGION 'DB-RAD <id>'}
     ...content...
     {$ENDREGION 'DB-RAD <id>'}
   Markers are found by a Pascal scanner, not by text search: a copy inside a comment or a string is not a marker.
   Anything the scanner is not sure of (a comment that never ends, regions that do not nest, a region that holds a part
   of a conditional) makes the unit unusable with a reason; nothing is guessed. *)

interface

type
  /// <summary>One compiler directive of a source text.</summary>
  TPasDirective = record
    /// <summary>1-based offset of the opening brace.</summary>
    Start: Integer;
    /// <summary>Length including the braces.</summary>
    Len: Integer;
    /// <summary>Text between the braces without the dollar sign.</summary>
    Text: string;
    /// <summary>First word, upper case: REGION, IFDEF, ...</summary>
    /// <returns>The word; '' for a directive that starts with no letter.</returns>
    function Keyword: string;
    /// <summary>The region name of a REGION / ENDREGION directive.</summary>
    /// <returns>The text behind the keyword without its quotes; '' when there is none.</returns>
    function RegionName: string;
    /// <summary>Offset right behind the closing brace.</summary>
    /// <returns>Start + Len.</returns>
    function Finish: Integer;
  end;

  /// <summary>Offsets First (inclusive) to Last (exclusive).</summary>
  TPasSpan = record
    /// <summary>First offset, 1-based.</summary>
    First: Integer;
    /// <summary>Offset behind the last one.</summary>
    Last: Integer;
  end;

  /// <summary>One {$REGION} ... {$ENDREGION} pair.</summary>
  TDlfrRegion = record
    /// <summary>The start marker.</summary>
    Start: TPasDirective;
    /// <summary>The end marker.</summary>
    Finish: TPasDirective;
    /// <summary>Upper-case id of a numbered ORM region; '' for another region.</summary>
    Id: string;
    /// <summary>Content: whole lines between the marker lines.</summary>
    Body: TPasSpan;
  end;

/// <summary>Reads the id of a numbered ORM region.</summary>
/// <param name="pName">Region name: DB-RAD 1A, DB-RADa 2, DB-RAD CL-KEY.</param>
/// <returns>The upper-case id of the ORM generator; '' for any other name.</returns>
function OrmRegionId(const pName: string): string;

/// <summary>Reads the numbered ORM regions of a unit that is to be rewritten.</summary>
/// <param name="pText">Unit text.</param>
/// <param name="pKnown">Upper-case ids the caller generates.</param>
/// <param name="pRegions">Receives the regions in the order of the text, Id = the id; empty when the unit is refused.</param>
/// <returns>'' or why the unit must not be rewritten: regions that do not nest; a start and an end of different ids; a
/// region named DB-RAD n whose id is not in pKnown; a marker that shares its line with other code; a region that holds
/// another DB-RAD region or a part of a conditional; a text that cannot be scanned.</returns>
function ReadOrmRegions(const pText: string; const pKnown: TArray<string>; out pRegions: TArray<TDlfrRegion>): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions;

const
  LF = #10;
  CR = #13;
  QUOTE = '''';
  KW_REGION = 'REGION';
  KW_ENDREGION = 'ENDREGION';
  BRACE_OPEN_LEN = 1;
  PAREN_OPEN_LEN = 2;
  TRIPLE_QUOTE = 3;
  IF_KEYWORDS: array[0..4] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT', 'IFNOPT');
  END_KEYWORDS: array[0..1] of string = ('ENDIF', 'IFEND');
  ELSE_KEYWORDS: array[0..1] of string = ('ELSE', 'ELSEIF');
  PAT_ORM_NAME = '^DB-RADa?\s+(\d+[A-Z]?|CL-[A-Z]+)$';
  PAT_DBRAD_NAME = '^DB-RADa?\s+\S';

type
  { What one pass over a text found. }
  TPasScan = record
    Directives: TArray<TPasDirective>;
    { '' or why the text cannot be trusted }
    Problem: string;
    { strings that reach the end of their line without a closing quote }
    OpenStrings: Integer;
  end;

  { One pass over the text; every Read... leaves FPos behind what it read. }
  TPasScanner = class
  strict private
    FText: string;
    FPos: Integer;
    FScan: TPasScan;
    function At(pPos: Integer): Char;
    procedure ReadLineComment;
    procedure ReadBraced(pOpenLen: Integer; const pClose: string);
    procedure AddDirective(pFirst, pOpenLen, pCloseLen: Integer);
    procedure ReadString;
    function QuotesAt(pPos: Integer): Integer;
    function LineBlankFrom(pPos: Integer): Boolean;
    function ReadBlockString(pQuotes: Integer): Boolean;
    procedure ReadPlainString;
  public
    constructor Create(const pText: string);
    function Run: TPasScan;
  end;

{ TPasDirective }

function TPasDirective.Keyword: string;
var
  VLen: Integer;
begin
  VLen := 0;
  while (VLen < Text.Length) and CharInSet(Text.Chars[VLen], ['A'..'Z', 'a'..'z']) do
    Inc(VLen);
  Result := Text.Substring(0, VLen).ToUpper;
end;

function TPasDirective.RegionName: string;
begin
  Result := Text.Substring(Keyword.Length).Trim;
  if Result.StartsWith(QUOTE) then
    Result := Result.Substring(1);
  if Result.EndsWith(QUOTE) then
    Result := Result.Substring(0, Result.Length - 1);
  Result := Result.Trim;
end;

function TPasDirective.Finish: Integer;
begin
  Result := Start + Len;
end;

{ TPasScanner }

constructor TPasScanner.Create(const pText: string);
begin
  inherited Create;
  FText := pText;
  FPos := 1;
end;

function TPasScanner.At(pPos: Integer): Char;
begin
  Result := if pPos <= Length(FText) then FText[pPos] else #0;
end;

procedure TPasScanner.ReadLineComment;
begin
  while (FPos <= Length(FText)) and not CharInSet(FText[FPos], [CR, LF]) do
    Inc(FPos);
end;

procedure TPasScanner.AddDirective(pFirst, pOpenLen, pCloseLen: Integer);
var
  VDirective: TPasDirective;
begin
  VDirective.Start := pFirst;
  VDirective.Len := FPos - pFirst;
  VDirective.Text := Copy(FText, pFirst + pOpenLen + 1, VDirective.Len - pOpenLen - pCloseLen - 1);
  FScan.Directives := FScan.Directives + [VDirective];
end;

procedure TPasScanner.ReadBraced(pOpenLen: Integer; const pClose: string);
var
  VFirst, VClose: Integer;
begin
  VFirst := FPos;
  VClose := Pos(pClose, FText, FPos + pOpenLen);
  if VClose = 0 then
  begin
    FScan.Problem := Format('the comment at offset %d has no end', [VFirst]);
    FPos := Length(FText) + 1;
  end
  else
  begin
    FPos := VClose + Length(pClose);
    if At(VFirst + pOpenLen) = '$' then
      AddDirective(VFirst, pOpenLen, Length(pClose));
  end;
end;

function TPasScanner.QuotesAt(pPos: Integer): Integer;
begin
  Result := 0;
  while At(pPos + Result) = QUOTE do
    Inc(Result);
end;

function TPasScanner.LineBlankFrom(pPos: Integer): Boolean;
begin
  while CharInSet(At(pPos), [' ', #9]) do
    Inc(pPos);
  Result := CharInSet(At(pPos), [CR, LF, #0]);
end;

{ A string over several lines: it ends at the first line that starts with the same run of quotes. }
function TPasScanner.ReadBlockString(pQuotes: Integer): Boolean;
var
  VPos: Integer;
begin
  VPos := FPos + pQuotes;
  Result := False;
  while not Result do
  begin
    VPos := Pos(LF, FText, VPos);
    if VPos = 0 then
      Exit;
    Inc(VPos);
    while CharInSet(At(VPos), [' ', #9]) do
      Inc(VPos);
    Result := QuotesAt(VPos) = pQuotes;
  end;
  FPos := VPos + pQuotes;
end;

procedure TPasScanner.ReadPlainString;
begin
  Inc(FPos);
  while not CharInSet(At(FPos), [CR, LF, #0]) do
  begin
    if (At(FPos) = QUOTE) and (At(FPos + 1) <> QUOTE) then
    begin
      Inc(FPos);
      Exit;
    end;
    Inc(FPos, if At(FPos) = QUOTE then 2 else 1);
  end;
  Inc(FScan.OpenStrings);
end;

procedure TPasScanner.ReadString;
var
  VQuotes: Integer;
begin
  VQuotes := QuotesAt(FPos);
  if (VQuotes >= TRIPLE_QUOTE) and Odd(VQuotes) and LineBlankFrom(FPos + VQuotes) and ReadBlockString(VQuotes) then
    Exit;
  ReadPlainString;
end;

function TPasScanner.Run: TPasScan;
begin
  FScan := Default(TPasScan);
  while FPos <= Length(FText) do
    if FText[FPos] = QUOTE then
      ReadString
    else if FText[FPos] = '{' then
      ReadBraced(BRACE_OPEN_LEN, '}')
    else if (FText[FPos] = '(') and (At(FPos + 1) = '*') then
      ReadBraced(PAREN_OPEN_LEN, '*)')
    else if (FText[FPos] = '/') and (At(FPos + 1) = '/') then
      ReadLineComment
    else
      Inc(FPos);
  Result := FScan;
end;

function ScanPascal(const pText: string): TPasScan;
var
  VScanner: TPasScanner;
begin
  VScanner := TPasScanner.Create(pText);
  try
    Result := VScanner.Run;
  finally
    VScanner.Free;
  end;
end;

{ ---- regions ---- }

function Rx(const pPattern: string): TRegEx;
begin
  Result := TRegEx.Create(pPattern, [roIgnoreCase]);
end;

{ Whole lines between the two marker lines. A marker that shares its line with something else gives an empty span with
  Last < First. }
function BodySpan(const pText: string; const pStart, pFinish: TPasDirective): TPasSpan;
var
  VPos: Integer;
begin
  Result.First := pFinish.Start + 1;
  Result.Last := pFinish.Start;
  VPos := Pos(LF, pText, pStart.Finish);
  if (VPos = 0) or (VPos > pFinish.Start) or (Trim(Copy(pText, pStart.Finish, VPos - pStart.Finish)) <> '') then
    Exit;
  Result.First := VPos + 1;
  VPos := pFinish.Start;
  while (VPos > 1) and (pText[VPos - 1] <> LF) do
    Dec(VPos);
  if Trim(Copy(pText, VPos, pFinish.Start - VPos)) = '' then
    Result.Last := VPos
  else
    Result.First := Result.Last + 1;
end;

{ Every region of a text; False with a reason when they do not nest or the text cannot be scanned. }
function ReadRegions(const pText: string; const pScan: TPasScan; out pRegions: TArray<TDlfrRegion>; out pReason: string): Boolean;
var
  VDirective: TPasDirective;
  VOpen: TArray<TPasDirective>;
  VRegion: TDlfrRegion;
begin
  pRegions := nil;
  VOpen := nil;
  pReason := pScan.Problem;
  if (pReason = '') and (pScan.OpenStrings > 0) then
    pReason := 'a string has no closing quote';
  for VDirective in pScan.Directives do
    if pReason <> '' then
      Break
    else if VDirective.Keyword = KW_REGION then
      VOpen := VOpen + [VDirective]
    else if VDirective.Keyword <> KW_ENDREGION then
      Continue
    else if Length(VOpen) = 0 then
      pReason := 'an end marker without a region: ' + VDirective.RegionName
    else
    begin
      VRegion := Default(TDlfrRegion);
      VRegion.Start := VOpen[High(VOpen)];
      VRegion.Finish := VDirective;
      VRegion.Body := BodySpan(pText, VRegion.Start, VDirective);
      pRegions := pRegions + [VRegion];
      SetLength(VOpen, Length(VOpen) - 1);
    end;
  if (pReason = '') and (Length(VOpen) > 0) then
    pReason := 'a region without an end marker: ' + VOpen[High(VOpen)].RegionName;
  Result := pReason = '';
end;

function OrmRegionId(const pName: string): string;
var
  VMatch: TMatch;
begin
  VMatch := Rx(PAT_ORM_NAME).Match(Trim(pName));
  Result := if VMatch.Success then VMatch.Groups[1].Value.ToUpper else '';
end;

{ '' or why the pair of one region cannot be trusted; a pair that names no ORM region is never a problem. }
function OrmPairProblem(const pText: string; const pRegion: TDlfrRegion; const pKnown: TArray<string>): string;
var
  VStart, VFinish, VId: string;
  VFirst: Integer;
begin
  VStart := pRegion.Start.RegionName;
  VFinish := pRegion.Finish.RegionName;
  VId := OrmRegionId(VStart);
  VFirst := pRegion.Start.Start;
  while (VFirst > 1) and (pText[VFirst - 1] <> LF) do
    Dec(VFirst);
  if (VId = '') and (OrmRegionId(VFinish) = '') and not Rx(PAT_DBRAD_NAME).IsMatch(VStart) and not Rx(PAT_DBRAD_NAME).IsMatch(VFinish) then
    Result := ''
  else if OrmRegionId(VFinish) <> VId then
    Result := Format('the end marker of "%s" is "%s"', [VStart, VFinish])
  else if not MatchText(VId, pKnown) then
    Result := 'unknown region id: ' + VStart
  else if (pRegion.Body.Last < pRegion.Body.First) or (Trim(Copy(pText, VFirst, pRegion.Start.Start - VFirst)) <> '') then
    Result := 'a marker is not alone on its line: ' + VStart
  else
    Result := '';
end;

{ True when every conditional that starts in the region ends in it and no other one does. }
function HoldsWholeConditionals(const pRegion: TDlfrRegion; const pScan: TPasScan): Boolean;
var
  VDirective: TPasDirective;
  VDepth: Integer;
begin
  VDepth := 0;
  Result := True;
  for VDirective in pScan.Directives do
    if (VDirective.Start > pRegion.Start.Start) and (VDirective.Start < pRegion.Finish.Start) then
    begin
      if MatchStr(VDirective.Keyword, IF_KEYWORDS) then
        Inc(VDepth)
      else if MatchStr(VDirective.Keyword, END_KEYWORDS) then
        Dec(VDepth);
      Result := Result and (VDepth >= 0) and ((VDepth > 0) or not MatchStr(VDirective.Keyword, ELSE_KEYWORDS));
    end;
  Result := Result and (VDepth = 0);
end;

{ '' or the generated region inside pRegion. }
function InnerProblem(const pRegion: TDlfrRegion; const pAll: TArray<TDlfrRegion>): string;
var
  VInner: TDlfrRegion;
begin
  Result := '';
  for VInner in pAll do
    if (VInner.Start.Start > pRegion.Start.Start) and (VInner.Start.Start < pRegion.Finish.Start)
      and Rx(PAT_DBRAD_NAME).IsMatch(VInner.Start.RegionName) then
      Result := Format('the region %s holds the region %s', [pRegion.Start.RegionName, VInner.Start.RegionName]);
end;

function ReadOrmRegions(const pText: string; const pKnown: TArray<string>; out pRegions: TArray<TDlfrRegion>): string;
var
  VAll: TArray<TDlfrRegion>;
  VRegion: TDlfrRegion;
  VScan: TPasScan;
begin
  pRegions := nil;
  VScan := ScanPascal(pText);
  if not ReadRegions(pText, VScan, VAll, Result) then
    Exit;
  for VRegion in VAll do
  begin
    Result := OrmPairProblem(pText, VRegion, pKnown);
    if (Result = '') and (OrmRegionId(VRegion.Start.RegionName) <> '') then
    begin
      Result := InnerProblem(VRegion, VAll);
      if (Result = '') and not HoldsWholeConditionals(VRegion, VScan) then
        Result := 'the region holds a part of a conditional: ' + VRegion.Start.RegionName;
      pRegions := pRegions + [VRegion];
      pRegions[High(pRegions)].Id := OrmRegionId(VRegion.Start.RegionName);
    end;
    if Result <> '' then
    begin
      pRegions := nil;
      Exit;
    end;
  end;
end;

end.
