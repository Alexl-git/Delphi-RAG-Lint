unit DRagLint.FieldRepo.TextBackup;

{ drag-lint 1.52 -- lane TTC: text backup core of the field repository.

  Writes / reads the diffable text form of a repository (design
  2026-11-16-tabletools-into-dl-design.md section 8, rules 1-8): 7-bit ASCII, CRLF, no BOM,
  fixed table and key order, NULL columns omitted, one trailer line per table.
  backup(restore(F)) = F byte for byte. A restore parses and validates the WHOLE file
  first (ERepoBackupFormatError with the line number), then replaces the rows in ONE
  transaction; it never executes text from the file. }

interface

uses
  System.SysUtils,
  System.Classes,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema;

type
  /// <summary>Raised when a backup text is malformed. LineNo is the 1-based line of the
  /// defect (the line after the last one for a truncated file; 0 when no line applies) and
  /// the message starts with 'line &lt;n&gt;: '.</summary>
  ERepoBackupFormatError = class(ERepoError)
  private
    FLineNo: Integer;
  public
    /// <summary>Creates the error and prefixes the message with the line number.</summary>
    /// <param name="pLineNo">1-based line of the defect.</param>
    /// <param name="pMessage">What is wrong.</param>
    constructor CreateAt(pLineNo: Integer; const pMessage: string);
    /// <summary>1-based line of the defect.</summary>
    property LineNo: Integer read FLineNo;
  end;

/// <summary>Escapes one value for the backup text (rule 7): backslash, CR, TAB, every other
/// code unit below 0x20 or above 0x7E and a trailing space become escapes; in a record
/// header the characters '|' and ']' do too.</summary>
/// <param name="pValue">The raw value (one line; LF is escaped too).</param>
/// <param name="pInHeader">True for a primary-key value in a record header.</param>
/// <returns>Pure 7-bit printable ASCII text.</returns>
function EscapeRepoValue(const pValue: string; pInHeader: Boolean): string;

/// <summary>Reverses EscapeRepoValue.</summary>
/// <param name="pText">Escaped text.</param>
/// <returns>The raw value.</returns>
/// <exception cref="ERepoBackupFormatError">A bad escape or a character outside
/// 0x20..0x7E (LineNo = 0).</exception>
function UnescapeRepoValue(const pText: string): string;

/// <summary>Renders the repository as backup text lines (no line terminators).</summary>
/// <param name="pConnection">Open repository connection; read only.</param>
/// <param name="pLines">Receives the lines; cleared first.</param>
/// <remarks>Deterministic: the same rows always give the same lines.</remarks>
procedure BackupRepositoryToStrings(pConnection: TFDConnection; pLines: TStrings);

/// <summary>Writes the backup text to a file: ASCII bytes, CRLF, no BOM, through
/// "file.tmp" and a rename so a failed write never leaves a half file.</summary>
/// <param name="pConnection">Open repository connection; read only.</param>
/// <param name="pFileName">Target file; replaced when it exists.</param>
/// <exception cref="ERepoError">A character above 0x7F survived escaping (a bug).</exception>
procedure BackupRepository(pConnection: TFDConnection; const pFileName: string);

/// <summary>Parses and validates the lines, then replaces every row of the repository in
/// one transaction. A column omitted in the text is inserted as NULL, never as its default.</summary>
/// <param name="pConnection">Open read-write repository connection.</param>
/// <param name="pLines">Backup text lines without terminators.</param>
/// <param name="pReplace">Must be True when the repository already holds rows.</param>
/// <exception cref="ERepoBackupFormatError">The text is malformed; nothing was changed.</exception>
/// <exception cref="ERepoError">The repository is not empty and pReplace is False.</exception>
procedure RestoreRepositoryFromStrings(pConnection: TFDConnection; pLines: TStrings;
  pReplace: Boolean);

/// <summary>Restore from a file. Reads raw bytes, rejects any byte of 0x80 or more and
/// accepts LF-only line ends.</summary>
/// <param name="pConnection">Open read-write repository connection.</param>
/// <param name="pFileName">Backup file.</param>
/// <param name="pReplace">Must be True when the repository already holds rows.</param>
/// <exception cref="ERepoBackupFormatError">The file is malformed; nothing was changed.</exception>
/// <exception cref="ERepoError">The repository is not empty and pReplace is False.</exception>
procedure RestoreRepository(pConnection: TFDConnection; const pFileName: string;
  pReplace: Boolean);

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Param;

const
  BACKUP_MAGIC = '#DLREPO 1';
  BACKUP_END = '#end ';
  TEXT_PREFIX = ' |';
  CHAR_FIRST = ' ';
  CHAR_LAST = '~';
  ASCII_LIMIT = $80;
  UNICODE_HEX_DIGITS = 4;
  HEX_RADIX = 16;
  HEX_ALPHA_BASE = 10;
  BYTE_HEX_DIGITS = 2;
  LF_BYTE = 10;
  ESC_BACKSLASH = '\\';
  PK_SEPARATOR = '|';
  HEADER_CLOSE = ']';
  BOOL_TRUE = 'true';
  BOOL_FALSE = 'false';
  MAX_BYTE_VALUE = 255;
  SMALLINT_MIN = -32768;
  SMALLINT_MAX = 32767;

type
  TCell = record
    IsNull: Boolean;
    Str: string;
    Int: Int64;
    Bool: Boolean;
  end;

  TCells = TArray<TCell>;

  TParsedRow = record
    TableIdx: Integer;
    Cells: TCells;
  end;

{ ---- escaping ------------------------------------------------------------ }

function NeedsUnicodeEscape(pC: Char; pIsLast, pInHeader: Boolean): Boolean;
begin
  Result := (pC < CHAR_FIRST) or (pC > CHAR_LAST) or ((pC = ' ') and pIsLast);
  if pInHeader then
    Result := Result or (pC = PK_SEPARATOR) or (pC = HEADER_CLOSE);
end;

function EscapeRepoValue(const pValue: string; pInHeader: Boolean): string;
var
  vSb: TStringBuilder;
  vI, vLast: Integer;
  vC: Char;
begin
  vSb := TStringBuilder.Create;
  try
    vLast := Length(pValue);
    for vI := 1 to vLast do
    begin
      vC := pValue[vI];
      if vC = '\' then
        vSb.Append(ESC_BACKSLASH)
      else if vC = #13 then
        vSb.Append('\r')
      else if vC = #9 then
        vSb.Append('\t')
      else if NeedsUnicodeEscape(vC, (vI = vLast), pInHeader) then
        vSb.Append('\u').Append(IntToHex(Ord(vC), UNICODE_HEX_DIGITS))
      else
        vSb.Append(vC);
    end;
    Result := vSb.ToString;
  finally
    vSb.Free;
  end;
end;

function HexValue(pC: Char): Integer;
begin
  case pC of
    '0'..'9': Result := Ord(pC) - Ord('0');
    'A'..'F': Result := Ord(pC) - Ord('A') + HEX_ALPHA_BASE;
    'a'..'f': Result := Ord(pC) - Ord('a') + HEX_ALPHA_BASE;
  else
    Result := -1;
  end;
end;

{ Returns '' on success, else the error text. }
function TryUnescape(const pText: string; out pResult: string): string;
var
  vSb: TStringBuilder;
  vI, vK, vCode, vDigit: Integer;
  vC: Char;
begin
  Result := '';
  vSb := TStringBuilder.Create;
  try
    vI := 1;
    while (vI <= Length(pText)) and (Result = '') do
    begin
      vC := pText[vI];
      if vC <> '\' then
      begin
        if (vC < CHAR_FIRST) or (vC > CHAR_LAST) then
          Result := 'character U+' + IntToHex(Ord(vC), UNICODE_HEX_DIGITS) + ' is not 7-bit printable ASCII'
        else
          vSb.Append(vC);
        Inc(vI);
      end
      else if vI = Length(pText) then
        Result := 'escape at the end of the value'
      else
      begin
        case pText[vI + 1] of
          '\':
            begin
              vSb.Append('\');
              Inc(vI, 2);
            end;
          'r':
            begin
              vSb.Append(#13);
              Inc(vI, 2);
            end;
          't':
            begin
              vSb.Append(#9);
              Inc(vI, 2);
            end;
          'u':
            begin
              vCode := 0;
              vK := 1;
              while (vK <= UNICODE_HEX_DIGITS) and (Result = '') do
              begin
                vDigit := if vI + 1 + vK > Length(pText) then -1 else HexValue(pText[vI + 1 + vK]);
                if vDigit < 0 then
                  Result := 'bad \u escape (four hex digits needed)'
                else
                  vCode := vCode * HEX_RADIX + vDigit;
                Inc(vK);
              end;
              if Result = '' then
                vSb.Append(Char(vCode));
              Inc(vI, 2 + UNICODE_HEX_DIGITS);
            end;
        else
          Result := 'unknown escape \' + pText[vI + 1];
        end;
      end;
    end;
    pResult := vSb.ToString;
  finally
    vSb.Free;
  end;
end;

function UnescapeRepoValue(const pText: string): string;
var
  vErr: string;
begin
  vErr := TryUnescape(pText, Result);
  if vErr <> '' then
    raise ERepoBackupFormatError.CreateAt(0, vErr);
end;

constructor ERepoBackupFormatError.CreateAt(pLineNo: Integer; const pMessage: string);
begin
  inherited Create('line ' + IntToStr(pLineNo) + ': ' + pMessage);
  FLineNo := pLineNo;
end;

{ ---- backup -------------------------------------------------------------- }

function ScalarText(pField: TField; const pCol: TRepoColumn): string;
begin
  case pCol.Kind of
    rckString: Result := EscapeRepoValue(pField.AsString, False);
    rckBoolean: Result := if pField.AsBoolean then BOOL_TRUE else BOOL_FALSE;
  else
    Result := IntToStr(pField.AsLargeInt);
  end;
end;

procedure AddTextLines(pLines: TStrings; const pName, pValue: string);
var
  vStart, vPos: Integer;
  vSeg: string;
begin
  pLines.Add(pName + ':');
  vStart := 1;
  repeat
    vPos := PosEx(#10, pValue, vStart);
    vSeg := if vPos = 0 then Copy(pValue, vStart, MaxInt) else Copy(pValue, vStart, vPos - vStart);
    pLines.Add(TEXT_PREFIX + EscapeRepoValue(vSeg, False));
    vStart := vPos + 1;
  until vPos = 0;
end;

function KeyPart(pQuery: TFDQuery; const pKey: TRepoColumn): string;
var
  vField: TField;
begin
  vField := pQuery.FieldByName(pKey.Name);
  Result := if pKey.Kind = rckString then EscapeRepoValue(vField.AsString, True) else IntToStr(vField.AsLargeInt);
end;

function RecordHeader(pQuery: TFDQuery; const pTable: TRepoTable): string;
var
  vKeys: TArray<TRepoColumn>;
  vI: Integer;
  vParts: string;
begin
  vKeys := pTable.PkColumns;
  vParts := '';
  for vI := 0 to High(vKeys) do
  begin
    if vI > 0 then
      vParts := vParts + PK_SEPARATOR;
    vParts := vParts + KeyPart(pQuery, vKeys[vI]);
  end;
  Result := '[' + pTable.Name + ' ' + vParts + HEADER_CLOSE;
end;

procedure AddRecord(pQuery: TFDQuery; const pTable: TRepoTable; pLines: TStrings);
var
  vCol: TRepoColumn;
  vField: TField;
begin
  pLines.Add(RecordHeader(pQuery, pTable));
  for vCol in pTable.Columns do
  begin
    if vCol.PkOrder > 0 then
      Continue;
    vField := pQuery.FieldByName(vCol.Name);
    if vField.IsNull then
      Continue;
    if vCol.Kind = rckText then
      AddTextLines(pLines, vCol.Name, vField.AsString)
    else
      pLines.Add(vCol.Name + '=' + ScalarText(vField, vCol));
  end;
  pLines.Add('');
end;

function OrderByClause(const pTable: TRepoTable): string;
var
  vKey: TRepoColumn;
begin
  Result := '';
  for vKey in pTable.PkColumns do
    Result := Result + IfThen(Result = '', '', ', ') + QuoteRepoIdent(vKey.Name);
end;

procedure BackupRepositoryToStrings(pConnection: TFDConnection; pLines: TStrings);
var
  vTable: TRepoTable;
  vQuery: TFDQuery;
  vCount: Integer;
begin
  pLines.Clear;
  pLines.Add(BACKUP_MAGIC);
  for vTable in RepoTables do
  begin
    vQuery := TFDQuery.Create(nil);
    try
      vQuery.Connection := pConnection;
      vQuery.FormatOptions.StrsTrim := False;
      vQuery.FormatOptions.StrsEmpty2Null := False;
      vQuery.SQL.Text := 'SELECT * FROM ' + QuoteRepoIdent(vTable.Name) + ' ORDER BY ' + OrderByClause(vTable);
      vQuery.Open;
      vCount := 0;
      while not vQuery.Eof do
      begin
        AddRecord(vQuery, vTable, pLines);
        Inc(vCount);
        vQuery.Next;
      end;
    finally
      vQuery.Free;
    end;
    pLines.Add(BACKUP_END + vTable.Name + ' ' + IntToStr(vCount));
  end;
end;

procedure BackupRepository(pConnection: TFDConnection; const pFileName: string);
var
  vLines: TStringList;
  vSb: TStringBuilder;
  vText: string;
  vBytes: TBytes;
  vI: Integer;
  vTmp: string;
begin
  vLines := TStringList.Create;
  vSb := TStringBuilder.Create;
  try
    BackupRepositoryToStrings(pConnection, vLines);
    for vI := 0 to vLines.Count - 1 do
      vSb.Append(vLines[vI]).Append(#13#10);
    vText := vSb.ToString;
  finally
    vSb.Free;
    vLines.Free;
  end;
  SetLength(vBytes, Length(vText));
  for vI := 1 to Length(vText) do
  begin
    if Ord(vText[vI]) >= ASCII_LIMIT then
      raise ERepoError.Create('backup text holds a non-ASCII character after escaping');
    vBytes[vI - 1] := Byte(Ord(vText[vI]));
  end;
  vTmp := pFileName + '.tmp';
  TFile.WriteAllBytes(vTmp, vBytes);
  if TFile.Exists(pFileName) then
    TFile.Replace(vTmp, pFileName, '')
  else
    TFile.Move(vTmp, pFileName);
end;

{ ---- restore: parse ------------------------------------------------------- }

type
  TBackupParser = class
  private
    FLines: TStrings;
    FTables: TArray<TRepoTable>;
    FRows: TList<TParsedRow>;
    procedure Fail(pLineNo: Integer; const pMessage: string);
    procedure CheckChars(pLineNo: Integer; const pLine: string);
    function ColIndex(const pTable: TRepoTable; const pName: string): Integer;
    function ParseCell(pLineNo: Integer; const pCol: TRepoColumn; const pRaw: string): TCell;
    function ParseText(pLineNo: Integer; var pNo: Integer): string;
    procedure ParseRecord(pTableIdx: Integer; var pNo: Integer; var pKeys: TDictionary<string, Integer>);
    procedure ParseTrailer(pTableIdx, pNo, pCount: Integer);
  public
    constructor Create(pLines: TStrings);
    destructor Destroy; override;
    procedure Parse;
    property Rows: TList<TParsedRow> read FRows;
    property Tables: TArray<TRepoTable> read FTables;
  end;

constructor TBackupParser.Create(pLines: TStrings);
begin
  inherited Create;
  FLines := pLines;
  FTables := RepoTables;
  FRows := TList<TParsedRow>.Create;
end;

destructor TBackupParser.Destroy;
begin
  FRows.Free;
  inherited Destroy;
end;

procedure TBackupParser.Fail(pLineNo: Integer; const pMessage: string);
begin
  raise ERepoBackupFormatError.CreateAt(pLineNo, pMessage);
end;

procedure TBackupParser.CheckChars(pLineNo: Integer; const pLine: string);
var
  vC: Char;
begin
  for vC in pLine do
    if (vC < CHAR_FIRST) or (vC > CHAR_LAST) then
      Fail(pLineNo, 'character U+' + IntToHex(Ord(vC), UNICODE_HEX_DIGITS)
        + ' is not 7-bit printable ASCII');
end;

function TBackupParser.ColIndex(const pTable: TRepoTable; const pName: string): Integer;
var
  vI: Integer;
begin
  Result := -1;
  for vI := 0 to High(pTable.Columns) do
    if SameStr(pTable.Columns[vI].Name, pName) then
      Exit(vI);
end;

function IsDecimal(const pText: string): Boolean;
var
  vI, vStart: Integer;
begin
  Result := pText <> '';
  vStart := 1;
  if Result and (pText[1] = '-') then
    vStart := 2;
  if Result and (vStart > Length(pText)) then
    Result := False;
  for vI := vStart to Length(pText) do
    if (pText[vI] < '0') or (pText[vI] > '9') then
      Result := False;
end;

function TBackupParser.ParseCell(pLineNo: Integer; const pCol: TRepoColumn; const pRaw: string): TCell;
var
  vErr: string;
begin
  Result := Default(TCell);
  case pCol.Kind of
    rckString:
      begin
        vErr := TryUnescape(pRaw, Result.Str);
        if vErr <> '' then
          Fail(pLineNo, pCol.Name + ': ' + vErr);
        if Length(Result.Str) > pCol.MaxLen then
          Fail(pLineNo, pCol.Name + ': value longer than ' + IntToStr(pCol.MaxLen));
      end;
    rckBoolean:
      begin
        if pRaw = BOOL_TRUE then
          Result.Bool := True
        else if pRaw = BOOL_FALSE then
          Result.Bool := False
        else
          Fail(pLineNo, pCol.Name + ': boolean must be true or false');
      end;
  else
    begin
      if (not IsDecimal(pRaw)) or (not TryStrToInt64(pRaw, Result.Int)) then
        Fail(pLineNo, pCol.Name + ': not a decimal number');
      if (pCol.Kind = rckByte) and ((Result.Int < 0) or (Result.Int > MAX_BYTE_VALUE)) then
        Fail(pLineNo, pCol.Name + ': byte value out of 0..255');
      if (pCol.Kind = rckSmallint) and ((Result.Int < SMALLINT_MIN) or (Result.Int > SMALLINT_MAX)) then
        Fail(pLineNo, pCol.Name + ': smallint value out of range');
    end;
  end;
end;

{ pNo is the line of "NAME:"; on return it is the first line after the text block. }
function TBackupParser.ParseText(pLineNo: Integer; var pNo: Integer): string;
var
  vCount: Integer;
  vErr, vPart, vLine: string;
  vSb: TStringBuilder;
begin
  vSb := TStringBuilder.Create;
  try
  vCount := 0;
  Inc(pNo);
  while (pNo <= FLines.Count) and StartsStr(TEXT_PREFIX, FLines[pNo - 1]) do
  begin
    vLine := FLines[pNo - 1];
    CheckChars(pNo, vLine);
    vErr := TryUnescape(Copy(vLine, Length(TEXT_PREFIX) + 1, MaxInt), vPart);
    if vErr <> '' then
      Fail(pNo, vErr);
    if vCount > 0 then
      vSb.Append(#10);
    vSb.Append(vPart);
    Inc(vCount);
    Inc(pNo);
  end;
  if vCount = 0 then
    Fail(pLineNo, 'TEXT column without " |" lines');
  Result := vSb.ToString;
  finally
    vSb.Free;
  end;
end;

procedure TBackupParser.ParseRecord(pTableIdx: Integer; var pNo: Integer;
  var pKeys: TDictionary<string, Integer>);
var
  vTable, vOther: TRepoTable;
  vHeaderNo, vSp, vSep, vIdx, vI: Integer;
  vLine, vInner, vName, vKeyText: string;
  vParts: TArray<string>;
  vPk: TArray<TRepoColumn>;
  vSeen: TArray<Boolean>;
  vRow: TParsedRow;
  vCol: TRepoColumn;
begin
  vTable := FTables[pTableIdx];
  vHeaderNo := pNo;
  vLine := FLines[pNo - 1];
  if vLine[Length(vLine)] <> HEADER_CLOSE then
    Fail(vHeaderNo, 'record header must end with "]"');
  vInner := Copy(vLine, 2, Length(vLine) - 2);
  vSp := Pos(' ', vInner);
  if vSp = 0 then
    Fail(vHeaderNo, 'record header needs "[TABLE key]"');
  vName := Copy(vInner, 1, vSp - 1);
  if not SameStr(vName, vTable.Name) then
  begin
    if FindRepoTable(vName, vOther) then
      Fail(vHeaderNo, 'record of ' + vName + ' where ' + vTable.Name
        + ' is open (table out of order, repeated, or #end missing)')
    else
      Fail(vHeaderNo, 'unknown table ' + vName);
  end;
  vKeyText := Copy(vInner, vSp + 1, MaxInt);
  vParts := vKeyText.Split([PK_SEPARATOR]);
  vPk := vTable.PkColumns;
  if Length(vParts) <> Length(vPk) then
    Fail(vHeaderNo, 'wrong number of key values: ' + IntToStr(Length(vParts)) + ' for '
      + IntToStr(Length(vPk)));
  vRow.TableIdx := pTableIdx;
  SetLength(vRow.Cells, Length(vTable.Columns));
  SetLength(vSeen, Length(vTable.Columns));
  for vI := 0 to High(vRow.Cells) do
    vRow.Cells[vI].IsNull := True;
  for vI := 0 to High(vPk) do
  begin
    vIdx := ColIndex(vTable, vPk[vI].Name);
    vRow.Cells[vIdx] := ParseCell(vHeaderNo, vPk[vI], vParts[vI]);
    vSeen[vIdx] := True;
  end;
  if pKeys.ContainsKey(vKeyText) then
    Fail(vHeaderNo, 'duplicate record key ' + vKeyText);
  pKeys.Add(vKeyText, vHeaderNo);
  Inc(pNo);
  while True do
  begin
    if pNo > FLines.Count then
      Fail(pNo, 'record not closed by a blank line');
    vLine := FLines[pNo - 1];
    CheckChars(pNo, vLine);
    if vLine = '' then
    begin
      Inc(pNo);
      Break;
    end;
    vSep := 0;
    for vI := 1 to Length(vLine) do
      if (vLine[vI] = '=') or (vLine[vI] = ':') then
      begin
        vSep := vI;
        Break;
      end;
    if vSep = 0 then
      Fail(pNo, 'line is neither NAME=value nor NAME: (body line outside a record?)');
    vName := Copy(vLine, 1, vSep - 1);
    vIdx := ColIndex(vTable, vName);
    if vIdx < 0 then
      Fail(pNo, 'unknown column ' + vName + ' in ' + vTable.Name);
    vCol := vTable.Columns[vIdx];
    if vCol.PkOrder > 0 then
      Fail(pNo, 'key column ' + vName + ' must not appear in the body');
    if vSeen[vIdx] then
      Fail(pNo, 'column ' + vName + ' given twice');
    vSeen[vIdx] := True;
    if vLine[vSep] = '=' then
    begin
      if vCol.Kind = rckText then
        Fail(pNo, 'TEXT column ' + vName + ' must use the NAME: form');
      vRow.Cells[vIdx] := ParseCell(pNo, vCol, Copy(vLine, vSep + 1, MaxInt));
      Inc(pNo);
    end
    else
    begin
      if (vCol.Kind <> rckText) or (vSep <> Length(vLine)) then
        Fail(pNo, 'only a TEXT column uses the NAME: form');
      vRow.Cells[vIdx].IsNull := False;
      vRow.Cells[vIdx].Str := ParseText(pNo, pNo);
    end;
  end;
  for vI := 0 to High(vTable.Columns) do
    if (not vSeen[vI]) and vTable.Columns[vI].NotNull then
      Fail(vHeaderNo, 'NOT NULL column ' + vTable.Columns[vI].Name + ' is missing');
  FRows.Add(vRow);
end;

procedure TBackupParser.ParseTrailer(pTableIdx, pNo, pCount: Integer);
var
  vRest, vName: string;
  vSp, vN: Integer;
begin
  vRest := Copy(FLines[pNo - 1], Length(BACKUP_END) + 1, MaxInt);
  vSp := Pos(' ', vRest);
  if vSp = 0 then
    Fail(pNo, 'trailer needs "#end TABLE n"');
  vName := Copy(vRest, 1, vSp - 1);
  if not SameStr(vName, FTables[pTableIdx].Name) then
    Fail(pNo, '#end ' + vName + ' where #end ' + FTables[pTableIdx].Name + ' is due');
  if (not IsDecimal(Copy(vRest, vSp + 1, MaxInt))) or (not TryStrToInt(Copy(vRest, vSp + 1, MaxInt), vN)) then
    Fail(pNo, 'trailer count is not a number');
  if vN <> pCount then
    Fail(pNo, 'trailer says ' + IntToStr(vN) + ' records but ' + IntToStr(pCount) + ' were read');
end;

procedure TBackupParser.Parse;
var
  vT, vNo, vCount: Integer;
  vLine: string;
  vKeys: TDictionary<string, Integer>;
begin
  if (FLines.Count = 0) or (FLines[0] <> BACKUP_MAGIC) then
    Fail(1, 'first line must be "' + BACKUP_MAGIC + '"');
  vNo := 2;
  for vT := 0 to High(FTables) do
  begin
    vCount := 0;
    vKeys := TDictionary<string, Integer>.Create;
    try
      while True do
      begin
        if vNo > FLines.Count then
          Fail(vNo, 'missing #end for ' + FTables[vT].Name);
        vLine := FLines[vNo - 1];
        CheckChars(vNo, vLine);
        if StartsStr(BACKUP_END, vLine) then
        begin
          ParseTrailer(vT, vNo, vCount);
          Inc(vNo);
          Break;
        end;
        if (vLine <> '') and (vLine[1] = '[') then
        begin
          ParseRecord(vT, vNo, vKeys);
          Inc(vCount);
        end
        else
          Fail(vNo, 'line outside a record');
      end;
    finally
      vKeys.Free;
    end;
  end;
  if vNo <= FLines.Count then
    Fail(vNo, 'content after the last #end');
end;

{ ---- restore: write ------------------------------------------------------- }

function ParamFieldType(pKind: TRepoColKind): TFieldType;
begin
  case pKind of
    rckString, rckText: Result := ftWideString;
    rckBoolean: Result := ftBoolean;
    rckInteger: Result := ftLargeint;
  else
    Result := ftSmallint;
  end;
end;

procedure InsertRows(pConnection: TFDConnection; pParser: TBackupParser);
var
  vT, vI: Integer;
  vTable: TRepoTable;
  vQuery: TFDQuery;
  vCols, vVals: string;
  vRow: TParsedRow;
  vCell: TCell;
  vParam: TFDParam;
begin
  for vT := 0 to High(pParser.Tables) do
  begin
    vTable := pParser.Tables[vT];
    pConnection.ExecSQL('DELETE FROM ' + QuoteRepoIdent(vTable.Name));
  end;
  for vT := 0 to High(pParser.Tables) do
  begin
    vTable := pParser.Tables[vT];
    vCols := '';
    vVals := '';
    for vI := 0 to High(vTable.Columns) do
    begin
      vCols := vCols + IfThen(vI = 0, '', ', ') + QuoteRepoIdent(vTable.Columns[vI].Name);
      vVals := vVals + IfThen(vI = 0, '', ', ') + ':p' + IntToStr(vI);
    end;
    vQuery := TFDQuery.Create(nil);
    try
      vQuery.Connection := pConnection;
      vQuery.FormatOptions.StrsTrim := False;
      vQuery.FormatOptions.StrsEmpty2Null := False;
      vQuery.SQL.Text := 'INSERT INTO ' + QuoteRepoIdent(vTable.Name) + ' (' + vCols + ') VALUES (' + vVals + ')';
      for vI := 0 to High(vTable.Columns) do
      begin
        vParam := vQuery.Params[vI];
        vParam.ParamType := ptInput;
        vParam.DataType := ParamFieldType(vTable.Columns[vI].Kind);
      end;
      for vRow in pParser.Rows do
      begin
        if vRow.TableIdx <> vT then
          Continue;
        for vI := 0 to High(vTable.Columns) do
        begin
          vCell := vRow.Cells[vI];
          vParam := vQuery.Params[vI];
          if vCell.IsNull then
            vParam.Value := Null
          else
            case vTable.Columns[vI].Kind of
              rckString, rckText: vParam.AsWideString := vCell.Str;
              rckBoolean: vParam.AsBoolean := vCell.Bool;
              rckInteger: vParam.AsLargeInt := vCell.Int;
            else
              vParam.AsSmallInt := vCell.Int;
            end;
        end;
        vQuery.ExecSQL;
      end;
    finally
      vQuery.Free;
    end;
  end;
end;

procedure RestoreRepositoryFromStrings(pConnection: TFDConnection; pLines: TStrings;
  pReplace: Boolean);
var
  vParser: TBackupParser;
begin
  vParser := TBackupParser.Create(pLines);
  try
    vParser.Parse;
    if (not pReplace) and (not RepoIsEmpty(pConnection)) then
      raise ERepoError.Create('the repository already holds rows; restore needs replace');
    pConnection.StartTransaction;
    try
      InsertRows(pConnection, vParser);
      pConnection.Commit;
    except
      on Exception do
        begin
          pConnection.Rollback;
          raise;
        end;
    end;
  finally
    vParser.Free;
  end;
end;

procedure RestoreRepository(pConnection: TFDConnection; const pFileName: string;
  pReplace: Boolean);
var
  vBytes: TBytes;
  vLines: TStringList;
  vText, vLine: string;
  vI, vLineNo, vStart, vPos: Integer;
begin
  vBytes := TFile.ReadAllBytes(pFileName);
  vLineNo := 1;
  for vI := 0 to High(vBytes) do
  begin
    if vBytes[vI] >= ASCII_LIMIT then
      raise ERepoBackupFormatError.CreateAt(vLineNo, 'non-ASCII byte 0x' + IntToHex(vBytes[vI], BYTE_HEX_DIGITS));
    if vBytes[vI] = LF_BYTE then
      Inc(vLineNo);
  end;
  vText := TEncoding.ASCII.GetString(vBytes);
  vLines := TStringList.Create;
  try
    vStart := 1;
    while vStart <= Length(vText) do
    begin
      vPos := PosEx(#10, vText, vStart);
      if vPos = 0 then
        vPos := Length(vText) + 1;
      vLine := Copy(vText, vStart, vPos - vStart);
      if (vLine <> '') and (vLine[Length(vLine)] = #13) then
        SetLength(vLine, Length(vLine) - 1);
      vLines.Add(vLine);
      vStart := vPos + 1;
    end;
    RestoreRepositoryFromStrings(pConnection, vLines, pReplace);
  finally
    vLines.Free;
  end;
end;

end.
