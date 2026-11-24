unit DRagLint.FieldRepo.HandlersRegions;

(* drag-lint 1.54 -- lane TT-HANDLERS: DLFR region text (design 2026-11-22-field-repository-v2-design.md section 9).

   A generated region is
     {$REGION 'DLFR <id> hash=<16 hex digits>'}
     ...content...
     {$ENDREGION 'DLFR <id>'}
   The hash is taken over the content, so a region whose content does not match its own header was edited by hand and
   is never written. Markers are found by a Pascal scanner, not by text search: a copy inside a comment or a string is
   not a marker. Anything the scanner is not sure of (a comment that never ends, regions that do not nest, a marker
   inside a conditional) makes the region unusable with a reason; nothing is guessed.

   The numbered ORM regions carry no hash: RenumberRegions only renames their markers (DB-RAD n -> DLFR n).
   Units are 7-bit ASCII: a file with another byte is refused, never converted. *)

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when a generated unit cannot be read or written as 7-bit ASCII, or changed on disk meanwhile.</summary>
  EDlfrError = class(Exception);

  /// <summary>One compiler directive of a source text.</summary>
  TPasDirective = record
    /// <summary>1-based offset of the opening brace.</summary>
    Start: Integer;
    /// <summary>Length including the braces.</summary>
    Len: Integer;
    /// <summary>Text between the braces without the dollar sign.</summary>
    Text: string;
    /// <summary>Number of open conditionals before the directive.</summary>
    IfDepth: Integer;
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

  /// <summary>What ScanPascal found.</summary>
  TPasScan = record
    /// <summary>The text with comments, strings and directives blanked: same length, line ends kept.</summary>
    Code: string;
    /// <summary>Every directive in order.</summary>
    Directives: TArray<TPasDirective>;
    /// <summary>Comments, strings and directives in order.</summary>
    Spans: TArray<TPasSpan>;
    /// <summary>'' or why the text cannot be trusted (a comment without end).</summary>
    Problem: string;
    /// <summary>Strings that reach the end of their line without a closing quote.</summary>
    OpenStrings: Integer;
    /// <summary>True when text inserted at pPos would be inside a comment, string or directive.</summary>
    /// <param name="pPos">1-based offset; the insertion goes before it.</param>
    /// <returns>False at the first character of a span and behind its last.</returns>
    function IsInside(pPos: Integer): Boolean;
    /// <summary>Number of conditionals open at an offset.</summary>
    /// <param name="pPos">1-based offset.</param>
    /// <returns>0 outside every $IF...</returns>
    function IfDepthAt(pPos: Integer): Integer;
  end;

  /// <summary>One {$REGION} ... {$ENDREGION} pair.</summary>
  TDlfrRegion = record
    /// <summary>The start marker.</summary>
    Start: TPasDirective;
    /// <summary>The end marker.</summary>
    Finish: TPasDirective;
    /// <summary>Region id; '' for a region that is not DLFR.</summary>
    Id: string;
    /// <summary>Hash of the header; '' = none.</summary>
    Hash: string;
    /// <summary>Content: whole lines between the marker lines.</summary>
    Body: TPasSpan;
    /// <summary>The content text.</summary>
    /// <param name="pText">The text the region was found in.</param>
    /// <returns>The lines between the markers, line ends included.</returns>
    function Content(const pText: string): string;
  end;

  /// <summary>State of a region in a unit.</summary>
  /// <remarks>drsEdited = the content does not match the hash of the header; drsUnusable = the markers cannot be trusted.</remarks>
  TDlfrRegionState = (drsAbsent, drsIntact, drsEdited, drsUnusable);

  /// <summary>Result of renumbering one unit.</summary>
  TDlfrRenumber = record
    /// <summary>The new text; the old one when nothing changes or the unit is refused.</summary>
    NewText: string;
    /// <summary>Renamed regions.</summary>
    Count: Integer;
    /// <summary>'' or why the unit was left unchanged.</summary>
    Refused: string;
    /// <summary>Regions named DB-RAD that are not numbered regions (left as they are).</summary>
    Notes: TArray<string>;
  end;

const
  /// <summary>Line end of generated text when the unit has none of its own.</summary>
  DLFR_CRLF = #13#10;

/// <summary>Splits source text into code, comments, strings and directives.</summary>
/// <param name="pText">Pascal source.</param>
/// <returns>The scan; conditionals are counted, not evaluated.</returns>
function ScanPascal(const pText: string): TPasScan;

/// <summary>Finds a DLFR region by id and checks its content against the hash of its header.</summary>
/// <param name="pText">Unit text.</param>
/// <param name="pId">Region id, e.g. tblOrders.OnCalcFields (case-insensitive).</param>
/// <param name="pRegion">Receives the region when the result is drsIntact or drsEdited.</param>
/// <param name="pReason">Receives why a region is edited or unusable.</param>
/// <returns>The state. drsUnusable also for a text whose regions do not nest, whatever the id.</returns>
function FindDlfrRegion(const pText, pId: string; out pRegion: TDlfrRegion; out pReason: string): TDlfrRegionState;

/// <summary>Text of a new region.</summary>
/// <param name="pId">Region id; no blanks.</param>
/// <param name="pContent">Whole lines, already indented.</param>
/// <param name="pIndent">Blanks before the marker lines.</param>
/// <param name="pEol">Line end of the marker lines.</param>
/// <returns>The region with a line end behind the end marker.</returns>
function RenderDlfrRegion(const pId, pContent, pIndent, pEol: string): string;

/// <summary>Replaces the content of an intact region and renews its hash.</summary>
/// <param name="pText">The text FindDlfrRegion read.</param>
/// <param name="pRegion">A region it called drsIntact.</param>
/// <param name="pContent">New content, whole lines.</param>
/// <returns>The text; every character outside the start marker and the content is kept, and nothing changes
/// when the content is the same.</returns>
/// <exception cref="EDlfrError">The region is not intact in pText (the caller skipped the check).</exception>
function ReplaceDlfrContent(const pText: string; const pRegion: TDlfrRegion; const pContent: string): string;

/// <summary>Reads the id of a numbered ORM region, in the old and the new spelling.</summary>
/// <param name="pName">Region name: DB-RAD 1A, DB-RADa 2, DLFR 1A, DLFR CL-KEY.</param>
/// <returns>The upper-case id of the ORM generator; '' for any other name, a hashed DLFR region included.</returns>
function OrmRegionId(const pName: string): string;  // dl:ok unused-public-symbol@eae1 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>Finds a numbered ORM region of a unit.</summary>
/// <param name="pText">Unit text.</param>
/// <param name="pOrmId">Id, e.g. 2.</param>
/// <param name="pRegion">Receives the first region of that id.</param>
/// <returns>False when there is none or the regions of the text cannot be trusted.</returns>
function FindOrmRegion(const pText, pOrmId: string; out pRegion: TDlfrRegion): Boolean;

/// <summary>Renames the numbered markers of a whole unit: DB-RAD n becomes DLFR n.</summary>
/// <param name="pText">Unit text.</param>
/// <returns>The new text. The unit is refused as a whole when a marker has no partner of the same id, the regions do
/// not nest, or an id exists in both spellings.</returns>
/// <remarks>Only the word DB-RAD inside real markers changes; a second run changes nothing.</remarks>
function RenumberRegions(const pText: string): TDlfrRenumber;

/// <summary>The line end a text uses.</summary>
/// <param name="pText">Any text.</param>
/// <returns>LF when its first line ends with LF only, else CRLF.</returns>
function EolOf(const pText: string): string;

/// <summary>Position of the first byte above 127.</summary>
/// <param name="pBytes">File bytes.</param>
/// <returns>0-based index; -1 when all are ASCII.</returns>
function FirstNonAscii(const pBytes: TBytes): Integer;  // dl:ok unused-public-symbol@70f1 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>True when a text is 7-bit ASCII.</summary>
/// <param name="pText">Any text.</param>
/// <returns>False for one character above 127.</returns>
function IsAsciiText(const pText: string): Boolean;

/// <summary>Reads a unit as ASCII.</summary>
/// <param name="pFile">Path.</param>
/// <returns>The text, every byte one character.</returns>
/// <exception cref="EDlfrError">The file does not exist or holds a byte above 127 (a BOM included).</exception>
function LoadAsciiUnit(const pFile: string): string;

/// <summary>Writes a changed unit.</summary>
/// <param name="pFile">Path.</param>
/// <param name="pOldText">What LoadAsciiUnit read.</param>
/// <param name="pNewText">New text. Equal to pOldText: the file is not touched.</param>
/// <returns>True when the file was written.</returns>
/// <exception cref="EDlfrError">The new text is not ASCII, the file is not what was read, or it cannot be written.</exception>
/// <remarks>Written beside the file first and then moved over it, so a failed write leaves the unit as it was and no
/// temporary file.</remarks>
function SaveAsciiUnit(const pFile, pOldText, pNewText: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.StrUtils,
  System.Hash,
  System.IOUtils,
  System.RegularExpressions;

const
  LF = #10;
  CR = #13;
  QUOTE = '''';
  KW_REGION = 'REGION';
  KW_ENDREGION = 'ENDREGION';
  NAME_DLFR = 'DLFR';
  NAME_DBRAD = 'DB-RAD';
  HASH_LEN = 16;
  MAX_ASCII = 127;
  BRACE_OPEN_LEN = 1;
  PAREN_OPEN_LEN = 2;
  TRIPLE_QUOTE = 3;
  TEMP_EXT = '.dlfr-tmp';
  IF_KEYWORDS: array[0..4] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT', 'IFNOPT');
  END_KEYWORDS: array[0..1] of string = ('ENDIF', 'IFEND');
  PAT_DLFR_NAME = '^DLFR\s+(\S+)(?:\s+hash=([0-9a-f]{16}))?\s*$';
  PAT_ANY_DLFR = '^DLFR\s+(\S+)';
  PAT_ORM_NAME = '^(?:DB-RADa?|DLFR)\s+(\d+[A-Z]?|CL-[A-Z]+)$';
  PAT_DBRAD_WORD = 'DB-RADa?';
  MAXLEN_ID = '2A'; // the one DLFR id that looks like an ORM id but is a hashed region of its own

type
  { One pass over the text; every Read... leaves FPos behind what it read. }
  TPasScanner = class
  strict private
    FText: string;
    FCode: TArray<Char>;
    FPos: Integer;
    FIfDepth: Integer;
    FScan: TPasScan;
    function At(pPos: Integer): Char;
    procedure Blank(pFirst, pLast: Integer);
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

{ TPasScan }

function TPasScan.IsInside(pPos: Integer): Boolean;
var
  VSpan: TPasSpan;
begin
  Result := False;
  for VSpan in Spans do
    if (VSpan.First < pPos) and (pPos < VSpan.Last) then
      Exit(True);
end;

function TPasScan.IfDepthAt(pPos: Integer): Integer;
var
  VDirective: TPasDirective;
begin
  Result := 0;
  for VDirective in Directives do
    if VDirective.Start >= pPos then
      Break
    else if MatchStr(VDirective.Keyword, IF_KEYWORDS) then
      Inc(Result)
    else if MatchStr(VDirective.Keyword, END_KEYWORDS) and (Result > 0) then
      Dec(Result);
end;

{ TDlfrRegion }

function TDlfrRegion.Content(const pText: string): string;
begin
  Result := Copy(pText, Body.First, Body.Last - Body.First);
end;

{ TPasScanner }

constructor TPasScanner.Create(const pText: string);
begin
  inherited Create;
  FText := pText;
  FCode := pText.ToCharArray;
  FPos := 1;
end;

function TPasScanner.At(pPos: Integer): Char;
begin
  Result := if pPos <= Length(FText) then FText[pPos] else #0;
end;

{ Marks pFirst .. pLast (exclusive) as no code. }
procedure TPasScanner.Blank(pFirst, pLast: Integer);
var
  VI: Integer;
  VSpan: TPasSpan;
begin
  VSpan.First := pFirst;
  VSpan.Last := pLast;
  FScan.Spans := FScan.Spans + [VSpan];
  for VI := pFirst to pLast - 1 do
    if not CharInSet(FText[VI], [CR, LF]) then
      FCode[VI - 1] := ' ';
end;

procedure TPasScanner.ReadLineComment;
var
  VFirst: Integer;
begin
  VFirst := FPos;
  while (FPos <= Length(FText)) and not CharInSet(FText[FPos], [CR, LF]) do
    Inc(FPos);
  Blank(VFirst, FPos);
end;

procedure TPasScanner.AddDirective(pFirst, pOpenLen, pCloseLen: Integer);
var
  VDirective: TPasDirective;
  VKeyword: string;
begin
  VDirective.Start := pFirst;
  VDirective.Len := FPos - pFirst;
  VDirective.Text := Copy(FText, pFirst + pOpenLen + 1, VDirective.Len - pOpenLen - pCloseLen - 1);
  VDirective.IfDepth := FIfDepth;
  FScan.Directives := FScan.Directives + [VDirective];
  VKeyword := VDirective.Keyword;
  if MatchStr(VKeyword, IF_KEYWORDS) then
    Inc(FIfDepth)
  else if MatchStr(VKeyword, END_KEYWORDS) and (FIfDepth > 0) then
    Dec(FIfDepth);
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
  Blank(VFirst, FPos);
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
  VPos, VFirst: Integer;
begin
  VFirst := FPos;
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
  Blank(VFirst, FPos);
end;

procedure TPasScanner.ReadPlainString;
var
  VFirst: Integer;
begin
  VFirst := FPos;
  Inc(FPos);
  while not CharInSet(At(FPos), [CR, LF, #0]) do
  begin
    if (At(FPos) = QUOTE) and (At(FPos + 1) <> QUOTE) then
    begin
      Inc(FPos);
      Blank(VFirst, FPos);
      Exit;
    end;
    Inc(FPos, if At(FPos) = QUOTE then 2 else 1);
  end;
  Inc(FScan.OpenStrings);
  Blank(VFirst, FPos);
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
  SetString(FScan.Code, PChar(FCode), Length(FCode));
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

function ContentHash(const pContent: string): string;
begin
  Result := THashSHA2.GetHashString(pContent.Replace(DLFR_CRLF, LF)).Substring(0, HASH_LEN).ToLower;
end;

function StartMarker(const pId, pContent: string): string;
begin
  Result := Format('{$REGION ''%s %s hash=%s''}', [NAME_DLFR, pId, ContentHash(pContent)]);
end;

function EndMarker(const pId: string): string;
begin
  Result := Format('{$ENDREGION ''%s %s''}', [NAME_DLFR, pId]);
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
  VMatch: TMatch;
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
      VMatch := Rx(PAT_DLFR_NAME).Match(VRegion.Start.RegionName);
      if VMatch.Success and (VMatch.Groups.Count > 2) then
        VRegion.Hash := VMatch.Groups[2].Value.ToLower;
      VMatch := Rx(PAT_ANY_DLFR).Match(VRegion.Start.RegionName);
      if VMatch.Success then
        VRegion.Id := VMatch.Groups[1].Value;
      pRegions := pRegions + [VRegion];
      SetLength(VOpen, Length(VOpen) - 1);
    end;
  if (pReason = '') and (Length(VOpen) > 0) then
    pReason := 'a region without an end marker: ' + VOpen[High(VOpen)].RegionName;
  Result := pReason = '';
end;

function MarkerProblem(const pRegion: TDlfrRegion): string;
begin
  Result := '';
  if (pRegion.Finish.RegionName <> '') and not SameText(pRegion.Finish.RegionName, NAME_DLFR + ' ' + pRegion.Id) then
    Result := 'the end marker names another region: ' + pRegion.Finish.RegionName
  else if (pRegion.Start.IfDepth > 0) or (pRegion.Finish.IfDepth > 0) then
    Result := 'the region is inside a conditional'
  else if pRegion.Body.Last < pRegion.Body.First then
    Result := 'a marker is not alone on its line';
end;

function FindDlfrRegion(const pText, pId: string; out pRegion: TDlfrRegion; out pReason: string): TDlfrRegionState;
var
  VRegions: TArray<TDlfrRegion>;
  VRegion: TDlfrRegion;
  VFound: Integer;
begin
  Result := drsUnusable;
  pRegion := Default(TDlfrRegion);
  if not ReadRegions(pText, ScanPascal(pText), VRegions, pReason) then
    Exit;
  VFound := 0;
  for VRegion in VRegions do
    if SameText(VRegion.Id, pId) then
    begin
      Inc(VFound);
      pRegion := VRegion;
    end;
  if VFound = 0 then
    Exit(drsAbsent);
  pReason := if VFound > 1 then 'the region is in the unit more than once' else MarkerProblem(pRegion);
  if pReason <> '' then
    Exit;
  Result := drsIntact;
  if pRegion.Hash = '' then
    pReason := 'hand-edited: the region header has no hash'
  else if pRegion.Hash <> ContentHash(pRegion.Content(pText)) then
    pReason := 'hand-edited: the content does not match the hash of the region header';
  if pReason <> '' then
    Result := drsEdited;
end;

function RenderDlfrRegion(const pId, pContent, pIndent, pEol: string): string;
begin
  Result := pIndent + StartMarker(pId, pContent) + pEol + pContent + pIndent + EndMarker(pId) + pEol;
end;

function ReplaceDlfrContent(const pText: string; const pRegion: TDlfrRegion; const pContent: string): string;
var
  VOld: string;
begin
  VOld := pRegion.Content(pText);
  if (pRegion.Hash = '') or (pRegion.Hash <> ContentHash(VOld)) then
    raise EDlfrError.Create('region ' + pRegion.Id + ' is hand-edited and must not be replaced');
  if VOld = pContent then
    Exit(pText);
  Result := Copy(pText, 1, pRegion.Start.Start - 1) + StartMarker(pRegion.Id, pContent) +
    Copy(pText, pRegion.Start.Finish, pRegion.Body.First - pRegion.Start.Finish) + pContent + Copy(pText, pRegion.Body.Last);
end;

{ ---- numbered ORM regions ---- }

function OrmRegionId(const pName: string): string;
var
  VMatch: TMatch;
begin
  VMatch := Rx(PAT_ORM_NAME).Match(Trim(pName));
  Result := if VMatch.Success then VMatch.Groups[1].Value.ToUpper else '';
  if Result = MAXLEN_ID then
    Result := '';
end;

function FindOrmRegion(const pText, pOrmId: string; out pRegion: TDlfrRegion): Boolean;
var
  VRegions: TArray<TDlfrRegion>;
  VRegion: TDlfrRegion;
  VReason: string;
begin
  pRegion := Default(TDlfrRegion);
  if ReadRegions(pText, ScanPascal(pText), VRegions, VReason) then
    for VRegion in VRegions do
      if SameText(OrmRegionId(VRegion.Start.RegionName), pOrmId) then
      begin
        pRegion := VRegion;
        Exit(True);
      end;
  Result := False;
end;

function IsDbRad(const pName: string): Boolean;
begin
  Result := StartsText(NAME_DBRAD, pName);
end;

{ The marker with DB-RAD renamed. }
function RenameMarker(const pText: string; const pDirective: TPasDirective): string;
begin
  Result := Copy(pText, 1, pDirective.Start - 1) +
    Rx(PAT_DBRAD_WORD).Replace(Copy(pText, pDirective.Start, pDirective.Len), NAME_DLFR, 1) + Copy(pText, pDirective.Finish);
end;

function IsOldMarker(const pDirective: TPasDirective): Boolean;
begin
  Result := IsDbRad(pDirective.RegionName) and (OrmRegionId(pDirective.RegionName) <> '');
end;

{ Why the numbered regions of a unit cannot be renamed; fills the ids of the old spelling. }
function RenumberProblem(const pRegions: TArray<TDlfrRegion>; pOld: TStrings): string;
var
  VRegion: TDlfrRegion;
  VId: string;
begin
  Result := '';
  for VRegion in pRegions do
    if IsOldMarker(VRegion.Start) or IsOldMarker(VRegion.Finish) then
    begin
      VId := OrmRegionId(VRegion.Start.RegionName);
      pOld.Add(VId);
      if (OrmRegionId(VRegion.Finish.RegionName) <> VId) or (IsOldMarker(VRegion.Start) <> IsOldMarker(VRegion.Finish)) then
        Exit(Format('the end marker of "%s" is "%s"', [VRegion.Start.RegionName, VRegion.Finish.RegionName]));
    end;
  for VRegion in pRegions do
    if StartsText(NAME_DLFR, VRegion.Start.RegionName) and (pOld.IndexOf(OrmRegionId(VRegion.Start.RegionName)) >= 0) then
      Exit('the unit has the region in both spellings: ' + VRegion.Start.RegionName);
end;

function RenumberRegions(const pText: string): TDlfrRenumber;
var
  VRegions: TArray<TDlfrRegion>;
  VScan: TPasScan;
  VOld: TStringList;
  VI: Integer;
  VDirective: TPasDirective;
  VName: string;
begin
  Result := Default(TDlfrRenumber);
  Result.NewText := pText;
  VScan := ScanPascal(pText);
  if not ReadRegions(pText, VScan, VRegions, Result.Refused) then
    Exit;
  VOld := TStringList.Create;
  try
    Result.Refused := RenumberProblem(VRegions, VOld);
  finally
    VOld.Free;
  end;
  if Result.Refused <> '' then
    Exit;
  for VI := High(VScan.Directives) downto 0 do
  begin
    VDirective := VScan.Directives[VI];
    if not MatchStr(VDirective.Keyword, [KW_REGION, KW_ENDREGION]) then
      Continue;
    VName := VDirective.RegionName;
    if not IsDbRad(VName) then
      Continue;
    if OrmRegionId(VName) <> '' then
      Result.NewText := RenameMarker(Result.NewText, VDirective);
    if VDirective.Keyword <> KW_REGION then
      Continue;
    if OrmRegionId(VName) <> '' then
      Inc(Result.Count)
    else
      Result.Notes := ['left as it is, not a numbered region: ' + VName] + Result.Notes;
  end;
end;

{ ---- files ---- }

function EolOf(const pText: string): string;
var
  VPos: Integer;
begin
  VPos := Pos(LF, pText);
  Result := if (VPos = 1) or ((VPos > 1) and (pText[VPos - 1] <> CR)) then LF else DLFR_CRLF;
end;

function FirstNonAscii(const pBytes: TBytes): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pBytes) do
    if pBytes[VI] > MAX_ASCII then
      Exit(VI);
end;

function IsAsciiText(const pText: string): Boolean;
var
  VC: Char;
begin
  Result := True;
  for VC in pText do
    if Ord(VC) > MAX_ASCII then
      Exit(False);
end;

function LoadAsciiUnit(const pFile: string): string;
var
  VBytes: TBytes;
  VBad: Integer;
begin
  if not TFile.Exists(pFile) then
    raise EDlfrError.Create('the unit does not exist: ' + pFile);
  VBytes := TFile.ReadAllBytes(pFile);
  VBad := FirstNonAscii(VBytes);
  if VBad >= 0 then
    raise EDlfrError.CreateFmt('%s is not 7-bit ASCII (byte $%.2x at offset %d): left unchanged', [ExtractFileName(pFile), VBytes[VBad], VBad]);
  Result := TEncoding.ASCII.GetString(VBytes);
end;

{ pFile with the letter case the folder has: a move onto another case would rename the file. }
function NameOnDisk(const pFile: string): string;
var
  VFound: TSearchRec;
begin
  Result := pFile;
  if System.SysUtils.FindFirst(pFile, faAnyFile, VFound) = 0 then
  begin
    Result := ExtractFilePath(pFile) + VFound.Name;
    System.SysUtils.FindClose(VFound);
  end;
end;

{ Writes pText beside pFile and moves it over pFile; no temporary file stays behind. }
procedure ReplaceFile(const pFile, pText: string);
var
  VTemp: string;
begin
  VTemp := pFile + TEMP_EXT;
  try
    try
      TFile.WriteAllBytes(VTemp, TEncoding.ASCII.GetBytes(pText));
    except
      on E: Exception do
        raise EDlfrError.Create('cannot write ' + VTemp + ': ' + E.Message);
    end;
    if not MoveFileEx(PChar(VTemp), PChar(NameOnDisk(pFile)), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      raise EDlfrError.Create('cannot replace ' + pFile + ': ' + SysErrorMessage(GetLastError));
  finally
    Winapi.Windows.DeleteFile(PChar(VTemp)); // after the move there is none
  end;
end;

function SaveAsciiUnit(const pFile, pOldText, pNewText: string): Boolean;
begin
  Result := pOldText <> pNewText;
  if not Result then
    Exit;
  if not IsAsciiText(pNewText) then
    raise EDlfrError.Create('the new text is not 7-bit ASCII: ' + pFile);
  if LoadAsciiUnit(pFile) <> pOldText then
    raise EDlfrError.Create('the file changed since it was read: ' + pFile);
  ReplaceFile(pFile, pNewText);
end;

end.
