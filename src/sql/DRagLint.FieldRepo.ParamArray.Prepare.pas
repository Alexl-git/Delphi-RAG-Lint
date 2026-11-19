unit DRagLint.FieldRepo.ParamArray.Prepare;

{ drag-lint 1.52 -- lane BK-TTFINISH U6: the IDE-only "query preparation" of the TableTools
  Param Array assistant (uFireDACParamArrayAssistant.pas lines 292-330), ported as a TEXT
  rewrite of the form's DFM plus the edits the IDE designer would have made to the unit.

  For every top-level TFDQuery whose SQL starts with SELECT (the assistant's regex, comments
  allowed before it) -- or only the one named by pOnlyQuery:
  - CachedUpdates := False   -> the CachedUpdates line is dropped (False is the default);
  - ObjectView := False      -> 'ObjectView = False' is written (the default is True), at the
                                place Delphi streams it (published order of TFDQuery);
  - SQL.Text := UpdateObject.InsertSQL.Text, UpdateObject := nil, the update object renamed
    'ZZZ' + Name (warning 'Update Object is not assigned.' when there is none);
  - SchemaAdapter := nil, the adapter renamed 'ZZZ' + Name (warning when there is none);
  - persistent fields cleared (their child objects removed);
  - CompQuery.Prepare        -> a ParamData collection is written for the INSERT parameters;
                                each DataType / Size comes from the removed persistent field of
                                that name (NEW_ / OLD_ prefix stripped), since no database is
                                described here. An unmatched parameter gets no DataType.
  The unit text gets what the designer does on a rename / delete: the component field
  declarations in the form class's first (published) section are renamed or removed. Code that
  still uses a removed or renamed name is left alone; the caller's compile gate refuses it.

  Deviations, on purpose:
  - persistent fields are cleared only on the prepared queries (the IDE cleared them on every
    TFDQuery of the form);
  - a component is renamed once per run, and never onto a name the form already holds (the IDE
    would add a second 'ZZZ' to a shared adapter, or raise on a duplicate name): a warning;
  - an update object / adapter that is not on this form (Form.Component) is not touched: warning;
  - only text lines inside the touched objects (and identifier references to a renamed
    component) change; every other byte of the DFM is kept. }

interface

type
  /// <summary>Outcome of PAPrepareQueries.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.RepoParamArray.pas) ?, declaration (DRagLint.FieldRepo.ParamArray.Prepare.pas) ?, DRagLint.FieldRepo.ParamArray.Prepare.EditPas (DRagLint.FieldRepo.ParamArray.Prepare.pas) ?, DRagLint.FieldRepo.ParamArray.Prepare.PAPrepareQueries (DRagLint.FieldRepo.ParamArray.Prepare.pas)</para>
  /// <para>Used in units: DRagLint.CLI.RepoParamArray, DRagLint.FieldRepo.ParamArray.Prepare</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPAPrepareResult = record
    /// <summary>The rewritten DFM text (the input when nothing changed).</summary>
    Dfm: string;
    /// <summary>The rewritten unit text (the input when nothing changed).</summary>
    Pas: string;
    /// <summary>True when Dfm or Pas differ from the input.</summary>
    Changed: Boolean;
    /// <summary>The queries that were prepared, in DFM order.</summary>
    Queries: TArray<string>;
    /// <summary>'old -> new' per renamed update object / schema adapter.</summary>
    Renamed: TArray<string>;
    /// <summary>The persistent field components removed ('query.field').</summary>
    RemovedFields: TArray<string>;
    /// <summary>What the IDE assistant reported as an error, or what could not be done.</summary>
    Warnings: TArray<string>;
  end;

/// <summary>Prepares the form's SELECT TFDQuery components for Array DML, as the TableTools
/// Param Array assistant did in the designer (see the unit header for every step).</summary>
/// <param name="pDfm">Text-form DFM of the form.</param>
/// <param name="pPas">The form's unit text; '' = no unit edits.</param>
/// <param name="pOnlyQuery">A TFDQuery name (case-insensitive) to prepare only that query;
/// '' = every top-level TFDQuery whose SQL starts with SELECT.</param>
/// <returns>The rewritten texts and what was done. A DFM the scanner does not understand gives
/// the input back unchanged with a warning.</returns>
/// <exception cref="EPAPrepare"><!-- drag-lint:auto exc -->no object line</exception>
/// <remarks>
/// Pure text function: no file access, no database. Line breaks follow the input
/// (CRLF when the input has any). Idempotent: a prepared query holds INSERT SQL, not SELECT.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RepoParamArray.AnalyseUnit (DRagLint.CLI.RepoParamArray.pas)</para>
/// <para>Calls: ContainsStr, Copy, Default, DRagLint.FieldRepo.ParamArray.Prepare.DecodeStringList, DRagLint.FieldRepo.ParamArray.Prepare.EditPas, DRagLint.FieldRepo.ParamArray.Prepare.FindProp, DRagLint.FieldRepo.ParamArray.Prepare.IsObjectLine, DRagLint.FieldRepo.ParamArray.Prepare.ScanObject, DRagLint.FieldRepo.ParamArray.Prepare.SplitText, DRagLint.FieldRepo.ParamArray.Prepare.TLineEdits.Init (+7 more)</para>
/// <para>Returns: Default(TPAPrepareResult); LRun.Res</para>
/// <para>Complexity: 18 (cyclomatic, outer body), 67 lines (full implementation)</para>
/// <para>Catches: EPAPrepare (swallowed)</para>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.DecodeStringList"/>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.EditPas"/>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.FindProp"/>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.IsObjectLine"/>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.ScanObject"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PAPrepareQueries(const pDfm, pPas, pOnlyQuery: string): TPAPrepareResult;

/// <summary>Unified diff with zero context lines (Myers line diff).</summary>
/// <param name="pFileName">File name for the '--- a/' / '+++ b/' header.</param>
/// <param name="pOld">Old text.</param>
/// <param name="pNew">New text.</param>
/// <returns>The diff (CRLF lines), or '' when the texts have the same lines.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RepoParamArray.AnalyseUnit (DRagLint.CLI.RepoParamArray.pas)</para>
/// <para>Calls: ContainsStr, DRagLint.FieldRepo.ParamArray.Prepare.DiffLines, DRagLint.FieldRepo.ParamArray.Prepare.EditScript, Format</para>
/// <para>Returns: ''; LSb.ToString</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 58 lines (full implementation)</para>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.DiffLines"/>
/// <seealso cref="DRagLint.FieldRepo.ParamArray.Prepare.EditScript"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PAUnifiedDiff(const pFileName, pOld, pNew: string): string;

implementation

uses
  System.SysUtils, System.StrUtils, System.RegularExpressions, System.Generics.Collections,
  DRagLint.FieldRepo.ParamArray;

const
  CRLF = #13#10;
  ZZZ = 'ZZZ';
  INDENT_STEP = '  ';
  EQ = ' = ';
  { TFDQuery properties streamed after ObjectView (published order, then the DefineProperties
    ones): ObjectView is inserted before the first of these. }
  AFTER_OBJECT_VIEW: array[0..51] of string = ('Constraints', 'CachedUpdates', 'FilterChanges',
    'Indexes', 'IndexesActive', 'IndexName', 'IndexFieldNames', 'Aggregates', 'AggregatesActive',
    'ConstraintsEnabled', 'MasterSource', 'MasterFields', 'DetailFields', 'OnUpdateRecord',
    'OnUpdateError', 'OnReconcileError', 'BeforeExecute', 'AfterExecute', 'BeforeApplyUpdates',
    'AfterApplyUpdates', 'BeforeGetRecords', 'AfterGetRecords', 'AfterGetRecord',
    'BeforeRowRequest', 'AfterRowRequest', 'OnMasterSetValues', 'LocalSQL', 'ChangeAlerter',
    'ChangeAlertName', 'ConnectionName', 'Connection', 'Transaction', 'UpdateTransaction',
    'SchemaAdapter', 'Params', 'FetchOptions', 'FormatOptions', 'ResourceOptions',
    'SecurityOptions', 'UpdateOptions', 'UpdateObject', 'OnError', 'OnExecuteError',
    'OnCommandChanged', 'SQL', 'Macros', 'Left', 'Top', 'ParamData', 'MacroData', 'DesignInfo',
    'DesignSize');
  FT_NAMES: array[TPAFieldType] of string = ('ftUnknown', 'ftString', 'ftWideString',
    'ftFixedChar', 'ftFixedWideChar', 'ftMemo', 'ftWideMemo', 'ftFmtMemo', 'ftOraClob',
    'ftOraInterval', 'ftLargeint', 'ftSmallint', 'ftInteger', 'ftWord', 'ftShortint', 'ftAutoInc',
    'ftByte', 'ftBytes', 'ftVarBytes', 'ftBlob', 'ftGraphic', 'ftOraBlob', 'ftStream', 'ftSingle',
    'ftFloat', 'ftExtended', 'ftCurrency', 'ftBCD', 'ftFMTBcd', 'ftBoolean', 'ftDate', 'ftTime',
    'ftDateTime', 'ftTimeStamp', 'ftOraTimeStamp', 'ftTimeStampOffset', 'ftGuid', 'ftVariant');
  SELECT_RX = '^\s*(?:--.*\n|\{.*?\}|\(\*.*?\*\)|/\*.*?\*/\s*)*\s*SELECT\b';
  NEW_PREFIX = 'NEW_';
  GRP_INDENT = 1;  { EditPas declaration regex groups: indent, name, ': Type;' tail }
  GRP_NAME = 2;
  GRP_TAIL = 3;
  V_PAD = 3;       { Myers V array: diagonals -Max-1 .. Max+1 }
  OLD_PREFIX = 'OLD_';

type
  EPAPrepare = class(Exception);

  { Not TDfmProp: that name belongs to DRagLint.V151.Dfm.Common alone (run_v152_DFMDUP_single_decl.ps1). }
  TPrepDfmProp = record
    Name: string;
    First: Integer;
    Last: Integer;
  end;

  TDfmObj = record
    Name: string;
    ClassName: string;
    First: Integer;
    Last: Integer;
    Props: TArray<TPrepDfmProp>;
    ChildFirst: TArray<Integer>;
    ChildLast: TArray<Integer>;
  end;

  { Line-level edit list over the original lines: inserted lines go before a line, a line can be
    deleted or replaced. Rendered once at the end, so every edit refers to ORIGINAL indices. }
  TLineEdits = record
    Orig: TArray<string>;
    Rep: TArray<string>;
    Del: TArray<Boolean>;
    Ins: TArray<TArray<string>>;
    procedure Init(const pLines: TArray<string>);
    procedure DeleteRange(pFirst, pLast: Integer);
    procedure InsertBefore(pIdx: Integer; const pLines: TArray<string>);
    function Render(const pBreak: string): string;
  end;

{ ---- text helpers ---- }

procedure SplitText(const pText: string; out pLines: TArray<string>; out pBreak: string);
begin
  pBreak := if ContainsStr(pText, CRLF) then CRLF else #10;
  pLines := pText.Split([pBreak]);
end;

function LeadingSpaces(const pLine: string): string;
var
  LIdx: Integer;
begin
  LIdx := 1;
  while (LIdx <= Length(pLine)) and (pLine[LIdx] = ' ') do
    Inc(LIdx);
  Result := Copy(pLine, 1, LIdx - 1);
end;

function IsObjectLine(const pTrimmed: string): Boolean;
begin
  Result := StartsText('object ', pTrimmed) or StartsText('inherited ', pTrimmed) or
    StartsText('inline ', pTrimmed);
end;

function PropValue(const pLine: string): string;
var
  LEq: Integer;
begin
  LEq := Pos(EQ, pLine);
  Result := if LEq = 0 then '' else Trim(Copy(pLine, LEq + Length(EQ), MaxInt));
end;

{ ---- TLineEdits ---- }

procedure TLineEdits.Init(const pLines: TArray<string>);
begin
  Orig := pLines;
  Rep := Copy(pLines);
  SetLength(Del, Length(pLines));
  SetLength(Ins, Length(pLines) + 1);
end;

procedure TLineEdits.DeleteRange(pFirst, pLast: Integer);
var
  LIdx: Integer;
begin
  for LIdx := pFirst to pLast do
    Del[LIdx] := True;
end;

procedure TLineEdits.InsertBefore(pIdx: Integer; const pLines: TArray<string>);
begin
  Ins[pIdx] := Ins[pIdx] + pLines;
end;

function TLineEdits.Render(const pBreak: string): string;
var
  LOut: TArray<string>;
  LIdx: Integer;
begin
  LOut := nil;
  for LIdx := 0 to High(Orig) do
  begin
    LOut := LOut + Ins[LIdx];
    if not Del[LIdx] then
      LOut := LOut + [Rep[LIdx]];
  end;
  LOut := LOut + Ins[Length(Orig)];
  Result := string.Join(pBreak, LOut);
end;

{ ---- DFM scanner ---- }

function ValueEnd(const pLines: TArray<string>; pIdx: Integer): Integer; forward;

{ A collection value ('Prop = <'): its items' properties are skipped as values (so nested
  collections and string lists are consumed whole); the line ending in '>' closes it. }
function CollectionEnd(const pLines: TArray<string>; pIdx: Integer): Integer;
var
  LIdx: Integer;
  LText: string;
begin
  LIdx := pIdx + 1;
  while LIdx <= High(pLines) do
  begin
    LText := Trim(pLines[LIdx]);
    if ContainsStr(LText, EQ) then
      LIdx := ValueEnd(pLines, LIdx)
    else if EndsStr('>', LText) then
      Exit(LIdx);
    Inc(LIdx);
  end;
  raise EPAPrepare.CreateFmt('unclosed collection at line %d', [pIdx + 1]);
end;

function CloserLine(const pLines: TArray<string>; pIdx: Integer; const pCloser: string): Integer;
begin
  Result := pIdx + 1;
  while (Result <= High(pLines)) and not EndsStr(pCloser, Trim(pLines[Result])) do
    Inc(Result);
  if Result > High(pLines) then
    raise EPAPrepare.CreateFmt('unclosed "%s" value at line %d', [pCloser, pIdx + 1]);
end;

{ Last line of the value that starts on property line pIdx. }
function ValueEnd(const pLines: TArray<string>; pIdx: Integer): Integer;
var
  LVal: string;
begin
  LVal := PropValue(pLines[pIdx]);
  if LVal = '(' then
    Result := CloserLine(pLines, pIdx, ')')
  else if LVal = '<' then
    Result := CollectionEnd(pLines, pIdx)
  else if LVal = '{' then
    Result := CloserLine(pLines, pIdx, '}')
  else if EndsStr('+', LVal) then
  begin
    Result := pIdx + 1;
    while (Result < High(pLines)) and EndsStr('+', Trim(pLines[Result])) do
      Inc(Result);
  end
  else
    Result := pIdx;
end;

function ScanObject(const pLines: TArray<string>; pFirst: Integer): TDfmObj;
var
  LIdx, LColon, LSpace: Integer;
  LText, LHead: string;
  LProp: TPrepDfmProp;
  LChild: TDfmObj;
begin
  Result := Default(TDfmObj);
  Result.First := pFirst;
  LHead := Trim(pLines[pFirst]);
  LColon := Pos(':', LHead);
  LSpace := Pos(' ', LHead);
  if LColon > 0 then
  begin
    Result.Name := Trim(Copy(LHead, LSpace + 1, LColon - LSpace - 1));
    Result.ClassName := Trim(Copy(LHead, LColon + 1, MaxInt));
    if ContainsStr(Result.ClassName, ' ') then
      Result.ClassName := Copy(Result.ClassName, 1, Pos(' ', Result.ClassName) - 1);
  end
  else
    Result.ClassName := Trim(Copy(LHead, LSpace + 1, MaxInt));
  LIdx := pFirst + 1;
  while LIdx <= High(pLines) do
  begin
    LText := Trim(pLines[LIdx]);
    if IsObjectLine(LText) then
    begin
      LChild := ScanObject(pLines, LIdx);
      Result.ChildFirst := Result.ChildFirst + [LIdx];
      Result.ChildLast := Result.ChildLast + [LChild.Last];
      LIdx := LChild.Last + 1;
    end
    else if SameText(LText, 'end') then
    begin
      Result.Last := LIdx;
      Exit;
    end
    else if ContainsStr(LText, EQ) then
    begin
      LProp.Name := Copy(LText, 1, Pos(EQ, LText) - 1);
      LProp.First := LIdx;
      LProp.Last := ValueEnd(pLines, LIdx);
      Result.Props := Result.Props + [LProp];
      LIdx := LProp.Last + 1;
    end
    else
      Inc(LIdx);
  end;
  raise EPAPrepare.CreateFmt('object at line %d has no "end"', [pFirst + 1]);
end;

function FindProp(const pObj: TDfmObj; const pName: string; out pProp: TPrepDfmProp): Boolean;
var
  LProp: TPrepDfmProp;
begin
  pProp := Default(TPrepDfmProp);
  for LProp in pObj.Props do
    if SameText(LProp.Name, pName) then
    begin
      pProp := LProp;
      Exit(True);
    end;
  Result := False;
end;

{ One DFM string expression ('abc'#13'd') to its text. }
function DecodeLiteral(const pText: string): string;
var
  LPos, LStart: Integer;
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LPos := 1;
    while LPos <= Length(pText) do
      if pText[LPos] = '''' then
      begin
        Inc(LPos);
        while LPos <= Length(pText) do
          if pText[LPos] <> '''' then
          begin
            LSb.Append(pText[LPos]);
            Inc(LPos);
          end
          else if (LPos < Length(pText)) and (pText[LPos + 1] = '''') then
          begin
            LSb.Append('''');
            Inc(LPos, 2);
          end
          else
            Break;
        Inc(LPos);
      end
      else if pText[LPos] = '#' then
      begin
        LStart := LPos + 1;
        Inc(LPos);
        while (LPos <= Length(pText)) and CharInSet(pText[LPos], ['0'..'9', '$', 'A'..'F', 'a'..'f']) do
          Inc(LPos);
        LSb.Append(Char(StrToIntDef(Copy(pText, LStart, LPos - LStart), Ord('?'))));
      end
      else
        Inc(LPos);
    Result := LSb.ToString;
  finally
    LSb.Free;
  end;
end;

{ The TStrings.Text of a 'X.Strings = (' list property. }
function DecodeStringList(const pLines: TArray<string>; const pProp: TPrepDfmProp): string;
var
  LIdx: Integer;
  LText: string;
  LItems, LParts: TArray<string>;
  LCont: Boolean;
begin
  LItems := nil;
  LParts := nil;
  for LIdx := pProp.First + 1 to pProp.Last do
  begin
    LText := Trim(pLines[LIdx]);
    if LIdx = pProp.Last then
      LText := Trim(Copy(LText, 1, Length(LText) - 1));
    if LText = '' then
      Continue;
    LCont := EndsStr('+', LText);
    if LCont then
      LText := Trim(Copy(LText, 1, Length(LText) - 1));
    LParts := LParts + [DecodeLiteral(LText)];
    if not LCont then
    begin
      LItems := LItems + [string.Join('', LParts)];
      LParts := nil;
    end;
  end;
  Result := string.Join(CRLF, LItems) + (if Length(LItems) > 0 then CRLF else '');
end;

{ Parameter names of an SQL text in order of first appearance (FireDAC ':NAME' / ':"Name"'),
  skipping string literals, quoted identifiers and comments. }
function SqlParamNames(const pSql: string): TArray<string>;
var
  LPos, LStart: Integer;
  LName: string;
  LSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  LSeen := TDictionary<string, Boolean>.Create;
  try
    LPos := 1;
    while LPos <= Length(pSql) do
    begin
      LName := '';
      case pSql[LPos] of
        '''', '"':
          begin
            LStart := LPos;
            Inc(LPos);
            while (LPos <= Length(pSql)) and (pSql[LPos] <> pSql[LStart]) do
              Inc(LPos);
          end;
        '-':
          if (LPos < Length(pSql)) and (pSql[LPos + 1] = '-') then
            while (LPos <= Length(pSql)) and (pSql[LPos] <> #10) do
              Inc(LPos);
        '/':
          if (LPos < Length(pSql)) and (pSql[LPos + 1] = '*') then
          begin
            LStart := PosEx('*/', pSql, LPos + 2);
            LPos := if LStart = 0 then Length(pSql) else LStart + 1;
          end;
        ':':
          if (LPos < Length(pSql)) and (pSql[LPos + 1] = ':') then
            Inc(LPos)
          else if (LPos < Length(pSql)) and (pSql[LPos + 1] = '"') then
          begin
            LStart := PosEx('"', pSql, LPos + 2);
            if LStart > 0 then
            begin
              LName := Copy(pSql, LPos + 2, LStart - LPos - 2);
              LPos := LStart;
            end;
          end
          else
          begin
            LStart := LPos + 1;
            while (LPos < Length(pSql)) and CharInSet(pSql[LPos + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) do
              Inc(LPos);
            LName := Copy(pSql, LStart, LPos - LStart + 1);
          end;
      end;
      if (LName <> '') and not LSeen.ContainsKey(UpperCase(LName)) then
      begin
        LSeen.Add(UpperCase(LName), True);
        Result := Result + [LName];
      end;
      Inc(LPos);
    end;
  finally
    LSeen.Free;
  end;
end;

{ ---- the preparation ---- }

type
  TPrepareRun = record
    Lines: TArray<string>;
    Edits: TLineEdits;
    Comps: TArray<TDfmObj>;
    Names: TDictionary<string, Integer>;  { every component name in the DFM (upper) -> comp index or -1 }
    RenameMap: TDictionary<string, string>;  { upper old name -> new name }
    Res: TPAPrepareResult;
    procedure Warn(const pText: string);
    function CompIndex(const pName: string): Integer;
    procedure Rename(pComp: Integer);
    procedure SetObjectViewFalse(const pQ: TDfmObj);
    procedure SwapInsertSql(const pQ, pUpd: TDfmObj; out pSql: string);
    function ParamDataLines(const pQ: TDfmObj; const pSql: string): TArray<string>;
    procedure PrepareQuery(const pQ: TDfmObj);
    procedure RenameReferences;
  end;

procedure TPrepareRun.Warn(const pText: string);
begin
  Res.Warnings := Res.Warnings + [pText];
end;

function TPrepareRun.CompIndex(const pName: string): Integer;
begin
  if not Names.TryGetValue(UpperCase(pName), Result) then
    Result := -1;
end;

procedure TPrepareRun.Rename(pComp: Integer);
var
  LOld, LNew, LLine: string;
begin
  LOld := Comps[pComp].Name;
  if RenameMap.ContainsKey(UpperCase(LOld)) then
    Exit;
  LNew := ZZZ + LOld;
  if Names.ContainsKey(UpperCase(LNew)) then
  begin
    Warn(Format('%s: not renamed to %s, the form already has a component of that name', [LOld, LNew]));
    Exit;
  end;
  RenameMap.Add(UpperCase(LOld), LNew);
  Names.Add(UpperCase(LNew), -1);
  Res.Renamed := Res.Renamed + [LOld + ' -> ' + LNew];
  LLine := Edits.Rep[Comps[pComp].First];
  Edits.Rep[Comps[pComp].First] := LeadingSpaces(LLine) +
    Copy(Trim(LLine), 1, Pos(' ', Trim(LLine))) + LNew + Copy(Trim(LLine), Pos(':', Trim(LLine)), MaxInt);
end;

procedure TPrepareRun.SetObjectViewFalse(const pQ: TDfmObj);
var
  LProp: TPrepDfmProp;
  LIndent, LBase: string;
  LAt: Integer;
begin
  LIndent := LeadingSpaces(Lines[pQ.First]) + INDENT_STEP;
  if FindProp(pQ, 'ObjectView', LProp) then
  begin
    if not SameText(PropValue(Lines[LProp.First]), 'False') then
      Edits.Rep[LProp.First] := LIndent + 'ObjectView = False';
    Exit;
  end;
  LAt := if Length(pQ.ChildFirst) > 0 then pQ.ChildFirst[0] else pQ.Last;
  for LProp in pQ.Props do
  begin
    LBase := if ContainsStr(LProp.Name, '.') then Copy(LProp.Name, 1, Pos('.', LProp.Name) - 1) else LProp.Name;
    if MatchText(LBase, AFTER_OBJECT_VIEW) then
    begin
      LAt := LProp.First;
      Break;
    end;
  end;
  Edits.InsertBefore(LAt, [LIndent + 'ObjectView = False']);
end;

procedure TPrepareRun.SwapInsertSql(const pQ, pUpd: TDfmObj; out pSql: string);
var
  LSqlProp, LInsProp: TPrepDfmProp;
  LHasSql: Boolean;
  LAt, LIdx: Integer;
  LNew: TArray<string>;
begin
  pSql := '';
  LHasSql := FindProp(pQ, 'SQL.Strings', LSqlProp);
  LNew := nil;
  if FindProp(pUpd, 'InsertSQL.Strings', LInsProp) then
  begin
    pSql := DecodeStringList(Lines, LInsProp);
    LNew := [LeadingSpaces(Lines[pQ.First]) + INDENT_STEP + 'SQL.Strings = ('];
    for LIdx := LInsProp.First + 1 to LInsProp.Last do
      LNew := LNew + [Lines[LIdx]];
  end;
  if LHasSql then
  begin
    Edits.DeleteRange(LSqlProp.First, LSqlProp.Last);
    LAt := LSqlProp.First;
  end
  else
    LAt := if Length(pQ.ChildFirst) > 0 then pQ.ChildFirst[0] else pQ.Last;
  if LNew <> nil then
    Edits.InsertBefore(LAt, LNew);
end;

function TPrepareRun.ParamDataLines(const pQ: TDfmObj; const pSql: string): TArray<string>;
var
  LIndent, LParam, LKey, LCls, LSize: string;
  LIdx, LPIdx: Integer;
  LField: TDfmObj;
  LProp: TPrepDfmProp;
  LFieldClass, LFieldSize: TDictionary<string, string>;
  LType: TPAFieldType;
  LParams: TArray<string>;
begin
  Result := nil;
  LParams := SqlParamNames(pSql);
  if LParams = nil then
    Exit;
  LFieldClass := TDictionary<string, string>.Create;
  LFieldSize := TDictionary<string, string>.Create;
  try
    for LIdx := 0 to High(pQ.ChildFirst) do
    begin
      LField := ScanObject(Lines, pQ.ChildFirst[LIdx]);
      if not FindProp(LField, 'FieldName', LProp) then
        Continue;
      LKey := UpperCase(DecodeLiteral(PropValue(Lines[LProp.First])));
      LFieldClass.AddOrSetValue(LKey, LField.ClassName);
      if FindProp(LField, 'Size', LProp) then
        LFieldSize.AddOrSetValue(LKey, PropValue(Lines[LProp.First]));
    end;
    LIndent := LeadingSpaces(Lines[pQ.First]) + INDENT_STEP;
    Result := [LIndent + 'ParamData = <'];
    for LPIdx := 0 to High(LParams) do
    begin
      LParam := LParams[LPIdx];
      LKey := UpperCase(LParam);
      if not LFieldClass.ContainsKey(LKey) and (StartsText(NEW_PREFIX, LKey) or StartsText(OLD_PREFIX, LKey)) then
        LKey := Copy(LKey, Length(NEW_PREFIX) + 1, MaxInt);
      Result := Result + [LIndent + INDENT_STEP + 'item',
        LIndent + INDENT_STEP + INDENT_STEP + 'Name = ' + QuotedStr(LParam)];
      LType := pftUnknown;
      if LFieldClass.TryGetValue(LKey, LCls) then
        LType := PATypeFromDfmToken(LCls);
      if LType <> pftUnknown then
        Result := Result + [LIndent + INDENT_STEP + INDENT_STEP + 'DataType = ' + FT_NAMES[LType]];
      Result := Result + [LIndent + INDENT_STEP + INDENT_STEP + 'ParamType = ptInput'];
      if (PAGeneralType(LType) in [pftString, pftByte]) and LFieldSize.TryGetValue(LKey, LSize) then
        Result := Result + [LIndent + INDENT_STEP + INDENT_STEP + 'Size = ' + LSize];
      Result := Result + [LIndent + INDENT_STEP + (if LPIdx = High(LParams) then 'end>' else 'end')];
    end;
  finally
    LFieldSize.Free;
    LFieldClass.Free;
  end;
end;

procedure TPrepareRun.PrepareQuery(const pQ: TDfmObj);
var
  LProp: TPrepDfmProp;
  LTarget, LIdx: Integer;
  LSql, LRef: string;
  LSwapped: Boolean;
  LParamData: TArray<string>;
begin
  Res.Queries := Res.Queries + [pQ.Name];
  if FindProp(pQ, 'CachedUpdates', LProp) then
    Edits.DeleteRange(LProp.First, LProp.Last);
  SetObjectViewFalse(pQ);
  LSwapped := False;
  LSql := '';
  if FindProp(pQ, 'UpdateObject', LProp) then
  begin
    LRef := PropValue(Lines[LProp.First]);
    LTarget := CompIndex(LRef);
    if (LTarget >= 0) and SameText(Comps[LTarget].ClassName, 'TFDUpdateSQL') then
    begin
      SwapInsertSql(pQ, Comps[LTarget], LSql);
      Rename(LTarget);
      Edits.DeleteRange(LProp.First, LProp.Last);
      LSwapped := True;
    end
    else
      Warn(Format('%s: update object %s is not a TFDUpdateSQL on this form; SQL not swapped', [pQ.Name, LRef]));
  end
  else
    Warn(pQ.Name + ': Update Object is not assigned.');
  if FindProp(pQ, 'SchemaAdapter', LProp) then
  begin
    LRef := PropValue(Lines[LProp.First]);
    LTarget := CompIndex(LRef);
    Edits.DeleteRange(LProp.First, LProp.Last);
    if LTarget >= 0 then
      Rename(LTarget)
    else
      Warn(Format('%s: schema adapter %s is not on this form; not renamed', [pQ.Name, LRef]));
  end
  else
    Warn(pQ.Name + ': Schema Adapter is not assigned.');
  if LSwapped then
  begin
    if FindProp(pQ, 'ParamData', LProp) then
      Edits.DeleteRange(LProp.First, LProp.Last);
    LParamData := ParamDataLines(pQ, LSql);
    if LParamData <> nil then
      Edits.InsertBefore(if Length(pQ.ChildFirst) > 0 then pQ.ChildFirst[0] else pQ.Last, LParamData);
  end;
  for LIdx := 0 to High(pQ.ChildFirst) do
  begin
    Edits.DeleteRange(pQ.ChildFirst[LIdx], pQ.ChildLast[LIdx]);
    Res.RemovedFields := Res.RemovedFields + [pQ.Name + '.' + ScanObject(Lines, pQ.ChildFirst[LIdx]).Name];
  end;
end;

procedure TPrepareRun.RenameReferences;
var
  LIdx: Integer;
  LMatch: TMatch;
  LNew: string;
begin
  if RenameMap.Count = 0 then
    Exit;
  for LIdx := 0 to High(Lines) do
  begin
    if Edits.Del[LIdx] then
      Continue;
    LMatch := TRegEx.Match(Edits.Rep[LIdx], '^(\s*[A-Za-z_][\w.]* = )([A-Za-z_]\w*)\s*$');
    if LMatch.Success and RenameMap.TryGetValue(UpperCase(LMatch.Groups[2].Value), LNew) then
      Edits.Rep[LIdx] := LMatch.Groups[1].Value + LNew;
  end;
end;

{ The designer's unit edits: in the form class's first section, removed component fields lose
  their declaration line and renamed ones get the new name. }
function EditPas(const pPas, pClass: string; const pRenames: TDictionary<string, string>;
  const pRemoved: TArray<string>; var pRes: TPAPrepareResult): string;
var
  LLines: TArray<string>;
  LBreak, LText, LName, LNew: string;
  LEdits: TLineEdits;
  LIdx, LStart: Integer;
  LMatch: TMatch;
  LGone: TDictionary<string, Boolean>;
  LDone: TDictionary<string, Boolean>;
  LKey: string;
begin
  SplitText(pPas, LLines, LBreak);
  LEdits := Default(TLineEdits);
  LEdits.Init(LLines);
  LStart := -1;
  for LIdx := 0 to High(LLines) do
    if TRegEx.IsMatch(LLines[LIdx], '^\s*' + pClass + '\s*=\s*class\b', [roIgnoreCase]) then
    begin
      LStart := LIdx;
      Break;
    end;
  if LStart < 0 then
  begin
    pRes.Warnings := pRes.Warnings + [Format('unit: class %s not found; component declarations not edited', [pClass])];
    Exit(pPas);
  end;
  LGone := TDictionary<string, Boolean>.Create;
  LDone := TDictionary<string, Boolean>.Create;
  try
    for LName in pRemoved do
      LGone.AddOrSetValue(UpperCase(LName), True);
    for LIdx := LStart + 1 to High(LLines) do
    begin
      LText := Trim(LLines[LIdx]);
      if TRegEx.IsMatch(LText, '^(private|protected|public|published|strict|end\b)', [roIgnoreCase]) then
        Break;
      LMatch := TRegEx.Match(LLines[LIdx], '^(\s*)([A-Za-z_]\w*)(\s*:\s*[\w.]+\s*;\s*)$');
      if not LMatch.Success then
        Continue;
      LKey := UpperCase(LMatch.Groups[GRP_NAME].Value);
      if LGone.ContainsKey(LKey) then
      begin
        LEdits.DeleteRange(LIdx, LIdx);
        LDone.AddOrSetValue(LKey, True);
      end
      else if pRenames.TryGetValue(LKey, LNew) then
      begin
        LEdits.Rep[LIdx] := LMatch.Groups[GRP_INDENT].Value + LNew + LMatch.Groups[GRP_TAIL].Value;
        LDone.AddOrSetValue(LKey, True);
      end;
    end;
    for LKey in LGone.Keys do
      if not LDone.ContainsKey(LKey) then
        pRes.Warnings := pRes.Warnings + [Format('unit: no declaration of %s in %s to remove', [LKey, pClass])];
    for LKey in pRenames.Keys do
      if not LDone.ContainsKey(LKey) then
        pRes.Warnings := pRes.Warnings + [Format('unit: no declaration of %s in %s to rename', [LKey, pClass])];
  finally
    LDone.Free;
    LGone.Free;
  end;
  Result := LEdits.Render(LBreak);
end;

function PAPrepareQueries(const pDfm, pPas, pOnlyQuery: string): TPAPrepareResult;
var
  LRun: TPrepareRun;
  LBreak, LText: string;
  LRoot: TDfmObj;
  LIdx, LFirst: Integer;
  LSelect: TRegEx;
  LProp: TPrepDfmProp;
  LRemoved: TArray<string>;
begin
  Result := Default(TPAPrepareResult);
  Result.Dfm := pDfm;
  Result.Pas := pPas;
  LRun := Default(TPrepareRun);
  SplitText(pDfm, LRun.Lines, LBreak);
  LRun.Edits.Init(LRun.Lines);
  LRun.Names := TDictionary<string, Integer>.Create;
  LRun.RenameMap := TDictionary<string, string>.Create;
  try
    try
      LFirst := 0;
      while (LFirst <= High(LRun.Lines)) and not IsObjectLine(Trim(LRun.Lines[LFirst])) do
        Inc(LFirst);
      if LFirst > High(LRun.Lines) then
        raise EPAPrepare.Create('no object line');
      LRoot := ScanObject(LRun.Lines, LFirst);
      for LIdx := 0 to High(LRun.Lines) do
      begin
        LText := Trim(LRun.Lines[LIdx]);
        if IsObjectLine(LText) and ContainsStr(LText, ':') then
          LRun.Names.AddOrSetValue(UpperCase(ScanObject(LRun.Lines, LIdx).Name), -1);
      end;
      for LIdx := 0 to High(LRoot.ChildFirst) do
      begin
        LRun.Comps := LRun.Comps + [ScanObject(LRun.Lines, LRoot.ChildFirst[LIdx])];
        LRun.Names.AddOrSetValue(UpperCase(LRun.Comps[LIdx].Name), LIdx);
      end;
      LSelect := TRegEx.Create(SELECT_RX, [roIgnoreCase, roSingleLine]);
      for LIdx := 0 to High(LRun.Comps) do
        if SameText(LRun.Comps[LIdx].ClassName, 'TFDQuery') and
          ((pOnlyQuery = '') or SameText(LRun.Comps[LIdx].Name, pOnlyQuery)) and
          FindProp(LRun.Comps[LIdx], 'SQL.Strings', LProp) and
          LSelect.IsMatch(DecodeStringList(LRun.Lines, LProp)) then
          LRun.PrepareQuery(LRun.Comps[LIdx]);
      LRun.RenameReferences;
      Result := LRun.Res;
      Result.Dfm := LRun.Edits.Render(LBreak);
      Result.Pas := pPas;
      LRemoved := nil;
      for LText in Result.RemovedFields do
        LRemoved := LRemoved + [Copy(LText, Pos('.', LText) + 1, MaxInt)];
      if (pPas <> '') and ((LRun.RenameMap.Count > 0) or (LRemoved <> nil)) then
        Result.Pas := EditPas(pPas, LRoot.ClassName, LRun.RenameMap, LRemoved, Result);
    except
      on E: EPAPrepare do
      begin
        Result := Default(TPAPrepareResult);
        Result.Dfm := pDfm;
        Result.Pas := pPas;
        Result.Warnings := ['DFM not understood, nothing prepared: ' + E.Message];
      end;
    end;
  finally
    LRun.RenameMap.Free;
    LRun.Names.Free;
  end;
  Result.Changed := (Result.Dfm <> pDfm) or (Result.Pas <> pPas);
end;

{ ---- unified diff ---- }

function DiffLines(const pText: string): TArray<string>;
var
  LBreak: string;
begin
  if pText = '' then
    Exit(nil);
  SplitText(pText, Result, LBreak);
  if (Length(Result) > 0) and (Result[High(Result)] = '') then
    SetLength(Result, Length(Result) - 1);
end;

{ Myers O((N+M)D) edit script: '=' keep, '-' delete old line, '+' insert new line, in order. }
function EditScript(const pA, pB: TArray<string>): string;
var
  LN, LM, LMax, LOff, LD, LK, LX, LY, LPrevK, LPrevX, LPrevY: Integer;
  LV, LSlice: TArray<Integer>;
  LTrace: TList<TArray<Integer>>;
  LOps: TStringBuilder;
  LFound: Boolean;
begin
  LN := Length(pA);
  LM := Length(pB);
  LMax := LN + LM;
  LOff := LMax + 1;
  SetLength(LV, 2 * LMax + V_PAD);
  LTrace := TList<TArray<Integer>>.Create;
  LOps := TStringBuilder.Create;
  try
    LFound := False;
    for LD := 0 to LMax do
    begin
      LTrace.Add(Copy(LV, LOff - LD, 2 * LD + 1));
      LK := -LD;
      while LK <= LD do
      begin
        LX := if (LK = -LD) or ((LK <> LD) and (LV[LOff + LK - 1] < LV[LOff + LK + 1])) then LV[LOff + LK + 1]
          else LV[LOff + LK - 1] + 1;
        LY := LX - LK;
        while (LX < LN) and (LY < LM) and (pA[LX] = pB[LY]) do
        begin
          Inc(LX);
          Inc(LY);
        end;
        LV[LOff + LK] := LX;
        if (LX >= LN) and (LY >= LM) then
        begin
          LFound := True;
          Break;
        end;
        Inc(LK, 2);
      end;
      if LFound then
        Break;
    end;
    LX := LN;
    LY := LM;
    for LD := LTrace.Count - 1 downto 0 do
    begin
      LSlice := LTrace[LD];
      LK := LX - LY;
      LPrevK := if (LK = -LD) or ((LK <> LD) and (LSlice[LK - 1 + LD] < LSlice[LK + 1 + LD])) then LK + 1 else LK - 1;
      LPrevX := if LD = 0 then 0 else LSlice[LPrevK + LD];
      LPrevY := LPrevX - LPrevK;
      while (LX > LPrevX) and (LY > LPrevY) do
      begin
        LOps.Append('=');
        Dec(LX);
        Dec(LY);
      end;
      if LD > 0 then
        LOps.Append(if LX = LPrevX then '+' else '-');
      LX := LPrevX;
      LY := LPrevY;
    end;
    Result := ReverseString(LOps.ToString);
  finally
    LOps.Free;
    LTrace.Free;
  end;
end;

function PAUnifiedDiff(const pFileName, pOld, pNew: string): string;
var
  LA, LB: TArray<string>;
  LOps: string;
  LSb: TStringBuilder;
  LPos, LI, LJ, LHi, LHj: Integer;
  LDel, LAdd: TArray<string>;
  LLine: string;
begin
  LA := DiffLines(pOld);
  LB := DiffLines(pNew);
  LOps := EditScript(LA, LB);
  if not (ContainsStr(LOps, '-') or ContainsStr(LOps, '+')) then
    Exit('');
  LSb := TStringBuilder.Create;
  try
    LSb.Append('--- a/' + pFileName + CRLF + '+++ b/' + pFileName + CRLF);
    LI := 0;
    LJ := 0;
    LPos := 1;
    while LPos <= Length(LOps) do
    begin
      if LOps[LPos] = '=' then
      begin
        Inc(LI);
        Inc(LJ);
        Inc(LPos);
        Continue;
      end;
      LHi := LI;
      LHj := LJ;
      LDel := nil;
      LAdd := nil;
      while (LPos <= Length(LOps)) and (LOps[LPos] <> '=') do
      begin
        if LOps[LPos] = '-' then
        begin
          LDel := LDel + [LA[LI]];
          Inc(LI);
        end
        else
        begin
          LAdd := LAdd + [LB[LJ]];
          Inc(LJ);
        end;
        Inc(LPos);
      end;
      LSb.Append(Format('@@ -%d,%d +%d,%d @@', [if LDel = nil then LHi else LHi + 1, Length(LDel),
        if LAdd = nil then LHj else LHj + 1, Length(LAdd)]) + CRLF);
      for LLine in LDel do
        LSb.Append('-' + LLine + CRLF);
      for LLine in LAdd do
        LSb.Append('+' + LLine + CRLF);
    end;
    Result := LSb.ToString;
  finally
    LSb.Free;
  end;
end;

end.
