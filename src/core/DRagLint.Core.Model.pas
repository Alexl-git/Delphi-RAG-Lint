unit DRagLint.Core.Model;

interface

type
  TSymbolKind = (
    skUnit, skProgram, skPackage,
    skClass, skInterface, skRecord, skEnum, skEnumValue,
    skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skField, skVarDecl, skConstDecl, skTypeAlias,
    skForm, skComponent,
    // v0.40.5 Tier 1: SQL DDL symbols extracted from MS*.SQL files.
    // Stored in the same symbols table so the existing query/hover/refs
    // infrastructure carries them transparently; the kind text
    // ('sql_table', 'sql_column', ...) is the disambiguator.
    skSqlTable, skSqlColumn, skSqlIndex, skSqlTrigger,
    skSqlGenerator, skSqlProcedure, skSqlView, skSqlException,
    skSqlDomain, skSqlConstraint,
    // v0.41: unit initialization / finalization sections (no name; one each
    // per unit at most).  Emitted as unit-child markers so the structure view
    // can list them.
    skInitialization, skFinalization
  );

  TSymbolKindHelper = record helper for TSymbolKind
    function ToText: string;
    class function FromText(const AText: string): TSymbolKind; static;
  end;

  TFileTxToken = record
    FileId: Int64;
    Path: string;
  end;

  TSymbol = record
    Id: Int64;
    FileId: Int64;
    ParentId: Int64;
    Kind: TSymbolKind;
    Name: string;
    QualifiedName: string;
    Signature: string;
    Modifiers: string;
    Section: string;     // 'interface' | 'implementation' | '' (usable-from-other-units)
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
  end;

  TReference = record
    Id: Int64;
    SymbolId: Int64;
    FileId: Int64;
    Kind: string;
    NameText: string;
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
    ContextText: string;  // v0.17: surrounding source lines (find-callers --context N)
  end;

  TChunk = record
    Id: Int64;
    FileId: Int64;
    SymbolId: Int64;
    Kind: string;
    StartLine: Integer;
    EndLine: Integer;
    Text: string;
  end;

  TLintFinding = record
    Id: Int64;
    RuleId: string;
    FileId: Int64;
    FilePath: string;
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
    Severity: string;
    Message: string;
  end;

  TDocCommentKind = (
    dckTripleSlash,
    dckDoubleSlashOne,
    dckTripleSlashOne,
    dckPasDocCurly,
    dckPasDocParen,
    dckLooseLine,
    dckLooseBlock
  );

  TDocFormat = (dfXmlDoc, dfPasDoc, dfOneline, dfLoose);

  TDocCommentRegion = record
    StartLine: Integer;
    EndLine:   Integer;
    StartCol:  Integer;
    Kind:      TDocCommentKind;
    RawText:   string;
  end;

  TDocParam = record
    Name: string;
    Desc: string;
  end;

  TDocException = record
    TypeName: string;
    Desc:     string;
  end;

  // v0.40.4: captured from `uses` clauses to support circular-dep detection,
  // move-down (interface->implementation) suggestions, and unused-unit
  // analysis in graphing + lint utilities.
  TUnitUseSection = (
    uusInterface,        // `interface uses ...`
    uusImplementation,   // `implementation uses ...`
    uusProgram,          // top-level uses in a .dpr
    uusPackage           // top-level uses in a .dpk
  );

  TUnitUse = record
    FileId:    Int64;          // owning file (set by indexer post-parse; -1 in parser output)
    UnitName:  string;         // verbatim, with dots: 'System.SysUtils'
    Section:   TUnitUseSection;
    InPath:    string;         // text inside `in '<path>'`; empty when absent
    StartLine: Integer;        // 1-based
    StartCol:  Integer;
    EndLine:   Integer;
    EndCol:    Integer;
  end;

  TParsedDoc = record
    Format:      TDocFormat;
    RawBlock:    string;
    Summary:     string;
    Remarks:     string;
    ReturnsText: string;
    Params:      TArray<TDocParam>;
    Exceptions:  TArray<TDocException>;
    ExampleText: string;
    SeeAlso:     TArray<string>;
    SinceText:   string;
    Deprecated:  Boolean;
    StartLine:   Integer;
    EndLine:     Integer;
    HasContent:  Boolean;
    // Raw JSON strings from storage (populated by GetSymbolDoc for renderers).
    // FillChar zeroes these; empty means not stored or not retrieved.
    ParamsJsonRaw:     string;
    ExceptionsJsonRaw: string;
    SeeAlsoJsonRaw:    string;
  end;

  // v0.16 Task 13: .drag-lint.json "docs" section config.
  // CaptureLooseComments: when False (default), loose // and {..} regions
  //   preceding a symbol are ignored by FindDocRegionAbove.
  // ImplPrecedence: reserved for future use; 'interface' is the only
  //   behavior in v0.16.
  // AllowBlankLineGap: number of blank lines permitted between a doc region
  //   and the following symbol declaration. Default 1.
  TDocConfig = record
    CaptureLooseComments: Boolean;
    ImplPrecedence:       string;
    AllowBlankLineGap:    Integer;
  end;

  TImpactLevel = record
    Depth:        Integer;
    CallerCount:  Integer;
    UnitCount:    Integer;
    Categories:   TArray<string>;
  end;

  TSurfaceLine = record
    Kind:       string;
    Text:       string;
    StartLine:  Integer;
    EndLine:    Integer;
  end;

  TSliceChunk = record
    Kind:       string;
    Text:       string;
    StartLine:  Integer;
    EndLine:    Integer;
  end;

  // v0.18: resolved caller entry for a context bundle (FilePath pre-resolved
  // from FileId so renderers don't need a store callback).
  TBundleCaller = record
    FilePath:    string;
    Line:        Integer;
    Col:         Integer;
    ContextText: string;
  end;

  // v0.26: compiler diagnostic finding (from dcc64 or msbuild output).
  TCompilerFinding = record
    FileId:   Int64;
    RawPath:  string;
    Code:     string;    // e.g. 'W1002'
    Severity: string;    // 'Error' | 'Warning' | 'Hint' | 'Information'
    LineNo:   Integer;
    ColNo:    Integer;
    Message:  string;
  end;

  // v0.18: context bundle — minimum AI-ready slice for a symbol.
  TContextBundle = record
    Task:          string;
    Verb:          string;
    QName:         string;
    GeneratedAt:   TDateTime;
    TokenEstimate: Integer;
    Doc:           TParsedDoc;
    HasDoc:        Boolean;
    ClassSurface:  TArray<TSurfaceLine>;
    ImplSlice:     TArray<TSliceChunk>;
    Callers:       TArray<TBundleCaller>;
    ImpactSummary: TArray<TImpactLevel>;
  end;

function DocFormatToStr(AFormat: TDocFormat): string;
function UnitUseSectionToStr(ASection: TUnitUseSection): string;
function StrToUnitUseSection(const AStr: string): TUnitUseSection;
function JsonEscape(const S: string): string;
function ParamsToJson(const AParams: TArray<TDocParam>): string;
function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
function SeeAlsoToJson(const ASeeAlso: TArray<string>): string;

function DefaultDocConfig: TDocConfig;

implementation

uses
  System.SysUtils;

const
  KindText: array[TSymbolKind] of string = (
    'unit', 'program', 'package',
    'class', 'interface', 'record', 'enum', 'enum_value',
    'procedure', 'function', 'method', 'constructor', 'destructor',
    'property', 'field', 'var', 'const', 'type',
    'form', 'component',
    'sql_table', 'sql_column', 'sql_index', 'sql_trigger',
    'sql_generator', 'sql_procedure', 'sql_view', 'sql_exception',
    'sql_domain', 'sql_constraint',
    'initialization', 'finalization'
  );

function TSymbolKindHelper.ToText: string;
begin
  Result := KindText[Self];
end;

class function TSymbolKindHelper.FromText(const AText: string): TSymbolKind;
var
  K: TSymbolKind;
begin
  for K := Low(TSymbolKind) to High(TSymbolKind) do
    if SameText(KindText[K], AText) then
      Exit(K);
  raise Exception.CreateFmt('Unknown symbol kind: "%s"', [AText]);
end;

function UnitUseSectionToStr(ASection: TUnitUseSection): string;
begin
  case ASection of
    uusInterface:      Result := 'interface';
    uusImplementation: Result := 'implementation';
    uusProgram:        Result := 'program';
    uusPackage:        Result := 'package';
  else
    Result := 'unknown';
  end;
end;

function StrToUnitUseSection(const AStr: string): TUnitUseSection;
begin
  if      SameText(AStr, 'interface')      then Result := uusInterface
  else if SameText(AStr, 'implementation') then Result := uusImplementation
  else if SameText(AStr, 'program')        then Result := uusProgram
  else if SameText(AStr, 'package')        then Result := uusPackage
  else                                          Result := uusImplementation;
end;

function DocFormatToStr(AFormat: TDocFormat): string;
begin
  case AFormat of
    dfXmlDoc:  Result := 'xmldoc';
    dfPasDoc:  Result := 'pasdoc';
    dfOneline: Result := 'oneline';
    dfLoose:   Result := 'loose';
  else
    Result := 'unknown';
  end;
end;

function JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
    else
      if C < #32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
    end;
  end;
end;

function ParamsToJson(const AParams: TArray<TDocParam>): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if Length(AParams) = 0 then
    Exit('');
  SetLength(Parts, Length(AParams));
  for I := 0 to High(AParams) do
    Parts[I] := Format('{"name":"%s","desc":"%s"}',
      [JsonEscape(AParams[I].Name), JsonEscape(AParams[I].Desc)]);
  Result := '[' + string.Join(',', Parts) + ']';
end;

function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if Length(AExceptions) = 0 then
    Exit('');
  SetLength(Parts, Length(AExceptions));
  for I := 0 to High(AExceptions) do
    Parts[I] := Format('{"type":"%s","desc":"%s"}',
      [JsonEscape(AExceptions[I].TypeName), JsonEscape(AExceptions[I].Desc)]);
  Result := '[' + string.Join(',', Parts) + ']';
end;

function SeeAlsoToJson(const ASeeAlso: TArray<string>): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if Length(ASeeAlso) = 0 then
    Exit('');
  SetLength(Parts, Length(ASeeAlso));
  for I := 0 to High(ASeeAlso) do
    Parts[I] := Format('"%s"', [JsonEscape(ASeeAlso[I])]);
  Result := '[' + string.Join(',', Parts) + ']';
end;

function DefaultDocConfig: TDocConfig;
begin
  Result.CaptureLooseComments := False;
  Result.ImplPrecedence := 'interface';
  Result.AllowBlankLineGap := 1;
end;

end.
