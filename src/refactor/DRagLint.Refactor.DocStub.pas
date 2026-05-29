unit DRagLint.Refactor.DocStub;

interface

uses
  System.SysUtils, System.Classes, System.RegularExpressions,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TDocStubFormat = (dsfXmlDoc, dsfPasDoc);

  TDocStubGenerator = class
  public
    class function Generate(const AStore: ISymbolStore;
      const AQName: string; AFormat: TDocStubFormat): string;
  end;

implementation

uses
  System.IOUtils;

// ---------------------------------------------------------------------------
// Signature parser helpers
// ---------------------------------------------------------------------------

// ExtractParamList: returns the text between the outermost ( and ) in
// ASignature, or '' if there are no parentheses or the list is empty.
function ExtractParamList(const ASig: string): string;
var
  OpenPos, ClosePos: Integer;
begin
  OpenPos := Pos('(', ASig);
  if OpenPos = 0 then Exit('');
  ClosePos := LastDelimiter(')', ASig);
  if ClosePos <= OpenPos then Exit('');
  Result := Trim(Copy(ASig, OpenPos + 1, ClosePos - OpenPos - 1));
end;

// IsFunction: true when the signature starts with 'function' or 'constructor'.
// Also returns true for 'method' kind when the text contains 'function ' keyword
// before the identifier.
function SignatureHasReturn(const ASig: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(Trim(ASig));
  Result := Lower.StartsWith('function') or Lower.StartsWith('constructor');
end;

// ParseParamNames: parses a param-list string such as
//   "const A, B: string; C: Boolean; D: Integer"
// and returns an array of bare param names (A, B, C, D).
// Handles const/var/out/in prefixes and grouped names (A, B: T).
function ParseParamNames(const AParamList: string): TArray<string>;
var
  Groups: TArray<string>;
  Group, NamesStr, NamesClean: string;
  Names: TArray<string>;
  N: string;
  NTrimmed: string;
  Acc: TStringList;
  ColonPos: Integer;
  I: Integer;
const
  Qualifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'in ', 'array of ');
begin
  if Trim(AParamList) = '' then
    Exit(nil);
  Groups := AParamList.Split([';']);
  Acc := TStringList.Create;
  try
    for I := 0 to High(Groups) do
    begin
      Group := Trim(Groups[I]);
      if Group = '' then Continue;
      // Strip leading qualifiers (const/var/out/in/array of).
      NamesStr := Group;
      var LowerGroup := LowerCase(NamesStr);
      for N in Qualifiers do
        if LowerGroup.StartsWith(N) then
        begin
          NamesStr := Copy(NamesStr, Length(N) + 1, MaxInt);
          LowerGroup := LowerCase(NamesStr);
        end;
      // Strip type after colon.
      ColonPos := Pos(':', NamesStr);
      if ColonPos > 0 then
        NamesStr := Copy(NamesStr, 1, ColonPos - 1);
      NamesClean := Trim(NamesStr);
      // Split by comma for grouped params.
      Names := NamesClean.Split([',']);
      for NTrimmed in Names do
      begin
        var Bare := Trim(NTrimmed);
        if Bare <> '' then
          Acc.Add(Bare);
      end;
    end;
    Result := Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

// ReadSourceLine: reads the text of the given 1-based line from AFilePath.
// Returns '' on any error. Used when the DB signature field is empty.
function ReadSourceLine(const AFilePath: string; ALine: Integer): string;
var
  Lines: TArray<string>;
begin
  Result := '';
  if (AFilePath = '') or (not TFile.Exists(AFilePath)) then
    Exit;
  try
    Lines := TFile.ReadAllLines(AFilePath, TEncoding.ANSI);
    if (ALine >= 1) and (ALine <= Length(Lines)) then
      Result := Trim(Lines[ALine - 1]);
  except
    Result := '';
  end;
end;

// ---------------------------------------------------------------------------
// TDocStubGenerator
// ---------------------------------------------------------------------------

class function TDocStubGenerator.Generate(const AStore: ISymbolStore;
  const AQName: string; AFormat: TDocStubFormat): string;
var
  Syms: TArray<TSymbol>;
  Sym: TSymbol;
  Sig, ParamList, FilePath: string;
  ParamNames: TArray<string>;
  N: string;
  Sb: TStringBuilder;
  HasReturn: Boolean;
begin
  Result := '';
  Syms := AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then
    Exit;
  Sym := Syms[0];
  Sig := Trim(Sym.Signature);

  // If the stored signature is empty (parser did not capture it), fall back
  // to reading the source line at the symbol's declaration position.
  if Sig = '' then
  begin
    FilePath := AStore.GetFilePath(Sym.FileId);
    Sig := ReadSourceLine(FilePath, Sym.StartLine);
  end;

  ParamList := ExtractParamList(Sig);
  ParamNames := ParseParamNames(ParamList);

  // Determine whether a return value exists:
  //   - From signature text when available.
  //   - From symbol kind when no signature text could be found.
  if Sig <> '' then
    HasReturn := SignatureHasReturn(Sig)
  else
    HasReturn := Sym.Kind in [skFunction, skConstructor];

  Sb := TStringBuilder.Create;
  try
    case AFormat of
      dsfXmlDoc:
      begin
        Sb.AppendLine('/// <summary>TODO: describe</summary>');
        for N in ParamNames do
          Sb.AppendLine('/// <param name="' + N + '">TODO: describe</param>');
        if HasReturn then
          Sb.Append('/// <returns>TODO: describe</returns>');
      end;
      dsfPasDoc:
      begin
        Sb.AppendLine('{**');
        Sb.AppendLine(' * TODO: describe');
        for N in ParamNames do
          Sb.AppendLine(' * @param ' + N + ' TODO: describe');
        if HasReturn then
          Sb.AppendLine(' * @returns TODO: describe');
        Sb.Append(' *}');
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
