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

  /// <summary>One convert-apply run, read from its apply/1 JSON.</summary>
  TApplyRow = record
    /// <summary>The engine's own ok flag; False also for unparseable output.</summary>
    Ok        : Boolean;
    /// <summary>'' when Ok; else the engine error, the first rule error
    /// ("line N: message") or the head of the unparseable output.</summary>
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

/// <summary>The backup path for AFile: AFile + '.BCK' + N, N one above the
/// highest existing N (gaps are not reused, so N orders backups in time).</summary>
/// <param name="AFile">The file about to be changed.</param>
/// <param name="AExists">File-existence probe (injected for tests).</param>
/// <returns>A path that does not exist yet.</returns>
function NextBackupPath(const AFile: string; const AExists: TFileProbe): string;

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

/// <summary>Decides whether a Convert run may start, and which books run.</summary>
/// <param name="ABooks">The checklist.</param>
/// <param name="AUnits">The source units (.pas paths).</param>
/// <param name="AIndexedUnits">Unit names in the project index (any case).</param>
/// <param name="AUnitRulesSupported">The engine reports apply_unit_rules.</param>
/// <returns>Ok=False when no book is checked, no unit is listed, or a unit is
/// not in the index (convert-apply would report a FALSE "could not locate .dfm
/// object block" for it); Runnable = checked books minus empty ones and minus
/// unit-rules-only ones while unsupported.</returns>
function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedUnits: TArray<string>; AUnitRulesSupported: Boolean): TPreflight;

/// <summary>Reads convert-apply's --format json output (schema apply/1).</summary>
/// <param name="AJson">The engine's merged stdout+stderr; text before the first
/// '{' and after the last '}' (the "(loaded defaults ...)" line) is ignored.</param>
/// <returns>See TApplyRow; never raises.</returns>
function ParseApplyJson(const AJson: string): TApplyRow;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , System.JSON
  , System.StrUtils
  , ConvRules.Model
  , ConvRules.UsesHarvest
  ;

const
  BCK_TAG          = '.BCK';
  ERR_HEAD_CHARS   = 200;
  BCK_PROBE_WINDOW = 50;

function NextBackupPath(const AFile: string; const AExists: TFileProbe): string;
var
  N: Integer;
  Highest: Integer;
begin
  Highest:= 0;
  N:= 1;
  // Probe upward until a run of misses longer than any plausible gap; the
  // convention in ORM3\CLIENT stays in single digits.
  while N <= Highest + BCK_PROBE_WINDOW do
  begin
    if AExists(AFile + BCK_TAG + IntToStr(N)) then
      Highest:= N;
    Inc(N);
  end;
  Result:= AFile + BCK_TAG + IntToStr(Highest + 1);
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

function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedUnits: TArray<string>; AUnitRulesSupported: Boolean): TPreflight;
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
    if not MatchText(ChangeFileExt(ExtractFileName(U), ''), AIndexedUnits) then
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
    if Obj.TryGetValue<TJSONArray>('rule_errors', Errs) then
      Result.RuleErrorCount:= Errs.Count;
    if not Result.Ok then
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

end.
