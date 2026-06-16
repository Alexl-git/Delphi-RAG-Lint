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

function WholeWordPresent(const AText, AWord: string): Boolean;
{ True if AWord appears in AText as a whole identifier (case-insensitive). }
var
  LowerT, LowerW: string;
  P, AfterIdx: Integer;
  BeforeOk, AfterOk: Boolean;
begin
  Result := False;
  if AWord = '' then Exit;
  LowerT := LowerCase(AText);
  LowerW := LowerCase(AWord);
  P := Pos(LowerW, LowerT);
  while P > 0 do
  begin
    BeforeOk := (P = 1) or
      not CharInSet(LowerT[P - 1], ['a'..'z', '0'..'9', '_']);
    AfterIdx := P + Length(LowerW);
    AfterOk := (AfterIdx > Length(LowerT)) or
      not CharInSet(LowerT[AfterIdx], ['a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then Exit(True);
    P := Pos(LowerW, LowerT, P + 1);
  end;
end;

function ExtractDeclType(const ALine, AVarName: string): string;
{ If ALine declares AVarName ("<names>: <Type>" or a param "(...AVarName: Type")
  return <Type>'s first identifier; '' otherwise. Skips ':=' assignments. }
var
  P, Q: Integer;
  Left, Right: string;
begin
  Result := '';
  P := Pos(':', ALine);
  if P = 0 then Exit;
  if (P < Length(ALine)) and (ALine[P + 1] = '=') then Exit;   { ':=' assignment }
  Left := Copy(ALine, 1, P - 1);
  if not WholeWordPresent(Left, AVarName) then Exit;
  Right := TrimLeft(Copy(ALine, P + 1, MaxInt));
  Q := 1;
  while (Q <= Length(Right)) and
        CharInSet(Right[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(Q);
  if Q > 1 then
    Result := Copy(Right, 1, Q - 1);
end;

function InferLocalVarType(const ALines: TArray<string>;
  ACursorIdx0: Integer; const AVarName: string): string;
{ v0.46: resolve a LOCAL variable / parameter's declared type by scanning UP
  from the cursor for "AVarName: Type" within the enclosing routine. Stops at
  the routine header (also checking its parameter list). The v0.19 resolver did
  not infer locals -- this is what lets hover narrow member access on a local
  (e.g. AButton.GroupIndex with AButton: TdxBarButton). }
var
  I: Integer;
  Lower: string;
begin
  Result := '';
  I := ACursorIdx0;
  if (I < 0) or (I > High(ALines)) then Exit;
  while I >= 0 do
  begin
    Lower := LowerCase(TrimLeft(ALines[I]));
    if (Pos('procedure ', Lower) = 1) or (Pos('function ', Lower) = 1) or
       (Pos('constructor ', Lower) = 1) or (Pos('destructor ', Lower) = 1) then
    begin
      { routine header -- params may declare it; then stop (boundary). }
      Result := ExtractDeclType(ALines[I], AVarName);
      Exit;
    end;
    Result := ExtractDeclType(ALines[I], AVarName);
    if Result <> '' then Exit;
    Dec(I);
    if ACursorIdx0 - I > 400 then Break;   { safety }
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
    { v0.46: LHS not a global symbol -> infer it as a local var/param and
      resolve its declared TYPE, so member access on a local narrows. }
    if LhsSym.Id <= 0 then
    begin
      var InferredType: string := InferLocalVarType(Lines, ALine - 1, LhsText);
      if InferredType <> '' then
      begin
        LhsSym := AStore.FindSymbolByExactNameAnywhere(InferredType);
        if LhsSym.Id <= 0 then
          Result.Note := Format('inferred %s: %s (type not indexed)',
            [LhsText, InferredType]);
      end;
    end;
    if LhsSym.Id > 0 then
    begin
      ResolvedSym := AStore.FindChildSymbolByName(LhsSym.Id, Result.Token);
      if ResolvedSym.Id > 0 then
      begin
        Result.Resolved := ResolvedSym;
        Result.HasResolved := True;
      end
      else if LhsSym.Kind in [skClass, skRecord, skInterface, skTypeAlias] then
      begin
        { member not a direct child -> likely inherited. Resolve to the OWNER
          TYPE so the hover can narrow by the type (and, failing that, by its
          unit). }
        Result.Resolved := LhsSym;
        Result.HasResolved := True;
        Result.Note := Format('owner type %s (member may be inherited)',
          [LhsSym.QualifiedName]);
      end
      else
        Result.Note := 'Member ' + Result.Token + ' not found on ' +
          LhsSym.QualifiedName + '.';
    end
    else if Result.Note = '' then
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
    begin
      { v0.46: infer a bare local var/param's declared type. }
      var InferredType: string := InferLocalVarType(Lines, ALine - 1, Result.Token);
      if InferredType <> '' then
      begin
        ResolvedSym := AStore.FindSymbolByExactNameAnywhere(InferredType);
        if ResolvedSym.Id > 0 then
        begin
          Result.Resolved := ResolvedSym;
          Result.HasResolved := True;
          Result.Note := Format('%s: %s', [Result.Token, InferredType]);
        end
        else
          Result.Note := Format('%s: %s (type not indexed)',
            [Result.Token, InferredType]);
      end
      else
        Result.Note := 'unresolved (local type not inferred)';
    end;
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
