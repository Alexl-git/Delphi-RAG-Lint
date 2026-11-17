unit DRagLint.FieldRepo.ParamArray;

{ drag-lint 1.52 -- lane TTPA (TableTools migration step M9): the two FireDAC Param Array
  assistants (uFireDACParamArrayAssistant.pas, "Single" = one unit, "Project" = every
  eligible unit of a project) as engine code, with no IDE and no ToolsAPI.

  The TableTools assistant read the live designer (TTable fields, prepared TFDQuery params)
  and pasted the Array-DML loop into the open editor. Here the same loop is produced as a
  PLAN: a block of text plus a unified diff of its insertion. The plan is applied only
  through a compile gate callback (the caller compiles the candidate text; a refusal leaves
  the source untouched). Column discovery reads the unit's DFM text instead of the designer.

  Differences from the IDE assistant, on purpose:
  - the IDE-only preparation of the query (swap in the UpdateSQL insert text, rename the
    update object / schema adapter) is not done; the DFM is never rewritten;
  - whitespace is normalised (two-space indent, no trailing blanks, no tabs);
  - the loader-form lines (progress, NRECS, Commit) of the original are emitted only when
    TPAOptions.ProgressForm is set;
  - a DFM may hold many tables and queries: the LAST table and the LAST query that has
    parameters are used (the IDE version merged every table's fields).
  Everything else (type tables, name matching, mismatch / missing markers) is a port. }

interface

uses
  System.SysUtils;

type
  /// <summary>Field / parameter data types the assistant distinguishes (the names of
  /// Data.DB TFieldType, without a Data.DB dependency).</summary>
  TPAFieldType = (pftUnknown, pftString, pftWideString, pftFixedChar, pftFixedWideChar,
    pftMemo, pftWideMemo, pftFmtMemo, pftOraClob, pftOraInterval, pftLargeint, pftSmallint,
    pftInteger, pftWord, pftShortint, pftAutoInc, pftByte, pftBytes, pftVarBytes, pftBlob,
    pftGraphic, pftOraBlob, pftStream, pftSingle, pftFloat, pftExtended, pftCurrency,
    pftBCD, pftFMTBcd, pftBoolean, pftDate, pftTime, pftDateTime, pftTimeStamp,
    pftOraTimeStamp, pftTimeStampOffset, pftGUID, pftVariant);

  /// <summary>One source field (Name = component identifier used in the code, FieldName =
  /// the matching key) or one query parameter (Name only; FieldName is ignored).</summary>
  TPAColumn = record
    Name: string;
    FieldName: string;
    DataType: TPAFieldType;
  end;

  /// <summary>A list of columns.</summary>
  TPAColumns = TArray<TPAColumn>;

  /// <summary>Emission options.</summary>
  /// <remarks>StepSize is the array size per Execute; ProgressForm names the loader form
  /// whose NRECS / cxlDone / prbRecords / IBD the original block drove ('' = omit).</remarks>
  TPAOptions = record
    StepSize: Integer;
    ProgressForm: string;
  end;

  /// <summary>Compile gate: returns True when the candidate unit text compiles.</summary>
  TPAGate = reference to function(const pUnitText: string): Boolean;

  /// <summary>Outcome of applying a plan to one unit.</summary>
  TPAStatus = (pasApplied, pasRefusedByGate, pasNoInsertPoint, pasNoBlock, pasExcluded);

  /// <summary>One unit given to the project assistant.</summary>
  TPAUnitInput = record
    UnitName: string;
    Source: string;
    Dfm: string;
  end;

  /// <summary>Result for one unit of a project run.</summary>
  TPAUnitResult = record
    UnitName: string;
    Status: TPAStatus;
    Plan: string;
    NewSource: string;
    Error: string;
  end;

  /// <summary>Results of a project run, in input order.</summary>
  TPAUnitResults = TArray<TPAUnitResult>;

/// <summary>Default options: STEPSIZE 20000, no loader-form lines.</summary>
/// <returns>The default TPAOptions.</returns>
function PADefaultOptions: TPAOptions;

/// <summary>Data.DB style display name of a type ('Integer', 'TimeStamp', ...).</summary>
/// <param name="pType">The type.</param>
/// <returns>The display name.</returns>
function PATypeName(pType: TPAFieldType): string;

/// <summary>Collapses a type to its family (port of GeneralTypeOf): two types with the
/// same family are assignable without conversion.</summary>
/// <param name="pType">The type.</param>
/// <returns>The family representative.</returns>
function PAGeneralType(pType: TPAFieldType): TPAFieldType;

/// <summary>Source-field accessor property (port of BDEFieldAccessor), e.g. 'AsInteger'.</summary>
/// <param name="pType">The field type.</param>
/// <returns>The accessor property name.</returns>
function PASourceAccessor(pType: TPAFieldType): string;

/// <summary>Param-array accessor property (port of FDParamArrayAccessor), e.g. 'AsIntegers'.</summary>
/// <param name="pType">The param type.</param>
/// <returns>The array accessor property name.</returns>
function PAParamArrayAccessor(pType: TPAFieldType): string;

/// <summary>Maps a Data.DB class name or 'ftXxx' token from a DFM to a type.</summary>
/// <param name="pToken">Field class ('TIntegerField') or data type ('ftInteger').</param>
/// <returns>The type, or pftUnknown when not recognised.</returns>
function PATypeFromDfmToken(const pToken: string): TPAFieldType;

/// <summary>Reads the last TTable's fields and the last parameterised TFDQuery's params
/// from DFM text.</summary>
/// <param name="pDfm">Text-form DFM.</param>
/// <param name="pQueryName">Out: query component name.</param>
/// <param name="pTableName">Out: table component name.</param>
/// <param name="pSrc">Out: table fields in DFM order.</param>
/// <param name="pDst">Out: query params in DFM order.</param>
/// <returns>True when both a table and a parameterised query were found.</returns>
function PADiscoverFromDfm(const pDfm: string; out pQueryName, pTableName: string;
  out pSrc, pDst: TPAColumns): Boolean;

/// <summary>Builds the Array-DML loop for one query/table pair (port of the assistant's
/// block generator).</summary>
/// <param name="pQueryName">TFDQuery component name.</param>
/// <param name="pTableName">TTable component name.</param>
/// <param name="pSrc">Source fields.</param>
/// <param name="pDst">Query params.</param>
/// <param name="pOpts">Emission options.</param>
/// <param name="pBlock">Out: the code block (CRLF lines).</param>
/// <param name="pError">Out: reason when False ('Query has no parameters.',
/// 'Table and / or Query is missing.' or a duplicate-name message).</param>
/// <returns>True when a block was produced.</returns>
/// <remarks>Matching: names upper-cased and sorted; pass 1 exact, pass 2 the query param
/// contains the field name. Unmatched params follow "// MISSING PARAMS", unmatched
/// fields "#### MISSING FIELDS ####"; an unassignable pair is emitted as a
/// "##### TYPE MISMATCH #####" line plus a commented assignment.</remarks>
function PABuildBlock(const pQueryName, pTableName: string; const pSrc, pDst: TPAColumns;
  const pOpts: TPAOptions; out pBlock, pError: string): Boolean;

/// <summary>Unified diff of inserting the block before the unit's last 'end.'.</summary>
/// <param name="pUnitName">Unit name for the diff header.</param>
/// <param name="pSource">Current unit text.</param>
/// <param name="pBlock">Block from PABuildBlock.</param>
/// <returns>The diff text, or '' when the unit has no insertion point.</returns>
function PABuildPlan(const pUnitName, pSource, pBlock: string): string;

/// <summary>Applies the block as a braced comment before the last 'end.', but only when
/// the compile gate accepts the candidate text.</summary>
/// <param name="pSource">Current unit text.</param>
/// <param name="pBlock">Block from PABuildBlock.</param>
/// <param name="pGate">Compile gate; called exactly once with the candidate text.</param>
/// <param name="pNewSource">Out: the candidate when applied, else pSource unchanged.</param>
/// <returns>pasApplied, pasRefusedByGate or pasNoInsertPoint.</returns>
function PAApplyPlan(const pSource, pBlock: string; const pGate: TPAGate;
  out pNewSource: string): TPAStatus;

/// <summary>True when a unit is processed by the project assistant: its name starts with
/// 'u' (any case) and it is not on the exclusion list.</summary>
/// <param name="pModuleName">Unit name without extension.</param>
/// <returns>True when the unit is processed.</returns>
function PAProjectEligible(const pModuleName: string): Boolean;

/// <summary>Project assistant: for every eligible unit discovers columns from its DFM,
/// builds the plan and applies it through the gate.</summary>
/// <param name="pUnits">The project's units with source and DFM text.</param>
/// <param name="pOpts">Emission options.</param>
/// <param name="pGate">Compile gate (see PAApplyPlan).</param>
/// <returns>One result per input unit; a unit with no table/query is pasNoBlock.</returns>
function PARunProject(const pUnits: array of TPAUnitInput; const pOpts: TPAOptions;
  const pGate: TPAGate): TPAUnitResults;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.StrUtils;

const
  PA_TYPE_NAMES: array[TPAFieldType] of string = ('Unknown', 'String', 'WideString',
    'FixedChar', 'FixedWideChar', 'Memo', 'WideMemo', 'FmtMemo', 'OraClob', 'OraInterval',
    'LargeInt', 'SmallInt', 'Integer', 'Word', 'Shortint', 'AutoInc', 'Byte', 'Bytes',
    'VarBytes', 'Blob', 'Graphic', 'OraBlob', 'Stream', 'Single', 'Float', 'Extended',
    'Currency', 'BCD', 'FMTBcd', 'Boolean', 'Date', 'Time', 'DateTime', 'TimeStamp',
    'OraTimeStamp', 'TimeStampOffset', 'Guid', 'Variant');
  PAD_PARAM = 25;
  PAD_ACCESSOR = 30;
  PAD_FIELD = 25;
  PAD_FIELD_ACC = 15;
  PAD_TYPE = 15;
  DEFAULT_STEP = 20000;
  EXCLUDED_UNITS: array[0..2] of string = ('uFolderCheck', 'uCOMPGRP', 'uTestHelper');
  CRLF = #13#10;
  FT_PREFIX_LEN = 2;
  DEPTH_COMPONENT = 2;
  DEPTH_FIELD = 3;
  EQ_LEN = 3;
  END_DOT = 'end.';

function PADefaultOptions: TPAOptions;
begin
  Result.StepSize := DEFAULT_STEP;
  Result.ProgressForm := '';
end;

function PATypeName(pType: TPAFieldType): string;
begin
  Result := PA_TYPE_NAMES[pType];
end;

function PAGeneralType(pType: TPAFieldType): TPAFieldType;
begin
  case pType of
    pftString, pftWideString, pftFixedChar, pftFixedWideChar, pftMemo, pftWideMemo,
      pftFmtMemo, pftOraClob, pftOraInterval:
      Result := pftString;
    pftLargeint, pftSmallint, pftInteger, pftWord, pftShortint, pftAutoInc:
      Result := pftInteger;
    pftByte, pftBytes, pftVarBytes:
      Result := pftByte;
    pftBlob, pftGraphic, pftOraBlob:
      Result := pftBlob;
    pftSingle, pftFloat, pftExtended:
      Result := pftFloat;
    pftDateTime, pftTimeStamp, pftOraTimeStamp, pftTimeStampOffset:
      Result := pftTimeStamp;
    pftStream, pftCurrency, pftBCD, pftFMTBcd, pftBoolean, pftDate, pftTime, pftGUID:
      Result := pType;
  else
    Result := pftVariant;
  end;
end;

function PASourceAccessor(pType: TPAFieldType): string;
begin
  case pType of
    pftString, pftWideString, pftFixedChar, pftFixedWideChar, pftMemo, pftWideMemo,
      pftFmtMemo, pftOraClob, pftOraInterval:
      Result := 'AsString';
    pftSmallint, pftInteger, pftWord, pftShortint, pftByte, pftAutoInc:
      Result := 'AsInteger';
    pftLargeint:
      Result := 'AsLargeInt';
    pftSingle, pftFloat, pftExtended:
      Result := 'AsFloat';
    pftCurrency:
      Result := 'AsCurrency';
    pftBCD:
      Result := 'AsBcd';
    pftFMTBcd:
      Result := 'AsFMTBcd';
    pftBoolean:
      Result := 'AsBoolean';
    pftDate:
      Result := 'AsDate';
    pftTime:
      Result := 'AsTime';
    pftDateTime, pftTimeStamp, pftOraTimeStamp:
      Result := 'AsDateTime';
    pftTimeStampOffset:
      Result := 'AsDateTimeOffset';
    pftBytes, pftVarBytes:
      Result := 'AsByte';
    pftBlob, pftGraphic, pftOraBlob:
      Result := 'AsBlob';
    pftStream:
      Result := 'AsStream';
    pftGUID:
      Result := 'AsGUID';
  else
    Result := 'AsVariant';
  end;
end;

function PAParamArrayAccessor(pType: TPAFieldType): string;
begin
  case pType of
    pftString, pftWideString, pftFixedChar, pftFixedWideChar, pftMemo, pftWideMemo,
      pftFmtMemo, pftOraClob, pftOraInterval:
      Result := 'AsWideStrings';
    pftSmallint, pftInteger, pftWord, pftShortint, pftAutoInc:
      Result := 'AsIntegers';
    pftByte, pftBytes, pftVarBytes:
      Result := 'AsBytes';
    pftLargeint:
      Result := 'AsLargeInts';
    pftSingle, pftFloat, pftExtended:
      Result := 'AsFloats';
    pftCurrency:
      Result := 'AsCurrencys';
    pftBCD:
      Result := 'AsBcds';
    pftFMTBcd:
      Result := 'AsFMTBcds';
    pftBoolean:
      Result := 'AsBooleans';
    pftDate:
      Result := 'AsDates';
    pftTime:
      Result := 'AsSQLTimeIntervals';
    pftDateTime, pftTimeStamp, pftOraTimeStamp:
      Result := 'AsSQLTimeStamps';
    pftTimeStampOffset:
      Result := 'AsSQLTimeStampOffsets';
    pftBlob, pftGraphic, pftOraBlob:
      Result := 'AsBlobs';
    pftStream:
      Result := 'AsStreams';
    pftGUID:
      Result := 'AsGUIDs';
  else
    Result := 'AsVariants';
  end;
end;

function PATypeFromDfmToken(const pToken: string): TPAFieldType;
const
  FIELD_CLASSES: array[0..24] of record
    Cls: string;
    Typ: TPAFieldType;
  end = (
    (Cls: 'TStringField'; Typ: pftString), (Cls: 'TWideStringField'; Typ: pftWideString),
    (Cls: 'TIntegerField'; Typ: pftInteger), (Cls: 'TSmallintField'; Typ: pftSmallint),
    (Cls: 'TLargeintField'; Typ: pftLargeint), (Cls: 'TWordField'; Typ: pftWord),
    (Cls: 'TFloatField'; Typ: pftFloat), (Cls: 'TSingleField'; Typ: pftSingle),
    (Cls: 'TCurrencyField'; Typ: pftCurrency), (Cls: 'TBCDField'; Typ: pftBCD),
    (Cls: 'TFMTBCDField'; Typ: pftFMTBcd), (Cls: 'TBooleanField'; Typ: pftBoolean),
    (Cls: 'TDateField'; Typ: pftDate), (Cls: 'TTimeField'; Typ: pftTime),
    (Cls: 'TDateTimeField'; Typ: pftDateTime), (Cls: 'TSQLTimeStampField'; Typ: pftTimeStamp),
    (Cls: 'TBlobField'; Typ: pftBlob), (Cls: 'TMemoField'; Typ: pftMemo),
    (Cls: 'TWideMemoField'; Typ: pftWideMemo), (Cls: 'TAutoIncField'; Typ: pftAutoInc),
    (Cls: 'TBytesField'; Typ: pftBytes), (Cls: 'TVarBytesField'; Typ: pftVarBytes),
    (Cls: 'TGuidField'; Typ: pftGUID), (Cls: 'TGraphicField'; Typ: pftGraphic),
    (Cls: 'TExtendedField'; Typ: pftExtended));
var
  LIdx: Integer;
  LType: TPAFieldType;
begin
  for LIdx := Low(FIELD_CLASSES) to High(FIELD_CLASSES) do
    if SameText(FIELD_CLASSES[LIdx].Cls, pToken) then
      Exit(FIELD_CLASSES[LIdx].Typ);
  if (Length(pToken) > FT_PREFIX_LEN) and SameText(Copy(pToken, 1, FT_PREFIX_LEN), 'ft') then
    for LType := Succ(Low(TPAFieldType)) to High(TPAFieldType) do
      if SameText(PA_TYPE_NAMES[LType], Copy(pToken, FT_PREFIX_LEN + 1, MaxInt)) then
        Exit(LType);
  Result := pftUnknown;
end;

{ ---- DFM discovery ---- }

type
  TDfmScope = record
    Kind: Char; { 'o' object, 'i' item }
    Name: string;
    ClassName: string;
    ListProp: string;
  end;

procedure AddColumn(var pCols: TPAColumns; const pName, pFieldName: string;
  pType: TPAFieldType);
begin
  SetLength(pCols, Length(pCols) + 1);
  pCols[High(pCols)].Name := pName;
  pCols[High(pCols)].FieldName := pFieldName;
  pCols[High(pCols)].DataType := pType;
end;

function UnquoteValue(const pText: string): string;
begin
  Result := Trim(pText);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function PADiscoverFromDfm(const pDfm: string; out pQueryName, pTableName: string; // dl:ok cyclomatic-complexity@bec1 -- REVIEWED 2026-11-17: one line-oriented DFM scanner; the branches are the DFM line kinds (object, item, end, property) sharing one scope stack
  out pSrc, pDst: TPAColumns): Boolean;
var
  LLines: TStringList;
  LStack: TList<TDfmScope>;
  LScope: TDfmScope;
  LLine, LProp, LVal, LName, LParamName: string;
  LColon, LEq, LIdx: Integer;
  LCurTable, LCurQuery: string;
  LTableFields, LQueryParams: TPAColumns;
  LFieldNamePending, LGoodQuery: string;
  LGoodParams: TPAColumns;
  LParamType: TPAFieldType;
  LFieldType: TPAFieldType;
begin
  pQueryName := '';
  pTableName := '';
  pSrc := nil;
  pDst := nil;
  LTableFields := nil;
  LQueryParams := nil;
  LCurTable := '';
  LCurQuery := '';
  LParamName := '';
  LGoodQuery := '';
  LGoodParams := nil;
  LParamType := pftUnknown;
  LLines := TStringList.Create;
  LStack := TList<TDfmScope>.Create;
  try
    LLines.Text := pDfm;
    for LIdx := 0 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[LIdx]);
      if StartsText('object ', LLine) or StartsText('inherited ', LLine) or
        StartsText('inline ', LLine) then
      begin
        LColon := Pos(':', LLine);
        LScope.Kind := 'o';
        LScope.Name := Trim(Copy(LLine, Pos(' ', LLine) + 1, LColon - Pos(' ', LLine) - 1));
        LScope.ClassName := Trim(Copy(LLine, LColon + 1, MaxInt));
        LScope.ListProp := '';
        LStack.Add(LScope);
        if (LStack.Count = DEPTH_COMPONENT) and SameText(LScope.ClassName, 'TTable') then
        begin
          LCurTable := LScope.Name;
          LTableFields := nil;
        end
        else if (LStack.Count = DEPTH_COMPONENT) and SameText(LScope.ClassName, 'TFDQuery') then
        begin
          LCurQuery := LScope.Name;
          LQueryParams := nil;
        end
        else if LStack.Count = DEPTH_FIELD then
          LFieldNamePending := if SameText(LStack[1].ClassName, 'TTable') then
            LScope.Name + '|' + LScope.ClassName
          else
            '';
        Continue;
      end;
      if SameText(LLine, 'item') then
      begin
        LScope.Kind := 'i';
        LScope.Name := '';
        LScope.ClassName := '';
        LScope.ListProp := LProp;
        LStack.Add(LScope);
        LParamName := '';
        LParamType := pftUnknown;
        Continue;
      end;
      if SameText(LLine, 'end') or SameText(LLine, 'end>') then
      begin
        if LStack.Count > 0 then
        begin
          LScope := LStack[LStack.Count - 1];
          if (LScope.Kind = 'i') and SameText(LScope.ListProp, 'ParamData') and
            (LStack.Count >= 2) and (LParamName <> '') and
            (LStack[LStack.Count - 2].Name = LCurQuery) then
            AddColumn(LQueryParams, LParamName, LParamName, LParamType);
          if (LScope.Kind = 'o') and (LStack.Count = DEPTH_COMPONENT) and SameText(LScope.ClassName, 'TFDQuery') and
            (Length(LQueryParams) > 0) then
          begin
            LGoodQuery := LScope.Name;
            LGoodParams := LQueryParams;
          end;
          LStack.Delete(LStack.Count - 1);
        end;
        Continue;
      end;
      LEq := Pos(' = ', LLine);
      if LEq = 0 then
        Continue;
      LName := Copy(LLine, 1, LEq - 1);
      LVal := Copy(LLine, LEq + EQ_LEN, MaxInt);
      if EndsStr('<', LVal) then
        LProp := LName;
      if (LStack.Count > 0) and (LStack[LStack.Count - 1].Kind = 'i') then
      begin
        if SameText(LName, 'Name') then
          LParamName := UnquoteValue(LVal)
        else if SameText(LName, 'DataType') then
          LParamType := PATypeFromDfmToken(Trim(LVal));
      end
      else if (LStack.Count = DEPTH_FIELD) and SameText(LName, 'FieldName') and
        (LFieldNamePending <> '') then
      begin
        LFieldType := PATypeFromDfmToken(Copy(LFieldNamePending,
          Pos('|', LFieldNamePending) + 1, MaxInt));
        AddColumn(LTableFields, Copy(LFieldNamePending, 1, Pos('|', LFieldNamePending) - 1),
          UnquoteValue(LVal), LFieldType);
      end;
    end;
  finally
    LStack.Free;
    LLines.Free;
  end;
  Result := (LCurTable <> '') and (LGoodQuery <> '');
  if Result then
  begin
    pTableName := LCurTable;
    pQueryName := LGoodQuery;
    pSrc := LTableFields;
    pDst := LGoodParams;
  end;
end;

{ ---- block builder ---- }

type
  TPair = record
    Src: Integer;
    Dst: Integer;
  end;

function SortedIndices(const pCols: TPAColumns; pUseFieldName: Boolean;
  out pDuplicate: string): TArray<Integer>;
var
  LIdx: Integer;
  LKeys: TArray<string>;
begin
  pDuplicate := '';
  SetLength(Result, Length(pCols));
  SetLength(LKeys, Length(pCols));
  for LIdx := 0 to High(pCols) do
  begin
    Result[LIdx] := LIdx;
    LKeys[LIdx] := UpperCase(if pUseFieldName then pCols[LIdx].FieldName else pCols[LIdx].Name);
  end;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const pA, pB: Integer): Integer
    begin
      Result := AnsiCompareStr(LKeys[pA], LKeys[pB]);
    end));
  for LIdx := 1 to High(Result) do
    if LKeys[Result[LIdx]] = LKeys[Result[LIdx - 1]] then
    begin
      pDuplicate := LKeys[Result[LIdx]];
      Exit;
    end;
end;

function MissingValue(pType: TPAFieldType): string;
begin
  case PAGeneralType(pType) of
    pftString, pftBlob, pftStream:
      Result := '''''';
    pftInteger, pftByte, pftFloat, pftCurrency, pftBCD, pftFMTBcd, pftTime:
      Result := '0';
    pftBoolean:
      Result := 'True';
  else
    Result := 'NULL';
  end;
end;

function IsPlainCoercion(pFamily, pParamFamily: TPAFieldType): Boolean;
begin
  Result := ((pFamily = pftInteger) and (pParamFamily = pftString)) or
    ((pParamFamily = pftFloat) and (pFamily in [pftTimeStamp, pftTime]));
end;

procedure AddPairLine(const pLines: TStringList; const pQuery: string;
  const pParam, pField: TPAColumn);
var
  LFam, LParamFam: TPAFieldType;
  LLhs, LFld, LTail: string;
begin
  LFam := PAGeneralType(pField.DataType);
  LParamFam := PAGeneralType(pParam.DataType);
  LLhs := Format('%s.Params[%s].%s:=', [pQuery, ('par' + pParam.Name).PadRight(PAD_PARAM),
    (PAParamArrayAccessor(pParam.DataType) + '[I]').PadRight(PAD_ACCESSOR)]);
  LFld := Format('%s.%s', [pField.Name.PadRight(PAD_FIELD),
    PASourceAccessor(pField.DataType).PadRight(PAD_FIELD_ACC)]);
  LTail := Format('// %s <- %s', [PATypeName(pParam.DataType).PadRight(PAD_TYPE),
    PATypeName(pField.DataType).PadRight(PAD_TYPE)]);
  if (pField.DataType = pftDateTime) and (pParam.DataType = pftTimeStampOffset) then
    pLines.Add(Format('      %s DateTimeToSQLTimeStampOffset(%s); %s',
      [LLhs, LFld, LTail]))
  else if LFam = LParamFam then
    pLines.Add(Format('      %s          %s; %s', [LLhs, LFld, LTail]))
  else if (LFam = pftString) and (LParamFam = pftByte) then
    pLines.Add(Format('      %s byte(ord(%s.%s[1])); %s',
      [LLhs, pField.Name.PadRight(PAD_FIELD), PASourceAccessor(pField.DataType).PadRight(PAD_FIELD_ACC), LTail]))
  else if IsPlainCoercion(LFam, LParamFam) then
    pLines.Add(Format('      %s          %s; %s', [LLhs, LFld, LTail]))
  else
  begin
    pLines.Add(Format('##### TYPE MISMATCH ##### <%s> <- <%s>',
      [PAParamArrayAccessor(pParam.DataType), PASourceAccessor(pField.DataType)]));
    pLines.Add(Format('//      %s          %s; %s', [LLhs, LFld, LTail]));
  end;
end;

procedure AddTail(const pLines: TStringList; const pQuery, pTable: string;
  const pOpts: TPAOptions);
var
  LForm: string;
begin
  LForm := pOpts.ProgressForm;
  pLines.Add('//');
  pLines.Add('//');
  if LForm <> '' then
    pLines.Add(Format('      Inc(%s.NRECS);', [LForm]));
  pLines.Add('');
  pLines.Add('      Inc(DoneCnt);');
  if LForm <> '' then
  begin
    pLines.Add('      if (DoneCnt mod 100) = 0 then');
    pLines.Add('      begin');
    pLines.Add(Format('        %s.cxlDone.Caption    := IntToStr(DoneCnt);', [LForm]));
    pLines.Add(Format('        %s.prbRecords.Position:= DoneCnt;', [LForm]));
    pLines.Add('        Application.ProcessMessages;');
    pLines.Add('      end;');
  end;
  pLines.Add('      if (I >= STEPSIZE - 2) then');
  pLines.Add('      begin');
  pLines.Add(Format('        %s.Execute(I + 1);', [pQuery]));
  pLines.Add('        I:= - 1;');
  pLines.Add('      end;');
  pLines.Add('    except');
  pLines.Add('      on e: Exception do');
  pLines.Add('        Application.HandleException(Self);');
  pLines.Add('    end; // try/except');
  pLines.Add('    Inc(I);');
  pLines.Add(Format('    %s.Next;', [pTable]));
  pLines.Add('  end; // while');
  pLines.Add('  if I > 0 then');
  pLines.Add(Format('    %s.Execute(I);', [pQuery]));
  if LForm <> '' then
    pLines.Add(Format('  %s.IBD.Commit;', [LForm]));
  pLines.Add(Format('  %s.Close;', [pTable]));
end;

function MatchColumns(const pSrc, pDst: TPAColumns; const pSrcOrder, pDstOrder: TArray<Integer>;
  out pPairs: TArray<TPair>; out pSrcLeft, pDstLeft: TArray<Integer>): Boolean;
var
  LSrcUsed, LDstUsed: TArray<Boolean>;
  LPass, LI, LJ: Integer;
  LSKey, LDKey: string;
  LPair: TPair;
  LPairs: TList<TPair>;
  LLeft: TList<Integer>;
begin
  Result := True;
  SetLength(LSrcUsed, Length(pSrc));
  SetLength(LDstUsed, Length(pDst));
  LPairs := TList<TPair>.Create;
  LLeft := TList<Integer>.Create;
  try
    for LPass := 1 to 2 do
      for LI in pSrcOrder do
      begin
        if LSrcUsed[LI] then
          Continue;
        LSKey := UpperCase(pSrc[LI].FieldName);
        for LJ in pDstOrder do
        begin
          if LDstUsed[LJ] then
            Continue;
          LDKey := UpperCase(pDst[LJ].Name);
          if ((LPass = 1) and (LSKey = LDKey)) or ((LPass = 2) and ContainsText(LDKey, LSKey)) then
          begin
            LSrcUsed[LI] := True;
            LDstUsed[LJ] := True;
            LPair.Src := LI;
            LPair.Dst := LJ;
            LPairs.Add(LPair);
            Break;
          end;
        end;
      end;
    for LI in pSrcOrder do
      if not LSrcUsed[LI] then
        LLeft.Add(LI);
    pSrcLeft := LLeft.ToArray;
    LLeft.Clear;
    for LJ in pDstOrder do
      if not LDstUsed[LJ] then
        LLeft.Add(LJ);
    pDstLeft := LLeft.ToArray;
    pPairs := LPairs.ToArray;
  finally
    LLeft.Free;
    LPairs.Free;
  end;
  TArray.Sort<TPair>(pPairs, TComparer<TPair>.Construct(
    function(const pA, pB: TPair): Integer
    begin
      Result := AnsiCompareStr(UpperCase(pSrc[pA.Src].FieldName), UpperCase(pSrc[pB.Src].FieldName));
    end));
end;

function PABuildBlock(const pQueryName, pTableName: string; const pSrc, pDst: TPAColumns;
  const pOpts: TPAOptions; out pBlock, pError: string): Boolean;
var
  LLines: TStringList;
  LSrcOrder, LDstOrder, LSrcLeft, LDstLeft: TArray<Integer>;
  LPairs: TArray<TPair>;
  LDup: string;
  LIdx: Integer;
  LStep: Integer;
begin
  pBlock := '';
  pError := '';
  Result := False;
  if Length(pDst) = 0 then
  begin
    pError := 'Query has no parameters.';
    Exit;
  end;
  if (pQueryName = '') or (pTableName = '') then
  begin
    pError := 'Table and / or Query is missing.';
    Exit;
  end;
  LSrcOrder := SortedIndices(pSrc, True, LDup);
  if LDup <> '' then
  begin
    pError := 'Duplicate field name <' + LDup + '>.';
    Exit;
  end;
  LDstOrder := SortedIndices(pDst, False, LDup);
  if LDup <> '' then
  begin
    pError := 'Duplicate param name <' + LDup + '>.';
    Exit;
  end;
  MatchColumns(pSrc, pDst, LSrcOrder, LDstOrder, LPairs, LSrcLeft, LDstLeft);
  LStep := pOpts.StepSize;
  if LStep <= 0 then
    LStep := DEFAULT_STEP;
  LLines := TStringList.Create;
  try
    LLines.Add('const');
    LLines.Add(Format('  STEPSIZE = %d;', [LStep]));
    LLines.Add('const');
    for LIdx := 0 to High(pDst) do
      LLines.Add(Format('  %s = %d;', [('par' + pDst[LIdx].Name).PadRight(PAD_PARAM), LIdx]));
    LLines.Add('');
    LLines.Add(Format('  %s.Params.BindMode := pbByNumber; // More efficient than pbByName for Array DML', [pQueryName]));
    LLines.Add(Format('  %s.Params.ArraySize:= STEPSIZE;', [pQueryName]));
    LLines.Add('  var I := 0;');
    LLines.Add('  var DoneCnt := 0;');
    LLines.Add('');
    LLines.Add(Format('  while not %s.EOF do', [pTableName]));
    LLines.Add('  begin');
    LLines.Add('    try');
    for LIdx := 0 to High(LPairs) do
      AddPairLine(LLines, pQueryName, pDst[LPairs[LIdx].Dst], pSrc[LPairs[LIdx].Src]);
    if Length(LDstLeft) > 0 then
    begin
      LLines.Add('// MISSING PARAMS');
      for LIdx in LDstLeft do
        LLines.Add(Format('%s.Params[%s].%s:=          %s; // %s',
          [pQueryName, ('par' + pDst[LIdx].Name).PadRight(PAD_PARAM),
          (PAParamArrayAccessor(pDst[LIdx].DataType) + '[I]').PadRight(PAD_ACCESSOR),
          MissingValue(pDst[LIdx].DataType), PATypeName(pDst[LIdx].DataType).PadRight(PAD_TYPE)]));
    end;
    if Length(LSrcLeft) > 0 then
    begin
      LLines.Add('#### MISSING FIELDS ####');
      for LIdx in LSrcLeft do
        LLines.Add(UpperCase(pSrc[LIdx].FieldName));
    end;
    AddTail(LLines, pQueryName, pTableName, pOpts);
    for LIdx := 0 to LLines.Count - 1 do
      LLines[LIdx] := TrimRight(LLines[LIdx]);
    pBlock := LLines.Text;
  finally
    LLines.Free;
  end;
  Result := True;
end;

{ ---- plan / apply ---- }

function FindInsertPos(const pSource: string): Integer;
var
  LLower: string;
  LPos, LIdx: Integer;
begin
  Result := 0;
  LLower := LowerCase(pSource);
  LPos := 0;
  for LIdx := Length(LLower) - Length(END_DOT) + 1 downto 1 do
    if Copy(LLower, LIdx, Length(END_DOT)) = END_DOT then
    begin
      LPos := LIdx;
      Break;
    end;
  if LPos = 0 then
    Exit;
  { back to the start of the line; only blanks may precede 'end.' there }
  while (LPos > 1) and CharInSet(pSource[LPos - 1], [' ', #9]) do
    Dec(LPos);
  if (LPos > 1) and not CharInSet(pSource[LPos - 1], [#10, #13]) then
    Exit;
  Result := LPos;
end;

function InsertText(const pBlock: string): string;
begin
  Result := CRLF + '{' + CRLF + pBlock + CRLF + '}' + CRLF;
end;

function CountLines(const pText: string): Integer;
var
  LIdx: Integer;
begin
  Result := 0;
  for LIdx := 1 to Length(pText) do
    if pText[LIdx] = #10 then
      Inc(Result);
end;

function PABuildPlan(const pUnitName, pSource, pBlock: string): string;
var
  LPos, LLine: Integer;
  LText: TStringList;
  LIdx: Integer;
  LOut: TStringList;
begin
  Result := '';
  LPos := FindInsertPos(pSource);
  if LPos = 0 then
    Exit;
  LLine := CountLines(Copy(pSource, 1, LPos - 1)) + 1;
  LText := TStringList.Create;
  LOut := TStringList.Create;
  try
    LText.Text := InsertText(pBlock);
    LOut.Add('--- a/' + pUnitName + '.pas');
    LOut.Add('+++ b/' + pUnitName + '.pas');
    LOut.Add(Format('@@ -%d,0 +%d,%d @@', [LLine, LLine, LText.Count]));
    for LIdx := 0 to LText.Count - 1 do
      LOut.Add('+' + LText[LIdx]);
    Result := LOut.Text;
  finally
    LOut.Free;
    LText.Free;
  end;
end;

function PAApplyPlan(const pSource, pBlock: string; const pGate: TPAGate;
  out pNewSource: string): TPAStatus;
var
  LPos: Integer;
  LCandidate: string;
begin
  pNewSource := pSource;
  LPos := FindInsertPos(pSource);
  if LPos = 0 then
    Exit(pasNoInsertPoint);
  LCandidate := Copy(pSource, 1, LPos - 1) + InsertText(pBlock) + Copy(pSource, LPos, MaxInt);
  if not pGate(LCandidate) then
    Exit(pasRefusedByGate);
  pNewSource := LCandidate;
  Result := pasApplied;
end;

function PAProjectEligible(const pModuleName: string): Boolean;
var
  LName: string;
begin
  Result := (pModuleName <> '') and StartsText('u', pModuleName);
  if Result then
    for LName in EXCLUDED_UNITS do
      if SameText(LName, pModuleName) then
        Exit(False);
end;

function PARunProject(const pUnits: array of TPAUnitInput; const pOpts: TPAOptions;
  const pGate: TPAGate): TPAUnitResults;
var
  LIdx: Integer;
  LQuery, LTable: string;
  LSrc, LDst: TPAColumns;
  LBlock: string;
begin
  SetLength(Result, Length(pUnits));
  for LIdx := 0 to High(pUnits) do
  begin
    Result[LIdx].UnitName := pUnits[LIdx].UnitName;
    Result[LIdx].NewSource := pUnits[LIdx].Source;
    if not PAProjectEligible(pUnits[LIdx].UnitName) then
      Result[LIdx].Status := pasExcluded
    else if not PADiscoverFromDfm(pUnits[LIdx].Dfm, LQuery, LTable, LSrc, LDst) then
      Result[LIdx].Status := pasNoBlock
    else if not PABuildBlock(LQuery, LTable, LSrc, LDst, pOpts, LBlock, Result[LIdx].Error) then
      Result[LIdx].Status := pasNoBlock
    else
    begin
      Result[LIdx].Plan := PABuildPlan(pUnits[LIdx].UnitName, pUnits[LIdx].Source, LBlock);
      Result[LIdx].Status := PAApplyPlan(pUnits[LIdx].Source, LBlock, pGate, Result[LIdx].NewSource);
    end;
  end;
end;

end.
