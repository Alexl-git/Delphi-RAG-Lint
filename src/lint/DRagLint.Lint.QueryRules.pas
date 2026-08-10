unit DRagLint.Lint.QueryRules;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  , System.RegularExpressions
  , TreeSitter
  , TreeSitterLib
  , TreeSitter.Query
  , DRagLint.Core.Model
  ;

type
  // A loaded external lint rule expressed as a tree-sitter S-expression query.
  // Sister .json file (same basename) supplies metadata: id, severity, message.
  /// <summary><!-- drag-lint:auto -->A loaded external lint rule expressed as a
  /// tree-sitter S-expression query. Sister .json file (same basename) supplies metadata:
  /// id, severity, message.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.Linter.TLinter.Destroy (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll (DRagLint.Lint.QueryRules.pas)
  /// Used in units: DRagLint.Lint.Linter, DRagLint.Lint.QueryRules
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryRule = class
    strict private
      FQuery          : TTSQuery       ;
      FId             : string         ;
      FSeverity       : string         ;
      FMessage        : string         ;
      FSourcePath     : string         ;
      FWarnCapture    : string         ;
      FEnabled        : Boolean        ;
      FRuleId         : string         ;
      FExcludeAncestors: TArray<string>;
      { The MIRROR of FExcludeAncestors: node kinds at least one of which must be
        an ancestor for the match to count at all. Empty = no requirement, which
        is every existing rule, so this changes nothing that does not ask for it.

        Added for concat-in-loop, whose id, comment and message all say "in a
        loop" while its query matched `S := S + X` ANYWHERE -- 328 findings on
        drag-lint's own source, most of them single-shot concatenations that are
        not quadratic in anything. A rule that cannot express its own
        precondition cannot be calibrated; this is that precondition. }
      FRequireAncestors: TArray<string>;
      { True if the picked node (or any ancestor up to the root) is one of the
        node kinds in FExcludeAncestors -- used to suppress a match that sits in
        a structural context the rule should not flag (e.g. an integer literal
        that IS the value of a const definition, for large-magic-number). }
      /// <summary><!-- drag-lint:auto -->True if the picked node (or any ancestor up to
      /// the root) is one of the node kinds in FExcludeAncestors -- used to suppress a
      /// match that sits in a structural context the rule should not flag (e.g. an
      /// integer literal that IS the value of a const definition, for
      /// large-magic-number).</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
      /// Calls: SameText
      /// Reads: FExcludeAncestors
      /// Pure
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function InExcludedAncestor(const ANode: TTSNode): Boolean;
      { True when FRequireAncestors is empty (no requirement) or the node has an
        ancestor of one of those kinds. }
      /// <summary><!-- drag-lint:auto -->True when FRequireAncestors is empty (no
      /// requirement) or the node has an ancestor of one of those kinds.</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
      /// Calls: SameText
      /// Reads: FRequireAncestors
      /// Pure
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function HasRequiredAncestor(const ANode: TTSNode): Boolean;
    public
      /// <param name="ALanguage"><!-- drag-lint:auto type -->const PTSLanguage</param>
      /// <param name="AQuerySource"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AScmPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AJsonPath"><!-- drag-lint:auto type -->const string</param>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll (DRagLint.Lint.QueryRules.pas), DRagLint.CLI.PrintReferences (DRagLint.CLI.pas) ?, DRagLint.CLI.PrintReferencesWithContext (DRagLint.CLI.pas) ?, DRagLint.CLI.PlanToJson (DRagLint.CLI.pas) ?, DRagLint.CLI.PrintSymbols (DRagLint.CLI.pas) ? (+73 more)
      /// Calls: Format, SameText, TreeSitter.Query.TTSQuery.Create, TSQueryError
      /// Complexity: 12 (cyclomatic, outer body), 57 lines (full implementation)
      /// Reads: FId, FExcludeAncestors, FRequireAncestors, FQuery   Writes: FSourcePath, FId, FSeverity, FMessage, FWarnCapture, FEnabled, FRuleId, FExcludeAncestors (+2 more)
      /// Touches: file system
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ALanguage: PTSLanguage; const AQuerySource, AScmPath, AJsonPath: string);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <param name="ARootNode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <param name="ASource"><!-- drag-lint:auto type -->const TBytes</param>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: FoundList.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: Default, DRagLint.Lint.QueryRules.AllPredicatesPass, DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor, DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor, Integer, SameText, TreeSitter.Query.TTSQuery.CaptureNameForID, TreeSitter.Query.TTSQueryCursor.Execute, TreeSitter.Query.TTSQueryCursor.NextMatch
      /// Complexity: 10 (cyclomatic, outer body), 70 lines (full implementation)
      /// Reads: FQuery, FWarnCapture, FId, FSeverity, FMessage
      /// Pure
      /// <seealso cref="DRagLint.Lint.QueryRules.AllPredicatesPass"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Run(const ARootNode: TTSNode; const ASource: TBytes; const AFilePath: string): TArray<TLintFinding>;
      property Id        : string  read FId      ;
      property Severity  : string  read FSeverity;
      property Message   : string  read FMessage ;
      property SourcePath: string  read FSourcePath;
      property Enabled   : Boolean read FEnabled ;
      property RuleId    : string  read FRuleId  ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.Linter.TLinter.Create (DRagLint.Lint.Linter.pas)
  /// Used in units: DRagLint.Lint.Linter
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryRuleLoader = class
    public
      // Loads every *.scm under ARulesDir as a TQueryRule, paired with the
      // sibling <basename>.json if present. Skips and warns on compile failures.
      /// <summary><!-- drag-lint:auto -->Loads every *.scm under ARulesDir as a
      /// TQueryRule, paired with the sibling &lt;basename&gt;.json if present. Skips and
      /// warns on compile failures.</summary>
      /// <param name="ALanguage"><!-- drag-lint:auto type -->const PTSLanguage</param>
      /// <param name="ARulesDir"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.Linter.TLinter.Create (DRagLint.Lint.Linter.pas)
      /// Calls: ChangeFileExt, DRagLint.Lint.QueryRules.TQueryRule.Create, Format, Writeln
      /// Touches: file system
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function LoadAll(const ALanguage: PTSLanguage; const ARulesDir: string): TArray<TQueryRule>;
  end;

implementation

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

{ TQueryRule }

function TQueryRule.InExcludedAncestor(const ANode: TTSNode): Boolean;
var
  Cur: TTSNode;
  Ex : string ;
begin
  Result:= False;
  if Length(FExcludeAncestors) = 0 then Exit;
  Cur:= ANode;
  while not Cur.IsNull do
  begin
    for Ex in FExcludeAncestors do
      if SameText(Cur.NodeType, Ex) then Exit(True);
    Cur:= Cur.Parent;
  end;
end;

function TQueryRule.HasRequiredAncestor(const ANode: TTSNode): Boolean;
var
  Cur: TTSNode;
  Rq : string ;
begin
  { No requirement declared -> every match qualifies. This is the path every
    pre-existing rule takes, so the feature cannot change their behaviour. }
  if Length(FRequireAncestors) = 0 then Exit(True);
  Result:= False;
  Cur:= ANode;
  while not Cur.IsNull do
  begin
    for Rq in FRequireAncestors do
      if SameText(Cur.NodeType, Rq) then Exit(True);
    Cur:= Cur.Parent;
  end;
end;

constructor TQueryRule.Create(const ALanguage: PTSLanguage; const AQuerySource, AScmPath, AJsonPath: string);
var
  ErrOff : UInt32       ;
  ErrType: TTSQueryError;
  JSON   : TJSONObject  ;
  RawJson: string       ;
  ExArr  : TJSONArray   ;
  ExVal  : TJSONValue   ;
begin
  inherited Create;
  FSourcePath:= AScmPath;
  FId:= TPath.GetFileNameWithoutExtension(AScmPath);
  FSeverity:= 'warning';
  FMessage:= Format('matched rule "%s"', [FId]);
  FWarnCapture:= 'warn';
  FEnabled:= True;   // rules run unless their sidecar json says "enabled": false

  if (AJsonPath <> '') and TFile.Exists(AJsonPath) then
  begin
    RawJson:= TFile.ReadAllText(AJsonPath, TEncoding.UTF8);
    JSON:= TJSONObject.ParseJSONValue(RawJson) as TJSONObject;
    if Assigned(JSON) then
    try
      if JSON.GetValue('id'          ) <> nil then begin FId:= JSON.GetValue('id').Value; FRuleId:= FId; end;
      if JSON.GetValue('severity'    ) <> nil then FSeverity   := JSON.GetValue('severity'    ).Value;
      if JSON.GetValue('message'     ) <> nil then FMessage    := JSON.GetValue('message'     ).Value;
      if JSON.GetValue('warn_capture') <> nil then FWarnCapture:= JSON.GetValue('warn_capture').Value;
      if JSON.GetValue('enabled'     ) <> nil then
        FEnabled:= not SameText(JSON.GetValue('enabled').Value, 'false');
      { Optional structural exemption: node kinds whose subtree should NOT fire
        this rule. A match is dropped when the picked node has an ancestor of any
        listed kind. E.g. large-magic-number lists "declConst" so a literal that
        IS a const's value is not told to "name the constant" -- it already is. }
      ExArr:= JSON.GetValue('exclude_if_ancestor') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          FExcludeAncestors:= FExcludeAncestors + [ExVal.Value];
      { Optional structural REQUIREMENT ("require_ancestor"): the match counts
        only inside one of these node kinds. E.g. concat-in-loop lists the three
        loop kinds, so `S := S + X` executed once no longer reports a quadratic
        cost that a single execution cannot have. }
      ExArr:= JSON.GetValue('require_ancestor') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          FRequireAncestors:= FRequireAncestors + [ExVal.Value];
    finally
      JSON.Free;
    end;
  end; // if

  ErrOff:= 0;
  ErrType:= TSQueryError(0);
  FQuery:= TTSQuery.Create(ALanguage, AQuerySource, ErrOff, ErrType);
  if FQuery.Query = nil then
  begin
    raise Exception.CreateFmt( 'tree-sitter query compile failed: rule "%s" (offset %d, errType %d, ' + 'source %s)', [FId, ErrOff, Ord(ErrType), AScmPath]);
  end;
end; // constructor

destructor TQueryRule.Destroy;
begin
  FQuery.Free;
  inherited;
end;

// Resolve a predicate step group to a list of args. The first arg is the
// operator (e.g. "eq?"); subsequent args are either captured node text or
// literal strings.
type
  TPredicateArg = record
    IsCapture   : Boolean;
    CaptureIndex: UInt32 ;
    StringValue : string ;
  end;

function ResolveCaptureText(const AMatch: TTSQueryMatch; ACaptureIndex: UInt32; const ASource: TBytes): string;
var
  Caps: TTSQueryCaptureArray;
  i   : Integer             ;
begin
  Result:= '';
  Caps:= AMatch.CapturesArray;
  for i:= 0 to Length(Caps) - 1 do
    if Caps[i].index = ACaptureIndex then Exit(NodeText(Caps[i].node, ASource));
end;

// Evaluate one predicate. Returns True if it passes.
function EvalPredicate(const AQuery: TTSQuery; const AMatch: TTSQueryMatch; const ASource: TBytes; const AArgs: TArray<TPredicateArg>): Boolean;
var
  i        : Integer;
  Op       : string ;
  FirstText: string ;
  Other    : string ;
  Pattern  : string ;
begin
  if Length(AArgs) < 1 then Exit(True);
  if not AArgs[0].IsCapture then Op:= AArgs[0].StringValue
  else Op:= '';

  if (Op = 'eq?') or (Op = 'not-eq?') then
  begin
    // (#eq? @cap "literal")  or  (#eq? @cap1 @cap2)
    // Resolve each subsequent arg to a string and compare all-equal.
    if Length(AArgs) < 3 then Exit(True);
    if AArgs[1].IsCapture then FirstText:= ResolveCaptureText(AMatch, AArgs[1].CaptureIndex, ASource)
    else FirstText:= AArgs[1].StringValue;
    Result:= True;
    for i:= 2 to Length(AArgs) - 1 do
    begin
      if AArgs[i].IsCapture then Other:= ResolveCaptureText(AMatch, AArgs[i].CaptureIndex, ASource)
      else Other:= AArgs[i].StringValue;
      if FirstText <> Other then
      begin
        Result:= False;
        Break;
      end;
    end;
    if Op = 'not-eq?' then Result:= not Result;
    Exit;
  end; // if

  if (Op = 'match?') or (Op = 'not-match?') then
  begin
    if Length(AArgs) <> 3 then Exit(True);
    if not AArgs[1].IsCapture then Exit(True);
    if AArgs[2].IsCapture then Exit(True);
    FirstText:= ResolveCaptureText(AMatch, AArgs[1].CaptureIndex, ASource);
    Pattern:= AArgs[2].StringValue;
    try
      Result:= TRegEx.IsMatch(FirstText, Pattern);
    except
      Result:= False;
    end;
    if Op = 'not-match?' then Result:= not Result;
    Exit;
  end;

  if (Op = 'any-of?') or (Op = 'not-any-of?') then
  begin
    if Length(AArgs) < 3 then Exit(True);
    if not AArgs[1].IsCapture then Exit(True);
    FirstText:= ResolveCaptureText(AMatch, AArgs[1].CaptureIndex, ASource);
    Result:= False;
    for i:= 2 to Length(AArgs) - 1 do
      if (not AArgs[i].IsCapture) and (AArgs[i].StringValue = FirstText) then
      begin
        Result:= True;
        Break;
      end;
    if Op = 'not-any-of?' then Result:= not Result;
    Exit;
  end;

  // Unknown predicate - treat as pass (don't suppress matches just because
  // we don't recognise a directive).
  Result:= True;
end; // function

function AllPredicatesPass(const AQuery: TTSQuery; const AMatch: TTSQueryMatch; const ASource: TBytes): Boolean;
var
  Steps  : TTSQueryPredicateStepArray;
  Current: TList<TPredicateArg>      ;
  Arg    : TPredicateArg             ;
  i      : Integer                   ;
begin
  Steps:= AQuery.PredicatesForPattern(AMatch.pattern_index);
  if Length(Steps) = 0 then Exit(True);
  Current:= TList<TPredicateArg>.Create;
  try
    for i:= 0 to Length(Steps) - 1 do
    begin
      case Steps[i].&type of
        TSQueryPredicateStepTypeCapture:
        begin
          Arg.IsCapture:= True;
          Arg.CaptureIndex:= Steps[i].value_id;
          Arg.StringValue:= '';
          Current.Add(Arg);
        end;
        TSQueryPredicateStepTypeString:
        begin
          Arg.IsCapture   := False;
          Arg.CaptureIndex:= 0;
          Arg.StringValue:= AQuery.StringValueForID(Steps[i].value_id);
          Current.Add(Arg);
        end;
        TSQueryPredicateStepTypeDone:
        begin
          // End of one predicate. Evaluate; if false, the whole match
          // fails. Then reset Current for the next predicate (if any).
          if not EvalPredicate(AQuery, AMatch, ASource, Current.ToArray) then Exit(False);
          Current.Clear;
        end;
      end; // case
    end; // for
    Result:= True;
  finally
    Current.Free;
  end; // try
end; // function

function TQueryRule.Run(const ARootNode: TTSNode; const ASource: TBytes; const AFilePath: string): TArray<TLintFinding>;
var
  Cursor     : TTSQueryCursor      ;
  Match      : TTSQueryMatch       ;
  Captures   : TTSQueryCaptureArray;
  CapIdx     : UInt32              ;
  FoundList  : TList<TLintFinding> ;
  Finding    : TLintFinding        ;
  CapNode    : TTSNode             ;
  CaptureName: string              ;
  Picked     : TTSNode             ;
  HasWarn    : Boolean             ;
  HasFirst   : Boolean             ;
  i          : Integer             ;
begin
  FoundList:= TList<TLintFinding>.Create;
  Cursor:= TTSQueryCursor.Create;
  try
    Cursor.Execute(FQuery, ARootNode);
    while Cursor.NextMatch(Match) do
    begin
      // v0.3: evaluate predicates before emitting a finding.
      if not AllPredicatesPass(FQuery, Match, ASource) then Continue;

      Captures:= Match.CapturesArray;
      // Prefer the capture named @<FWarnCapture>; otherwise pin to the
      // first capture.
      Picked:= Default(TTSNode);
      HasWarn := False;
      HasFirst:= False;
      for i:= 0 to Length(Captures) - 1 do
      begin
        CapIdx:= Captures[i].index;
        CaptureName:= FQuery.CaptureNameForID(CapIdx);
        CapNode:= Captures[i].node;
        if (not HasFirst) then
        begin
          Picked  := CapNode;
          HasFirst:= True;
        end;
        if SameText(CaptureName, FWarnCapture) then
        begin
          Picked := CapNode;
          HasWarn:= True;
          Break;
        end;
      end; // for
      if not (HasWarn or HasFirst) then Continue;

      { Structural exemption (JSON "exclude_if_ancestor"): drop the match when the
        picked node lives inside one of the excluded node kinds. }
      if InExcludedAncestor(Picked) then Continue;
      if not HasRequiredAncestor(Picked) then Continue;

      Finding:= Default(TLintFinding);
      Finding.RuleId  := FId;
      Finding.Severity:= FSeverity;
      Finding.FilePath:= AFilePath;
      Finding.Message := FMessage;
      Finding.StartLine:= Integer(Picked.StartPoint.row   ) + 1;
      Finding.StartCol := Integer(Picked.StartPoint.column) + 1;
      Finding.EndLine  := Integer(Picked.EndPoint  .row   ) + 1;
      Finding.EndCol   := Integer(Picked.EndPoint  .column) + 1;
      FoundList.Add(Finding);
    end; // while
    Result:= FoundList.ToArray;
  finally
    Cursor.Free;
    FoundList.Free;
  end; // try
end; // function

{ TQueryRuleLoader }

class function TQueryRuleLoader.LoadAll(const ALanguage: PTSLanguage; const ARulesDir: string): TArray<TQueryRule>;
var
  Files   : TArray<string>   ;
  ScmPath : string           ;
  JsonPath: string           ;
  Source  : string           ;
  Rule    : TQueryRule       ;
  List    : TList<TQueryRule>;
begin
  SetLength(Result, 0);
  if not TDirectory.Exists(ARulesDir) then Exit;
  Files:= TDirectory.GetFiles(ARulesDir, '*.scm', TSearchOption.soAllDirectories);
  List:= TList<TQueryRule>.Create;
  try
    for ScmPath in Files do
    begin
      JsonPath:= ChangeFileExt(ScmPath, '.json');
      try
        Source:= TFile.ReadAllText(ScmPath, TEncoding.UTF8);
        Rule:= TQueryRule.Create(ALanguage, Source, ScmPath, JsonPath);
        List.Add(Rule);
      except
        on E: Exception do Writeln(Format('  RULE-LOAD-FAIL %s: %s', [ScmPath, E.Message]));
      end;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

end.
