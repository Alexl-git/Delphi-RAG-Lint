unit DRagLint.CLI.RuleScope;

(* drag-lint 1.52 -- verbs `rules disable` / `rules enable` (ruling B4 part 3,
  PLAN section 5 D1: scope line | unit | project, a reason on every entry).
  DRagLint.CLI.pas parses the flags and calls RunRuleScope in ONE dispatch line
  (FRAME contract); everything else lives here. Owned by lane DISRULE.

  THE THREE SCOPES AND WHERE EACH ONE IS RECORDED.
    line    -- a `dl:ok <rule>@<hash>` marker on the finding's line, the same marker
               `drag-lint allow` writes (TReviewMarkers.InsertInto, MarkerHash.ExpectedHash),
               with `REVIEWED <yyyy-mm-dd>: <reason>` as its reason. The source is the
               only place a line review can live: it must move with the code.
    unit    -- "rule_overrides": { "<rule>": { "exclude_units": ["<Unit>"] } } in the
               project's drag-lint-lint.json. NO comment is written into the source.
    project -- "rule_overrides": { "<rule>": { "enabled": false } } in the same file.
  Unit and project entries carry "reason" and "date" beside them. `rules enable` undoes
  exactly one disable: the marker entry, the unit, or the enabled=false (and the rule's
  id in the top-level "disabled" list, where the Lint Options dock records a project-wide
  disable). An entry left with nothing in it is removed, and so is an empty block.

  THE CONFIG FILE. --config wins; else beside --project (or its _D-RAG folder when only
  that one exists; a new file goes beside the .dproj, where the Lint Options dock saves);
  else the nearest drag-lint-lint.json walking up from --in -- the same order lint's own
  discovery uses, so the file written is the file the next lint reads. Every other key in
  it survives; it is rewritten as 7-bit ASCII with CRLF (a non-ASCII character becomes a
  \uXXXX escape, which is the same JSON value). *)

interface

/// <summary>Runs `drag-lint rules disable|enable --rule &lt;id&gt; --scope line|unit|project
/// [--in F --line N] --reason "..." [--project P] [--config C] [--json]`.</summary>
/// <param name="pAction">'disable' or 'enable' (the positional after `rules`).</param>
/// <param name="pRuleId">--rule value. disable checks it against the rule catalogue;
/// enable accepts any id, so an entry for a rule that no longer exists can be removed.</param>
/// <param name="pScope">--scope value: 'line', 'unit' or 'project'; '' when absent (an error).</param>
/// <param name="pFile">--in (alias --file) value: the unit (line and unit scope), '' when absent.</param>
/// <param name="pLine">--line value: the finding's 1-based line (line scope), 0 when absent.</param>
/// <param name="pReason">--reason value: required by disable, ignored by enable.</param>
/// <param name="pProject">--project value (.dproj): locates the project config, '' when absent.</param>
/// <param name="pConfigPath">--config value: the project lint config to edit, '' when absent.</param>
/// <param name="pJson">--json (or --format json): one JSON object on stdout instead of a text line.</param>
/// <returns>Process exit code: 0 done, 1 nothing to do (already disabled / nothing to
/// enable), 2 usage error or refused (unknown rule, missing flag, a line that cannot carry
/// a marker, an unreadable config).</returns>
/// <remarks>
/// Line scope edits the source file in place, keeping its encoding and every other
/// byte; unit and project scope edit only the config file. A refused call writes nothing.
/// Line scope refuses the routine-metric rules (their marker binds the measured value, which
/// only `drag-lint allow` measures) and the review-marker / parser-error ids, as allow does.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.RuleScope.Outcome, DRagLint.CLI.RuleScope.Report, DRagLint.CLI.RuleScope.RunConfigScope, DRagLint.CLI.RuleScope.RunLineScope, DRagLint.CLI.RuleScope.Validate, LowerCase, SameText, Trim</para>
/// <para>Returns: Res.Code</para>
/// <seealso cref="DRagLint.CLI.RuleScope.Outcome"/>
/// <seealso cref="DRagLint.CLI.RuleScope.Report"/>
/// <seealso cref="DRagLint.CLI.RuleScope.RunConfigScope"/>
/// <seealso cref="DRagLint.CLI.RuleScope.RunLineScope"/>
/// <seealso cref="DRagLint.CLI.RuleScope.Validate"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunRuleScope(const pAction, pRuleId, pScope, pFile: string; pLine: Integer;
  const pReason, pProject, pConfigPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  DRagLint.Lint.RuleCatalog,
  DRagLint.Lint.ReviewMarker,
  DRagLint.Lint.MarkerHash,
  DRagLint.Refactor.TextEdit;

const
  EXIT_DONE    = 0;
  EXIT_NOTHING = 1;
  EXIT_USAGE   = 2;
  SCOPE_LINE    = 'line';
  SCOPE_UNIT    = 'unit';
  SCOPE_PROJECT = 'project';
  ACTION_DISABLE = 'disable';
  CONFIG_NAME   = 'drag-lint-lint.json';
  STATE_DIR     = '_D-RAG';
  KEY_OVERRIDES = 'rule_overrides';
  KEY_UNITS     = 'exclude_units';
  KEY_ENABLED   = 'enabled';
  KEY_REASON    = 'reason';
  KEY_DATE      = 'date';
  KEY_DISABLED  = 'disabled';
  JSON_INDENT   = 2;
  ASCII_LAST    = #127;
  HEX_DIGITS    = 4;
  CATEGORY_MARKERS = 'review-markers';
  RULE_PARSER_ERROR = 'parser-error';

type
  { One call's inputs, so the helpers take one argument instead of nine. }
  TScopeRequest = record
    Disable : Boolean;
    RuleId  : string ;
    Scope   : string ;
    FileName: string ;
    Line    : Integer;
    Reason  : string ;
    Project : string ;
    Config  : string ;
    Json    : Boolean;
  end;

  { What a call did: the exit code, the file it wrote or would have written, a message. }
  TScopeOutcome = record
    Code   : Integer;
    Target : string ;
    Message: string ;
  end;

function Outcome(pCode: Integer; const pTarget, pMessage: string): TScopeOutcome;
begin
  Result.Code   := pCode;
  Result.Target := pTarget;
  Result.Message:= pMessage;
end;

function Today: string;
begin
  Result:= FormatDateTime('yyyy-mm-dd', Date);
end;

{ disable only: the id must be a catalogue rule, and one a human can accept. }
function CheckRuleForDisable(const pRuleId: string; out pMessage: string): Boolean;
begin
  pMessage:= '';
  for var RI: TRuleInfo in TRuleCatalog.BuildCatalog('', '') do
    if SameText(RI.Id, pRuleId) then
    begin
      if SameText(RI.Category, CATEGORY_MARKERS) or SameText(RI.Id, RULE_PARSER_ERROR) then
        pMessage:= Format('Rule "%s" cannot be disabled here: it is not a finding about code.', [pRuleId]);
      Exit(pMessage = '');
    end;
  pMessage:= Format('Unknown rule id: %s', [pRuleId]);
  Result:= False;
end;

{ ---------------------------------------------------------------- config file }

{ The nearest drag-lint-lint.json at or above pDir, the folder then its _D-RAG, as lint finds it. }
function FindConfigAbove(const pDir: string): string;
begin
  var Dir: string:= IncludeTrailingPathDelimiter(pDir);
  while Dir <> '' do
  begin
    Result:= TPath.Combine(Dir, CONFIG_NAME);
    if TFile.Exists(Result) then Exit;
    Result:= TPath.Combine(TPath.Combine(Dir, STATE_DIR), CONFIG_NAME);
    if TFile.Exists(Result) then Exit;
    var Parent: string:= ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break; { drive root reached }
    Dir:= Parent;
  end;
  Result:= '';
end;

function ResolveConfigPath(const pReq: TScopeRequest; out pPath, pMessage: string): Boolean;
begin
  pMessage:= '';
  pPath:= pReq.Config;
  if pPath = '' then
    if pReq.Project <> '' then
    begin
      var ProjDir: string:= ExtractFilePath(TPath.GetFullPath(pReq.Project));
      pPath:= TPath.Combine(ProjDir, CONFIG_NAME);
      var InState: string:= TPath.Combine(TPath.Combine(ProjDir, STATE_DIR), CONFIG_NAME);
      if (not TFile.Exists(pPath)) and TFile.Exists(InState) then pPath:= InState;
    end
    else if pReq.FileName <> '' then
      pPath:= FindConfigAbove(ExtractFilePath(TPath.GetFullPath(StringReplace(pReq.FileName, '/', '\', [rfReplaceAll]))));
  if pPath = '' then
    pMessage:= 'No project lint config found: pass --project <App.dproj> or --config <drag-lint-lint.json> ' +
      '(a new ' + CONFIG_NAME + ' is created beside the project).';
  Result:= pPath <> '';
end;

{ The config as a JSON object; an absent file is an empty object. nil + message when the
  file does not parse: rewriting it would destroy what the user wrote. }
function LoadConfigJson(const pPath: string; out pMessage: string): TJSONObject;
begin
  pMessage:= '';
  if not TFile.Exists(pPath) then Exit(TJSONObject.Create);
  var Parsed: TJSONValue:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pPath));  // dl:ok taint-path-traversal@7c13 -- REVIEWED 2026-11-17: v152 DISRULE: the path is the user's own --in / --config / --project argument; editing that file is the verb's job (same review as CLI.Explain)
  if Parsed is TJSONObject then Exit(TJSONObject(Parsed));
  Parsed.Free;
  pMessage:= Format('%s is not a JSON object; fix it by hand first (nothing was written).', [pPath]);
  Result:= nil;
end;

{ 7-bit ASCII + CRLF + a final CRLF; a non-ASCII character becomes a \uXXXX escape (same JSON value). }
procedure SaveConfigJson(const pPath: string; pRoot: TJSONObject);
begin
  var Text: string:= pRoot.Format(JSON_INDENT).Replace(#13#10, #10).Replace(#10, #13#10) + #13#10;
  var SB: TStringBuilder:= TStringBuilder.Create(Length(Text));
  try
    for var Ch: Char in Text do
      if Ch > ASCII_LAST then SB.Append('\u').Append(IntToHex(Ord(Ch), HEX_DIGITS))
      else SB.Append(Ch);
    TFile.WriteAllBytes(pPath, TEncoding.ASCII.GetBytes(SB.ToString));  // dl:ok taint-path-traversal@1a09 -- REVIEWED 2026-11-17: v152 DISRULE: the path is the user's own --in / --config / --project argument; editing that file is the verb's job (same review as CLI.Explain)
  finally
    SB.Free;
  end;
end;

{ The pair named pName (case-insensitive), or nil. }
function FindPair(pObj: TJSONObject; const pName: string): TJSONPair;
begin
  for var P: TJSONPair in pObj do
    if SameText(P.JsonString.Value, pName) then Exit(P);
  Result:= nil;
end;

procedure SetPair(pObj: TJSONObject; const pName: string; pValue: TJSONValue);
begin
  var Old: TJSONPair:= FindPair(pObj, pName);
  if Old <> nil then pObj.RemovePair(Old.JsonString.Value).Free;
  pObj.AddPair(pName, pValue);
end;

procedure DropPair(pObj: TJSONObject; const pName: string);
begin
  var Old: TJSONPair:= FindPair(pObj, pName);
  if Old <> nil then pObj.RemovePair(Old.JsonString.Value).Free;
end;

{ The object under pName, created (or replacing a non-object) when pCreate. }
function ChildObject(pObj: TJSONObject; const pName: string; pCreate: Boolean): TJSONObject;
begin
  var P: TJSONPair:= FindPair(pObj, pName);
  if (P <> nil) and (P.JsonValue is TJSONObject) then Exit(TJSONObject(P.JsonValue));
  if not pCreate then Exit(nil);
  Result:= TJSONObject.Create;
  SetPair(pObj, pName, Result);
end;

{ Removes pId (case-insensitive) from the array under pName; True when it was there. }
function RemoveFromArray(pObj: TJSONObject; const pName, pId: string): Boolean;
begin
  Result:= False;
  var P: TJSONPair:= FindPair(pObj, pName);
  if (P = nil) or (P.JsonValue is not TJSONArray) then Exit;
  var Arr: TJSONArray:= TJSONArray(P.JsonValue);
  for var i: Integer:= Arr.Count - 1 downto 0 do
    if SameText(Arr.Items[i].Value, pId) then
    begin
      Arr.Remove(i).Free;
      Result:= True;
    end;
end;

function ArrayContains(pObj: TJSONObject; const pName, pId: string): Boolean;
begin
  var P: TJSONPair:= FindPair(pObj, pName);
  if (P <> nil) and (P.JsonValue is TJSONArray) then
    for var V: TJSONValue in TJSONArray(P.JsonValue) do
      if SameText(V.Value, pId) then Exit(True);
  Result:= False;
end;

{ An entry with neither exclude_units nor enabled says nothing: drop it, and an empty block. }
procedure PruneEntry(pRoot, pOverrides: TJSONObject; const pRuleId: string);
begin
  var Entry: TJSONObject:= ChildObject(pOverrides, pRuleId, False);
  if Entry <> nil then
  begin
    var Units: TJSONPair:= FindPair(Entry, KEY_UNITS);
    if (Units <> nil) and (Units.JsonValue is TJSONArray) and (TJSONArray(Units.JsonValue).Count = 0) then
      DropPair(Entry, KEY_UNITS);
    if (FindPair(Entry, KEY_UNITS) = nil) and (FindPair(Entry, KEY_ENABLED) = nil) then
      DropPair(pOverrides, pRuleId);
  end;
  if pOverrides.Count = 0 then DropPair(pRoot, KEY_OVERRIDES);
end;

{ True when the pair holds the JSON literal false. }
function IsFalse(pPair: TJSONPair): Boolean;
begin
  Result:= (pPair <> nil) and (pPair.JsonValue is TJSONBool) and not TJSONBool(pPair.JsonValue).AsBoolean;
end;

function UnitOf(const pFileName: string): string;
begin
  Result:= ExtractFileName(StringReplace(pFileName, '/', '\', [rfReplaceAll]));
  var Ext: string:= ExtractFileExt(Result);
  if SameText(Ext, '.pas') or SameText(Ext, '.dfm') then Result:= ChangeFileExt(Result, '');
end;

{ Applies one unit / project disable or enable to the parsed config; False = nothing to do. }
function EditConfig(const pReq: TScopeRequest; pRoot: TJSONObject; out pWhat: string): Boolean;
begin
  var Overrides: TJSONObject:= ChildObject(pRoot, KEY_OVERRIDES, pReq.Disable);
  var Entry: TJSONObject:= nil;
  if Overrides <> nil then Entry:= ChildObject(Overrides, pReq.RuleId, pReq.Disable);
  var IsUnit: Boolean:= SameText(pReq.Scope, SCOPE_UNIT);
  var UnitName: string:= UnitOf(pReq.FileName);
  pWhat:= if IsUnit then Format('"%s" in unit %s', [pReq.RuleId, UnitName]) else Format('"%s" in this project', [pReq.RuleId]);
  if pReq.Disable then
  begin
    if IsUnit then
    begin
      Result:= not ArrayContains(Entry, KEY_UNITS, UnitName);
      if Result then
      begin
        if FindPair(Entry, KEY_UNITS) = nil then SetPair(Entry, KEY_UNITS, TJSONArray.Create);
        TJSONArray(FindPair(Entry, KEY_UNITS).JsonValue).Add(UnitName);
      end;
    end
    else
    begin
      var Enabled: TJSONPair:= FindPair(Entry, KEY_ENABLED);
      Result:= not IsFalse(Enabled);
      if Result then SetPair(Entry, KEY_ENABLED, TJSONBool.Create(False));
    end;
    if Result then
    begin
      SetPair(Entry, KEY_REASON, TJSONString.Create(pReq.Reason));
      SetPair(Entry, KEY_DATE, TJSONString.Create(Today));
    end;
    Exit;
  end;
  Result:= False;
  if IsUnit then
    Result:= (Entry <> nil) and RemoveFromArray(Entry, KEY_UNITS, UnitName)
  else
  begin
    var Enabled: TJSONPair:= if Entry <> nil then FindPair(Entry, KEY_ENABLED) else nil;
    if IsFalse(Enabled) then
    begin
      DropPair(Entry, KEY_ENABLED);
      Result:= True;
    end;
    { the Lint Options dock records a project-wide disable in the top-level "disabled" list }
    Result:= RemoveFromArray(pRoot, KEY_DISABLED, pReq.RuleId) or Result;
  end;
  if Overrides <> nil then PruneEntry(pRoot, Overrides, pReq.RuleId);
end;

function RunConfigScope(const pReq: TScopeRequest): TScopeOutcome;
var
  Path, Msg, What: string;
begin
  if SameText(pReq.Scope, SCOPE_UNIT) and (pReq.FileName = '') then
    Exit(Outcome(EXIT_USAGE, '', 'unit scope needs --in <Unit.pas> (the unit the rule is silenced in).'));
  if not ResolveConfigPath(pReq, Path, Msg) then Exit(Outcome(EXIT_USAGE, '', Msg));
  var Root: TJSONObject:= LoadConfigJson(Path, Msg);
  if Root = nil then Exit(Outcome(EXIT_USAGE, Path, Msg));
  try
    if not EditConfig(pReq, Root, What) then
      Exit(Outcome(EXIT_NOTHING, Path, if pReq.Disable then What + ' is already disabled'
                                       else 'nothing to enable: ' + What + ' is not disabled by ' + Path));
    SaveConfigJson(Path, Root);
  finally
    Root.Free;
  end;
  Result:= Outcome(EXIT_DONE, Path, (if pReq.Disable then 'disabled ' else 'enabled ') + What + ' (' + Path + ')');
end;

{ ---------------------------------------------------------------- line scope }

{ Replaces the text of 1-based line pLine in pRaw, keeping every line terminator. }
function SpliceLine(var pRaw: string; pLine: Integer; const pNewText: string): Boolean;
begin
  var P: Integer:= 1;
  var LN: Integer:= 1;
  while (LN < pLine) and (P <= Length(pRaw)) do
  begin
    if pRaw[P] = #10 then Inc(LN);
    Inc(P);
  end;
  if LN <> pLine then Exit(False);
  var LineEnd: Integer:= P;
  while (LineEnd <= Length(pRaw)) and not CharInSet(pRaw[LineEnd], [#13, #10]) do Inc(LineEnd);
  pRaw:= Copy(pRaw, 1, P - 1) + pNewText + Copy(pRaw, LineEnd, MaxInt);
  Result:= True;
end;

{ The marker line for disable; '' + message when the line cannot carry a reviewable marker. }
function MarkedLine(const pReq: TScopeRequest; const pLines: TArray<string>; pMarkLine: Integer;
  out pMessage: string): string;
begin
  pMessage:= '';
  var OldLine: string:= pLines[pMarkLine - 1];
  if IsRoutineMetricRule(pReq.RuleId) then
    pMessage:= Format('"%s" is a whole-routine metric rule: its marker records the measured value. ' +
      'Use `drag-lint allow %s --fix-line %d --fix-rule %s --apply`, or disable it for the unit or the project.',
      [pReq.RuleId, pReq.FileName, pReq.Line, pReq.RuleId])
  else if Trim(TReviewMarkers.NormalizeLine(OldLine)) = '' then
    pMessage:= Format('%s:%d carries no code (comment or blank line): a dl:ok marker there could never match.',
      [pReq.FileName, pReq.Line])
  else
  begin
    var Hash: string:= ExpectedHash(pLines, pReq.RuleId, pReq.Line, 0);
    Result:= TReviewMarkers.InsertInto(OldLine, pReq.RuleId, 'REVIEWED ' + Today + ': ' + pReq.Reason, Hash);
    for var Ch: Char in Result do
      if Ch > ASCII_LAST then pMessage:= 'the reason must be 7-bit ASCII (the source file stays ASCII).';
    var RoundTrip: Boolean:= False;
    for var M: TReviewMarker in TReviewMarkers.Parse(Result) do
      RoundTrip:= RoundTrip or SameText(M.RuleId, pReq.RuleId);
    if (pMessage = '') and not RoundTrip then
      pMessage:= Format('a dl:ok marker on %s:%d would not parse back (block comment or string literal); ' +
        'disable the rule for the unit instead.', [pReq.FileName, pReq.Line]);
    if pMessage = '' then Exit;
  end;
  Result:= '';
end;

function RunLineScope(const pReq: TScopeRequest): TScopeOutcome;
var
  Raw, Msg: string;
begin
  if (pReq.FileName = '') or (pReq.Line <= 0) then
    Exit(Outcome(EXIT_USAGE, '', 'line scope needs --in <Unit.pas> and --line <N>.'));
  if not TFile.Exists(pReq.FileName) then Exit(Outcome(EXIT_USAGE, '', 'File not found: ' + pReq.FileName));
  var Fmt: TTextFileFormat:= TTextFileFormat.Decode(TFile.ReadAllBytes(pReq.FileName), Raw);  // dl:ok taint-path-traversal@ecf3 -- REVIEWED 2026-11-17: v152 DISRULE: the path is the user's own --in / --config / --project argument; editing that file is the verb's job (same review as CLI.Explain)
  var Lines: TArray<string>:= Raw.Replace(#13#10, #10).Split([#10]);
  if pReq.Line > Length(Lines) then
    Exit(Outcome(EXIT_USAGE, pReq.FileName, Format('Line %d is past the end of %s', [pReq.Line, pReq.FileName])));
  { a finding on a /// line is reviewed on the declaration the block documents (as allow does) }
  var MarkLine: Integer:= DocCommentMarkerLine(Lines, pReq.Line);
  var OldLine : string := Lines[MarkLine - 1];
  var NewLine : string;
  if pReq.Disable then
  begin
    NewLine:= MarkedLine(pReq, Lines, MarkLine, Msg);
    if Msg <> '' then Exit(Outcome(EXIT_USAGE, pReq.FileName, Msg));
  end
  else NewLine:= TReviewMarkers.RemoveFrom(OldLine, pReq.RuleId);
  if NewLine = OldLine then
    Exit(Outcome(EXIT_NOTHING, pReq.FileName, Format(if pReq.Disable then '%s:%d already allows "%s"'
      else 'nothing to enable: %s:%d carries no dl:ok marker for "%s"', [pReq.FileName, MarkLine, pReq.RuleId])));
  SpliceLine(Raw, MarkLine, NewLine);
  TFile.WriteAllBytes(pReq.FileName, Fmt.Encode(Raw));  // dl:ok taint-path-traversal@bf7e -- REVIEWED 2026-11-17: v152 DISRULE: the path is the user's own --in / --config / --project argument; editing that file is the verb's job (same review as CLI.Explain)
  Result:= Outcome(EXIT_DONE, pReq.FileName, Format('%s "%s" on %s:%d',
    [if pReq.Disable then 'disabled' else 'enabled', pReq.RuleId, pReq.FileName, MarkLine]));
end;

{ ---------------------------------------------------------------- entry point }

procedure Report(const pReq: TScopeRequest; const pOut: TScopeOutcome);
begin
  if not pReq.Json then
  begin
    { stdout, refusals included (as allow does): the IDE command captures stdout only }
    Writeln(if pOut.Code = EXIT_USAGE then 'rules: ' + pOut.Message else pOut.Message);
    Exit;
  end;
  var J: TJSONObject:= TJSONObject.Create;
  try
    J.AddPair('action', if pReq.Disable then ACTION_DISABLE else 'enable');
    J.AddPair('rule', pReq.RuleId);
    J.AddPair('scope', pReq.Scope);
    J.AddPair(if SameText(pReq.Scope, SCOPE_LINE) then 'file' else 'config', pOut.Target);
    if SameText(pReq.Scope, SCOPE_LINE) then J.AddPair('line', TJSONNumber.Create(pReq.Line));
    J.AddPair('changed', TJSONBool.Create(pOut.Code = EXIT_DONE));
    J.AddPair('exit', TJSONNumber.Create(pOut.Code));
    J.AddPair('message', pOut.Message);
    Writeln(J.ToJSON);
  finally
    J.Free;
  end;
end;

function Validate(const pReq: TScopeRequest; const pAction: string; out pMessage: string): Boolean;
begin
  pMessage:= '';
  if not (SameText(pAction, ACTION_DISABLE) or SameText(pAction, 'enable')) then
    pMessage:= 'Usage: drag-lint rules disable|enable --rule <id> --scope line|unit|project ...'
  else if pReq.RuleId = '' then pMessage:= 'missing --rule <id>.'
  else if not (SameText(pReq.Scope, SCOPE_LINE) or SameText(pReq.Scope, SCOPE_UNIT) or SameText(pReq.Scope, SCOPE_PROJECT)) then
    pMessage:= Format('--scope must be line, unit or project (got "%s").', [pReq.Scope])
  else if pReq.Disable and (Trim(pReq.Reason) = '') then
    pMessage:= 'disable needs --reason "<one line>": it is stored beside the entry.'
  else if pReq.Disable then CheckRuleForDisable(pReq.RuleId, pMessage);
  Result:= pMessage = '';
end;

function RunRuleScope(const pAction, pRuleId, pScope, pFile: string; pLine: Integer;  // dl:ok too-many-parameters@c2ad -- REVIEWED 2026-11-17 v152 FRAME: one positional per CLI flag keeps the CLI.pas dispatch a single line with no options builder there (FRAME contract, TT plan section 6 E1 shape)
  const pReason, pProject, pConfigPath: string; pJson: Boolean): Integer;
var
  Req: TScopeRequest;
  Msg: string;
  Res: TScopeOutcome;
begin
  Req.Disable := SameText(pAction, ACTION_DISABLE);
  Req.RuleId  := Trim(pRuleId);
  Req.Scope   := LowerCase(Trim(pScope));
  Req.FileName:= pFile;
  Req.Line    := pLine;
  Req.Reason  := Trim(pReason);
  Req.Project := pProject;
  Req.Config  := pConfigPath;
  Req.Json    := pJson;
  Res:= if not Validate(Req, pAction, Msg) then Outcome(EXIT_USAGE, '', Msg)
        else if Req.Scope = SCOPE_LINE then RunLineScope(Req)
        else RunConfigScope(Req);
  Report(Req, Res);
  Result:= Res.Code;
end;

end.
