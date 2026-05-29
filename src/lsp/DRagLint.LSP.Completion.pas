unit DRagLint.LSP.Completion;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.Generics.Collections, System.StrUtils, System.Types,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Lint.Linter,
  DRagLint.Resolver.TypeAt;

type
  // v0.20: LSP response builders for completion, signatureHelp, diagnostics.
  TLspCompletion = class
  public
    class function MapSymbolKindToLspKind(AKind: TSymbolKind): Integer;
    // ASevText is the string severity stored in TLintFinding.Severity
    // ('error', 'warning', 'info', 'hint').
    class function MapLintSeverityToLspSeverity(const ASevText: string): Integer;
    // v0.26: map compiler finding severity ('Error'|'Warning'|'Hint'|
    // 'Information') to LSP DiagnosticSeverity (1=Error, 2=Warning,
    // 3=Information, 4=Hint).
    class function MapCompilerSeverityToLspSeverity(const ASev: string): Integer;
    class function BuildCompletionItems(const AStore: ISymbolStore;
      const AFile: string; ALine, ACol: Integer): TJSONArray;
    class function BuildSignatureHelp(const AStore: ISymbolStore;
      const AFile: string; ALine, ACol: Integer): TJSONObject;
    // v0.26: AStore is optional; when supplied, compiler_findings for this file
    // are merged into the result alongside lint findings.
    class function BuildDiagnostics(const ALinter: TLinter;
      const AFile: string;
      const AStore: ISymbolStore = nil): TJSONArray;
  private
    class function MakeCompletionItem(const ASym: TSymbol;
      const AStore: ISymbolStore): TJSONObject;
    class function EmptySigHelp: TJSONObject;
    class function StripParamModifier(const AName: string): string;
  end;

implementation

{ TLspCompletion }

class function TLspCompletion.EmptySigHelp: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('signatures', TJSONArray.Create);
  Result.AddPair('activeSignature', TJSONNumber.Create(0));
  Result.AddPair('activeParameter', TJSONNumber.Create(0));
end;

class function TLspCompletion.StripParamModifier(const AName: string): string;
const
  Modifiers: array[0..3] of string = ('const ', 'var ', 'out ', 'constref ');
var
  I: Integer;
begin
  Result := AName;
  for I := 0 to High(Modifiers) do
    if StartsText(Modifiers[I], Result) then
    begin
      Result := Trim(Copy(Result, Length(Modifiers[I]) + 1, MaxInt));
      Break;
    end;
end;

class function TLspCompletion.MapSymbolKindToLspKind(
  AKind: TSymbolKind): Integer;
begin
  case AKind of
    skClass:       Result := 7;   // Class
    skRecord:      Result := 22;  // Struct
    skInterface:   Result := 8;   // Interface
    skEnum:        Result := 13;  // Enum
    skEnumValue:   Result := 20;  // EnumMember
    skMethod,
    skFunction,
    skProcedure:   Result := 2;   // Method
    skConstructor,
    skDestructor:  Result := 4;   // Constructor
    skProperty:    Result := 10;  // Property
    skField:       Result := 5;   // Field
    skUnit,
    skProgram,
    skPackage:     Result := 9;   // Module
    skConstDecl:   Result := 21;  // Constant
    skVarDecl:     Result := 6;   // Variable
  else
    Result := 1;  // Text (default for skForm, skComponent, skTypeAlias, etc.)
  end;
end;

class function TLspCompletion.MapLintSeverityToLspSeverity(
  const ASevText: string): Integer;
begin
  if SameText(ASevText, 'error') then
    Result := 1
  else if SameText(ASevText, 'warning') then
    Result := 2
  else if SameText(ASevText, 'info') then
    Result := 3
  else if SameText(ASevText, 'hint') then
    Result := 4
  else
    Result := 3; // Information as default
end;

// v0.26: compiler finding severity uses title-case strings from
// TCompileChecker.NormalizeSeverity: 'Error', 'Warning', 'Hint', 'Information'.
class function TLspCompletion.MapCompilerSeverityToLspSeverity(
  const ASev: string): Integer;
begin
  if SameText(ASev, 'Error') then
    Result := 1
  else if SameText(ASev, 'Warning') then
    Result := 2
  else if SameText(ASev, 'Information') then
    Result := 3
  else if SameText(ASev, 'Hint') then
    Result := 4
  else
    Result := 3; // default Information
end;

class function TLspCompletion.MakeCompletionItem(const ASym: TSymbol;
  const AStore: ISymbolStore): TJSONObject;
var
  Doc: TParsedDoc;
  DetailStr: string;
  DocStr: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('label', ASym.Name);
  Result.AddPair('kind', TJSONNumber.Create(MapSymbolKindToLspKind(ASym.Kind)));
  if ASym.Signature <> '' then
    DetailStr := ASym.Signature
  else
    DetailStr := ASym.QualifiedName;
  Result.AddPair('detail', DetailStr);
  Result.AddPair('insertText', ASym.Name);
  Result.AddPair('sortText', '0_' + ASym.Name);
  if Assigned(AStore) then
  begin
    Doc := AStore.GetSymbolDoc(ASym.Id);
    if Doc.HasContent and (Doc.Summary <> '') then
    begin
      DocStr := Doc.Summary;
      if Doc.ReturnsText <> '' then
        DocStr := DocStr + #10 + 'Returns: ' + Doc.ReturnsText;
      Result.AddPair('documentation', DocStr);
    end;
  end;
end;

class function TLspCompletion.BuildCompletionItems(const AStore: ISymbolStore;
  const AFile: string; ALine, ACol: Integer): TJSONArray;
var
  Lines: TArray<string>;
  LineText: string;
  SubLine: string;
  I: Integer;
  IsDot: Boolean;
  LhsEnd: Integer;
  LhsStr: string;
  PrefixStr: string;
  TypeResult: TTypeAtResult;
  Children: TArray<TSymbol>;
  Matches: TArray<TSymbol>;
  Sym: TSymbol;
begin
  Result := TJSONArray.Create;
  if not TFile.Exists(AFile) then
    Exit;
  Lines := TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then
    Exit;
  LineText := Lines[ALine - 1];

  // SubLine is the text from col 1 up to ACol.
  if ACol < 1 then
    Exit
  else if ACol > Length(LineText) then
    SubLine := LineText
  else
    SubLine := Copy(LineText, 1, ACol);

  // Walk left from end of SubLine skipping whitespace.
  I := Length(SubLine);
  while (I >= 1) and CharInSet(SubLine[I], [' ', #9]) do
    Dec(I);

  IsDot := (I >= 1) and (SubLine[I] = '.');

  if IsDot then
  begin
    // Member completion: walk further left to extract LHS identifier chain.
    LhsEnd := I - 1;
    while (LhsEnd >= 1) and CharInSet(SubLine[LhsEnd], [' ', #9]) do
      Dec(LhsEnd);
    // LhsEnd is now at the last char of the LHS expression.
    // Walk left while identifier chars or dot (Foo.Bar etc.).
    I := LhsEnd;
    while (I >= 1) and
          CharInSet(SubLine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      Dec(I);
    LhsStr := Copy(SubLine, I + 1, LhsEnd - I);

    if LhsStr = '' then
      Exit;

    // Resolve the LHS to find the declared type.
    TypeResult := TTypeAtResolver.Resolve(AStore, AFile, ALine, LhsEnd);
    if TypeResult.HasResolved and
       (TypeResult.Resolved.Kind in [skClass, skRecord, skInterface]) then
    begin
      Children := AStore.FindAllChildSymbols(TypeResult.Resolved.Id);
      for Sym in Children do
        Result.AddElement(MakeCompletionItem(Sym, AStore));
    end;
  end
  else
  begin
    // Identifier completion: walk left while identifier chars to get prefix.
    I := Length(SubLine);
    while (I >= 1) and
          CharInSet(SubLine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      Dec(I);
    PrefixStr := Copy(SubLine, I + 1, Length(SubLine) - I);

    if PrefixStr = '' then
      Exit;

    Matches := AStore.FindSymbolsByPrefix(PrefixStr, 50);
    for Sym in Matches do
      Result.AddElement(MakeCompletionItem(Sym, AStore));
  end;
end;

class function TLspCompletion.BuildSignatureHelp(const AStore: ISymbolStore;
  const AFile: string; ALine, ACol: Integer): TJSONObject;
var
  Lines: TArray<string>;
  LineText: string;
  I: Integer;
  C: Char;
  Depth: Integer;
  OpenParenCol: Integer;
  CalleeEnd: Integer;
  TypeResult: TTypeAtResult;
  SigStr: string;
  ActiveParam: Integer;
  Params: TStringList;
  SigInfoObj: TJSONObject;
  SigsArr: TJSONArray;
  ParamsArr: TJSONArray;
  ParamObj: TJSONObject;
  J: Integer;
  DocStr: string;
  InSigParenStr: string;
  SigParenStart: Integer;
  Groups: TStringDynArray;
  GrpIdx: Integer;
  Grp: string;
  ColonPos: Integer;
  NamesStr: string;
  Names: TStringDynArray;
  NIdx: Integer;
  NName: string;
begin
  Result := nil;
  if not TFile.Exists(AFile) then
  begin
    Result := EmptySigHelp;
    Exit;
  end;
  Lines := TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then
  begin
    Result := EmptySigHelp;
    Exit;
  end;
  LineText := Lines[ALine - 1];

  // Walk left from ACol to find unmatched '(' (top-level open paren).
  OpenParenCol := 0;
  Depth := 0;
  I := ACol;
  if I > Length(LineText) then
    I := Length(LineText);
  while I >= 1 do
  begin
    C := LineText[I];
    if C = ')' then
      Inc(Depth)
    else if C = '(' then
    begin
      if Depth = 0 then
      begin
        OpenParenCol := I;
        Break;
      end;
      Dec(Depth);
    end;
    Dec(I);
  end;

  if OpenParenCol = 0 then
  begin
    Result := EmptySigHelp;
    Exit;
  end;

  // Extract callee identifier from just before the '('.
  CalleeEnd := OpenParenCol - 1;
  while (CalleeEnd >= 1) and CharInSet(LineText[CalleeEnd], [' ', #9]) do
    Dec(CalleeEnd);
  I := CalleeEnd;
  while (I >= 1) and
        CharInSet(LineText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
    Dec(I);

  if CalleeEnd < 1 then
  begin
    Result := EmptySigHelp;
    Exit;
  end;

  // Resolve callee symbol.
  TypeResult := TTypeAtResolver.Resolve(AStore, AFile, ALine, CalleeEnd);
  if not TypeResult.HasResolved then
  begin
    Result := EmptySigHelp;
    Exit;
  end;

  SigStr := TypeResult.Resolved.Signature;
  if SigStr = '' then
  begin
    Result := EmptySigHelp;
    Exit;
  end;

  // Count active parameter: top-level commas between OpenParenCol and ACol.
  ActiveParam := 0;
  Depth := 0;
  for I := OpenParenCol + 1 to ACol do
  begin
    if I > Length(LineText) then
      Break;
    C := LineText[I];
    if C = '(' then
      Inc(Depth)
    else if C = ')' then
    begin
      if Depth > 0 then
        Dec(Depth);
    end
    else if (C = ',') and (Depth = 0) then
      Inc(ActiveParam);
  end;

  // Parse parameters from the signature string.
  // SigStr format: "function Name(a: T; b, c: U): RetType" etc.
  Params := TStringList.Create;
  try
    SigParenStart := Pos('(', SigStr);
    if SigParenStart > 0 then
    begin
      // Extract content inside outermost parentheses.
      Depth := 0;
      InSigParenStr := '';
      for I := SigParenStart to Length(SigStr) do
      begin
        C := SigStr[I];
        if C = '(' then
        begin
          Inc(Depth);
          if Depth > 1 then
            InSigParenStr := InSigParenStr + C;
        end
        else if C = ')' then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
          InSigParenStr := InSigParenStr + C;
        end
        else
          InSigParenStr := InSigParenStr + C;
      end;

      // Split on ';' (Delphi param groups: a, b: Integer; c: string).
      Groups := SplitString(InSigParenStr, ';');
      for GrpIdx := 0 to High(Groups) do
      begin
        Grp := Trim(Groups[GrpIdx]);
        if Grp = '' then
          Continue;
        // Get names before the colon.
        ColonPos := Pos(':', Grp);
        if ColonPos > 0 then
          NamesStr := Copy(Grp, 1, ColonPos - 1)
        else
          NamesStr := Grp;
        // Split on ',' to get individual names.
        Names := SplitString(NamesStr, ',');
        for NIdx := 0 to High(Names) do
        begin
          NName := Trim(Names[NIdx]);
          NName := StripParamModifier(NName);
          if NName <> '' then
            Params.Add(NName);
        end;
      end;
    end;

    // Build the SignatureHelp JSON response.
    SigsArr := TJSONArray.Create;
    SigInfoObj := TJSONObject.Create;
    SigInfoObj.AddPair('label', SigStr);

    if TypeResult.HasDoc and (TypeResult.Doc.Summary <> '') then
    begin
      DocStr := TypeResult.Doc.Summary;
      if TypeResult.Doc.ReturnsText <> '' then
        DocStr := DocStr + #10 + 'Returns: ' + TypeResult.Doc.ReturnsText;
      SigInfoObj.AddPair('documentation', DocStr);
    end;

    ParamsArr := TJSONArray.Create;
    for J := 0 to Params.Count - 1 do
    begin
      ParamObj := TJSONObject.Create;
      ParamObj.AddPair('label', Params[J]);
      ParamsArr.AddElement(ParamObj);
    end;
    SigInfoObj.AddPair('parameters', ParamsArr);
    SigsArr.AddElement(SigInfoObj);

    Result := TJSONObject.Create;
    Result.AddPair('signatures', SigsArr);
    Result.AddPair('activeSignature', TJSONNumber.Create(0));
    Result.AddPair('activeParameter', TJSONNumber.Create(ActiveParam));
  finally
    Params.Free;
  end;
end;

class function TLspCompletion.BuildDiagnostics(const ALinter: TLinter;
  const AFile: string;
  const AStore: ISymbolStore = nil): TJSONArray;
var
  Findings: TArray<TLintFinding>;
  F: TLintFinding;
  DiagObj: TJSONObject;
  RangeObj: TJSONObject;
  StartObj: TJSONObject;
  EndObj: TJSONObject;
  // v0.26 compiler findings
  FileId: Int64;
  CFindings: TArray<TCompilerFinding>;
  CF: TCompilerFinding;
  CStart, CEnd, CRange: TJSONObject;
begin
  Result := TJSONArray.Create;
  if not TFile.Exists(AFile) then
    Exit;

  // --- Lint findings ---
  if Assigned(ALinter) then
  begin
    Findings := ALinter.LintFile(AFile);
    for F in Findings do
    begin
      DiagObj := TJSONObject.Create;

      StartObj := TJSONObject.Create;
      StartObj.AddPair('line', TJSONNumber.Create(F.StartLine - 1));
      StartObj.AddPair('character', TJSONNumber.Create(F.StartCol - 1));

      EndObj := TJSONObject.Create;
      EndObj.AddPair('line', TJSONNumber.Create(F.EndLine - 1));
      EndObj.AddPair('character', TJSONNumber.Create(F.EndCol - 1));

      RangeObj := TJSONObject.Create;
      RangeObj.AddPair('start', StartObj);
      RangeObj.AddPair('end', EndObj);

      DiagObj.AddPair('range', RangeObj);
      DiagObj.AddPair('severity',
        TJSONNumber.Create(MapLintSeverityToLspSeverity(F.Severity)));
      DiagObj.AddPair('source', 'drag-lint');
      DiagObj.AddPair('code', F.RuleId);
      DiagObj.AddPair('message', F.Message);

      Result.AddElement(DiagObj);
    end;
  end;

  // --- v0.26: Compiler findings from the DB ---
  if Assigned(AStore) then
  begin
    FileId := AStore.FindFileIdByPath(AFile);
    if FileId > 0 then
    begin
      CFindings := AStore.FindCompilerFindingsForFile(FileId);
      for CF in CFindings do
      begin
        DiagObj := TJSONObject.Create;

        // LineNo/ColNo are 1-based; LSP range is 0-based.
        CStart := TJSONObject.Create;
        CStart.AddPair('line',
          TJSONNumber.Create(CF.LineNo - 1));
        CStart.AddPair('character',
          TJSONNumber.Create(CF.ColNo - 1));

        CEnd := TJSONObject.Create;
        CEnd.AddPair('line',
          TJSONNumber.Create(CF.LineNo - 1));
        CEnd.AddPair('character',
          TJSONNumber.Create(CF.ColNo));

        CRange := TJSONObject.Create;
        CRange.AddPair('start', CStart);
        CRange.AddPair('end', CEnd);

        DiagObj.AddPair('range', CRange);
        DiagObj.AddPair('severity',
          TJSONNumber.Create(
            MapCompilerSeverityToLspSeverity(CF.Severity)));
        DiagObj.AddPair('source', 'dcc');
        DiagObj.AddPair('code', CF.Code);
        DiagObj.AddPair('message', CF.Message);

        Result.AddElement(DiagObj);
      end;
    end;
  end;
end;

end.
