unit DRagLint.Lint.Linter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Types,
  System.Generics.Collections,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Core.Model,
  DRagLint.Parser.Delphi13,
  DRagLint.Lint.QueryRules;

type
  TLinter = class
  strict private
    FLanguage: PTSLanguage;
    FQueryRules: TArray<TQueryRule>;
    function CheckFileImpl(const AFilePath: string): TArray<TLintFinding>;
  public
    constructor Create(const ARulesDir: string = '');
    destructor Destroy; override;
    function LintFile(const AFilePath: string): TArray<TLintFinding>;
    function LintFolder(const APath: string;
      ARecursive: Boolean = True): TArray<TLintFinding>;
    function ExternalRuleCount: Integer;
  end;

implementation

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx, EndIdx, Len: Integer;
begin
  Result := '';
  if ANode.IsNull then
    Exit;
  StartIdx := Integer(ANode.StartByte);
  EndIdx := Integer(ANode.EndByte);
  Len := EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then
    Exit;
  Result := TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

// v0.9: detect `// comment` placed inside a multi-line argument list,
// set literal, or array literal. YADF (and similar reformatters) will
// reflow the next element into the comment and silently destroy code.
//
// Detection is textual because the hazard is about source layout, not
// semantics: scan line by line, track paren/bracket depth (ignoring
// content inside string/char literals and comments themselves), and
// flag any line where a `//` comment appears while depth > 0 AND the
// next non-blank line continues the construct (i.e., either another
// argument or a closing `)`/`]`).
procedure CheckInlineCommentInMultilineArgs(const ASource: TBytes;
  const AFilePath: string; AFindings: TList<TLintFinding>);
type
  TLineInfo = record
    Text: string;
    DepthEntry: Integer;     // paren+bracket depth at start of line
    DepthExit: Integer;      // depth at end of line
    SlashSlashCol: Integer;  // 1-based column of //, or 0 if none
  end;
var
  Lines: TStringDynArray;
  Infos: TArray<TLineInfo>;
  I, J, Depth, Col: Integer;
  Line: string;
  C: Char;
  InStr, InCmt, InBraceCmt, InParenStarCmt: Boolean;
  Finding: TLintFinding;
  HasNext: Boolean;
begin
  if Length(ASource) = 0 then
    Exit;
  Lines := SplitString(StringReplace(
    TEncoding.UTF8.GetString(ASource), #13#10, #10, [rfReplaceAll]), #10);
  SetLength(Infos, Length(Lines));
  Depth := 0;
  InBraceCmt := False;
  InParenStarCmt := False;
  for I := 0 to High(Lines) do
  begin
    Line := Lines[I];
    Infos[I].Text := Line;
    Infos[I].DepthEntry := Depth;
    Infos[I].SlashSlashCol := 0;
    InStr := False;
    InCmt := False;
    Col := 1;
    while Col <= Length(Line) do
    begin
      C := Line[Col];
      if InCmt then
        Break  // // runs to end of line; bail this column
      else if InBraceCmt then
      begin
        if C = '}' then InBraceCmt := False;
        Inc(Col);
      end
      else if InParenStarCmt then
      begin
        if (C = '*') and (Col < Length(Line)) and (Line[Col + 1] = ')') then
        begin
          InParenStarCmt := False;
          Inc(Col, 2);
        end
        else
          Inc(Col);
      end
      else if InStr then
      begin
        if C = '''' then
          InStr := False;
        Inc(Col);
      end
      else
      begin
        if C = '''' then
        begin
          InStr := True;
          Inc(Col);
        end
        else if C = '{' then
        begin
          InBraceCmt := True;
          Inc(Col);
        end
        else if (C = '(') and (Col < Length(Line)) and
                (Line[Col + 1] = '*') then
        begin
          InParenStarCmt := True;
          Inc(Col, 2);
        end
        else if (C = '/') and (Col < Length(Line)) and
                (Line[Col + 1] = '/') then
        begin
          // Only count `//` as a hazard if it carries a comment payload
          // (whitespace + at least one non-space). A bare `//` is rare
          // but harmless; require some text after to flag.
          if (Col + 2 <= Length(Line)) and
             (Trim(Copy(Line, Col + 2, Length(Line) - Col - 1)) <> '') then
            Infos[I].SlashSlashCol := Col;
          InCmt := True;
          Break;
        end
        else if (C = '(') or (C = '[') then
        begin
          Inc(Depth);
          Inc(Col);
        end
        else if (C = ')') or (C = ']') then
        begin
          if Depth > 0 then Dec(Depth);
          Inc(Col);
        end
        else
          Inc(Col);
      end;
    end;
    Infos[I].DepthExit := Depth;
  end;

  for I := 0 to High(Infos) do
  begin
    if (Infos[I].SlashSlashCol > 0) and (Infos[I].DepthEntry > 0) then
    begin
      // Whole-line comments aren't the YADF hazard; only trailing
      // (post-value) ones are. Require non-whitespace BEFORE `//`.
      if Trim(Copy(Infos[I].Text, 1, Infos[I].SlashSlashCol - 1)) = '' then
        Continue;
      // Also skip lines that close out of the multi-line construct —
      // YADF can't reflow into a comment that has no following sibling.
      if Infos[I].DepthExit = 0 then
        Continue;
      HasNext := False;
      for J := I + 1 to High(Infos) do
      begin
        if Trim(Infos[J].Text) <> '' then
        begin
          HasNext := True;
          Break;
        end;
      end;
      if not HasNext then
        Continue;
      Finding := Default(TLintFinding);
      Finding.RuleId := 'inline-comment-in-multiline-args';
      Finding.Severity := 'warning';
      Finding.Message :=
        '// comment inside multi-line argument/array list — reformatters ' +
        '(YADF, etc.) may reflow the next element into this comment. ' +
        'Move the comment above the line or to its own line.';
      Finding.FilePath := AFilePath;
      Finding.StartLine := I + 1;
      Finding.StartCol := Infos[I].SlashSlashCol;
      Finding.EndLine := I + 1;
      Finding.EndCol := Length(Infos[I].Text) + 1;
      AFindings.Add(Finding);
    end;
  end;
end;

procedure WalkForFieldByNameInLoop(const ANode: TTSNode; const ASource: TBytes;
  const AFilePath: string; AInLoopDepth: Integer;
  AFindings: TList<TLintFinding>);
var
  NT: string;
  Entity, Rhs: TTSNode;
  CalleeName: string;
  Finding: TLintFinding;
  i, ChildInLoop: Integer;
begin
  if ANode.IsNull then
    Exit;
  NT := ANode.NodeType;
  ChildInLoop := AInLoopDepth;
  if (NT = 'while') or (NT = 'for') or (NT = 'repeat') then
    Inc(ChildInLoop);

  if (AInLoopDepth > 0) and (NT = 'exprCall') then
  begin
    Entity := ANode.ChildByField('entity');
    if (not Entity.IsNull) and (Entity.NodeType = 'exprDot') then
    begin
      Rhs := Entity.ChildByField('rhs');
      if not Rhs.IsNull then
      begin
        CalleeName := NodeText(Rhs, ASource);
        if SameText(CalleeName, 'FieldByName') then
        begin
          Finding := Default(TLintFinding);
          Finding.RuleId := 'field-by-name-in-loop';
          Finding.Severity := 'warning';
          Finding.Message :=
            'FieldByName() inside a loop body — cache the TField reference ' +
            'in a local variable before the loop and reuse it';
          Finding.FilePath := AFilePath;
          Finding.StartLine := Integer(Rhs.StartPoint.row) + 1;
          Finding.StartCol := Integer(Rhs.StartPoint.column) + 1;
          Finding.EndLine := Integer(Rhs.EndPoint.row) + 1;
          Finding.EndCol := Integer(Rhs.EndPoint.column) + 1;
          AFindings.Add(Finding);
        end;
      end;
    end;
  end;

  for i := 0 to ANode.NamedChildCount - 1 do
    WalkForFieldByNameInLoop(ANode.NamedChild(i), ASource, AFilePath,
      ChildInLoop, AFindings);
end;

{ TLinter }

constructor TLinter.Create(const ARulesDir: string);
var
  ResolvedDir: string;
begin
  inherited Create;
  FLanguage := tree_sitter_delphi13;
  if ARulesDir = '' then
    ResolvedDir := TPath.Combine(
      TPath.GetDirectoryName(ParamStr(0)), 'rules')
  else
    ResolvedDir := ARulesDir;
  FQueryRules := TQueryRuleLoader.LoadAll(FLanguage, ResolvedDir);
end;

destructor TLinter.Destroy;
var
  R: TQueryRule;
begin
  for R in FQueryRules do
    R.Free;
  inherited;
end;

function TLinter.ExternalRuleCount: Integer;
begin
  Result := Length(FQueryRules);
end;

function TLinter.CheckFileImpl(
  const AFilePath: string): TArray<TLintFinding>;
var
  Parser: TTSParser;
  Tree: TTSTree;
  Source: TBytes;
  Findings: TList<TLintFinding>;
begin
  Findings := TList<TLintFinding>.Create;
  Tree := nil;
  Parser := nil;
  try
    Source := TFile.ReadAllBytes(AFilePath);
    Parser := TTSParser.Create;
    Parser.Language := FLanguage;
    Tree := Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint;
        var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining := Length(Source) - Integer(AByteIndex);
        if Remaining <= 0 then
        begin
          ABytesRead := 0;
          SetLength(Result, 0);
          Exit;
        end;
        SetLength(Result, Remaining);
        Move(Source[AByteIndex], Result[0], Remaining);
        ABytesRead := Remaining;
      end,
      TTSInputEncoding.TSInputEncodingUTF8);
    WalkForFieldByNameInLoop(Tree.RootNode, Source, AFilePath, 0, Findings);
    CheckInlineCommentInMultilineArgs(Source, AFilePath, Findings);
    // External *.scm rules
    var R: TQueryRule;
    for R in FQueryRules do
    begin
      var QFindings := R.Run(Tree.RootNode, Source, AFilePath);
      var F: TLintFinding;
      for F in QFindings do
        Findings.Add(F);
    end;
    Result := Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end;

function TLinter.LintFile(
  const AFilePath: string): TArray<TLintFinding>;
begin
  Result := CheckFileImpl(AFilePath);
end;

function TLinter.LintFolder(const APath: string;
  ARecursive: Boolean): TArray<TLintFinding>;
var
  Mode: TSearchOption;
  Files: TArray<string>;
  F: string;
  All: TList<TLintFinding>;
  PartArr: TArray<TLintFinding>;
  P: TLintFinding;
  Patterns: TArray<string>;
  Pattern: string;
begin
  if ARecursive then
    Mode := TSearchOption.soAllDirectories
  else
    Mode := TSearchOption.soTopDirectoryOnly;
  Patterns := ['*.pas', '*.dpr', '*.dpk'];
  All := TList<TLintFinding>.Create;
  try
    for Pattern in Patterns do
    begin
      Files := TDirectory.GetFiles(APath, Pattern, Mode);
      for F in Files do
      begin
        try
          PartArr := CheckFileImpl(F);
          for P in PartArr do
            All.Add(P);
        except
          on E: Exception do
            Writeln(Format('  SKIP %s: %s: %s',
              [F, E.ClassName, E.Message]));
        end;
      end;
    end;
    Result := All.ToArray;
  finally
    All.Free;
  end;
end;

end.
