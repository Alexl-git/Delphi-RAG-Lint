unit DRagLint.Core.Model;

interface

type
  TSymbolKind = (
    skUnit, skProgram, skPackage,
    skClass, skInterface, skRecord, skEnum, skEnumValue,
    skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skField, skVarDecl, skConstDecl, skTypeAlias,
    skForm, skComponent
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

function DocFormatToStr(AFormat: TDocFormat): string;
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
    'form', 'component'
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
