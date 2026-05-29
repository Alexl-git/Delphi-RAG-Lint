unit DRagLint.Resolver.TypeAt;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TTypeAtResult = record
    FileName:    string;
    Line:        Integer;
    Col:         Integer;
    Token:       string;
    Containing:  TSymbol;
    HasContain:  Boolean;
    Resolved:    TSymbol;
    HasResolved: Boolean;
    Doc:         TParsedDoc;
    HasDoc:      Boolean;
    Note:        string;
  end;

  TTypeAtResolver = class
  public
    class function Resolve(const AStore: ISymbolStore;
      const AFile: string; ALine, ACol: Integer): TTypeAtResult;
    class function ExtractTokenAt(const ALine: string;
      ACol: Integer; out APrecedingDot: Boolean;
      out ALhs: string): string;
    class function RenderText(const AResult: TTypeAtResult): string;
    class function RenderJson(const AResult: TTypeAtResult): string;
  end;

implementation

class function TTypeAtResolver.ExtractTokenAt(const ALine: string;
  ACol: Integer; out APrecedingDot: Boolean; out ALhs: string): string;
var
  I, Start, EndIdx: Integer;
begin
  Result := '';
  APrecedingDot := False;
  ALhs := '';
  if (ACol < 1) or (ACol > Length(ALine)) then
    Exit;

  // Walk left to find token start
  Start := ACol;
  while (Start > 1) and
        CharInSet(ALine[Start - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(Start);

  // Walk right to find token end
  EndIdx := ACol;
  while (EndIdx <= Length(ALine)) and
        CharInSet(ALine[EndIdx], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(EndIdx);

  if EndIdx > Start then
    Result := Copy(ALine, Start, EndIdx - Start);

  // Check char immediately before token start
  if (Start > 1) and (ALine[Start - 1] = '.') then
  begin
    APrecedingDot := True;
    // Walk further left to extract LHS (allow dots so Foo.Bar.Baz works)
    I := Start - 2;
    while (I >= 1) and
          CharInSet(ALine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      Dec(I);
    ALhs := Copy(ALine, I + 1, Start - 2 - I);
  end;
end;

class function TTypeAtResolver.Resolve(const AStore: ISymbolStore;
  const AFile: string; ALine, ACol: Integer): TTypeAtResult;
var
  Lines: TArray<string>;
  LineText: string;
  PrecedingDot: Boolean;
  LhsText: string;
  FileId: Int64;
  LhsSym: TSymbol;
  ResolvedSym: TSymbol;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FileName := AFile;
  Result.Line := ALine;
  Result.Col := ACol;
  Result.Note := '';

  if not TFile.Exists(AFile) then
  begin
    Result.Note := 'File not found.';
    Exit;
  end;
  Lines := TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then
  begin
    Result.Note := 'Line out of range.';
    Exit;
  end;
  LineText := Lines[ALine - 1];
  Result.Token := ExtractTokenAt(LineText, ACol, PrecedingDot, LhsText);

  FileId := AStore.FindFileIdByPath(AFile);
  if FileId > 0 then
  begin
    Result.Containing := AStore.FindContainingSymbol(FileId, ALine);
    Result.HasContain := Result.Containing.Id > 0;
  end;

  if Result.Token = '' then
  begin
    Result.Note := 'No identifier at position.';
    Exit;
  end;

  if PrecedingDot and (LhsText <> '') then
  begin
    LhsSym := AStore.FindSymbolByExactNameAnywhere(LhsText);
    if LhsSym.Id > 0 then
    begin
      ResolvedSym := AStore.FindChildSymbolByName(LhsSym.Id, Result.Token);
      if ResolvedSym.Id > 0 then
      begin
        Result.Resolved := ResolvedSym;
        Result.HasResolved := True;
      end
      else
        Result.Note := 'Member ' + Result.Token + ' not found on ' + LhsText + '.';
    end
    else
      Result.Note := 'LHS ' + LhsText + ' unresolved.';
  end
  else
  begin
    ResolvedSym := AStore.FindSymbolByExactNameAnywhere(Result.Token);
    if ResolvedSym.Id > 0 then
    begin
      Result.Resolved := ResolvedSym;
      Result.HasResolved := True;
    end
    else
      Result.Note :=
        'unresolved (likely a local variable; v0.19 does not infer)';
  end;

  if Result.HasResolved then
  begin
    Result.Doc := AStore.GetSymbolDoc(Result.Resolved.Id);
    Result.HasDoc := Result.Doc.HasContent;
  end;
end;

class function TTypeAtResolver.RenderText(
  const AResult: TTypeAtResult): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('File:         ' + AResult.FileName);
    SB.AppendLine(Format('Position:     line %d, col %d',
      [AResult.Line, AResult.Col]));
    if AResult.HasContain then
      SB.AppendLine('Containing:   ' + AResult.Containing.QualifiedName);
    if AResult.Token <> '' then
      SB.AppendLine('Token:        ' + AResult.Token);
    if AResult.HasResolved then
    begin
      SB.AppendLine('Resolved:     ' + AResult.Resolved.QualifiedName);
      if AResult.Resolved.Signature <> '' then
        SB.AppendLine('Signature:    ' + AResult.Resolved.Signature);
    end
    else if AResult.Note <> '' then
      SB.AppendLine('Resolved:     ' + AResult.Note);
    if AResult.HasDoc and (AResult.Doc.Summary <> '') then
      SB.AppendLine('Doc:          ' + AResult.Doc.Summary);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TTypeAtResolver.RenderJson(
  const AResult: TTypeAtResult): string;
begin
  Result := Format(
    '{"file":"%s","line":%d,"col":%d,"token":"%s",' +
    '"containing":"%s","resolved":"%s","signature":"%s","note":"%s"}',
    [StringReplace(AResult.FileName, '\', '/', [rfReplaceAll]),
     AResult.Line,
     AResult.Col,
     AResult.Token,
     AResult.Containing.QualifiedName,
     AResult.Resolved.QualifiedName,
     AResult.Resolved.Signature,
     AResult.Note]);
end;

end.
