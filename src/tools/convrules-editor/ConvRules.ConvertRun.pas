unit ConvRules.ConvertRun;

{ Pure decisions behind the Convert tab (spec 2026-09-29, part 2): backup
  names, what a rule book contains, book order, which source units a dropped
  path stands for, the pre-flight verdict, and the reading of convert-apply's
  apply/1 JSON. No UI and no engine calls -- ConvRules.ConvertRunner executes,
  ConvRules.ConvertTab renders; ConvRulesModelTests.dpr pins every rule here. }

interface

uses
  System.SysUtils
  , ConvRules.Glyph
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
    /// <summary>True when the book holds a #link with a glyph expression (BookHasGlyphLinks); runnable only when the engine reports glyph_stitch.</summary>
    HasGlyph: Boolean;
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
    /// <summary>`ancestor_unit` -- the declaring ancestor's unit; '' for outside.</summary>
    AncestorUnit : string;
    /// <summary>`ancestor_state` -- unconverted / converted / mismatched / outside.</summary>
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
    /// <summary>todos[] + reemit_notes[] + warnings[] -- the manual remainder. When inherited[]
    /// is not empty, the engine's per-instance 'line N: warning: inherited instance ...'
    /// warnings are left out: InheritedLeftNote already counts those instances.</summary>
    Remainder : TArray<string>;
    /// <summary>inherited[] -- the instances left unconverted; empty for an engine
    /// without inherited_instances (it refuses such a unit instead). A non-object
    /// entry is skipped; a missing or wrongly-typed field reads as '' / 0.</summary>
    InheritedLeft: TArray<TInheritedLeft>;
    /// <summary>`component_part` -- what happened to the .dfm's component part
    /// ('skipped-no-instances': the .dfm holds no instance of its own, only inherited
    /// ones, engine C8 N1); '' when absent.</summary>
    ComponentPart: string;
    /// <summary>glyphs[] -- one outcome per converted instance per G-link (engine ask N3); [] when the engine sends none.</summary>
    Glyphs    : TArray<TGlyphOutcome>;
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

/// <summary>AEntry with Kind and HasGlyph set from the book's text -- the ONE place
/// the Convert tab classifies a book, on first listing and on every refresh alike.</summary>
/// <param name="AEntry">The entry; Path and Checked are kept.</param>
/// <param name="ARulesText">The .rules text.</param>
/// <returns>The entry with Kind = BookKindOfText and HasGlyph = BookHasGlyphLinks of
/// ARulesText (both recomputed, so an edit that removed the last G-link clears it).</returns>
function ClassifiedEntry(const AEntry: TBookEntry; const ARulesText: string): TBookEntry;

/// <summary>The checklist suffix for a book and whether its check box is enabled.</summary>
/// <param name="AEntry">The classified entry.</param>
/// <param name="AUnitRulesOk">The engine reports apply_unit_rules.</param>
/// <param name="AGlyphOk">The engine reports glyph_stitch.</param>
/// <param name="AEnabled">False = the book cannot be checked (unit-rules-only while
/// apply_unit_rules is missing, or a G-link book while glyph_stitch is missing).</param>
/// <returns>'  (empty)', '  (unit rules: engine support pending)' or '  (unit rules not
/// applied: engine)' by Kind, then GLYPH_BOOK_PENDING_SUFFIX appended for a G-link book
/// while glyph_stitch is missing; '' when nothing applies.</returns>
function BookListSuffix(const AEntry: TBookEntry; AUnitRulesOk, AGlyphOk: Boolean; out AEnabled: Boolean): string;

/// <summary>The castlib a Convert run records and passes: APath when that file exists.</summary>
/// <param name="APath">The editor's resolved casts.castlib path; '' = none.</param>
/// <returns>APath, or '' when it is '' or names no file (the adapter then passes no
/// --castlib, so the report must not name one either).</returns>
function ExistingCastLib(const APath: string): string;

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
/// <param name="AGlyphSupported">The engine reports glyph_stitch; without it a book whose HasGlyph is True is skipped with a note.</param>
/// <returns>Ok=False when no book is checked, no unit is listed, or a unit's
/// FILE is not in the index (convert-apply would report a FALSE "could not
/// locate .dfm object block" for it); Runnable = checked books minus empty ones
/// minus unit-rules-only ones while unsupported, and minus G-link books while glyph_stitch is unsupported.</returns>
function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedFiles: TArray<string>; AUnitRulesSupported, AGlyphSupported: Boolean): TPreflight;

/// <summary>Reads convert-apply's --format json output (schema apply/1).</summary>
/// <param name="AJson">The engine's merged stdout+stderr; text before the first
/// '{' and after the last '}' (the "(loaded defaults ...)" line) is ignored.</param>
/// <returns>See TApplyRow; never raises.</returns>
function ParseApplyJson(const AJson: string): TApplyRow;

/// <summary>PURE: the converted row's note for what was left (spec E10).</summary>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2). False
/// (1.22.0) changes the converted words only (see returns).</param>
/// <param name="AItems">TApplyRow.InheritedLeft -- the engine's own inherited[],
/// reported after the runner's reindex and shown UNFILTERED (controller ruling M4: the
/// R4 omission of ancestors converted earlier in the run is the editor-side code-use
/// note's alone).</param>
/// <returns>'' for none; else 'N inherited instance(s) left: &lt;words&gt;' per distinct
/// words, first-seen order, joined '; '. The words by ancestor_state: unconverted
/// 'ancestor &lt;U&gt; not converted'; converted 'ancestor &lt;U&gt; converted -- retype
/// pending (engine N2)' with retype, else 'ancestor &lt;U&gt; converted -- this unit still has
/// &lt;Type&gt; there and may not compile or load until the engine can retype inherited
/// instances (N2)' (an inherited object of the From type under an ancestor that now
/// declares the To type fails at load, and From-only member uses stop compiling); mismatched 'ancestor &lt;U&gt; has &lt;Found&gt; (neither
/// &lt;From&gt; nor &lt;To&gt;)', the three types read from the engine's reason, or
/// 'ancestor &lt;U&gt; has another type -- &lt;reason&gt;' when the reason has another
/// shape; outside 'ancestor not determinable -- &lt;reason&gt;' (the engine sends no
/// ancestor_unit); any other state 'ancestor &lt;U&gt;: &lt;state&gt;'.</returns>
/// <remarks>Grouping is by the words, so it is by (state, unit), plus the type found for
/// mismatched and the reason for outside.</remarks>
function InheritedLeftNote(const AItems: TArray<TInheritedLeft>; ARetypeSupported: Boolean): string;

/// <summary>PURE: one run-report note for one left instance.</summary>
/// <param name="AItem">The instance.</param>
/// <param name="ARetypeSupported">As for InheritedLeftNote.</param>
/// <returns>'&lt;name&gt;: &lt;type&gt; line N -- &lt;words&gt; (&lt;reason&gt;)', the words as
/// InheritedLeftNote's; ' (&lt;reason&gt;)' is left out when the reason is '' or the words
/// already carry it (outside, and a mismatched reason that could not be read).</returns>
function InheritedReportNote(const AItem: TInheritedLeft; ARetypeSupported: Boolean): string;

/// <summary>PURE: the note of a csConverted row.</summary>
/// <param name="AApply">The book's apply/1 answer (Ok).</param>
/// <param name="AInheritedSupported">The engine reports inherited_instances: only then is
/// inherited[] read as that contract (InheritedLeftNote is appended).</param>
/// <param name="ARetypeSupported">The engine reports inherited_retype (passed to
/// InheritedLeftNote).</param>
/// <returns>'N edit(s), M remaining for manual work', then '; no component of its own to
/// convert' when ComponentPart is 'skipped-no-instances' (the engine converted around a
/// .dfm holding only inherited instances, exit 0 -- not a failure), then '; ' +
/// InheritedLeftNote when supported and something was left.</returns>
function ConvertedRowNote(const AApply: TApplyRow; AInheritedSupported, ARetypeSupported: Boolean): string;

/// <summary>PURE: why the Convert tab must not add sources right now, or '' when it may.</summary>
/// <param name="ARunning">A conversion run is in progress.</param>
/// <param name="AChecking">The inherited-instance check is busy: its analysis runs, or
/// one of its prompts is up (the E6 offer, the Convert gate question, the E7 order
/// warning).</param>
/// <returns>The status-line refusal text; '' = the sources may be added.</returns>
/// <remarks>OLE delivers a drop inside ANY modal loop, a MessageDlg included. A prompt
/// was built from the list as it was when it opened, and its answer rewrites that list
/// (E6) or runs it (the gate, E7), so a unit added under it would be lost or listed but
/// not run: the prompt counts as busy. A run outranks a check.</remarks>
function SourcesAddRefusal(ARunning, AChecking: Boolean): string;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , System.JSON
  , System.Math
  , System.RegularExpressions
  , System.StrUtils
  , ConvRules.Model
  , ConvRules.UsesHarvest
  ;

const
  BCK_TAG          = '.BCK';
  ERR_HEAD_CHARS   = 200;
  // The engine's per-instance inherited warning (also an items[] inherited-instance-skipped):
  // 'line N: warning: inherited instance <Name>: <Type> skipped -- <reason>'.
  INHERITED_WARNING_PATTERN = '^line \d+: warning: inherited instance ';
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

function ClassifiedEntry(const AEntry: TBookEntry; const ARulesText: string): TBookEntry;
begin
  Result:= AEntry;
  Result.Kind    := BookKindOfText(ARulesText);
  Result.HasGlyph:= BookHasGlyphLinks(ARulesText);
end;

function BookListSuffix(const AEntry: TBookEntry; AUnitRulesOk, AGlyphOk: Boolean; out AEnabled: Boolean): string;
begin
  AEnabled:= True;
  Result  := '';
  case AEntry.Kind of
    bkEmpty:
      Result:= '  (empty)';
    bkUnitsOnly:
      if not AUnitRulesOk then
      begin
        Result  := '  (unit rules: engine support pending)';
        AEnabled:= False;
      end;
    bkMixed:
      if not AUnitRulesOk then
        Result:= '  (unit rules not applied: engine)';
  end; // case
  if AEntry.HasGlyph and not AGlyphOk then
  begin
    Result  := Result + GLYPH_BOOK_PENDING_SUFFIX;
    AEnabled:= False;
  end;
end;

function ExistingCastLib(const APath: string): string;
begin
  Result:= if (APath <> '') and TFile.Exists(APath) then APath else '';
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

function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedFiles: TArray<string>; AUnitRulesSupported, AGlyphSupported: Boolean): TPreflight;
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
    if B.HasGlyph and not AGlyphSupported then
    begin
      Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': glyph links: engine support pending -- skipped'];
      Continue;
    end;
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

{ glyphs[] (C10, engine ask N3). Every key is optional and every read is
  type-checked: an older engine sends no array, a future one may add keys or change
  a type, and a value of the wrong JSON type reads as its default -- nothing here
  raises (GetValue<T> would, on a wrong type). }
function GlyphOutcomes(AObj: TJSONObject): TArray<TGlyphOutcome>;

  // A JSON string; TJSONNumber descends from TJSONString, so it is excluded.
  function Str(AItem: TJSONObject; const AKey: string): string;
  var
    LVal: TJSONValue;
  begin
    LVal:= AItem.GetValue(AKey);
    if (LVal is TJSONString) and not (LVal is TJSONNumber) then
      Result:= TJSONString(LVal).Value
    else
      Result:= '';
  end;

  // A JSON number holding an integer; anything else (3.5, "3", true) is False.
  function TryInt(AVal: TJSONValue; out AInt: Integer): Boolean;
  begin
    AInt:= 0;
    Result:= (AVal is TJSONNumber) and TryStrToInt(TJSONNumber(AVal).Value, AInt);
  end;

  function Int(AItem: TJSONObject; const AKey: string): Integer;
  begin
    if not TryInt(AItem.GetValue(AKey), Result) then
      Result:= 0;
  end;

var
  LArr  : TJSONValue;
  LSlots: TJSONValue;
  LItem : TJSONObject;
  LSlot : Integer;
  O     : TGlyphOutcome;
begin
  Result:= nil;
  LArr:= AObj.GetValue('glyphs');
  if not (LArr is TJSONArray) then
    Exit;
  for var LVal: TJSONValue in TJSONArray(LArr) do
  begin
    if not (LVal is TJSONObject) then
      Continue;
    LItem:= TJSONObject(LVal);
    O:= Default(TGlyphOutcome);
    O.Instance   := Str(LItem, 'instance');
    O.FromPath   := Str(LItem, 'from_path');
    O.ToPath     := Str(LItem, 'to_path');
    O.Kind       := Str(LItem, 'kind');
    O.Alternative:= Str(LItem, 'alternative');
    O.Message    := Str(LItem, 'message');
    O.SourceN    := Int(LItem, 'source_n');
    O.RuleLine   := Int(LItem, 'rule_line');
    LSlots:= LItem.GetValue('dropped_slots');
    if LSlots is TJSONArray then
      for var LSlotVal: TJSONValue in TJSONArray(LSlots) do
        if TryInt(LSlotVal, LSlot) then
          O.DroppedSlots:= O.DroppedSlots + [LSlot];
    Result:= Result + [O];
  end;
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

  // AWarnings minus the engine's per-instance inherited warnings when inherited[] is
  // there (AHasList): those are the "left" note's, so counting them as manual remainder
  // too would count each instance twice. Without inherited[] they stay.
  function OwnWarnings(const AWarnings: TArray<string>; AHasList: Boolean): TArray<string>;
  begin
    Result:= nil;
    for var LWarn: string in AWarnings do
      if not (AHasList and TRegEx.IsMatch(LWarn, INHERITED_WARNING_PATTERN)) then
        Result:= Result + [LWarn];
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
    Result.InheritedLeft:= InheritedItems(Obj);
    Result.Remainder := Strings(Obj, 'todos') + Strings(Obj, 'reemit_notes') + OwnWarnings(Strings(Obj, 'warnings'), Length(Result.InheritedLeft) > 0);
    Result.ComponentPart:= Str(Obj, 'component_part');
    Result.Glyphs    := GlyphOutcomes(Obj);
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
  LEFT_FMT        = '%d inherited instance(s) left: %s';
  STATE_UNCONV    = 'unconverted';
  STATE_CONV      = 'converted';
  STATE_MISMATCH  = 'mismatched';
  STATE_OUTSIDE   = 'outside';
  WORDS_UNCONV    = 'ancestor %s not converted';
  WORDS_CONV      = 'ancestor %s converted -- retype pending (engine N2)';
  WORDS_CONV_N1   = 'ancestor %s converted -- this unit still has %s there and may not compile or load until the engine can retype inherited instances (N2)';
  WORDS_MISMATCH  = 'ancestor %s has %s (neither %s nor %s)';
  WORDS_MIS_OTHER = 'ancestor %s has another type -- %s';
  WORDS_OUTSIDE   = 'ancestor not determinable -- %s';
  WORDS_OTHER     = 'ancestor %s: %s';
  REPORT_LEFT_FMT = '%s: %s line %d -- %s';
  REPORT_REASON   = ' (%s)';
  NOTE_CONVERTED  = '%d edit(s), %d remaining for manual work';
  NOTE_NO_OWN_COMPONENT = '; no component of its own to convert';
  PART_SKIPPED_NO_INSTANCES = 'skipped-no-instances';
  // The engine's mismatched reason (DRagLint.Convert.Apply, 1.22.0):
  // 'declared in <Unit> as <Found>, neither <From> nor <To> -- not converted'.
  MIS_HEAD    = 'declared in ';
  MIS_AS      = ' as ';
  MIS_NEITHER = ', neither ';
  MIS_NOR     = ' nor ';
  MIS_TAIL    = ' -- ';
  SOURCES_REFUSED_RUNNING  = 'A conversion is running -- sources cannot be added until it finishes.';
  SOURCES_REFUSED_CHECKING = 'Inherited instances are being checked -- add the sources again when it finishes.';

// The engine's mismatched reason read back: True with the three type names when
// AItem.Reason has exactly MIS_HEAD + AncestorUnit + MIS_AS + Found + MIS_NEITHER + From
// + MIS_NOR + To + MIS_TAIL..., each name one non-empty word.
function TryReadMismatch(const AItem: TInheritedLeft; out AFound, AFrom, ATo: string): Boolean;

  // The text of ARest up to ASep (ARest then starts after it); False when ASep is
  // absent or the cut is not one word.
  function Cut(var ARest: string; const ASep: string; out AWord: string): Boolean;
  var
    LPos: Integer;
  begin
    LPos := Pos(ASep, ARest);
    AWord:= if LPos > 0 then Copy(ARest, 1, LPos - 1) else '';
    ARest:= if LPos > 0 then Copy(ARest, LPos + Length(ASep), MaxInt) else '';
    Result:= (AWord <> '') and (Pos(' ', AWord) = 0) and (Pos(',', AWord) = 0);
  end;

var
  LHead: string;
  LRest: string;
begin
  AFound:= '';
  AFrom := '';
  ATo   := '';
  LHead := MIS_HEAD + AItem.AncestorUnit + MIS_AS;
  if (AItem.AncestorUnit = '') or not StartsText(LHead, AItem.Reason) then
    Exit(False);
  LRest := Copy(AItem.Reason, Length(LHead) + 1, MaxInt);
  Result:= Cut(LRest, MIS_NEITHER, AFound) and Cut(LRest, MIS_NOR, AFrom) and Cut(LRest, MIS_TAIL, ATo);
end;

// What was left, in words, per ancestor_state (see InheritedLeftNote).
function LeftWords(const AItem: TInheritedLeft; ARetypeSupported: Boolean): string;
var
  LFound, LFrom, LTo: string;
begin
  if SameText(AItem.AncestorState, STATE_UNCONV) then
    Result:= Format(WORDS_UNCONV, [AItem.AncestorUnit])
  else if SameText(AItem.AncestorState, STATE_CONV) then
    Result:= if ARetypeSupported then Format(WORDS_CONV, [AItem.AncestorUnit]) else Format(WORDS_CONV_N1, [AItem.AncestorUnit, AItem.TypeName])
  else if SameText(AItem.AncestorState, STATE_MISMATCH) then
    Result:= if TryReadMismatch(AItem, LFound, LFrom, LTo) then Format(WORDS_MISMATCH, [AItem.AncestorUnit, LFound, LFrom, LTo])
      else Format(WORDS_MIS_OTHER, [AItem.AncestorUnit, AItem.Reason])
  else if SameText(AItem.AncestorState, STATE_OUTSIDE) then
    Result:= Format(WORDS_OUTSIDE, [AItem.Reason])
  else
    Result:= Format(WORDS_OTHER, [AItem.AncestorUnit, AItem.AncestorState]);
end;

function InheritedLeftNote(const AItems: TArray<TInheritedLeft>; ARetypeSupported: Boolean): string;
var
  LWords : TArray<string>; // one per distinct LeftWords, first-seen order
  LCounts: TArray<Integer>;
  LIdx   : Integer;
  LParts : TArray<string>;
  LText  : string;
begin
  LWords := nil;
  LCounts:= nil;
  // The words carry the grouping: ancestor + state, plus the type found (mismatched)
  // or the reason (outside, an unread mismatched reason) -- two different texts are
  // never merged under one count.
  for var LItem: TInheritedLeft in AItems do
  begin
    LText:= LeftWords(LItem, ARetypeSupported);
    LIdx := High(LWords);
    while (LIdx >= 0) and not SameText(LWords[LIdx], LText) do
      Dec(LIdx);
    if LIdx < 0 then
    begin
      LWords := LWords + [LText];
      LCounts:= LCounts + [0];
      LIdx   := High(LWords);
    end;
    Inc(LCounts[LIdx]);
  end;
  LParts:= nil;
  for var I: Integer:= 0 to High(LWords) do
    LParts:= LParts + [Format(LEFT_FMT, [LCounts[I], LWords[I]])];
  Result:= string.Join('; ', LParts);
end;

function InheritedReportNote(const AItem: TInheritedLeft; ARetypeSupported: Boolean): string;
var
  LWords: string;
begin
  LWords:= LeftWords(AItem, ARetypeSupported);
  Result:= Format(REPORT_LEFT_FMT, [AItem.Name, AItem.TypeName, AItem.Line, LWords]);
  if (AItem.Reason <> '') and (Pos(AItem.Reason, LWords) = 0) then
    Result:= Result + Format(REPORT_REASON, [AItem.Reason]);
end;

function ConvertedRowNote(const AApply: TApplyRow; AInheritedSupported, ARetypeSupported: Boolean): string;
var
  LLeft: string;
begin
  Result:= Format(NOTE_CONVERTED, [AApply.EditsCount, Length(AApply.Remainder)]);
  if SameText(AApply.ComponentPart, PART_SKIPPED_NO_INSTANCES) then
    Result:= Result + NOTE_NO_OWN_COMPONENT;
  // E10: only an engine with inherited_instances sends inherited[]; the gate keeps an
  // older engine's output from being read as this contract. Unfiltered (ruling M4).
  LLeft:= if AInheritedSupported then InheritedLeftNote(AApply.InheritedLeft, ARetypeSupported) else '';
  if LLeft <> '' then
    Result:= Result + '; ' + LLeft;
end;
function SourcesAddRefusal(ARunning, AChecking: Boolean): string;
begin
  if ARunning then
    Result:= SOURCES_REFUSED_RUNNING
  else if AChecking then
    Result:= SOURCES_REFUSED_CHECKING
  else
    Result:= '';
end;

end.
