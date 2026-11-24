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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.Repo.RunRepoVerb (DRagLint.CLI.Repo.pas) ?, DRagLint.FieldRepo.TextBackup.RestoreRepository (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.TBackupParser.Fail (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.UnescapeRepoValue (DRagLint.FieldRepo.TextBackup.pas)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.TextBackup</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ERepoBackupFormatError = class(ERepoError)
  private
    FLineNo: Integer;
  public
    /// <summary>Creates the error and prefixes the message with the line number.</summary>
    /// <param name="pLineNo">1-based line of the defect.</param>
    /// <param name="pMessage">What is wrong.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.TextBackup.RestoreRepository (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.TBackupParser.Fail (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.UnescapeRepoValue (DRagLint.FieldRepo.TextBackup.pas)</para>
    /// <para>Calls: Create, IntToStr</para>
    /// <para>constructor</para>
    /// <para>Writes: FLineNo</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.TextBackup.AddTextLines (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.KeyPart (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.ScalarText (DRagLint.FieldRepo.TextBackup.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.TextBackup.NeedsUnicodeEscape, IntToHex</para>
/// <para>Returns: VSb.ToString</para>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.NeedsUnicodeEscape"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EscapeRepoValue(const pValue: string; pInHeader: Boolean): string;

/// <summary>Reverses EscapeRepoValue.</summary>
/// <param name="pText">Escaped text.</param>
/// <returns>The raw value.</returns>
/// <exception cref="ERepoBackupFormatError">A bad escape or a character outside
/// 0x20..0x7E (LineNo = 0).</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.FieldRepo.TextBackup.ERepoBackupFormatError.CreateAt, DRagLint.FieldRepo.TextBackup.TryUnescape</para>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.ERepoBackupFormatError.CreateAt"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.TryUnescape"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnescapeRepoValue(const pText: string): string;

/// <summary>Renders the repository as backup text lines (no line terminators).</summary>
/// <param name="pConnection">Open repository connection; read only.</param>
/// <param name="pLines">Receives the lines; cleared first.</param>
/// <remarks>
/// Deterministic: the same rows always give the same lines.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.TextBackup.BackupRepository (DRagLint.FieldRepo.TextBackup.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.QuoteRepoIdent, DRagLint.FieldRepo.Schema.RepoTables, DRagLint.FieldRepo.TextBackup.AddRecord, DRagLint.FieldRepo.TextBackup.OrderByClause, IntToStr</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTables"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.AddRecord"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.OrderByClause"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BackupRepositoryToStrings(pConnection: TFDConnection; pLines: TStrings);

/// <summary>Writes the backup text to a file: ASCII bytes, CRLF, no BOM, through a
/// temporary file beside it and one rename. A failure leaves an existing file as it was and no temporary file.</summary>
/// <param name="pConnection">Open repository connection; read only.</param>
/// <param name="pFileName">Target file; replaced when it exists.</param>
/// <exception cref="ERepoError">A character above 0x7F survived escaping (a bug).</exception>
/// <exception cref="EOSError">The target cannot be replaced (in use, read-only).</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoBackup (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: Byte, DRagLint.FieldRepo.TextBackup.BackupRepositoryToStrings</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.BackupRepositoryToStrings"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BackupRepository(pConnection: TFDConnection; const pFileName: string);

/// <summary>Parses and validates the lines, then replaces every row of the repository in
/// one transaction. A column omitted in the text is inserted as NULL, never as its default. An older backup restored
/// into a repository of schema REPO_SCHEMA_VERSION gets the data steps of `repo migrate`.</summary>
/// <param name="pConnection">Open read-write repository connection.</param>
/// <param name="pLines">Backup text lines without terminators.</param>
/// <param name="pReplace">Must be True when the repository already holds rows.</param>
/// <exception cref="ERepoBackupFormatError">The text is malformed; nothing was changed.</exception>
/// <exception cref="ERepoError">The repository is not empty and pReplace is False.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.TextBackup.RestoreRepository (DRagLint.FieldRepo.TextBackup.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.RepoIsEmpty, DRagLint.FieldRepo.TextBackup.InsertRows, DRagLint.FieldRepo.TextBackup.TBackupParser.Create, DRagLint.FieldRepo.TextBackup.TBackupParser.Parse</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Transaction: starts, commits, rolls back</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoIsEmpty"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.InsertRows"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.TBackupParser.Create"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.TBackupParser.Parse"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RestoreRepositoryFromStrings(pConnection: TFDConnection; pLines: TStrings;
  pReplace: Boolean);

/// <summary>Restore from a file. Reads raw bytes, rejects any byte of 0x80 or more and
/// accepts LF-only line ends.</summary>
/// <param name="pConnection">Open read-write repository connection.</param>
/// <param name="pFileName">Backup file.</param>
/// <param name="pReplace">Must be True when the repository already holds rows.</param>
/// <exception cref="ERepoBackupFormatError">The file is malformed; nothing was changed.</exception>
/// <exception cref="ERepoError">The repository is not empty and pReplace is False.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoRestore (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: Copy, DRagLint.FieldRepo.TextBackup.ERepoBackupFormatError.CreateAt, DRagLint.FieldRepo.TextBackup.RestoreRepositoryFromStrings, IntToHex, PosEx</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.ERepoBackupFormatError.CreateAt"/>
/// <seealso cref="DRagLint.FieldRepo.TextBackup.RestoreRepositoryFromStrings"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RestoreRepository(pConnection: TFDConnection; const pFileName: string;
  pReplace: Boolean);

/// <summary>Reads the schema version a backup file declares on its first line.</summary>
/// <param name="pFileName">Backup file (ASCII).</param>
/// <returns>1 for `#DLREPO 1`, 2 for `#DLREPO 2`, 3 for `#DLREPO 3`, 0 for any other first line (or an empty file).</returns>
/// <remarks>Used by `repo restore` to create a missing repository at the backup's own version.</remarks>
function BackupFileVersion(const pFileName: string): Integer;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Param;

const
  BACKUP_MAGIC_PREFIX = '#DLREPO ';
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
  VSb: TStringBuilder;
  VI, VLast: Integer;
  VC: Char;
begin
  VSb := TStringBuilder.Create;
  try
    VLast := Length(pValue);
    for VI := 1 to VLast do
    begin
      VC := pValue[VI];
      if VC = '\' then
        VSb.Append(ESC_BACKSLASH)
      else if VC = #13 then
        VSb.Append('\r')
      else if VC = #9 then
        VSb.Append('\t')
      else if NeedsUnicodeEscape(VC, (VI = VLast), pInHeader) then
        VSb.Append('\u').Append(IntToHex(Ord(VC), UNICODE_HEX_DIGITS))
      else
        VSb.Append(VC);
    end;
    Result := VSb.ToString;
  finally
    VSb.Free;
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
  VSb: TStringBuilder;
  VI, VK, VCode, VDigit: Integer;
  VC: Char;
begin
  Result := '';
  VSb := TStringBuilder.Create;
  try
    VI := 1;
    while (VI <= Length(pText)) and (Result = '') do
    begin
      VC := pText[VI];
      if VC <> '\' then
      begin
        if (VC < CHAR_FIRST) or (VC > CHAR_LAST) then
          Result := 'character U+' + IntToHex(Ord(VC), UNICODE_HEX_DIGITS) + ' is not 7-bit printable ASCII'
        else
          VSb.Append(VC);
        Inc(VI);
      end
      else if VI = Length(pText) then
        Result := 'escape at the end of the value'
      else
      begin
        case pText[VI + 1] of
          '\':
            begin
              VSb.Append('\');
              Inc(VI, 2);
            end;
          'r':
            begin
              VSb.Append(#13);
              Inc(VI, 2);
            end;
          't':
            begin
              VSb.Append(#9);
              Inc(VI, 2);
            end;
          'u':
            begin
              VCode := 0;
              VK := 1;
              while (VK <= UNICODE_HEX_DIGITS) and (Result = '') do
              begin
                VDigit := if VI + 1 + VK > Length(pText) then -1 else HexValue(pText[VI + 1 + VK]);
                if VDigit < 0 then
                  Result := 'bad \u escape (four hex digits needed)'
                else
                  VCode := VCode * HEX_RADIX + VDigit;
                Inc(VK);
              end;
              if Result = '' then
                VSb.Append(Char(VCode));
              Inc(VI, 2 + UNICODE_HEX_DIGITS);
            end;
        else
          Result := 'unknown escape \' + pText[VI + 1];
        end;
      end;
    end;
    pResult := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

function UnescapeRepoValue(const pText: string): string;
var
  VErr: string;
begin
  VErr := TryUnescape(pText, Result);
  if VErr <> '' then
    raise ERepoBackupFormatError.CreateAt(0, VErr);
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
  VStart, VPos: Integer;
  VSeg: string;
begin
  pLines.Add(pName + ':');
  VStart := 1;
  repeat
    VPos := PosEx(#10, pValue, VStart);
    VSeg := if VPos = 0 then Copy(pValue, VStart, MaxInt) else Copy(pValue, VStart, VPos - VStart);
    pLines.Add(TEXT_PREFIX + EscapeRepoValue(VSeg, False));
    VStart := VPos + 1;
  until VPos = 0;
end;

function KeyPart(pQuery: TFDQuery; const pKey: TRepoColumn): string;
var
  VField: TField;
begin
  VField := pQuery.FieldByName(pKey.Name);
  Result := if pKey.Kind = rckString then EscapeRepoValue(VField.AsString, True) else IntToStr(VField.AsLargeInt);
end;

function RecordHeader(pQuery: TFDQuery; const pTable: TRepoTable): string;
var
  VKeys: TArray<TRepoColumn>;
  VI: Integer;
  VParts: string;
begin
  VKeys := pTable.PkColumns;
  VParts := '';
  for VI := 0 to High(VKeys) do
  begin
    if VI > 0 then
      VParts := VParts + PK_SEPARATOR;  // dl:ok concat-in-loop@fb70 -- REVIEWED SLZ-S11 2026-11-22: loop over a primary key's few columns; a TStringBuilder adds nothing
    VParts := VParts + KeyPart(pQuery, VKeys[VI]);  // dl:ok concat-in-loop@16a9 -- REVIEWED SLZ-S11 2026-11-22: loop over a primary key's few columns; a TStringBuilder adds nothing
  end;
  Result := '[' + pTable.Name + ' ' + VParts + HEADER_CLOSE;
end;

procedure AddRecord(pQuery: TFDQuery; const pTable: TRepoTable; pLines: TStrings);
var
  VCol: TRepoColumn;
  VField: TField;
begin
  pLines.Add(RecordHeader(pQuery, pTable));
  for VCol in pTable.Columns do
  begin
    if VCol.PkOrder > 0 then
      Continue;
    VField := pQuery.FieldByName(VCol.Name);
    if VField.IsNull then
      Continue;
    if VCol.Kind = rckText then
      AddTextLines(pLines, VCol.Name, VField.AsString)
    else
      pLines.Add(VCol.Name + '=' + ScalarText(VField, VCol));
  end;
  pLines.Add('');
end;

function OrderByClause(const pTable: TRepoTable): string;
var
  VKey: TRepoColumn;
begin
  Result := '';
  for VKey in pTable.PkColumns do
    Result := Result + IfThen(Result = '', '', ', ') + QuoteRepoIdent(VKey.Name);
end;

procedure BackupRepositoryToStrings(pConnection: TFDConnection; pLines: TStrings);
var
  VTable: TRepoTable;
  VQuery: TFDQuery;
  VCount, VVersion: Integer;
begin
  pLines.Clear;
  VVersion := RepoSchemaVersion(pConnection);
  pLines.Add(BACKUP_MAGIC_PREFIX + IntToStr(VVersion));
  for VTable in RepoTablesFor(VVersion) do
  begin
    VQuery := TFDQuery.Create(nil);
    try
      VQuery.Connection := pConnection;
      VQuery.FormatOptions.StrsTrim := False;
      VQuery.FormatOptions.StrsEmpty2Null := False;
      VQuery.SQL.Text := 'SELECT * FROM ' + QuoteRepoIdent(VTable.Name) + ' ORDER BY ' + OrderByClause(VTable);
      VQuery.Open;
      VCount := 0;
      while not VQuery.Eof do
      begin
        AddRecord(VQuery, VTable, pLines);
        Inc(VCount);
        VQuery.Next;
      end;
    finally
      VQuery.Free;
    end;
    pLines.Add(BACKUP_END + VTable.Name + ' ' + IntToStr(VCount));
  end;
end;

{ The whole content goes into a new file beside the target, then one rename replaces the target: whatever fails, the old
  file is complete and no temporary file stays. Not TFile.Replace: its wrapper refuses an empty backup name. }
procedure WriteFileAtomic(const pFileName: string; const pBytes: TBytes);
var
  VTmp: string;
begin
  VTmp := pFileName + '.' + TGUID.NewGuid.ToString.Trim(['{', '}']) + '.tmp';
  try
    TFile.WriteAllBytes(VTmp, pBytes);
    if not MoveFileEx(PChar(VTmp), PChar(pFileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    System.SysUtils.DeleteFile(VTmp);
    raise;
  end;
end;

procedure BackupRepository(pConnection: TFDConnection; const pFileName: string);
var
  VLines: TStringList;
  VSb: TStringBuilder;
  VText: string;
  VBytes: TBytes;
  VI: Integer;
begin
  VLines := TStringList.Create;
  VSb := TStringBuilder.Create;
  try
    BackupRepositoryToStrings(pConnection, VLines);
    for VI := 0 to VLines.Count - 1 do
      VSb.Append(VLines[VI]).Append(#13#10);
    VText := VSb.ToString;
  finally
    VSb.Free;
    VLines.Free;
  end;
  SetLength(VBytes, Length(VText));
  for VI := 1 to Length(VText) do
  begin
    if Ord(VText[VI]) >= ASCII_LIMIT then
      raise ERepoError.Create('backup text holds a non-ASCII character after escaping');
    VBytes[VI - 1] := Byte(Ord(VText[VI]));
  end;
  WriteFileAtomic(pFileName, VBytes);
end;

{ ---- restore: parse ------------------------------------------------------- }

function BackupLineVersion(const pLine: string): Integer;
var
  VVersion: Integer;
begin
  Result := 0;
  for VVersion := REPO_SCHEMA_MIN_VERSION to REPO_SCHEMA_VERSION do
    if SameStr(pLine, BACKUP_MAGIC_PREFIX + IntToStr(VVersion)) then
      Exit(VVersion);
end;

function BackupFileVersion(const pFileName: string): Integer;
var
  VLines: TStringList;
begin
  VLines := TStringList.Create;
  try
    VLines.LoadFromFile(pFileName, TEncoding.ASCII);
    Result := if VLines.Count = 0 then 0 else BackupLineVersion(VLines[0]);
  finally
    VLines.Free;
  end;
end;

type
  TBackupParser = class
  private
    FLines: TStrings;
    FTables: TArray<TRepoTable>;
    FVersion: Integer;
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
    property Version: Integer read FVersion;
  end;

constructor TBackupParser.Create(pLines: TStrings);
begin
  inherited Create;
  FLines := pLines;
  FTables := nil;
  FVersion := 0;
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
  VC: Char;
begin
  for VC in pLine do
    if (VC < CHAR_FIRST) or (VC > CHAR_LAST) then
      Fail(pLineNo, 'character U+' + IntToHex(Ord(VC), UNICODE_HEX_DIGITS)
        + ' is not 7-bit printable ASCII');
end;

function TBackupParser.ColIndex(const pTable: TRepoTable; const pName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pTable.Columns) do
    if SameStr(pTable.Columns[VI].Name, pName) then
      Exit(VI);
end;

function IsDecimal(const pText: string): Boolean;
var
  VI, VStart: Integer;
begin
  Result := pText <> '';
  VStart := 1;
  if Result and (pText[1] = '-') then
    VStart := 2;
  if Result and (VStart > Length(pText)) then
    Result := False;
  for VI := VStart to Length(pText) do
    if (pText[VI] < '0') or (pText[VI] > '9') then
      Result := False;
end;

function TBackupParser.ParseCell(pLineNo: Integer; const pCol: TRepoColumn; const pRaw: string): TCell;
var
  VErr: string;
begin
  Result := Default(TCell);
  case pCol.Kind of
    rckString:
      begin
        VErr := TryUnescape(pRaw, Result.Str);
        if VErr <> '' then
          Fail(pLineNo, pCol.Name + ': ' + VErr);
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
  VCount: Integer;
  VErr, VPart, VLine: string;
  VSb: TStringBuilder;
begin
  VSb := TStringBuilder.Create;
  try
  VCount := 0;
  Inc(pNo);
  while (pNo <= FLines.Count) and StartsStr(TEXT_PREFIX, FLines[pNo - 1]) do
  begin
    VLine := FLines[pNo - 1];
    CheckChars(pNo, VLine);
    VErr := TryUnescape(Copy(VLine, Length(TEXT_PREFIX) + 1, MaxInt), VPart);
    if VErr <> '' then
      Fail(pNo, VErr);
    if VCount > 0 then
      VSb.Append(#10);
    VSb.Append(VPart);
    Inc(VCount);
    Inc(pNo);
  end;
  if VCount = 0 then
    Fail(pLineNo, 'TEXT column without " |" lines');
  Result := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

procedure TBackupParser.ParseRecord(pTableIdx: Integer; var pNo: Integer;
  var pKeys: TDictionary<string, Integer>);
var
  VTable, VOther: TRepoTable;
  VHeaderNo, VSp, VSep, VIdx, VI: Integer;
  VLine, VInner, VName, VKeyText: string;
  VParts: TArray<string>;
  VPk: TArray<TRepoColumn>;
  VSeen: TArray<Boolean>;
  VRow: TParsedRow;
  VCol: TRepoColumn;
begin
  VTable := FTables[pTableIdx];
  VHeaderNo := pNo;
  VLine := FLines[pNo - 1];
  if VLine[Length(VLine)] <> HEADER_CLOSE then
    Fail(VHeaderNo, 'record header must end with "]"');
  VInner := Copy(VLine, 2, Length(VLine) - 2);
  VSp := Pos(' ', VInner);
  if VSp = 0 then
    Fail(VHeaderNo, 'record header needs "[TABLE key]"');
  VName := Copy(VInner, 1, VSp - 1);
  if not SameStr(VName, VTable.Name) then
  begin
    if FindRepoTable(VName, VOther) then
      Fail(VHeaderNo, 'record of ' + VName + ' where ' + VTable.Name
        + ' is open (table out of order, repeated, or #end missing)')
    else
      Fail(VHeaderNo, 'unknown table ' + VName);
  end;
  VKeyText := Copy(VInner, VSp + 1, MaxInt);
  VParts := VKeyText.Split([PK_SEPARATOR]);
  VPk := VTable.PkColumns;
  if Length(VParts) <> Length(VPk) then
    Fail(VHeaderNo, 'wrong number of key values: ' + IntToStr(Length(VParts)) + ' for '
      + IntToStr(Length(VPk)));
  VRow.TableIdx := pTableIdx;
  SetLength(VRow.Cells, Length(VTable.Columns));
  SetLength(VSeen, Length(VTable.Columns));
  for VI := 0 to High(VRow.Cells) do
    VRow.Cells[VI].IsNull := True;
  for VI := 0 to High(VPk) do
  begin
    VIdx := ColIndex(VTable, VPk[VI].Name);
    VRow.Cells[VIdx] := ParseCell(VHeaderNo, VPk[VI], VParts[VI]);
    VSeen[VIdx] := True;
  end;
  if pKeys.ContainsKey(VKeyText) then
    Fail(VHeaderNo, 'duplicate record key ' + VKeyText);
  pKeys.Add(VKeyText, VHeaderNo);
  Inc(pNo);
  while True do
  begin
    if pNo > FLines.Count then
      Fail(pNo, 'record not closed by a blank line');
    VLine := FLines[pNo - 1];
    CheckChars(pNo, VLine);
    if VLine = '' then
    begin
      Inc(pNo);
      Break;
    end;
    VSep := 0;
    for VI := 1 to Length(VLine) do
      if (VLine[VI] = '=') or (VLine[VI] = ':') then
      begin
        VSep := VI;
        Break;
      end;
    if VSep = 0 then
      Fail(pNo, 'line is neither NAME=value nor NAME: (body line outside a record?)');
    VName := Copy(VLine, 1, VSep - 1);
    VIdx := ColIndex(VTable, VName);
    if VIdx < 0 then
      Fail(pNo, 'unknown column ' + VName + ' in ' + VTable.Name);
    VCol := VTable.Columns[VIdx];
    if VCol.PkOrder > 0 then
      Fail(pNo, 'key column ' + VName + ' must not appear in the body');
    if VSeen[VIdx] then
      Fail(pNo, 'column ' + VName + ' given twice');
    VSeen[VIdx] := True;
    if VLine[VSep] = '=' then
    begin
      if VCol.Kind = rckText then
        Fail(pNo, 'TEXT column ' + VName + ' must use the NAME: form');
      VRow.Cells[VIdx] := ParseCell(pNo, VCol, Copy(VLine, VSep + 1, MaxInt));
      Inc(pNo);
    end
    else
    begin
      if (VCol.Kind <> rckText) or (VSep <> Length(VLine)) then
        Fail(pNo, 'only a TEXT column uses the NAME: form');
      VRow.Cells[VIdx].IsNull := False;
      VRow.Cells[VIdx].Str := ParseText(pNo, pNo);
    end;
  end;
  for VI := 0 to High(VTable.Columns) do
    if (not VSeen[VI]) and VTable.Columns[VI].NotNull then
      Fail(VHeaderNo, 'NOT NULL column ' + VTable.Columns[VI].Name + ' is missing');
  FRows.Add(VRow);
end;

procedure TBackupParser.ParseTrailer(pTableIdx, pNo, pCount: Integer);
var
  VRest, VName: string;
  VSp, VN: Integer;
begin
  VRest := Copy(FLines[pNo - 1], Length(BACKUP_END) + 1, MaxInt);
  VSp := Pos(' ', VRest);
  if VSp = 0 then
    Fail(pNo, 'trailer needs "#end TABLE n"');
  VName := Copy(VRest, 1, VSp - 1);
  if not SameStr(VName, FTables[pTableIdx].Name) then
    Fail(pNo, '#end ' + VName + ' where #end ' + FTables[pTableIdx].Name + ' is due');
  if (not IsDecimal(Copy(VRest, VSp + 1, MaxInt))) or (not TryStrToInt(Copy(VRest, VSp + 1, MaxInt), VN)) then
    Fail(pNo, 'trailer count is not a number');
  if VN <> pCount then
    Fail(pNo, 'trailer says ' + IntToStr(VN) + ' records but ' + IntToStr(pCount) + ' were read');
end;

procedure TBackupParser.Parse;
var
  VT, VNo, VCount: Integer;
  VLine: string;
  VKeys: TDictionary<string, Integer>;
begin
  if (FLines.Count = 0) or (BackupLineVersion(FLines[0]) = 0) then
    Fail(1, Format('first line must be "%0:s%1:d" to "%0:s%2:d"', [BACKUP_MAGIC_PREFIX, REPO_SCHEMA_MIN_VERSION, REPO_SCHEMA_VERSION]));
  FVersion := BackupLineVersion(FLines[0]);
  FTables := RepoTablesFor(FVersion);
  VNo := 2;
  for VT := 0 to High(FTables) do
  begin
    VCount := 0;
    VKeys := TDictionary<string, Integer>.Create;
    try
      while True do
      begin
        if VNo > FLines.Count then
          Fail(VNo, 'missing #end for ' + FTables[VT].Name);
        VLine := FLines[VNo - 1];
        CheckChars(VNo, VLine);
        if StartsStr(BACKUP_END, VLine) then
        begin
          ParseTrailer(VT, VNo, VCount);
          Inc(VNo);
          Break;
        end;
        if (VLine <> '') and (VLine[1] = '[') then
        begin
          ParseRecord(VT, VNo, VKeys);
          Inc(VCount);
        end
        else
          Fail(VNo, 'line outside a record');
      end;
    finally
      VKeys.Free;
    end;
  end;
  if VNo <= FLines.Count then
    Fail(VNo, 'content after the last #end');
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
  VT, VI: Integer;
  VTable: TRepoTable;
  VQuery: TFDQuery;
  VCols, VVals: string;
  VRow: TParsedRow;
  VCell: TCell;
  VParam: TFDParam;
begin
  { every table of the repository's own version is emptied, also the tables an older
    backup does not carry (they are restored empty) }
  for VTable in RepoTablesFor(RepoSchemaVersion(pConnection)) do
    pConnection.ExecSQL('DELETE FROM ' + QuoteRepoIdent(VTable.Name));
  for VT := 0 to High(pParser.Tables) do
  begin
    VTable := pParser.Tables[VT];
    VCols := '';
    VVals := '';
    for VI := 0 to High(VTable.Columns) do
    begin
      VCols := VCols + IfThen(VI = 0, '', ', ') + QuoteRepoIdent(VTable.Columns[VI].Name);
      VVals := VVals + IfThen(VI = 0, '', ', ') + ':p' + IntToStr(VI);
    end;
    VQuery := TFDQuery.Create(nil);
    try
      VQuery.Connection := pConnection;
      VQuery.FormatOptions.StrsTrim := False;
      VQuery.FormatOptions.StrsEmpty2Null := False;
      VQuery.SQL.Text := 'INSERT INTO ' + QuoteRepoIdent(VTable.Name) + ' (' + VCols + ') VALUES (' + VVals + ')';
      for VI := 0 to High(VTable.Columns) do
      begin
        VParam := VQuery.Params[VI];
        VParam.ParamType := ptInput;
        VParam.DataType := ParamFieldType(VTable.Columns[VI].Kind);
      end;
      for VRow in pParser.Rows do
      begin
        if VRow.TableIdx <> VT then
          Continue;
        for VI := 0 to High(VTable.Columns) do
        begin
          VCell := VRow.Cells[VI];
          VParam := VQuery.Params[VI];
          if VCell.IsNull then
            VParam.Value := Null
          else
            case VTable.Columns[VI].Kind of
              rckString, rckText: VParam.AsWideString := VCell.Str;
              rckBoolean: VParam.AsBoolean := VCell.Bool;
              rckInteger: VParam.AsLargeInt := VCell.Int;
            else
              VParam.AsSmallInt := VCell.Int;
            end;
        end;
        VQuery.ExecSQL;
      end;
    finally
      VQuery.Free;
    end;
  end;
end;

{ True when the tables RepoIsEmpty leaves out, but a restore would empty, hold no rows. }
function UserTablesEmpty(pConnection: TFDConnection): Boolean;
var
  VTable: TRepoTable;
begin
  for VTable in RepoTablesFor(RepoSchemaVersion(pConnection)) do
    if MatchText(VTable.Name, [REPO_TABLE_LAYOUT_EVENTS, REPO_TABLE_EXCEPTIONS, REPO_TABLE_GRID_COLUMNS])
      and (RepoRowCount(pConnection, VTable.Name) > 0) then
      Exit(False);
  Result := True;
end;

procedure RestoreRepositoryFromStrings(pConnection: TFDConnection; pLines: TStrings;
  pReplace: Boolean);
var
  VParser: TBackupParser;
begin
  VParser := TBackupParser.Create(pLines);
  try
    VParser.Parse;
    if VParser.Version > RepoSchemaVersion(pConnection) then
      raise ERepoError.CreateFmt('backup schema %d does not match repository schema %d: migrate first (repo migrate --apply)',
        [VParser.Version, RepoSchemaVersion(pConnection)]);
    if (not pReplace) and ((not RepoIsEmpty(pConnection)) or (not UserTablesEmpty(pConnection))) then
      raise ERepoError.Create('the repository already holds rows; restore needs replace');
    pConnection.StartTransaction;
    try
      InsertRows(pConnection, VParser);
      if (VParser.Version < REPO_SCHEMA_VERSION) and (RepoSchemaVersion(pConnection) = REPO_SCHEMA_VERSION) then
        MigrateRepoRows(pConnection, VParser.Version);
      pConnection.Commit;
    except
      on Exception do
        begin
          pConnection.Rollback;
          raise;
        end;
    end;
  finally
    VParser.Free;
  end;
end;

procedure RestoreRepository(pConnection: TFDConnection; const pFileName: string;
  pReplace: Boolean);
var
  VBytes: TBytes;
  VLines: TStringList;
  VText, VLine: string;
  VI, VLineNo, VStart, VPos: Integer;
begin
  VBytes := TFile.ReadAllBytes(pFileName);
  VLineNo := 1;
  for VI := 0 to High(VBytes) do
  begin
    if VBytes[VI] >= ASCII_LIMIT then
      raise ERepoBackupFormatError.CreateAt(VLineNo, 'non-ASCII byte 0x' + IntToHex(VBytes[VI], BYTE_HEX_DIGITS));
    if VBytes[VI] = LF_BYTE then
      Inc(VLineNo);
  end;
  VText := TEncoding.ASCII.GetString(VBytes);
  VLines := TStringList.Create;
  try
    VStart := 1;
    while VStart <= Length(VText) do
    begin
      VPos := PosEx(#10, VText, VStart);
      if VPos = 0 then
        VPos := Length(VText) + 1;
      VLine := Copy(VText, VStart, VPos - VStart);
      if (VLine <> '') and (VLine[Length(VLine)] = #13) then
        SetLength(VLine, Length(VLine) - 1);
      VLines.Add(VLine);
      VStart := VPos + 1;
    end;
    RestoreRepositoryFromStrings(pConnection, VLines, pReplace);
  finally
    VLines.Free;
  end;
end;

end.
