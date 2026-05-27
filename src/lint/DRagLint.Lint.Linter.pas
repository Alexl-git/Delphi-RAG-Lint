unit DRagLint.Lint.Linter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
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
