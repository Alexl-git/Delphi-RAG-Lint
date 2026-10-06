unit ConvRules.ConvertRun;

{ Pure decisions behind the Convert tab (spec 2026-09-29, part 2): backup
  names, what a rule book contains, book order, which source units a dropped
  path stands for, the pre-flight verdict, and the reading of convert-apply's
  apply/1 JSON. No UI and no engine calls -- ConvRules.ConvertRunner executes,
  ConvRules.ConvertTab renders; ConvRulesModelTests.dpr pins every rule here. }

interface

uses
  System.SysUtils
  , ConvRules.UnitStatus
  ;

type
  /// <summary>What a rule book holds, as far as the Convert tab cares.</summary>
  /// <remarks>bkUnitsOnly books cannot run until the engine applies unit rules
  /// (capability apply_unit_rules); bkMixed books run their #convert blocks and
  /// report their unit rules as not applied.</remarks>
  TBookKind = (bkEmpty, bkConvertOnly, bkUnitsOnly, bkMixed);

  /// <summary>One line of the Convert tab's book checklist.</summary>
  TBookEntry = record
    /// <summary>Full path of the .rules file.</summary>
    Path   : string;
    /// <summary>The user's check.</summary>
    Checked: Boolean;
    /// <summary>BookKindOfText of the file's text.</summary>
    Kind   : TBookKind;
  end;

  /// <summary>One inherited / inline instance convert-apply left unconverted (apply/1
  /// `inherited[]`, engine C8 N1; key names follow the engine's merge notice).</summary>
  TInheritedLeft = record
    /// <summary>`name` -- the instance.</summary>
    Name         : string;
    /// <summary>`type` -- its class.</summary>
    TypeName     : string;
    /// <summary>`line` -- its .dfm line; 0 when absent or not an integer.</summary>
    Line         : Integer;
    /// <summary>`ancestor_unit` -- the declaring ancestor's unit.</summary>
    AncestorUnit : string;
    /// <summary>`ancestor_state` -- unconverted / converted / outside.</summary>
    AncestorState: string;
    /// <summary>`reason` -- the engine's words.</summary>
    Reason       : string;
  end;

  /// <summary>One convert-apply run, read from its apply/1 JSON.</summary>
  TApplyRow = record
    /// <summary>The engine's own ok flag; False also for unparseable output.</summary>
    Ok        : Boolean;
    /// <summary>The engine declined the unit (apply/1 "refused": true -- inherited
    /// instances, an {$IFDEF} in a uses clause, a stale .dfm span) and did not touch
    /// it. A known limitation, not a fault. Ok is False; Error holds the engine's
    /// "reason".</summary>
    Refused   : Boolean;
    /// <summary>'' when Ok; else the engine's refusal reason, the engine error,
    /// the first rule error ("line N: message") or the head of the unparseable
    /// output.</summary>
    Error     : string;
    /// <summary>edits_count.</summary>
    EditsCount: Integer;
    /// <summary>rule_errors[] length. Greater than 0 = the BOOK failed the
    /// engine's validation (measured 2026-09-29: ok=false, error "conversion
    /// rules failed validation", file untouched) -- a book fault, not a unit
    /// fault.</summary>
    RuleErrorCount: Integer;
    /// <summary>converted[] -- one line per converted instance.</summary>
    Converted : TArray<string>;
    /// <summary>todos[] + reemit_notes[] + warnings[] -- the manual remainder.</summary>
    Remainder : TArray<string>;
    /// <summary>inherited[] -- the instances left unconverted; empty for an engine
    /// without inherited_instances (it refuses such a unit instead). A non-object
    /// entry is skipped; a missing or wrongly-typed field reads as '' / 0.</summary>
    InheritedLeft: TArray<TInheritedLeft>;
  end;

  /// <summary>The verdict before any file is touched.</summary>
  TPreflight = record
    /// <summary>False = refuse the run; Problems says why.</summary>
    Ok      : Boolean;
    /// <summary>Reasons the run is refused.</summary>
    Problems: TArray<string>;
    /// <summary>Checked books that will run, in list (application) order.</summary>
    Runnable: TArray<string>;
    /// <summary>Non-fatal facts for the results (skipped unit-rules books,
    /// unit rules a mixed book will not apply).</summary>
    Notes   : TArray<string>;
  end;

/// <summary>The backup paths for ONE unit's files, sharing one number: N is one
/// above the highest existing .BCK&lt;N&gt; over ALL of AFiles, so a unit's .pas
/// and .dfm restore points pair up by number (X.pas.BCK1 + X.dfm.BCK3 -> both
/// get .BCK4). Gaps are not reused, so N orders backups in time.</summary>
/// <param name="AFiles">The unit's files (its .pas and its .dfm), whether or
/// not each exists -- a stale X.dfm.BCK&lt;N&gt; still counts.</param>
/// <param name="AExists">File-existence probe (injected for tests).</param>
/// <returns>AFiles[i] + '.BCK' + N, in AFiles order; none of them exists yet.</returns>
function SharedBackupPaths(const AFiles: TArray<string>; const AExists: TFileProbe): TArray<string>;

/// <summary>Classifies a rule book by the directives it holds.</summary>
/// <param name="ARulesText">The .rules text.</param>
/// <returns>bkEmpty (no #convert, no unit rule), bkConvertOnly, bkUnitsOnly or bkMixed.</returns>
function BookKindOfText(const ARulesText: string): TBookKind;

/// <summary>AEntries with entry AIndex moved ADelta places (clamped to the ends).</summary>
/// <param name="AEntries">The checklist, in application order.</param>
/// <param name="AIndex">The entry to move.</param>
/// <param name="ADelta">-1 = up, +1 = down.</param>
/// <returns>A new array; AEntries unchanged when the move is out of range.</returns>
function MoveEntry(const AEntries: TArray<TBookEntry>; AIndex, ADelta: Integer): TArray<TBookEntry>;

/// <summary>The .pas files APaths stand for: a .pas is itself, a folder its
/// *.pas (not recursive), a .dpr its member files that exist, a .dproj its
/// MainSource .dpr's members.</summary>
/// <param name="APaths">Dropped / added paths.</param>
/// <param name="AErrors">One line per path that could not be expanded.</param>
/// <returns>Full paths, first occurrence order, de-duplicated case-insensitively.</returns>
/// <remarks>A .dpr member is an entry WITH an `in '...'` path; a plain entry
/// (Vcl.Forms) is a library unit, neither expanded nor reported.</remarks>
function ExpandSources(const APaths: TArray<string>; out AErrors: TArray<string>): TArray<string>;

/// <summary>True when the FILE AUnitPas is one of AIndexedFiles: both sides
/// ExpandFileName'd, compared case-insensitively.</summary>
/// <param name="AUnitPas">A .pas path.</param>
/// <param name="AIndexedFiles">File paths in the project index (its `files`
/// table, TEngineAdapter.ListIndexedFiles).</param>
/// <returns>True = indexed.</returns>
/// <remarks>By PATH, never by unit name: convert-apply locates a unit's .dfm
/// block by its path, and the migration case is a same-named unit in another
/// tree (M2022\DM1.pas beside the project's own DM1.pas) -- a name match would
/// pass a unit the engine then cannot find.</remarks>
function UnitInIndex(const AUnitPas: string; const AIndexedFiles: TArray<string>): Boolean;

/// <summary>PURE: where the FILE APath is in APaths, by UnitInIndex's compare (both
/// sides ExpandFileName'd, case-insensitively).</summary>
/// <param name="APath">A file path.</param>
/// <param name="APaths">The paths to search.</param>
/// <returns>The first matching index; -1 when absent.</returns>
function PathIndex(const APath: string; const APaths: TArray<string>): Integer;

/// <summary>The Convert tab's DISPLAYED text for one source row.</summary>
/// <param name="AUnitPas">The listed .pas path. It stays the item string --
/// the job and Preflight consume it -- so only the display changes.</param>
/// <param name="AIndexedFiles">File paths in the project index (see UnitInIndex).</param>
/// <param name="AIndexKnown">False when the index could not be read: then
/// nothing is flagged -- unknown is never reported as indexed OR unindexed.</param>
/// <param name="AFlagged">True = the unit is known NOT to be in the index.</param>
/// <returns>AUnitPas, plus ' -- not in the project index' when AFlagged.</returns>
function SourceRowText(const AUnitPas: string; const AIndexedFiles: TArray<string>; AIndexKnown: Boolean; out AFlagged: Boolean): string;

/// <summary>Decides whether a Convert run may start, and which books run.</summary>
/// <param name="ABooks">The checklist.</param>
/// <param name="AUnits">The source units (.pas paths).</param>
/// <param name="AIndexedFiles">File paths in the project index (see UnitInIndex).</param>
/// <param name="AUnitRulesSupported">The engine reports apply_unit_rules.</param>
/// <returns>Ok=False when no book is checked, no unit is listed, or a unit's
/// FILE is not in the index (convert-apply would report a FALSE "could not
/// locate .dfm object block" for it); Runnable = checked books minus empty ones
/// and minus unit-rules-only ones while unsupported.</returns>
function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedFiles: TArray<string>; AUnitRulesSupported: Boolean): TPreflight;

/// <summary>Reads convert-apply's --format json output (schema apply/1).</summary>
/// <param name="AJson">The engine's merged stdout+stderr; text before the first
/// '{' and after the last '}' (the "(loaded defaults ...)" line) is ignored.</param>
/// <returns>See TApplyRow; never raises.</returns>
function ParseApplyJson(const AJson: string): TApplyRow;

/// <summary>PURE: the converted row's note for what was left (spec E10).</summary>
/// <param name="AItems">TApplyRow.InheritedLeft.</param>
/// <param name="AConvertedUnits">Unit names (no path, no extension) converted EARLIER IN
/// THE SAME RUN: an item whose ancestor_unit is one of them is not counted (spec E11 /
/// N2a: that run converts it).</param>
/// <returns>'' for none; else per (ancestor, state) in first-seen order 'N inherited
/// instance(s) left: ancestor &lt;U&gt; not converted' ('not in the index' for outside,
/// the raw state otherwise), joined '; '.</returns>
function InheritedLeftNote(const AItems: TArray<TInheritedLeft>; const AConvertedUnits: TArray<string> = nil): string;

/// <summary>PURE: one run-report note for one left instance.</summary>
/// <param name="AItem">The instance.</param>
/// <returns>'&lt;name&gt;: &lt;type&gt; line N -- ancestor &lt;U&gt; &lt;state&gt; (&lt;reason&gt;)'.</returns>
function InheritedReportNote(const AItem: TInheritedLeft): string;

/// <summary>PURE: AItems without those whose ancestor_unit converted EARLIER IN THE SAME
/// RUN (spec E11 / N2a: that run converts them too; ruling R4).</summary>
/// <param name="AItems">TApplyRow.InheritedLeft.</param>
/// <param name="AConvertedUnits">Unit names converted earlier in the run
/// (ConvertRunner.UnitsConvertedIn); matched case-insensitively.</param>
/// <returns>The kept items, AItems order.</returns>
function InheritedLeftOmitting(const AItems: TArray<TInheritedLeft>; const AConvertedUnits: TArray<string>): TArray<TInheritedLeft>;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , System.JSON
  , System.Math
  , System.StrUtils
  , ConvRules.Model
  , ConvRules.UsesHarvest
  ;

const
  BCK_TAG          = '.BCK';
  ERR_HEAD_CHARS   = 200;
  BCK_PROBE_WINDOW = 50;

// The highest N with AFile + '.BCK' + N present; 0 when there is none.
function HighestBackupN(const AFile: string; const AExists: TFileProbe): Integer;
var
  N: Integer;
begin
  Result:= 0;
  N:= 1;
  // Probe upward until a run of misses longer than any plausible gap; the
  // convention in ORM3\CLIENT stays in single digits.
  while N <= Result + BCK_PROBE_WINDOW do
  begin
    if AExists(AFile + BCK_TAG + IntToStr(N)) then
      Result:= N;
    Inc(N);
  end;
end;


function SharedBackupPaths(const AFiles: TArray<string>; const AExists: TFileProbe): TArray<string>;
var
  Highest: Integer;
begin
  Highest:= 0;
  for var LFile: string in AFiles do
    Highest:= Max(Highest, HighestBackupN(LFile, AExists));
  Result:= nil;
  for var LFile: string in AFiles do
    Result:= Result + [LFile + BCK_TAG + IntToStr(Highest + 1)];
end;

function BookKindOfText(const ARulesText: string): TBookKind;
var
  Book    : TRuleBook;
  HasConv : Boolean;
  HasUnits: Boolean;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(ARulesText);
    HasConv := Length(Book.ConvertHeaders) > 0;
    HasUnits:= Length(Book.UnitNodes) > 0;
  finally
    Book.Free;
  end; // try
  if HasConv and HasUnits then
    Result:= bkMixed
  else if HasConv then
    Result:= bkConvertOnly
  else if HasUnits then
    Result:= bkUnitsOnly
  else
    Result:= bkEmpty;
end;

function MoveEntry(const AEntries: TArray<TBookEntry>; AIndex, ADelta: Integer): TArray<TBookEntry>;
var
  Target: Integer;
  Tmp   : TBookEntry;
begin
  Result:= Copy(AEntries);
  Target:= AIndex + ADelta;
  if (AIndex < 0) or (AIndex > High(Result)) or (Target < 0) or (Target > High(Result)) then
    Exit;
  Tmp:= Result[AIndex];
  Result[AIndex]:= Result[Target];
  Result[Target]:= Tmp;
end;

function ExpandSources(const APaths: TArray<string>; out AErrors: TArray<string>): TArray<string>;
var
  Found: TArray<string>;

  procedure AddPas(const AFile: string);
  begin
    if not MatchText(AFile, Found) then
      Found:= Found + [AFile];
  end;

  // A locked or unreadable file becomes one AErrors line, never an exception:
  // this runs on Explorer drops, and a bad project must not crash a drop.
  function TryRead(const AFile: string; out AText: string): Boolean;
  begin
    AText:= '';
    try
      AText:= TFile.ReadAllText(AFile);
      Result:= True;
    except
      on E: Exception do
      begin
        AErrors:= AErrors + [Format('%s: cannot read (%s)', [ExtractFileName(AFile), E.Message])];
        Result:= False;
      end;
    end; // try
  end;

  procedure AddDpr(const ADpr: string);
  var
    LText: string;
  begin
    if not TryRead(ADpr, LText) then
      Exit;
    for var LMember: TDprMember in ReadDprMembers(LText, ExtractFilePath(ADpr)) do
      if LMember.FilePath = '' then
        Continue // a plain entry (Vcl.Forms) is a library unit, not a member
      else if TFile.Exists(LMember.FilePath) then
        AddPas(TPath.GetFullPath(LMember.FilePath))
      else
        AErrors:= AErrors + [Format('%s: member %s not found (%s)', [ExtractFileName(ADpr), LMember.UnitName, LMember.FilePath])];
  end;

var
  P  : string;
  Ext: string;
begin
  Found  := nil;
  AErrors:= nil;
  for P in APaths do
  begin
    Ext:= LowerCase(ExtractFileExt(P));
    if TDirectory.Exists(P) then
    begin
      for var LFile: string in TDirectory.GetFiles(P, '*.pas') do
        AddPas(TPath.GetFullPath(LFile));
    end
    else if not TFile.Exists(P) then
      AErrors:= AErrors + [P + ': not found']
    else if Ext = '.pas' then
      AddPas(TPath.GetFullPath(P))
    else if Ext = '.dpr' then
      AddDpr(P)
    else if Ext = '.dproj' then
    begin
      var LProj: string;
      if TryRead(P, LProj) then
      begin
        var LMain: string:= MainSourceOf(LProj, ExtractFilePath(P));
        if (LMain <> '') and TFile.Exists(LMain) then
          AddDpr(LMain)
        else
          AErrors:= AErrors + [ExtractFileName(P) + ': no MainSource .dpr found'];
      end;
    end
    else
      AErrors:= AErrors + [P + ': not a .pas, .dpr, .dproj or folder'];
  end; // for
  Result:= Found;
end;

function PathIndex(const APath: string; const APaths: TArray<string>): Integer;
var
  LFull: string;
begin
  LFull:= ExpandFileName(APath);
  for var I: Integer:= 0 to High(APaths) do
    if SameText(ExpandFileName(APaths[I]), LFull) then
      Exit(I);
  Result:= -1;
end;

function UnitInIndex(const AUnitPas: string; const AIndexedFiles: TArray<string>): Boolean;
begin
  Result:= PathIndex(AUnitPas, AIndexedFiles) >= 0;
end;

function SourceRowText(const AUnitPas: string; const AIndexedFiles: TArray<string>; AIndexKnown: Boolean; out AFlagged: Boolean): string;
begin
  AFlagged:= AIndexKnown and not UnitInIndex(AUnitPas, AIndexedFiles);
  Result  := AUnitPas;
  if AFlagged then
    Result:= Result + ' -- not in the project index';
end;

function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedFiles: TArray<string>; AUnitRulesSupported: Boolean): TPreflight;
var
  B       : TBookEntry;
  U       : string;
  Missing : TArray<string>;
  AnyCheck: Boolean;
begin
  Result:= Default(TPreflight);
  AnyCheck:= False;
  for B in ABooks do
  begin
    if not B.Checked then
      Continue;
    AnyCheck:= True;
    case B.Kind of
      bkEmpty:
        Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': no #convert and no unit rule -- skipped'];
      bkUnitsOnly:
        if AUnitRulesSupported then
          Result.Runnable:= Result.Runnable + [B.Path]
        else
          Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': unit rules: engine support pending -- skipped'];
      bkMixed:
      begin
        Result.Runnable:= Result.Runnable + [B.Path];
        if not AUnitRulesSupported then
          Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': its unit rules are not applied (engine support pending)'];
      end;
      else
        Result.Runnable:= Result.Runnable + [B.Path];
    end; // case
  end; // for
  if not AnyCheck then
    Result.Problems:= Result.Problems + ['No rule book is checked.'];
  if Length(AUnits) = 0 then
    Result.Problems:= Result.Problems + ['No source unit is listed.'];
  Missing:= nil;
  for U in AUnits do
    if not UnitInIndex(U, AIndexedFiles) then
      Missing:= Missing + [ExtractFileName(U)];
  if Length(Missing) > 0 then
    Result.Problems:= Result.Problems + [Format('Not in the project index (index the project first): %s', [string.Join(', ', Missing)])];
  if AnyCheck and (Length(Result.Runnable) = 0) and (Length(Result.Problems) = 0) then
    Result.Problems:= Result.Problems + ['None of the checked rule books can run (see notes).'];
  Result.Ok:= Length(Result.Problems) = 0;
end;

function ParseApplyJson(const AJson: string): TApplyRow;

  function Strings(AObj: TJSONObject; const AKey: string): TArray<string>;
  var
    Arr: TJSONArray;
  begin
    Result:= nil;
    if AObj.TryGetValue<TJSONArray>(AKey, Arr) then
      for var LVal: TJSONValue in Arr do
        Result:= Result + [LVal.Value];
  end;

  // A JSON string member's text; '' when absent or of another JSON type
  // (TJSONNumber descends from TJSONString, so it is excluded by name).
  function Str(AObj: TJSONObject; const AKey: string): string;
  var
    LVal: TJSONValue;
  begin
    LVal:= AObj.Values[AKey];
    Result:= if (LVal is TJSONString) and not (LVal is TJSONNumber) then LVal.Value else '';
  end;

  // apply/1 inherited[] (C8 N1). Read type-checked, never by GetValue<T>: a
  // malformed entry must not cost the whole row (GetValue raises on a mismatch).
  function InheritedItems(AObj: TJSONObject): TArray<TInheritedLeft>;
  var
    LItem: TInheritedLeft;
    LNum : TJSONValue;
  begin
    Result:= nil;
    if not (AObj.Values['inherited'] is TJSONArray) then
      Exit;
    for var LVal: TJSONValue in TJSONArray(AObj.Values['inherited']) do
      if LVal is TJSONObject then
      begin
        LItem:= Default(TInheritedLeft);
        LItem.Name         := Str(TJSONObject(LVal), 'name');
        LItem.TypeName     := Str(TJSONObject(LVal), 'type');
        LItem.AncestorUnit := Str(TJSONObject(LVal), 'ancestor_unit');
        LItem.AncestorState:= Str(TJSONObject(LVal), 'ancestor_state');
        LItem.Reason       := Str(TJSONObject(LVal), 'reason');
        LNum:= TJSONObject(LVal).Values['line'];
        if not ((LNum is TJSONNumber) and TryStrToInt(LNum.Value, LItem.Line)) then
          LItem.Line:= 0;
        Result:= Result + [LItem];
      end;
  end;

var
  Root: TJSONValue;
  Obj : TJSONObject;
  Errs: TJSONArray;
  Text: string;
begin
  Result:= Default(TApplyRow);
  Errs:= nil;
  // stderr is merged into the pipe: skip anything before the document, and --
  // measured 2026-09-29, the engine's "(loaded defaults ...)" line lands AFTER
  // it -- anything after the last '}' (ParseJSONValue rejects trailing text).
  Text:= Trim(AJson);
  if (Text <> '') and (Text[1] <> '{') and (Pos('{', Text) > 0) then
    Text:= Copy(Text, Pos('{', Text), MaxInt);
  if (Text <> '') and (Text[1] = '{') then
    Text:= Copy(Text, 1, LastDelimiter('}', Text));
  Root:= TJSONObject.ParseJSONValue(Text);
  try
    if not (Root is TJSONObject) then
    begin
      Result.Error:= 'unparseable engine output: ' + Copy(Trim(AJson), 1, ERR_HEAD_CHARS);
      Exit;
    end;
    Obj:= TJSONObject(Root);
    Result.Ok        := Obj.GetValue<Boolean>('ok', False);
    Result.EditsCount:= Obj.GetValue<Integer>('edits_count', 0);
    Result.Converted := Strings(Obj, 'converted');
    Result.Remainder := Strings(Obj, 'todos') + Strings(Obj, 'reemit_notes') + Strings(Obj, 'warnings');
    Result.InheritedLeft:= InheritedItems(Obj);
    if Obj.TryGetValue<TJSONArray>('rule_errors', Errs) then
      Result.RuleErrorCount:= Errs.Count;
    Result.Refused:= (not Result.Ok) and Obj.GetValue<Boolean>('refused', False);
    if Result.Refused then
    begin
      Result.Error:= Obj.GetValue<string>('reason', '');
      if Result.Error = '' then
        Result.Error:= 'convert-apply refused the unit and gave no reason';
    end
    else if not Result.Ok then
    begin
      // The first rule error is more useful than the generic "conversion rules
      // failed validation" the engine puts in 'error'.
      if Result.RuleErrorCount > 0 then
        Result.Error:= Format('line %d: %s', [Errs.Items[0].GetValue<Integer>('line', 0), Errs.Items[0].GetValue<string>('message', '')])
      else
        Result.Error:= Obj.GetValue<string>('error', '');
      if Result.Error = '' then
        Result.Error:= 'convert-apply reported ok=false with no reason';
    end;
  finally
    Root.Free;
  end; // try
end;

const
  LEFT_FMT        = '%d inherited instance(s) left: ancestor %s %s';
  STATE_UNCONV    = 'unconverted';
  STATE_OUTSIDE   = 'outside';
  WORDS_UNCONV    = 'not converted';
  WORDS_OUTSIDE   = 'not in the index';
  REPORT_LEFT_FMT = '%s: %s line %d -- ancestor %s %s (%s)';

function InheritedLeftNote(const AItems: TArray<TInheritedLeft>; const AConvertedUnits: TArray<string>): string;
var
  LGroups: TArray<TInheritedLeft>; // one per (ancestor, state), first-seen order
  LCounts: TArray<Integer>;
  LIdx   : Integer;
  LParts : TArray<string>;
  LWords : string;
begin
  LGroups:= nil;
  LCounts:= nil;
  for var LItem: TInheritedLeft in InheritedLeftOmitting(AItems, AConvertedUnits) do
  begin
    LIdx:= High(LGroups);
    while (LIdx >= 0) and not (SameText(LGroups[LIdx].AncestorUnit, LItem.AncestorUnit) and SameText(LGroups[LIdx].AncestorState, LItem.AncestorState)) do
      Dec(LIdx);
    if LIdx < 0 then
    begin
      LGroups:= LGroups + [LItem];
      LCounts:= LCounts + [0];
      LIdx   := High(LGroups);
    end;
    Inc(LCounts[LIdx]);
  end;
  LParts:= nil;
  for var I: Integer:= 0 to High(LGroups) do
  begin
    LWords:= LGroups[I].AncestorState;
    if SameText(LWords, STATE_UNCONV) then
      LWords:= WORDS_UNCONV
    else if SameText(LWords, STATE_OUTSIDE) then
      LWords:= WORDS_OUTSIDE;
    LParts:= LParts + [Format(LEFT_FMT, [LCounts[I], LGroups[I].AncestorUnit, LWords])];
  end;
  Result:= string.Join('; ', LParts);
end;

function InheritedLeftOmitting(const AItems: TArray<TInheritedLeft>; const AConvertedUnits: TArray<string>): TArray<TInheritedLeft>;
begin
  Result:= nil;
  for var LItem: TInheritedLeft in AItems do
    if not MatchText(LItem.AncestorUnit, AConvertedUnits) then
      Result:= Result + [LItem];
end;

function InheritedReportNote(const AItem: TInheritedLeft): string;
begin
  Result:= Format(REPORT_LEFT_FMT, [AItem.Name, AItem.TypeName, AItem.Line, AItem.AncestorUnit, AItem.AncestorState, AItem.Reason]);
end;

end.
