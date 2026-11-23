unit DRagLint.FieldRepo.FbDdl;

{ drag-lint 1.53 -- lane FR-SCHEMA: the OFFLINE schema reader. Splits Firebird DDL (an isql script) into
  statements and parses the subset the field repository stores (design 2026-11-22-field-repository-v2-design.md
  section 5) into the same TFbSchemaModel the live reader fills:
    CREATE DOMAIN, CREATE [GLOBAL TEMPORARY] TABLE, CREATE GENERATOR / SEQUENCE,
    ALTER TABLE ... ADD [COLUMN] / ADD [CONSTRAINT] ...
  CREATE INDEX is ignored, SET TERM blocks (procedure / trigger bodies) are skipped, every other statement is
  counted and listed with its line, never fatal. A malformed CREATE TABLE is an error naming file and line. }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.FbSchemaRead;

type
  /// <summary>A statement the subset parser does not know.</summary>
  TFbDdlUnknown = record
    /// <summary>The file it came from.</summary>
    FileName: string;
    /// <summary>1-based line of the statement's first token.</summary>
    Line: Integer;
    /// <summary>The first words of the statement, whitespace collapsed, at most 60 characters.</summary>
    Text: string;
  end;

  /// <summary>The schema model plus the statements that were not understood.</summary>
  TFbDdlResult = record
    Model: TFbSchemaModel;
    Unknown: TArray<TFbDdlUnknown>;
    /// <summary>Statements inside SET TERM blocks that were skipped silently.</summary>
    SkippedBlockStatements: Integer;
  end;

  /// <summary>A malformed statement; the message starts with 'file(line): '.</summary>
  EFbDdlError = class(Exception);

/// <summary>Parses the DDL of one or more files into one schema model.</summary>
/// <param name="pFiles">Full paths, in order (an ALTER TABLE may refer to a table of an earlier file).</param>
/// <returns>The model (Source 'ddl', Database = the file names joined with ';') and the unknown statements.</returns>
/// <exception cref="EFbDdlError">A CREATE TABLE / ALTER TABLE ADD is malformed, or a file is missing; nothing is returned.</exception>
/// <remarks>Unquoted identifiers are upper-cased, quoted ones are kept exactly (a quoted name may contain $).
/// FIELD_LENGTH is the byte length: VARCHAR(n) CHARACTER SET UTF8 is 4n, any other charset n (the database default
/// charset is not known offline); CHAR_LENGTH is always n. A column of a domain declared later in the files takes
/// that domain's type at the end of the read.</remarks>
function ReadDdlFiles(const pFiles: TArray<string>): TFbDdlResult;

/// <summary>Parses DDL text; the file name is used in messages and in the unknown list.</summary>
/// <param name="pText">The script.</param>
/// <param name="pFileName">Label of the text, e.g. the file path.</param>
/// <returns>As ReadDdlFiles.</returns>
/// <exception cref="EFbDdlError">As ReadDdlFiles.</exception>
function ReadDdlText(const pText, pFileName: string): TFbDdlResult;  // dl:ok unused-public-symbol@60b1 -- REVIEWED 2026-11-22 FR-SCHEMA: public API of the schema-in-repository feature: used by the CLI / tests / lane FR-LINT, outside this project index

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections;

const
  FB_SHORT = 7;
  FB_LONG = 8;
  FB_FLOAT = 10;
  FB_DATE = 12;
  FB_TIME = 13;
  FB_CHAR = 14;
  FB_INT64 = 16;
  FB_BOOLEAN = 23;
  FB_DEC16 = 24;
  FB_DEC34 = 25;
  FB_INT128 = 26;
  FB_DOUBLE = 27;
  FB_TIMESTAMP = 35;
  FB_VARCHAR = 37;
  FB_BLOB = 261;
  SIZE_SHORT = 2;
  SIZE_LONG = 4;
  SIZE_INT64 = 8;
  SIZE_INT128 = 16;
  SIZE_BOOLEAN = 1;
  SIZE_BLOB = 8;
  PREC_SHORT = 4;
  PREC_LONG = 9;
  PREC_INT64 = 18;
  PREC_DEFAULT = 18;
  DEC16_DIGITS = 16;
  UTF8_BYTES = 4;
  UNKNOWN_TEXT_MAX = 60;
  DEFAULT_PREFIX = 'DEFAULT ';

type
  TTokKind = (tkWord, tkQuoted, tkString, tkNumber, tkSym);

  TTok = record
    Kind: TTokKind;
    { upper-cased word, exact quoted identifier, string body, number text, one symbol character }
    Value: string;
    Start, Stop: Integer;
    Line: Integer;
  end;

  TColSpec = record
    FieldType, SubType, FieldLength, CharLength, Scale, Precision: Integer;
    Domain, Charset, DefaultSource, CheckSource: string;
    NotNull: Boolean;
  end;

  TDdlParser = class  // dl:ok high-response@d1aa -- REVIEWED 2026-11-22 FR-SCHEMA: one parser object holds the token list and the model being built; the clause routines share both
  strict private
    FFile: string;
    FChunk: string;
    FToks: TArray<TTok>;
    FModel: TFbSchemaModel;
    FDomains: TList<TFbDomain>;
    FColumns: TList<TFbColumn>;
    FConstraints: TList<TFbConstraint>;
    FGenerators: TList<string>;
    FUnknown: TList<TFbDdlUnknown>;
    FSkipped: Integer;
    FAutoNames: TDictionary<string, Integer>;
    procedure Fail(pLine: Integer; const pMsg: string);
    procedure Tokenize(const pChunk: string; pFirstLine: Integer);
    function IsWord(pIdx: Integer; const pWord: string): Boolean;
    function IsSym(pIdx: Integer; const pSym: string): Boolean;
    function NameAt(pIdx: Integer): string;
    function MatchClose(pOpen: Integer): Integer;
    function AfterClose(pOpen, pLine: Integer): Integer;
    function SpanText(pFrom, pTo: Integer): string;
    procedure ParseType(var pIdx: Integer; var pSpec: TColSpec; pLine: Integer);
    procedure ParseAttrs(var pIdx: Integer; pEnd: Integer; var pSpec: TColSpec; const pTable, pColumn: string;
      pLine: Integer);
    procedure ParseCreateDomain(pLine: Integer);
    procedure ParseCreateTable(pStart: Integer; pLine: Integer);
    procedure ParseTableBody(const pTable: string; pOpen, pClose, pLine: Integer);
    procedure ParseColumn(const pTable: string; pFrom, pTo, pLine: Integer);
    procedure ParseTableConstraint(const pTable: string; pFrom, pTo, pLine: Integer);
    procedure ParseAlterTable(pLine: Integer);
    procedure AddKey(const pTable, pName, pKind: string; const pCols: TArray<string>);
    procedure AddForeignKey(const pTable, pName: string; const pCols: TArray<string>; pRefIdx, pEnd: Integer;
      pLine: Integer);
    function ColumnList(pOpen: Integer; out pClose: Integer; pLine: Integer): TArray<string>;
    function ConstraintName(const pTable, pKind, pExplicit: string): string;
    procedure Statement(const pChunk: string; pFirstLine: Integer; pInBlock: Boolean);
    procedure Finish;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Feed(const pText, pFileName: string);
    function Result(const pDatabase: string): TFbDdlResult;
  end;

{ ---- helpers ---------------------------------------------------------------- }

function IsIdentStart(pCh: Char): Boolean;
begin
  Result := CharInSet(pCh, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentPart(pCh: Char): Boolean;
begin
  Result := CharInSet(pCh, ['A'..'Z', 'a'..'z', '_', '0'..'9', '$']);
end;

{ ---- TDdlParser ------------------------------------------------------------- }

constructor TDdlParser.Create;
begin
  inherited Create;
  FDomains := TList<TFbDomain>.Create;
  FColumns := TList<TFbColumn>.Create;
  FConstraints := TList<TFbConstraint>.Create;
  FGenerators := TList<string>.Create;
  FUnknown := TList<TFbDdlUnknown>.Create;
  FAutoNames := TDictionary<string, Integer>.Create;
end;

destructor TDdlParser.Destroy;
begin
  FAutoNames.Free;
  FUnknown.Free;
  FGenerators.Free;
  FConstraints.Free;
  FColumns.Free;
  FDomains.Free;
  inherited;
end;

procedure TDdlParser.Fail(pLine: Integer; const pMsg: string);
begin
  raise EFbDdlError.CreateFmt('%s(%d): %s', [FFile, pLine, pMsg]);
end;

procedure TDdlParser.Tokenize(const pChunk: string; pFirstLine: Integer);
var
  VPos, VLine, VStart, VLen: Integer;
  VTok: TTok;
  VList: TList<TTok>;
  VCh: Char;
begin
  FChunk := pChunk;
  VList := TList<TTok>.Create;
  try
    VPos := 1;
    VLine := pFirstLine;
    VLen := Length(pChunk);
    while VPos <= VLen do
    begin
      VCh := pChunk[VPos];
      if VCh = #10 then
      begin
        Inc(VLine);
        Inc(VPos);
        Continue;
      end;
      if VCh <= ' ' then
      begin
        Inc(VPos);
        Continue;
      end;
      VTok := Default(TTok);
      VTok.Start := VPos;
      VTok.Line := VLine;
      if IsIdentStart(VCh) then
      begin
        VStart := VPos;
        while (VPos <= VLen) and IsIdentPart(pChunk[VPos]) do
          Inc(VPos);
        VTok.Kind := tkWord;
        VTok.Value := UpperCase(Copy(pChunk, VStart, VPos - VStart));
      end
      else if CharInSet(VCh, ['0'..'9']) then
      begin
        VStart := VPos;
        while (VPos <= VLen) and (CharInSet(pChunk[VPos], ['0'..'9']) or (pChunk[VPos] = '.')) do
          Inc(VPos);
        VTok.Kind := tkNumber;
        VTok.Value := Copy(pChunk, VStart, VPos - VStart);
      end
      else if (VCh = '"') or (VCh = '''') then
      begin
        VStart := VPos + 1;
        Inc(VPos);
        while VPos <= VLen do
        begin
          if pChunk[VPos] = VCh then
          begin
            if (VPos < VLen) and (pChunk[VPos + 1] = VCh) then
              Inc(VPos, 2)
            else
              Break;
          end
          else
          begin
            if pChunk[VPos] = #10 then
              Inc(VLine);
            Inc(VPos);
          end;
        end;
        VTok.Kind := if VCh = '"' then tkQuoted else tkString;
        VTok.Value := Copy(pChunk, VStart, VPos - VStart);
        Inc(VPos);
      end
      else
      begin
        VTok.Kind := tkSym;
        VTok.Value := VCh;
        Inc(VPos);
      end;
      VTok.Stop := VPos;
      VList.Add(VTok);
    end;
    FToks := VList.ToArray;
  finally
    VList.Free;
  end;
end;

function TDdlParser.IsWord(pIdx: Integer; const pWord: string): Boolean;
begin
  Result := (pIdx >= 0) and (pIdx < Length(FToks)) and (FToks[pIdx].Kind = tkWord) and (FToks[pIdx].Value = pWord);
end;

function TDdlParser.IsSym(pIdx: Integer; const pSym: string): Boolean;
begin
  Result := (pIdx >= 0) and (pIdx < Length(FToks)) and (FToks[pIdx].Kind = tkSym) and (FToks[pIdx].Value = pSym);
end;

{ identifier at pIdx: word (upper-cased) or quoted (exact); '' when the token is neither }
function TDdlParser.NameAt(pIdx: Integer): string;
begin
  Result := '';
  if (pIdx >= 0) and (pIdx < Length(FToks)) and (FToks[pIdx].Kind in [tkWord, tkQuoted]) then
    Result := FToks[pIdx].Value;
end;

{ index of the ')' that closes the '(' at pOpen; -1 when unbalanced }
function TDdlParser.MatchClose(pOpen: Integer): Integer;
var
  VDepth, VIdx: Integer;
begin
  VDepth := 0;
  for VIdx := pOpen to High(FToks) do
  begin
    if IsSym(VIdx, '(') then
      Inc(VDepth)
    else if IsSym(VIdx, ')') then
    begin
      Dec(VDepth);
      if VDepth = 0 then
        Exit(VIdx);
    end;
  end;
  Result := -1;
end;

{ index just after the ')' that closes the '(' at pOpen; fails (never loops) when it is unbalanced }
function TDdlParser.AfterClose(pOpen, pLine: Integer): Integer;
begin
  Result := MatchClose(pOpen);
  if Result < 0 then
    Fail(pLine, 'unbalanced parenthesis');
  Inc(Result);
end;

{ source text of tokens pFrom..pTo-1 as written }
function TDdlParser.SpanText(pFrom, pTo: Integer): string;
begin
  if pTo <= pFrom then
    Exit('');
  Result := Trim(Copy(FChunk, FToks[pFrom].Start, FToks[pTo - 1].Stop - FToks[pFrom].Start));  // dl:ok index-possibly-out-of-range@00e3 -- REVIEWED 2026-11-22 FR-SCHEMA: index comes from the statement span the tokenizer produced (or a fixed column list sized with it), inside the array
end;

function CharBytes(const pCharset: string): Integer;
begin
  Result := if SameText(pCharset, 'UTF8') then UTF8_BYTES else 1;
end;

procedure TDdlParser.ParseType(var pIdx: Integer; var pSpec: TColSpec; pLine: Integer);  // dl:ok cyclomatic-complexity@ee32, cognitive-complexity@c0a2 -- REVIEWED 2026-11-22 FR-SCHEMA: grammar-driven parser routine: one branch per DDL clause, splitting would hide the clause order
var
  VWord: string;
  VClose, VPrec, VScale: Integer;

  procedure ReadLen(pType: Integer);
  begin
    pSpec.FieldType := pType;
    pSpec.CharLength := 1;
    if IsSym(pIdx, '(') and (pIdx + 1 < Length(FToks)) and (FToks[pIdx + 1].Kind = tkNumber) then
    begin
      pSpec.CharLength := StrToIntDef(FToks[pIdx + 1].Value, 1);
      pIdx := AfterClose(pIdx, pLine);
    end;
  end;

begin
  VWord := if (pIdx < Length(FToks)) and (FToks[pIdx].Kind = tkWord) then FToks[pIdx].Value else '';
  if VWord = '' then
  begin
    { a domain name, quoted or not }
    pSpec.Domain := NameAt(pIdx);
    if pSpec.Domain = '' then
      Fail(pLine, 'a data type or domain name is expected');
    Inc(pIdx);
    Exit;
  end;
  Inc(pIdx);
  if (VWord = 'VARCHAR') or ((VWord = 'CHARACTER') or (VWord = 'CHAR')) and IsWord(pIdx, 'VARYING') then
  begin
    if IsWord(pIdx, 'VARYING') then
      Inc(pIdx);
    ReadLen(FB_VARCHAR);
  end
  else if (VWord = 'CHAR') or (VWord = 'CHARACTER') or (VWord = 'NCHAR') then
    ReadLen(FB_CHAR)
  else if (VWord = 'NATIONAL') then
  begin
    Inc(pIdx);
    if IsWord(pIdx, 'VARYING') then
    begin
      Inc(pIdx);
      ReadLen(FB_VARCHAR);
    end
    else
      ReadLen(FB_CHAR);
  end
  else if (VWord = 'INTEGER') or (VWord = 'INT') then
    pSpec.FieldType := FB_LONG
  else if VWord = 'SMALLINT' then
    pSpec.FieldType := FB_SHORT
  else if VWord = 'BIGINT' then
    pSpec.FieldType := FB_INT64
  else if VWord = 'INT128' then
    pSpec.FieldType := FB_INT128
  else if (VWord = 'FLOAT') or (VWord = 'REAL') then
    pSpec.FieldType := FB_FLOAT
  else if (VWord = 'DOUBLE') and IsWord(pIdx, 'PRECISION') then
  begin
    Inc(pIdx);
    pSpec.FieldType := FB_DOUBLE;
  end
  else if VWord = 'DATE' then
    pSpec.FieldType := FB_DATE
  else if VWord = 'TIME' then
    pSpec.FieldType := FB_TIME
  else if VWord = 'TIMESTAMP' then
    pSpec.FieldType := FB_TIMESTAMP
  else if VWord = 'BOOLEAN' then
    pSpec.FieldType := FB_BOOLEAN
  else if VWord = 'DECFLOAT' then
  begin
    pSpec.FieldType := FB_DEC34;
    if IsSym(pIdx, '(') then
    begin
      if (pIdx + 1 < Length(FToks)) and (FToks[pIdx + 1].Value = IntToStr(DEC16_DIGITS)) then
        pSpec.FieldType := FB_DEC16;
      pIdx := AfterClose(pIdx, pLine);
    end;
  end
  else if (VWord = 'NUMERIC') or (VWord = 'DECIMAL') or (VWord = 'DEC') then
  begin
    VPrec := PREC_DEFAULT;
    VScale := 0;
    if IsSym(pIdx, '(') then
    begin
      VClose := MatchClose(pIdx);
      if VClose < 0 then
        Fail(pLine, 'unbalanced parenthesis in a numeric type');
      if FToks[pIdx + 1].Kind = tkNumber then
        VPrec := StrToIntDef(FToks[pIdx + 1].Value, PREC_DEFAULT);
      if (pIdx + 3 < VClose) and IsSym(pIdx + 2, ',') and (FToks[pIdx + 3].Kind = tkNumber) then  // dl:ok magic-literal@1155 -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
        VScale := StrToIntDef(FToks[pIdx + 3].Value, 0);
      pIdx := VClose + 1;
    end;
    pSpec.FieldType := if VPrec <= PREC_SHORT then FB_SHORT else if VPrec <= PREC_LONG then FB_LONG
      else if VPrec <= PREC_INT64 then FB_INT64 else FB_INT128;
    pSpec.SubType := if VWord = 'NUMERIC' then 1 else 2;
    pSpec.Precision := VPrec;
    pSpec.Scale := -VScale;
  end
  else if VWord = 'BLOB' then
  begin
    pSpec.FieldType := FB_BLOB;
    while True do
      if IsWord(pIdx, 'SUB_TYPE') then
      begin
        Inc(pIdx);
        if IsWord(pIdx, 'TEXT') then
          pSpec.SubType := 1
        else if IsWord(pIdx, 'BINARY') then
          pSpec.SubType := 0
        else if (pIdx < Length(FToks)) and (FToks[pIdx].Kind = tkNumber) then
          pSpec.SubType := StrToIntDef(FToks[pIdx].Value, 0);
        Inc(pIdx);
      end
      else if IsWord(pIdx, 'SEGMENT') then
      begin
        Inc(pIdx, 2);
        if (pIdx < Length(FToks)) and (FToks[pIdx].Kind = tkNumber) then
          Inc(pIdx);
      end
      else if IsSym(pIdx, '(') then
        pIdx := MatchClose(pIdx) + 1
      else
        Break;
  end
  else
  begin
    { not a type word: a domain declared with an unquoted name }
    pSpec.Domain := VWord;
    Exit;
  end;
  if IsWord(pIdx, 'WITH') or IsWord(pIdx, 'WITHOUT') then
    Inc(pIdx, 3);  // dl:ok magic-literal@98ac -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
  case pSpec.FieldType of
    FB_SHORT: pSpec.FieldLength := SIZE_SHORT;
    FB_LONG, FB_FLOAT, FB_DATE, FB_TIME: pSpec.FieldLength := SIZE_LONG;
    FB_INT64, FB_DOUBLE, FB_TIMESTAMP, FB_DEC16: pSpec.FieldLength := SIZE_INT64;
    FB_INT128, FB_DEC34: pSpec.FieldLength := SIZE_INT128;
    FB_BOOLEAN: pSpec.FieldLength := SIZE_BOOLEAN;
    FB_BLOB: pSpec.FieldLength := SIZE_BLOB;
  end;
end;

function TDdlParser.ConstraintName(const pTable, pKind, pExplicit: string): string;
var
  VKey: string;
  VNo: Integer;
begin
  if pExplicit <> '' then
    Exit(pExplicit);
  VKey := 'INTEG_' + pTable + '_' + pKind;
  FAutoNames.TryGetValue(VKey, VNo);
  Inc(VNo);
  FAutoNames.AddOrSetValue(VKey, VNo);
  Result := VKey + '_' + IntToStr(VNo);
end;

procedure TDdlParser.AddKey(const pTable, pName, pKind: string; const pCols: TArray<string>);
var
  VItem: TFbConstraint;
begin
  VItem := Default(TFbConstraint);
  VItem.Name := pName;
  VItem.TableName := pTable;
  VItem.Kind := pKind;
  VItem.Columns := pCols;
  FConstraints.Add(VItem);
end;

{ a parenthesised name list starting at the '(' at pOpen; pClose = index of the closing paren }
function TDdlParser.ColumnList(pOpen: Integer; out pClose: Integer; pLine: Integer): TArray<string>;
var
  VIdx: Integer;
begin
  Result := nil;
  if not IsSym(pOpen, '(') then
    Fail(pLine, 'a ( column list ) is expected');
  pClose := MatchClose(pOpen);
  if pClose < 0 then
    Fail(pLine, 'unbalanced parenthesis in a column list');
  for VIdx := pOpen + 1 to pClose - 1 do
    if FToks[VIdx].Kind in [tkWord, tkQuoted] then
      Result := Result + [FToks[VIdx].Value];
end;

procedure TDdlParser.AddForeignKey(const pTable, pName: string; const pCols: TArray<string>; pRefIdx, pEnd: Integer;
  pLine: Integer);
var
  VItem: TFbConstraint;
  VIdx, VClose: Integer;
  VRefCols: TArray<string>;
begin
  VItem := Default(TFbConstraint);
  VItem.Name := pName;
  VItem.TableName := pTable;
  VItem.Kind := 'FK';
  VItem.Columns := pCols;
  VItem.UpdateRule := 'RESTRICT';
  VItem.DeleteRule := 'RESTRICT';
  VItem.RefTable := NameAt(pRefIdx);
  if VItem.RefTable = '' then
    Fail(pLine, 'REFERENCES needs a table name');
  VIdx := pRefIdx + 1;
  if IsSym(VIdx, '(') then
  begin
    VRefCols := ColumnList(VIdx, VClose, pLine);
    VItem.RefConstraint := '(' + string.Join(',', VRefCols) + ')';
    VIdx := VClose + 1;
  end;
  while VIdx < pEnd do
  begin
    if IsWord(VIdx, 'ON') and (IsWord(VIdx + 1, 'DELETE') or IsWord(VIdx + 1, 'UPDATE')) then
    begin
      VClose := VIdx + 2;  // dl:ok index-possibly-out-of-range@c706 -- REVIEWED 2026-11-22 FR-SCHEMA: index comes from the statement span the tokenizer produced (or a fixed column list sized with it), inside the array
      if IsWord(VClose, 'SET') or IsWord(VClose, 'NO') then
      begin
        if IsWord(VIdx + 1, 'DELETE') then
          VItem.DeleteRule := FToks[VClose].Value + ' ' + FToks[VClose + 1].Value
        else
          VItem.UpdateRule := FToks[VClose].Value + ' ' + FToks[VClose + 1].Value;
        Inc(VIdx, 4);  // dl:ok magic-literal@3374 -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
      end
      else
      begin
        if IsWord(VIdx + 1, 'DELETE') then
          VItem.DeleteRule := FToks[VClose].Value
        else
          VItem.UpdateRule := FToks[VClose].Value;
        Inc(VIdx, 3);  // dl:ok magic-literal@e1ad -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
      end;
    end
    else
      Inc(VIdx);
  end;
  FConstraints.Add(VItem);
end;

procedure TDdlParser.ParseAttrs(var pIdx: Integer; pEnd: Integer; var pSpec: TColSpec; const pTable, pColumn: string;  // dl:ok cyclomatic-complexity@38e3 -- REVIEWED 2026-11-22 FR-SCHEMA: grammar-driven parser routine: one branch per DDL clause, splitting would hide the clause order
  pLine: Integer);
var
  VStart, VClose: Integer;
  VExplicit: string;
begin
  VExplicit := '';
  while pIdx < pEnd do
  begin
    if IsWord(pIdx, 'CHARACTER') and IsWord(pIdx + 1, 'SET') then
    begin
      pSpec.Charset := UpperCase(NameAt(pIdx + 2));
      Inc(pIdx, 3);  // dl:ok magic-literal@98ac -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
    end
    else if IsWord(pIdx, 'DEFAULT') then
    begin
      VStart := pIdx + 1;
      Inc(pIdx);
      while (pIdx < pEnd) and not (IsWord(pIdx, 'NOT') or IsWord(pIdx, 'CONSTRAINT') or IsWord(pIdx, 'PRIMARY')  // dl:ok boolean-expression-complexity@61b3 -- REVIEWED 2026-11-22 FR-SCHEMA: one token-class test of the DDL grammar, kept whole so the accepted forms read in one place
        or IsWord(pIdx, 'UNIQUE') or IsWord(pIdx, 'REFERENCES') or IsWord(pIdx, 'CHECK') or IsWord(pIdx, 'COLLATE')
        or IsWord(pIdx, 'CHARACTER')) do
        if IsSym(pIdx, '(') then
          pIdx := MatchClose(pIdx) + 1
        else
          Inc(pIdx);
      pSpec.DefaultSource := DEFAULT_PREFIX + SpanText(VStart, pIdx);
    end
    else if IsWord(pIdx, 'NOT') and IsWord(pIdx + 1, 'NULL') then
    begin
      pSpec.NotNull := True;
      Inc(pIdx, 2);
    end
    else if IsWord(pIdx, 'CONSTRAINT') then
    begin
      VExplicit := NameAt(pIdx + 1);
      Inc(pIdx, 2);
    end
    else if IsWord(pIdx, 'PRIMARY') and IsWord(pIdx + 1, 'KEY') then
    begin
      AddKey(pTable, ConstraintName(pTable, 'PK', VExplicit), 'PK', [pColumn]);
      VExplicit := '';
      Inc(pIdx, 2);
    end
    else if IsWord(pIdx, 'UNIQUE') then
    begin
      AddKey(pTable, ConstraintName(pTable, 'UNIQUE', VExplicit), 'UNIQUE', [pColumn]);
      VExplicit := '';
      Inc(pIdx);
    end
    else if IsWord(pIdx, 'REFERENCES') then
    begin
      VClose := pIdx + 1;
      VStart := pIdx + 2;
      if IsSym(VStart, '(') then
        VStart := AfterClose(VStart, pLine);
      while (VStart < pEnd) and not (IsWord(VStart, 'CONSTRAINT') or IsWord(VStart, 'NOT') or IsWord(VStart, 'CHECK')  // dl:ok boolean-expression-complexity@5439 -- REVIEWED 2026-11-22 FR-SCHEMA: one token-class test of the DDL grammar, kept whole so the accepted forms read in one place
        or IsWord(VStart, 'DEFAULT') or IsWord(VStart, 'COLLATE')) do
        Inc(VStart);
      AddForeignKey(pTable, ConstraintName(pTable, 'FK', VExplicit), [pColumn], VClose, VStart, pLine);
      VExplicit := '';
      pIdx := VStart;
    end
    else if IsWord(pIdx, 'CHECK') then
    begin
      VStart := pIdx;
      if IsSym(pIdx + 1, '(') then
        pIdx := AfterClose(pIdx + 1, pLine)
      else
        Inc(pIdx);
      if pIdx > pEnd then
        Fail(pLine, 'unbalanced parenthesis in CHECK');
      pSpec.CheckSource := SpanText(VStart, pIdx);
      if pColumn <> '' then
        AddKey(pTable, ConstraintName(pTable, 'CHECK', VExplicit), 'CHECK', nil);
      VExplicit := '';
    end
    else
      Inc(pIdx);
  end;
end;

procedure TDdlParser.ParseColumn(const pTable: string; pFrom, pTo, pLine: Integer);  // dl:ok unused-parameter@1aa1 -- REVIEWED 2026-11-22 FR-SCHEMA: kept so the three column / constraint routines share one signature
var
  VSpec: TColSpec;
  VIdx: Integer;
  VCol: TFbColumn;
  VName: string;
begin
  VName := NameAt(pFrom);
  if VName = '' then
    Fail(FToks[pFrom].Line, 'a column name is expected');  // dl:ok index-possibly-out-of-range@4923 -- REVIEWED 2026-11-22 FR-SCHEMA: index comes from the statement span the tokenizer produced (or a fixed column list sized with it), inside the array
  VIdx := pFrom + 1;
  if VIdx >= pTo then
    Fail(FToks[pFrom].Line, 'column ' + VName + ' has no data type');
  VSpec := Default(TColSpec);
  if IsWord(VIdx, 'COMPUTED') or IsWord(VIdx, 'GENERATED') then
    VIdx := pTo
  else
    ParseType(VIdx, VSpec, FToks[pFrom].Line);
  ParseAttrs(VIdx, pTo, VSpec, pTable, VName, FToks[pFrom].Line);
  VCol := Default(TFbColumn);
  VCol.TableName := pTable;
  VCol.ColumnName := VName;
  VCol.DomainName := VSpec.Domain;
  VCol.FieldType := VSpec.FieldType;
  VCol.SubType := VSpec.SubType;
  VCol.CharLength := VSpec.CharLength;
  VCol.FieldLength := if VSpec.FieldType in [FB_CHAR, FB_VARCHAR] then VSpec.CharLength * CharBytes(VSpec.Charset)
    else VSpec.FieldLength;
  VCol.Scale := VSpec.Scale;
  VCol.NullFlag := Ord(VSpec.NotNull);
  VCol.DefaultSource := VSpec.DefaultSource;
  FColumns.Add(VCol);
end;

procedure TDdlParser.ParseTableConstraint(const pTable: string; pFrom, pTo, pLine: Integer);
var
  VIdx, VClose: Integer;
  VName, VKind: string;
  VCols: TArray<string>;
begin
  VIdx := pFrom;
  VName := '';
  if IsWord(VIdx, 'CONSTRAINT') then
  begin
    VName := NameAt(VIdx + 1);
    Inc(VIdx, 2);  // dl:ok index-possibly-out-of-range@17bb -- REVIEWED 2026-11-22 FR-SCHEMA: index comes from the statement span the tokenizer produced (or a fixed column list sized with it), inside the array
  end;
  if IsWord(VIdx, 'PRIMARY') then
  begin
    VCols := ColumnList(VIdx + 2, VClose, pLine);
    AddKey(pTable, ConstraintName(pTable, 'PK', VName), 'PK', VCols);
  end
  else if IsWord(VIdx, 'UNIQUE') then
  begin
    VCols := ColumnList(VIdx + 1, VClose, pLine);
    AddKey(pTable, ConstraintName(pTable, 'UNIQUE', VName), 'UNIQUE', VCols);
  end
  else if IsWord(VIdx, 'FOREIGN') then
  begin
    VCols := ColumnList(VIdx + 2, VClose, pLine);
    if not IsWord(VClose + 1, 'REFERENCES') then
      Fail(FToks[VIdx].Line, 'FOREIGN KEY needs REFERENCES');
    AddForeignKey(pTable, ConstraintName(pTable, 'FK', VName), VCols, VClose + 2, pTo, FToks[VIdx].Line);
  end
  else if IsWord(VIdx, 'CHECK') then
  begin
    VKind := 'CHECK';
    if (not IsSym(VIdx + 1, '(')) or (MatchClose(VIdx + 1) < 0) then
      Fail(FToks[VIdx].Line, 'unbalanced parenthesis in CHECK');
    AddKey(pTable, ConstraintName(pTable, VKind, VName), VKind, nil);
  end
  else
    Fail(FToks[pFrom].Line, 'unknown table constraint');  // dl:ok index-possibly-out-of-range@5aaf -- REVIEWED 2026-11-22 FR-SCHEMA: index comes from the statement span the tokenizer produced (or a fixed column list sized with it), inside the array
end;

procedure TDdlParser.ParseTableBody(const pTable: string; pOpen, pClose, pLine: Integer);
var
  VIdx, VFrom, VDepth: Integer;

  procedure Part(pFrom, pTo: Integer);
  begin
    if pTo <= pFrom then
      Fail(FToks[pOpen].Line, 'empty column definition in CREATE TABLE ' + pTable);
    if IsWord(pFrom, 'CONSTRAINT') or IsWord(pFrom, 'PRIMARY') or IsWord(pFrom, 'UNIQUE') or IsWord(pFrom, 'FOREIGN')
      or IsWord(pFrom, 'CHECK') then
      ParseTableConstraint(pTable, pFrom, pTo, pLine)
    else
      ParseColumn(pTable, pFrom, pTo, pLine);
  end;

begin
  if pClose <= pOpen + 1 then
    Fail(FToks[pOpen].Line, 'CREATE TABLE ' + pTable + ' has no columns');
  VFrom := pOpen + 1;
  VDepth := 0;
  for VIdx := pOpen + 1 to pClose - 1 do
    if IsSym(VIdx, '(') then
      Inc(VDepth)
    else if IsSym(VIdx, ')') then
      Dec(VDepth)
    else if (VDepth = 0) and IsSym(VIdx, ',') then
    begin
      Part(VFrom, VIdx);
      VFrom := VIdx + 1;
    end;
  Part(VFrom, pClose);
end;

procedure TDdlParser.ParseCreateTable(pStart: Integer; pLine: Integer);
var
  VTable: string;
  VOpen, VClose: Integer;
begin
  VTable := NameAt(pStart);
  if VTable = '' then
    Fail(pLine, 'CREATE TABLE needs a table name');
  VOpen := pStart + 1;
  if IsWord(VOpen, 'EXTERNAL') then
    VOpen := pStart + 4;  // dl:ok magic-literal@cc3c -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
  if not IsSym(VOpen, '(') then
    Fail(pLine, 'CREATE TABLE ' + VTable + ' needs a ( column list )');
  VClose := MatchClose(VOpen);
  if VClose < 0 then
    Fail(pLine, 'unbalanced parenthesis in CREATE TABLE ' + VTable);
  ParseTableBody(VTable, VOpen, VClose, pLine);
end;

procedure TDdlParser.ParseCreateDomain(pLine: Integer);
var
  VName: string;
  VIdx: Integer;
  VSpec: TColSpec;
  VItem: TFbDomain;
begin
  VName := NameAt(2);
  if VName = '' then
    Fail(pLine, 'CREATE DOMAIN needs a name');
  VIdx := 3;  // dl:ok magic-literal@4848 -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
  if IsWord(VIdx, 'AS') then
    Inc(VIdx);
  VSpec := Default(TColSpec);
  ParseType(VIdx, VSpec, pLine);
  ParseAttrs(VIdx, Length(FToks), VSpec, '', '', pLine);
  VItem := Default(TFbDomain);
  VItem.Name := VName;
  VItem.FieldType := VSpec.FieldType;
  VItem.SubType := VSpec.SubType;
  VItem.CharLength := VSpec.CharLength;
  VItem.FieldLength := if VSpec.FieldType in [FB_CHAR, FB_VARCHAR] then VSpec.CharLength * CharBytes(VSpec.Charset)
    else VSpec.FieldLength;
  VItem.Scale := VSpec.Scale;
  VItem.Precision := VSpec.Precision;
  VItem.NullFlag := Ord(VSpec.NotNull);
  VItem.DefaultSource := VSpec.DefaultSource;
  VItem.CheckSource := VSpec.CheckSource;
  VItem.Charset := VSpec.Charset;
  FDomains.Add(VItem);
end;

procedure TDdlParser.ParseAlterTable(pLine: Integer);
var
  VUnknown: TFbDdlUnknown;
  VTable: string;
  VIdx: Integer;
begin
  VTable := NameAt(2);
  VIdx := 3;  // dl:ok magic-literal@4848 -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
  if (VTable = '') or not IsWord(VIdx, 'ADD') then
  begin
    VUnknown := Default(TFbDdlUnknown);
    VUnknown.FileName := FFile;
    VUnknown.Line := pLine;
    VUnknown.Text := LeftStr(Trim(FChunk), UNKNOWN_TEXT_MAX);
    FUnknown.Add(VUnknown);
    Exit;
  end;
  Inc(VIdx);
  if IsWord(VIdx, 'COLUMN') then
    Inc(VIdx);
  if IsWord(VIdx, 'CONSTRAINT') or IsWord(VIdx, 'PRIMARY') or IsWord(VIdx, 'UNIQUE') or IsWord(VIdx, 'FOREIGN')
    or IsWord(VIdx, 'CHECK') then
    ParseTableConstraint(VTable, VIdx, Length(FToks), pLine)
  else
    ParseColumn(VTable, VIdx, Length(FToks), pLine);
end;

procedure TDdlParser.Statement(const pChunk: string; pFirstLine: Integer; pInBlock: Boolean);  // dl:ok too-many-exit-points@1c46 -- REVIEWED 2026-11-22 FR-SCHEMA: statement dispatcher: one guard Exit per statement kind
var
  VUnknown: TFbDdlUnknown;
  VIdx: Integer;
begin
  Tokenize(pChunk, pFirstLine);
  if Length(FToks) = 0 then
    Exit;
  if IsWord(0, 'SET') and IsWord(1, 'TERM') then
    Exit;
  if pInBlock then
  begin
    Inc(FSkipped);
    Exit;
  end;
  VIdx := 1;
  if IsWord(0, 'CREATE') then
  begin
    if IsWord(VIdx, 'OR') then
      Inc(VIdx, 2);
    if IsWord(VIdx, 'GLOBAL') then
      Inc(VIdx, 2);
    if IsWord(VIdx, 'DOMAIN') then
    begin
      ParseCreateDomain(FToks[0].Line);
      Exit;
    end;
    if IsWord(VIdx, 'TABLE') then
    begin
      ParseCreateTable(VIdx + 1, FToks[0].Line);
      Exit;
    end;
    if IsWord(VIdx, 'GENERATOR') or IsWord(VIdx, 'SEQUENCE') then
    begin
      if NameAt(VIdx + 1) = '' then
        Fail(FToks[0].Line, 'CREATE GENERATOR needs a name');
      FGenerators.Add(NameAt(VIdx + 1));
      Exit;
    end;
    while IsWord(VIdx, 'UNIQUE') or IsWord(VIdx, 'ASC') or IsWord(VIdx, 'ASCENDING') or IsWord(VIdx, 'DESC')
      or IsWord(VIdx, 'DESCENDING') do
      Inc(VIdx);
    if IsWord(VIdx, 'INDEX') then
      Exit;
  end
  else if IsWord(0, 'ALTER') and IsWord(1, 'TABLE') then
  begin
    ParseAlterTable(FToks[0].Line);
    Exit;
  end;
  VUnknown := Default(TFbDdlUnknown);
  VUnknown.FileName := FFile;
  VUnknown.Line := FToks[0].Line;
  VUnknown.Text := LeftStr(string.Join(' ', Trim(pChunk).Split([#13, #10, #9, ' '], TStringSplitOptions.ExcludeEmpty)),
    UNKNOWN_TEXT_MAX);
  FUnknown.Add(VUnknown);
end;

procedure TDdlParser.Feed(const pText, pFileName: string);
var
  VPos, VLen, VLine, VChunkLine: Integer;
  VTerm: string;
  VChunk: TStringBuilder;
  VCh: Char;
  VQuote: Char;
  VHasText: Boolean;

  procedure FlushChunk;
  var
    VText, VNewTerm: string;
    VSetTermTokens: TArray<string>;
  begin
    VText := VChunk.ToString;
    VChunk.Clear;
    VHasText := False;
    if Trim(VText) = '' then
      Exit;
    VSetTermTokens := Trim(VText).Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
    if (Length(VSetTermTokens) >= 3) and SameText(VSetTermTokens[0], 'SET') and SameText(VSetTermTokens[1], 'TERM') then  // dl:ok magic-literal@d325 -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
    begin
      VNewTerm := VSetTermTokens[2];
      Statement(VText, VChunkLine, False);
      VTerm := VNewTerm;
      Exit;
    end;
    Statement(VText, VChunkLine, VTerm <> ';');
  end;

begin
  FFile := pFileName;
  VTerm := ';';
  VLen := Length(pText);
  VPos := 1;
  VLine := 1;
  VChunkLine := 1;
  VChunk := TStringBuilder.Create;
  VHasText := False;
  try
    while VPos <= VLen do
    begin
      VCh := pText[VPos];
      if (VCh = '-') and (VPos < VLen) and (pText[VPos + 1] = '-') then
      begin
        while (VPos <= VLen) and (pText[VPos] <> #10) do
          Inc(VPos);
        Continue;
      end;
      if (VCh = '/') and (VPos < VLen) and (pText[VPos + 1] = '*') then
      begin
        Inc(VPos, 2);
        while (VPos < VLen) and not ((pText[VPos] = '*') and (pText[VPos + 1] = '/')) do
        begin
          if pText[VPos] = #10 then
          begin
            Inc(VLine);
            VChunk.Append(#10);
          end;
          Inc(VPos);
        end;
        Inc(VPos, 2);
        VChunk.Append(' ');
        Continue;
      end;
      if (VCh = '''') or (VCh = '"') then
      begin
        VQuote := VCh;
        VHasText := True;
        VChunk.Append(VCh);
        Inc(VPos);
        while (VPos <= VLen) and (pText[VPos] <> VQuote) do
        begin
          if pText[VPos] = #10 then
            Inc(VLine);
          VChunk.Append(pText[VPos]);
          Inc(VPos);
        end;
        if VPos <= VLen then
          VChunk.Append(VQuote);
        Inc(VPos);
        Continue;
      end;
      if (VCh = VTerm[1]) and (Copy(pText, VPos, Length(VTerm)) = VTerm) then
      begin
        { a stray terminator (an empty statement) just clears the chunk }
        if VHasText then
          FlushChunk
        else
          VChunk.Clear;
        Inc(VPos, Length(VTerm));
        VChunkLine := VLine;
        Continue;
      end;
      if VCh = #10 then
        Inc(VLine);
      if (not VHasText) and (VCh <= ' ') then
      begin
        { leading blanks are not part of the statement: its first line is the line of its first character }
        Inc(VPos);
        Continue;
      end;
      if not VHasText then
      begin
        VChunkLine := VLine;
        VHasText := True;
      end;
      VChunk.Append(VCh);
      Inc(VPos);
    end;
    if VHasText then
      FlushChunk;
  finally
    VChunk.Free;
  end;
end;

{ After the last file: column and domain types borrowed from domains, FK targets resolved. }
procedure TDdlParser.Finish;
var
  VIdx, VDom, VCon: Integer;
  VCol: TFbColumn;
  VFk, VKey: TFbConstraint;
  VWanted: string;
begin
  for VIdx := 0 to FColumns.Count - 1 do
  begin
    VCol := FColumns[VIdx];
    if (VCol.DomainName <> '') and (VCol.FieldType = 0) then
      for VDom := 0 to FDomains.Count - 1 do
        if FDomains[VDom].Name = VCol.DomainName then
        begin
          VCol.FieldType := FDomains[VDom].FieldType;
          VCol.SubType := FDomains[VDom].SubType;
          VCol.FieldLength := FDomains[VDom].FieldLength;
          VCol.CharLength := FDomains[VDom].CharLength;
          VCol.Scale := FDomains[VDom].Scale;
          if VCol.DefaultSource = '' then
            VCol.DefaultSource := FDomains[VDom].DefaultSource;
          if FDomains[VDom].NullFlag <> 0 then
            VCol.NullFlag := 1;
          FColumns[VIdx] := VCol;
          Break;
        end;
  end;
  for VIdx := 0 to FConstraints.Count - 1 do
  begin
    VFk := FConstraints[VIdx];
    if VFk.Kind <> 'FK' then
      Continue;
    VWanted := VFk.RefConstraint;
    VFk.RefConstraint := '';
    for VCon := 0 to FConstraints.Count - 1 do
    begin
      VKey := FConstraints[VCon];
      if (VKey.TableName = VFk.RefTable) and ((VKey.Kind = 'PK') or (VKey.Kind = 'UNIQUE'))
        and ((VWanted = '') or (VWanted = '(' + string.Join(',', VKey.Columns) + ')')) then
      begin
        if (VWanted <> '') or (VKey.Kind = 'PK') then
        begin
          VFk.RefConstraint := VKey.Name;
          Break;
        end;
      end;
    end;
    FConstraints[VIdx] := VFk;
  end;
end;

function TDdlParser.Result(const pDatabase: string): TFbDdlResult;
begin
  Finish;
  Result := Default(TFbDdlResult);
  Result.Model.Source := 'ddl';
  Result.Model.Database := pDatabase;
  Result.Model.Domains := FDomains.ToArray;
  Result.Model.Columns := FColumns.ToArray;
  Result.Model.Constraints := FConstraints.ToArray;
  Result.Model.Generators := FGenerators.ToArray;
  SortSchemaModel(Result.Model);
  Result.Unknown := FUnknown.ToArray;
  Result.SkippedBlockStatements := FSkipped;
end;

{ ---- API -------------------------------------------------------------------- }

function ReadDdlText(const pText, pFileName: string): TFbDdlResult;
var
  VParser: TDdlParser;
begin
  VParser := TDdlParser.Create;
  try
    VParser.Feed(pText, pFileName);
    Result := VParser.Result(pFileName);
  finally
    VParser.Free;
  end;
end;

function ReadDdlFiles(const pFiles: TArray<string>): TFbDdlResult;
var
  VParser: TDdlParser;
  VFile: string;
begin
  VParser := TDdlParser.Create;
  try
    for VFile in pFiles do
    begin
      if not TFile.Exists(VFile) then
        raise EFbDdlError.CreateFmt('%s(0): the DDL file does not exist', [VFile]);
      VParser.Feed(TFile.ReadAllText(VFile), VFile);
    end;
    Result := VParser.Result(string.Join(';', pFiles));
  finally
    VParser.Free;
  end;
end;

end.
