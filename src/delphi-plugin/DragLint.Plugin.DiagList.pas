unit DragLint.Plugin.DiagList;

{ Pure ordering / lookup / clipboard helpers for the Diagnostics rows of the
  drag-lint Structure panel. No ToolsAPI, no VCL -- so a console harness can
  pin the behaviour (tests\autotest\run_diaglist_harness.ps1).

  WHY A UNIT OF ITS OWN (owner report 2026-10-13): the panel displayed its
  rows in line order while "Copy All Diagnostics" walked the raw cache order
  (rule-grouped), so the pasted list did not match what was on screen. Both
  now take their order from DiagDisplayOrder, so they cannot drift again. }

interface

uses
  DragLint.Plugin.DiagnosticCache;

type
  /// <summary>What a `lint --fix` PREVIEW (no --apply) says about a naming
  /// rename in a unit that several project indexes own (spec criteria 16-19).</summary>
  /// <remarks>Read from the engine's rename-owners / rename-project /
  /// rename-target / rename-unknown / rename-dropped-at-write lines and its
  /// 'autofix: rename refused -- ' summary. A unit with one owner prints none of
  /// them, so every field stays empty and OwnerCount is 0.</remarks>
  TRenamePreview = record
    /// <summary>Owning project indexes, from 'rename-owners: N of M indexes'.</summary>
    OwnerCount: Integer;
    /// <summary>Indexes probed for ownership (the M of the same line).</summary>
    Probed: Integer;
    /// <summary>One line per owning project, e.g. 'Micronite2027 -- index fresh, 3 reference(s)'.
    /// A project named only in a rename-target count reads 'index not reported'.</summary>
    ProjectLines: TArray<string>;
    /// <summary>The text after the last 'autofix: rename refused -- ', or ''.</summary>
    Refused: string;
    /// <summary>Each rename-unknown line's text: an index whose ownership could not be read.</summary>
    Unknown: TArray<string>;
    /// <summary>'Old -> New' for every rename-target the engine will apply.</summary>
    Renames: TArray<string>;
    /// <summary>Every dropped rename-target ('L40 Old -> New: reason') and rename-dropped-at-write line.</summary>
    Dropped: TArray<string>;
    /// <summary>Old and new name of the first applied rename-target; '' when none.</summary>
    OldName, NewName: string;
    /// <summary>Single-project naming renames, from 'rename-local: N' (printed only under
    /// --fix-naming); 0 when absent.</summary>
    LocalRenames: Integer;
    /// <summary>Distinct owning projects a rename-project line reported index=stale:
    /// a preview never reindexes (Ruling 12), so the apply will.</summary>
    StaleCount: Integer;
    /// <summary>Each distinct rename-unindexed line's text, 'section (dbpath)': a
    /// configured project whose index file does not exist, so it was not checked
    /// (Ruling 14).</summary>
    Unindexed: TArray<string>;
  end;

  /// <summary>What the plugin does after a rename preview: apply at once (one
  /// owner, as before), ask first, or stop and show the refusal.</summary>
  TRenamePreviewAction = (rpaApply, rpaConfirm, rpaRefuse, rpaConfirmLocal);

/// <summary>Parses the multi-project rename lines of a `lint --fix` preview.</summary>
/// <param name="AOutput">Full stdout+stderr of the run.</param>
/// <returns>The preview; all-empty with OwnerCount 0 when the output has no rename- lines.</returns>
/// <remarks>Tags are found anywhere in a line, not only at its start: stdout and
/// stderr share one pipe. A rename-project line may carry a ' (reason)' suffix,
/// and a rename-unknown line is free text (e.g. 'manifest did not load completely: ...').
/// Reference counts are summed per project over every applied rename-target.
/// A project reported 'index=stale' counts once in StaleCount however many files
/// name it; rename-unindexed lines are kept once each. Pinned by
/// run_diaglist_harness.ps1 R50-R56.</remarks>
function ParseRenamePreview(const AOutput: string): TRenamePreview;

/// <summary>Decides what follows a rename preview.</summary>
/// <param name="APreview">A value returned by ParseRenamePreview.</param>
/// <returns>rpaRefuse whenever a refusal was printed, whatever the owner count
/// ('rename-owners: 0 of 0' with a refusal is a broken manifest, not one owner);
/// rpaConfirm for 2+ owners, any unknown ownership, or any rename-unindexed
/// section -- the last even with one indexed owner and under Fix all, since a
/// project with no index may still compile the unit (owner decision
/// 2026-10-14); otherwise rpaConfirmLocal when 'rename-local: N' (N above 0)
/// was printed, else rpaApply. Pinned by run_diaglist_harness.ps1 R56-R61.</returns>
function RenamePreviewAction(const APreview: TRenamePreview): TRenamePreviewAction;

const
  /// <summary>Budget for one stale owner's reindex inside a rename apply: the
  /// engine's own per-project index run (measured up to ~528 s on Micronite2027,
  /// 2026-10-13).</summary>
  RENAME_STALE_REINDEX_MS = 600000;

/// <summary>The job timeout for a rename APPLY that follows a preview (B-19).</summary>
/// <param name="APreview">A value returned by ParseRenamePreview.</param>
/// <param name="ABaseMs">The fix's own timeout (Fix it 60 s, Fix all 120 s);
/// &lt;=0 = no deadline.</param>
/// <returns>ABaseMs plus RENAME_STALE_REINDEX_MS per owner the preview reported
/// index=stale, since the apply reindexes those before it writes (Ruling 12);
/// ABaseMs unchanged when there is no stale owner or no deadline. Pinned by
/// run_diaglist_harness.ps1 R67-R69.</returns>
function RenameApplyTimeoutMs(const APreview: TRenamePreview; ABaseMs: Integer): Integer;

/// <summary>The confirmation shown before a multi-project rename, or a naming
/// rename with unindexed projects configured, is written.</summary>
/// <param name="AUnit">File name of the unit being fixed.</param>
/// <param name="AOld">The old name, '' when not known.</param>
/// <param name="ANew">The new name.</param>
/// <param name="APreview">The parsed preview: its projects, drops and unknowns are listed.</param>
/// <returns>Multi-line text naming every owning project with its index state and
/// reference count, warning that stale indexes are reindexed before writing
/// when any is (Ruling 12), and stating that only projects with a drag-lint
/// index were checked -- naming the configured ones that have none on one
/// 'Not checked (no index): A, B -- ...' line, capped at 10 sections
/// (criterion 19, Ruling 14). With fewer than 2 owners and no unknown index
/// (the single-owner case) it states that one project index owns the unit
/// instead of an owner count.</returns>
function RenameConfirmText(const AUnit, AOld, ANew: string; const APreview: TRenamePreview): string;

/// <summary>The confirmation shown before a Fix all writes single-project naming renames.</summary>
/// <param name="AProject">The project the unit belongs to (its index's base name).</param>
/// <param name="APreview">The parsed preview; LocalRenames is the count.</param>
/// <returns>'Rename N identifier(s) in AProject?' as the first line, then what Yes and No do.</returns>
function RenameLocalConfirmText(const AProject: string; const APreview: TRenamePreview): string;

/// <summary>Tells whether ANY 'autofix: applied N edit(s)' line with N above zero
/// is in a run's output -- not only the last autofix: line.</summary>
/// <param name="AOutput">Full stdout+stderr of a `lint --fix --apply` run.</param>
/// <returns>True when edits were written.</returns>
/// <remarks>A rename refused after other fixes on the line went ahead prints the
/// refusal LAST, so AutofixSummary is the refusal while the file on disk has
/// changed; the editor buffer must still be reloaded.</remarks>
function AutofixAppliedInOutput(const AOutput: string): Boolean;

/// <summary>Returns the display order of ADiags: indices into ADiags sorted by
/// (Line, StartCol, original index).</summary>
/// <param name="ADiags">The findings as read from the cache; not modified.</param>
/// <returns>A permutation of 0..High(ADiags).</returns>
/// <remarks>The original-index tie-break makes the order total, so it does not
/// depend on the stability of the sort algorithm. The panel rows and every
/// clipboard copy use this one order.</remarks>
function DiagDisplayOrder(const ADiags: TArray<TDragLintDiagnostic>): TArray<Integer>;

/// <summary>Picks the row nearest to ALine among rows whose 1-based lines are
/// ALines (ascending, as produced by DiagDisplayOrder).</summary>
/// <param name="ALines">1-based line of each row, in display order.</param>
/// <param name="ALine">1-based editor line the caret is on.</param>
/// <returns>The row index, or -1 when ALines is empty or ALine is not positive.</returns>
/// <remarks>An exact match returns the FIRST row on that line. Otherwise the row
/// with the smallest distance wins; on a tie the row ABOVE the caret wins, so
/// moving down through a gap keeps the finding you just passed lit until the
/// next one is closer.</remarks>
function NearestDiagRow(const ALines: TArray<Integer>; ALine: Integer): Integer;

/// <summary>Formats one finding as a clipboard line:
/// '[W] (10:5) message  [rule-id]'.</summary>
/// <param name="ADiag">The finding; Line and StartCol are 0-based.</param>
/// <returns>The line without a trailing line break.</returns>
function DiagClipboardLine(const ADiag: TDragLintDiagnostic): string;

/// <summary>Builds clipboard text for the rows AIndices of ADiags, in the order
/// given, preceded by AFilePath on its own line when it is not empty.</summary>
/// <param name="AFilePath">Header line; '' for none.</param>
/// <param name="ADiags">All findings of the file.</param>
/// <param name="AIndices">Indices into ADiags to emit, already in display order.
/// An index out of range is skipped.</param>
/// <returns>CRLF-separated text, ending in CRLF; '' when nothing is emitted.</returns>
function DiagClipboardText(const AFilePath: string; const ADiags: TArray<TDragLintDiagnostic>;
  const AIndices: TArray<Integer>): string;

/// <summary>Counts the findings whose rule-id is in AFixable.</summary>
/// <param name="ADiags">The findings of the file.</param>
/// <param name="AFixable">Rule-ids that have a registered fix; compared case-insensitively.</param>
/// <returns>How many findings 'Fix all in unit' could act on; 0 disables it.</returns>
function CountFixableDiags(const ADiags: TArray<TDragLintDiagnostic>; const AFixable: TArray<string>): Integer;

/// <summary>A content signature of a finding set: line, column, severity, rule-id
/// and message of every row, in the order given.</summary>
/// <param name="ADiags">The findings as read from the cache.</param>
/// <returns>A 32-bit FNV-1a hash; equal sets give equal values.</returns>
/// <remarks>The dock refreshed the Diagnostics node only when the COUNT changed,
/// so a re-lint that replaced two findings with two others never reached the
/// panel. Comparing this signature catches that.</remarks>
function DiagSetSignature(const ADiags: TArray<TDragLintDiagnostic>): Cardinal;

/// <summary>Extracts the engine's autofix summary from `lint --fix` output.</summary>
/// <param name="AOutput">Full stdout+stderr of the run.</param>
/// <returns>The text after the LAST 'autofix: ', up to the end of its line --
/// e.g. 'applied 2 edit(s) across 1 file(s) (.bak written)' or
/// 'no fixable findings (of 14 finding(s))' -- or '' when there is none.</returns>
/// <remarks>The tag is found anywhere in a line, not only at its start: stdout
/// and stderr share one pipe, so an unbuffered stderr note can be split by it.</remarks>
function AutofixSummary(const AOutput: string): string;

/// <summary>The naming rules the engine reports as fixable but not opted in.</summary>
/// <param name="AOutput">Full stdout+stderr of a `lint --fix` run.</param>
/// <returns>The engine's list, e.g. 'const-casing, type-name-prefix', or ''.</returns>
function AutofixOptOutRules(const AOutput: string): string;

/// <summary>The unit an unused-unit-in-uses finding names.</summary>
/// <param name="AMessage">The finding's message: "Unit 'X' is listed in the uses clause ...".</param>
/// <returns>'X', or '' when the message does not have that shape.</returns>
function UnusedUnitFromMessage(const AMessage: string): string;

/// <summary>Summarises a `uses-fix --format json` document for one unit, in the
/// same 'applied N edit(s)' shape AutofixSummary returns, so one completion
/// path handles both kinds of fix.</summary>
/// <param name="AOutput">The engine's stdout; text before the first '{' is ignored.</param>
/// <param name="AUnitName">The unit the fix was asked about (the --only value).</param>
/// <returns>'applied 1 edit(s): X removed (.bak written)', 'applied 1 edit(s): X
/// moved to the implementation section (.bak written)', 'no change: X -- reason',
/// or '' when there is no parseable document.</returns>
function UsesFixSummary(const AOutput, AUnitName: string): string;

/// <summary>Tells whether an autofix summary reports at least one applied edit.</summary>
/// <param name="ASummary">A value returned by AutofixSummary.</param>
/// <returns>True for 'applied N edit(s)' with N above zero.</returns>
function AutofixApplied(const ASummary: string): Boolean;

/// <summary>Summarises a `cycles --fix --format json` document (schema cycle-fix/1) in one line,
/// for the Diagnostics root row and the Messages pane -- the "Fix this cycle" result (E18 T15b).</summary>
/// <param name="AJson">The engine's output. Text before the first '{' and after the last '}' (stderr
/// notes sharing the pipe) is ignored.</param>
/// <returns>
/// <para>'applied: &lt;units&gt; -- &lt;recipe&gt; cut &lt;edge&gt;; &lt;N&gt; file(s) written, &lt;M&gt; new; compile ok (&lt;s&gt; s); verified'
/// -- or '...; not verified: &lt;verify_reason&gt;' when the re-index did not confirm it;</para>
/// <para>'refused: &lt;kind&gt; -- &lt;reason&gt;' for the first refusal (top level first, then the group's);
/// for dirty-baseline the reason is the first dcc error line;</para>
/// <para>'rolled back: &lt;reason&gt;' when the engine undid its writes;</para>
/// <para>'dry run: &lt;verdict&gt; -- &lt;recipe&gt; cut &lt;edge&gt;; baseline ok (&lt;s&gt; s); add --apply';</para>
/// <para>'failed: &lt;error&gt;' for any other engine error; 'cycle fix: no circular group to fix' for an
/// empty run; 'cycle fix: unreadable output' when there is no cycle-fix/1 object.</para>
/// </returns>
/// <remarks>Pure. Units are joined with ', ' in the engine's order; the group reported is the LAST
/// one (a default scan lists the groups it skipped first). ' cut &lt;edge&gt;' is left out when the recipe
/// has no single edge (a Part A move). Seconds have one decimal, '.' separator.</remarks>
function CycleFixSummary(const AJson: string): string;

/// <summary>Tells whether a `cycles --fix` DRY RUN may be offered for --apply.</summary>
/// <param name="AJson">The dry run's output (as CycleFixSummary reads it).</param>
/// <returns>True only for mode dry-run, no error, no refusal at either level, baseline status ok
/// and a mechanical verdict on the group.</returns>
function CycleFixCanApply(const AJson: string): Boolean;

/// <summary>The "Apply cycle fix" confirmation, built from a dry run's document.</summary>
/// <param name="AJson">The dry run's output; CycleFixCanApply should be True for it.</param>
/// <returns>Lines joined by CRLF: the question naming the cycle's units, the recipe and the edge it
/// cuts, the number of files edited, the new unit names (or 'none'), the baseline build status and
/// time, and what happens on a failed build; '' when AJson is unreadable.</returns>
function CycleFixConfirmText(const AJson: string): string;

/// <summary>The files an applied `cycles --fix` wrote: the group's written[] array.</summary>
/// <param name="AJson">The apply run's output.</param>
/// <returns>Absolute paths in the engine's order; empty when nothing was written or AJson is unreadable.</returns>
function CycleFixWrittenFiles(const AJson: string): TArray<string>;

/// <summary>The files a `cycles --fix` plan edits: the distinct edits[].file of the group.</summary>
/// <param name="AJson">A dry run's output.</param>
/// <returns>Distinct paths (compared case-insensitively), sorted; empty when AJson is unreadable.</returns>
/// <remarks>The IDE refuses --apply while any of them has unsaved edits: the apply rewrites them on
/// disk and reloads the buffers, which would drop those edits.</remarks>
function CycleFixEditedFiles(const AJson: string): TArray<string>;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.RegularExpressions
  , System.StrUtils
  , System.JSON
  , System.Classes { TStringList -- the distinct edited files of a cycle fix }
  ;

function DiagDisplayOrder(const ADiags: TArray<TDragLintDiagnostic>): TArray<Integer>;
var
  Diags: TArray<TDragLintDiagnostic>;
  I    : Integer;
begin
  Diags:= ADiags; { a local the comparer can capture; const params cannot be }
  SetLength(Result, Length(Diags));
  for I:= 0 to High(Result) do Result[I]:= I;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result:= Diags[A].Line - Diags[B].Line;
      if Result = 0 then Result:= Diags[A].StartCol - Diags[B].StartCol;
      if Result = 0 then Result:= A - B;
    end));
end;

function NearestDiagRow(const ALines: TArray<Integer>; ALine: Integer): Integer;
var
  I       : Integer;
  Dist    : Integer;
  BestDist: Integer;
begin
  Result:= -1;
  if (ALine <= 0) or (Length(ALines) = 0) then Exit;
  BestDist:= MaxInt;
  for I:= 0 to High(ALines) do
  begin
    Dist:= Abs(ALines[I] - ALine);
    { strict '<' keeps the earliest row on a tie: the first row on an exact
      line, and the row above the caret when two are equally far }
    if Dist < BestDist then
    begin
      BestDist:= Dist;
      Result  := I;
    end;
  end;
end;

function DiagClipboardLine(const ADiag: TDragLintDiagnostic): string;
const
  CPrefix: array [TDragLintSeverity] of string = ('[E] ', '[W] ', '[H] ', '[I] ');
begin
  Result:= CPrefix[ADiag.Severity] + Format('(%d:%d) ', [ADiag.Line + 1, ADiag.StartCol + 1]) + ADiag.Message;
  if ADiag.Code <> '' then Result:= Result + '  [' + ADiag.Code + ']';
end;

function DiagClipboardText(const AFilePath: string; const ADiags: TArray<TDragLintDiagnostic>;
  const AIndices: TArray<Integer>): string;
var
  SB   : TStringBuilder;
  Index: Integer;
  Count: Integer;
begin
  Count:= 0;
  SB:= TStringBuilder.Create;
  try
    if AFilePath <> '' then SB.Append(AFilePath).Append(sLineBreak);
    for Index in AIndices do
    begin
      if (Index < 0) or (Index > High(ADiags)) then Continue;
      SB.Append(DiagClipboardLine(ADiags[Index])).Append(sLineBreak);
      Inc(Count);
    end;
    Result:= if Count = 0 then '' else SB.ToString;
  finally
    SB.Free;
  end;
end;

function CountFixableDiags(const ADiags: TArray<TDragLintDiagnostic>; const AFixable: TArray<string>): Integer;
var
  D : TDragLintDiagnostic;
  Id: string;
begin
  Result:= 0;
  for D in ADiags do
  begin
    if D.Code = '' then Continue;
    for Id in AFixable do
      if SameText(Id, D.Code) then
      begin
        Inc(Result);
        Break;
      end;
  end;
end;

function DiagSetSignature(const ADiags: TArray<TDragLintDiagnostic>): Cardinal;
const
  CFnvOffset = 2166136261;
  CFnvPrime  = 16777619;
var
  D: TDragLintDiagnostic;
  S: string;
  C: Char;
begin
  Result:= CFnvOffset;
  for D in ADiags do
  begin
    S:= Format('%d|%d|%d|%s|%s'#10, [D.Line, D.StartCol, Ord(D.Severity), D.Code, D.Message]);
    for C in S do
    begin
      Result:= Result xor Ord(C);
      {$Q-}
      Result:= Result * CFnvPrime;
      {$Q+}
    end;
  end;
end;

function AutofixSummary(const AOutput: string): string;
const
  CTag = 'autofix: ';
var
  P: Integer;
  E: Integer;
begin
  { FOUND ANYWHERE, NOT AT A LINE START. The plugin reads stdout and stderr
    through ONE pipe, and the engine's stderr note is unbuffered: on ORM3's
    BASICS.PAS (2026-10-13) the captured line was
      '...cross-file duplicate-code, in' + 'autofix: no fixable findings ...'
    -- the summary landed mid-way through a note, a start-of-line match missed
    it, and the IDE reported nothing at all. The summary is one Writeln, so it
    runs intact to the end of its line. }
  Result:= '';
  P:= AOutput.LastIndexOf(CTag);
  if P < 0 then Exit;
  Result:= AOutput.Substring(P + Length(CTag));
  E:= Result.IndexOfAny([#13, #10]);
  if E >= 0 then Result:= Result.Substring(0, E);
  Result:= Result.Trim;
end;

function AutofixOptOutRules(const AOutput: string): string;
const
  CTag = 'fixable but NOT opted in: ';
var
  P: Integer;
  E: Integer;
begin
  Result:= '';
  P:= AOutput.IndexOf(CTag);
  if P < 0 then Exit;
  Result:= AOutput.Substring(P + Length(CTag));
  E:= Result.IndexOf('. ');
  if E >= 0 then Result:= Result.Substring(0, E);
  E:= Result.IndexOfAny([#13, #10]);
  if E >= 0 then Result:= Result.Substring(0, E);
  Result:= Result.Trim;
end;

function UnusedUnitFromMessage(const AMessage: string): string;
var
  M: TMatch;
begin
  M:= TRegEx.Match(AMessage, '^Unit ''([^'']+)''');
  Result:= if M.Success then M.Groups[1].Value else '';
end;

function UsesFixSummary(const AOutput, AUnitName: string): string;
var
  P    : Integer;
  Root : TJSONValue;
  Items: TJSONArray;
  It   : TJSONValue;
  Done : string;
begin
  Result:= '';
  P:= Pos('{', AOutput);
  if P = 0 then Exit;
  Root:= TJSONObject.ParseJSONValue(Copy(AOutput, P, MaxInt));
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    Exit;
  end;
  try
    if not TJSONObject(Root).TryGetValue<TJSONArray>('items', Items) then Exit;
    for It in Items do
    begin
      if not SameText(It.GetValue<string>('unit', ''), AUnitName) then Continue;
      if SameText(It.GetValue<string>('status', ''), 'verified') then
      begin
        Done:= if SameText(It.GetValue<string>('kind', ''), 'move') then 'moved to the implementation section' else 'removed';
        Exit(Format('applied 1 edit(s): %s %s (.bak written)', [AUnitName, Done]));
      end;
      Exit(Format('no change: %s -- %s', [AUnitName, It.GetValue<string>('reason', It.GetValue<string>('status', ''))]));
    end;
    Result:= Format('no change: %s -- not in this unit''s uses clause', [AUnitName]);
  finally
    Root.Free;
  end;
end;

function AutofixApplied(const ASummary: string): Boolean;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ASummary, '^applied (\d+) edit');
  Result:= M.Success and (StrToIntDef(M.Groups[1].Value, 0) > 0);
end;

{ The text after ATag in ALine, wherever the tag sits: stdout and stderr share
  one pipe, so an unbuffered stderr fragment can precede it on the same line. }
function TagRest(const ALine, ATag: string; out ARest: string): Boolean;
var
  P: Integer;
begin
  P:= ALine.IndexOf(ATag);
  Result:= P >= 0;
  ARest:= if Result then ALine.Substring(P + Length(ATag)).Trim else '';
end;

function ParseRenamePreview(const AOutput: string): TRenamePreview;
const
  CTagOwners  = 'rename-owners: ';
  CTagProject = 'rename-project: ';
  CTagUnknown = 'rename-unknown: ';
  CTagTarget  = 'rename-target: ';
  CTagAtWrite = 'rename-dropped-at-write: ';
  CTagRefused = 'autofix: rename refused -- ';
  CTagLocal   = 'rename-local: ';
  CTagUnindexed = 'rename-unindexed: ';
  CStaleState   = 'index stale';
var
  Names : TArray<string> ; { owning projects, first-seen order }
  States: TArray<string> ; { 'index fresh', ... ; '' until a rename-project line names it }
  Refs  : TArray<Integer>; { references summed over every applied target }
  Line  : string         ;
  Rest  : string         ;
  M     : TMatch         ;
  I     : Integer        ;

  function ProjectIndex(const AName: string): Integer;
  var
    J: Integer;
  begin
    for J:= 0 to High(Names) do
      if SameText(Names[J], AName) then Exit(J);
    Names := Names  + [AName];
    States:= States + [''];
    Refs  := Refs   + [0];
    Result:= High(Names);
  end;

  { One 'L<n> Old -> New apply A=n ...' / '... dropped <reason>' line into APreview. }
  procedure AddTarget(const ARest: string; var APreview: TRenamePreview);
  var
    TM  : TMatch ;
    Tok : string ;
    Eq  : Integer;
    Proj: Integer;
  begin
    TM:= TRegEx.Match(ARest, '^L(?<line>\d+) (?<old>\S+) -> (?<new>\S+) (?<kind>apply|dropped) ?(?<rest>.*)$');
    if not TM.Success then Exit;
    if TM.Groups['kind'].Value = 'dropped' then
    begin
      APreview.Dropped:= APreview.Dropped + [Format('L%s %s -> %s: %s', [TM.Groups['line'].Value, TM.Groups['old'].Value, TM.Groups['new'].Value, TM.Groups['rest'].Value])];
      Exit;
    end;
    APreview.Renames:= APreview.Renames + [TM.Groups['old'].Value + ' -> ' + TM.Groups['new'].Value];
    if APreview.OldName = '' then
    begin
      APreview.OldName:= TM.Groups['old'].Value;
      APreview.NewName:= TM.Groups['new'].Value;
    end;
    for Tok in TM.Groups['rest'].Value.Split([' '], TStringSplitOptions.ExcludeEmpty) do
    begin
      Eq:= Tok.LastIndexOf('=');
      if Eq <= 0 then Continue;
      Proj:= ProjectIndex(Tok.Substring(0, Eq));
      Refs[Proj]:= Refs[Proj] + StrToIntDef(Tok.Substring(Eq + 1), 0);
    end;
  end;

begin
  Result:= Default(TRenamePreview);
  for Line in AOutput.Split([#10]) do
    if TagRest(Line, CTagOwners, Rest) then
    begin
      M:= TRegEx.Match(Rest, '^(\d+) of (\d+)');
      if M.Success then
      begin
        Result.OwnerCount:= StrToIntDef(M.Groups[1].Value, 0);
        Result.Probed    := StrToIntDef(M.Groups[2].Value, 0);
      end;
    end
    else if TagRest(Line, CTagProject, Rest) then
    begin
      { '<name> index=<state>[ (<reason>)]' -- the reason is kept verbatim }
      M:= TRegEx.Match(Rest, '^(\S+) index=(.*)$');
      if M.Success then States[ProjectIndex(M.Groups[1].Value)]:= 'index ' + M.Groups[2].Value
      else if Rest <> '' then ProjectIndex(Rest.Split([' '])[0]);
    end
    else if TagRest(Line, CTagLocal, Rest) then Result.LocalRenames:= StrToIntDef(Rest, 0)
    else if TagRest(Line, CTagUnknown, Rest) then Result.Unknown:= Result.Unknown + [Rest]
    else if TagRest(Line, CTagUnindexed, Rest) then
    begin
      if IndexText(Rest, Result.Unindexed) < 0 then Result.Unindexed:= Result.Unindexed + [Rest];
    end
    else if TagRest(Line, CTagAtWrite, Rest) then Result.Dropped:= Result.Dropped + [Rest]
    else if TagRest(Line, CTagTarget, Rest) then AddTarget(Rest, Result)
    else if TagRest(Line, CTagRefused, Rest) then Result.Refused:= Rest;
  for I:= 0 to High(Names) do
  begin
    Result.ProjectLines:= Result.ProjectLines + [Format('%s -- %s, %d reference(s)',
      [Names[I], (if States[I] <> '' then States[I] else 'index not reported'), Refs[I]])];
    if StartsText(CStaleState, States[I]) then Inc(Result.StaleCount);
  end;
end;

function RenameApplyTimeoutMs(const APreview: TRenamePreview; ABaseMs: Integer): Integer;
begin
  Result:= if ABaseMs <= 0 then ABaseMs else ABaseMs + APreview.StaleCount * RENAME_STALE_REINDEX_MS;
end;

function RenamePreviewAction(const APreview: TRenamePreview): TRenamePreviewAction;
begin
  if APreview.Refused <> '' then Exit(rpaRefuse);
  { unknown ownership with no refusal is a batch run whose global targets were
    dropped: 0 owners then does NOT mean "one project", so ask. A
    rename-unindexed line (printed only when the run has naming targets) means
    a project that may compile this unit was not checked: ask too, even with
    one indexed owner (owner decision 2026-10-14) }
  if (APreview.OwnerCount >= 2) or (Length(APreview.Unknown) > 0) or (Length(APreview.Unindexed) > 0) then
    Exit(rpaConfirm);
  { 'rename-local:' is printed only under --fix-naming (Fix all): a batch of
    naming renames is always confirmed, even in one project }
  Result:= if APreview.LocalRenames > 0 then rpaConfirmLocal else rpaApply;
end;

function RenameConfirmText(const AUnit, AOld, ANew: string; const APreview: TRenamePreview): string;
const
  CListCap = 10; { BASICS.PAS has ~80 naming findings: a dialog taller than the screen hides Yes/No }
  CDbSuffix = ' ('; { a rename-unindexed entry is 'section (dbpath)' }
var
  SB   : TStringBuilder;
  S    : string        ;
  Multi: Boolean       ;
  Names: TArray<string>;
  K    : Integer       ;

  procedure AppendCapped(const AItems: TArray<string>);
  var
    J: Integer;
  begin
    for J:= 0 to High(AItems) do
    begin
      if J = CListCap then
      begin
        SB.AppendFormat('  ... and %d more', [Length(AItems) - CListCap]).Append(sLineBreak);
        Break;
      end;
      SB.Append('  ').Append(AItems[J]).Append(sLineBreak);
    end;
  end;

begin
  { single-owner path (only rename-unindexed brought us here): the engine
    printed no rename-owners / rename-target lines, so there are no counts }
  Multi:= (APreview.OwnerCount >= 2) or (Length(APreview.Unknown) > 0);
  SB:= TStringBuilder.Create;
  try
    if (Length(APreview.Renames) <= 1) and (AOld <> '') then
      SB.AppendFormat('Rename %s -> %s in %s?', [AOld, ANew, AUnit]).Append(sLineBreak)
    else if Multi or (Length(APreview.Renames) > 0) then
    begin
      SB.AppendFormat('Apply %d rename(s) in %s?', [Length(APreview.Renames), AUnit]).Append(sLineBreak);
      AppendCapped(APreview.Renames);
    end
    else if APreview.LocalRenames > 0 then
      SB.AppendFormat('Rename %d identifier(s) in %s?', [APreview.LocalRenames, AUnit]).Append(sLineBreak)
    else
      SB.AppendFormat('Apply the naming rename in %s?', [AUnit]).Append(sLineBreak);
    SB.Append(sLineBreak);
    if Multi then
    begin
      SB.AppendFormat('This unit is compiled by %d indexed project(s) (%d index(es) checked). Yes renames it in every one of them:',
        [APreview.OwnerCount, APreview.Probed]).Append(sLineBreak);
      for S in APreview.ProjectLines do SB.Append('  ').Append(S).Append(sLineBreak);
    end
    else
      SB.Append('No other indexed project compiles this unit. Yes renames it in the one project index that owns it.')
        .Append(sLineBreak);
    if Length(APreview.Dropped) > 0 then
    begin
      SB.Append(sLineBreak).Append('NOT renamed (nothing is written for these):').Append(sLineBreak);
      AppendCapped(APreview.Dropped);
    end;
    if Length(APreview.Unknown) > 0 then
    begin
      SB.Append(sLineBreak).Append('Ownership could not be read from:').Append(sLineBreak);
      for S in APreview.Unknown do SB.Append('  ').Append(S).Append(sLineBreak);
    end;
    if APreview.StaleCount > 0 then
      SB.Append(sLineBreak)
        .AppendFormat('%d project index(es) are stale and will be reindexed before writing -- this can take several minutes.',
          [APreview.StaleCount]).Append(sLineBreak);
    SB.Append(sLineBreak)
      .Append('Note: only projects with a drag-lint index were checked. A project that compiles this unit ')
      .Append('but has no configured index is not renamed, and may stop compiling.').Append(sLineBreak);
    if Length(APreview.Unindexed) > 0 then
    begin
      Names:= nil;
      for K:= 0 to High(APreview.Unindexed) do
      begin
        if K = CListCap then Break;
        S:= APreview.Unindexed[K];
        if Pos(CDbSuffix, S) > 0 then S:= Copy(S, 1, Pos(CDbSuffix, S) - 1);
        Names:= Names + [S];
      end;
      SB.Append('Not checked (no index): ').Append(string.Join(', ', Names));
      if Length(APreview.Unindexed) > CListCap then
        SB.AppendFormat(' and %d more', [Length(APreview.Unindexed) - CListCap]);
      SB.Append(' -- projects without a drag-lint index may still compile this unit.').Append(sLineBreak);
    end;
    SB.Append(sLineBreak)
      .Append('No writes nothing.');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenameLocalConfirmText(const AProject: string; const APreview: TRenamePreview): string;
begin
  Result:= Format('Rename %d identifier(s) in %s?', [APreview.LocalRenames, AProject]) + sLineBreak + sLineBreak
    + 'Each rename changes the declaration and every use the index knows about. No writes nothing.';
end;

function AutofixAppliedInOutput(const AOutput: string): Boolean;
var
  M: TMatch;
begin
  for M in TRegEx.Matches(AOutput, 'autofix: applied (\d+) edit') do
    if StrToIntDef(M.Groups[1].Value, 0) > 0 then Exit(True);
  Result:= False;
end;

{ ---- E18 T15b: `cycles --fix --format json` (cycle-fix/1) ---- }

const
  CCycleFixSchema   = 'cycle-fix/1';
  CCycleFixRolled   = 'rolled back';
  CCycleFixDirty    = 'dirty-baseline';
  CCycleFixOk       = 'ok';
  CCycleFixDryRun   = 'dry-run';
  CCycleFixApply    = 'apply';
  CCycleMechanical  = 'mechanical';
  CCycleUnreadable  = 'cycle fix: unreadable output';

// The cycle-fix/1 object in AJson, or nil; the caller frees it. The document runs from the first
// opening brace to the LAST closing brace that ends it: a stderr note after it may carry braces.
function ParseCycleFix(const AJson: string): TJSONObject;
var
  P, Q: Integer;
  V   : TJSONValue;
begin
  Result:= nil;
  P:= Pos('{', AJson);
  if P = 0 then Exit;
  Q:= Length(AJson);
  while Q > P do
  begin
    if AJson[Q] = '}' then
    begin
      V:= TJSONObject.ParseJSONValue(Copy(AJson, P, Q - P + 1));
      if (V is TJSONObject) and SameText(TJSONObject(V).GetValue<string>('schema', ''), CCycleFixSchema) then
        Exit(TJSONObject(V));
      V.Free;
    end;
    Dec(Q);
  end;
end;

{ The group the run reported on: the LAST element of cycles[], or nil. }
function LastCycle(const ARoot: TJSONObject): TJSONObject;
var
  Arr: TJSONArray;
begin
  Result:= nil;
  if not ARoot.TryGetValue<TJSONArray>('cycles', Arr) then Exit;
  if Arr.Count = 0 then Exit;
  if Arr.Items[Arr.Count - 1] is TJSONObject then Result:= TJSONObject(Arr.Items[Arr.Count - 1]);
end;

{ The strings of a JSON array field of AObj, '' entries kept. }
function StringsOf(const AObj: TJSONObject; const AField: string): TArray<string>;
var
  Arr: TJSONArray;
begin
  Result:= nil;
  if (AObj = nil) or not AObj.TryGetValue<TJSONArray>(AField, Arr) then Exit;
  for var V in Arr do Result:= Result + [V.Value];
end;

{ The first element of AObj.refusals as an object, or nil. }
function FirstRefusal(const AObj: TJSONObject): TJSONObject;
var
  Arr: TJSONArray;
begin
  Result:= nil;
  if AObj = nil then Exit;
  if not AObj.TryGetValue<TJSONArray>('refusals', Arr) then Exit;
  if Arr.Count = 0 then Exit;
  if Arr.Items[0] is TJSONObject then Result:= TJSONObject(Arr.Items[0]);
end;

{ '<s> s' with one decimal from AObj.<AField>.seconds; '' when absent. }
function SecondsOf(const AObj: TJSONObject; const AField: string): string;
var
  Sub: TJSONObject;
begin
  Result:= '';
  if (AObj = nil) or not AObj.TryGetValue<TJSONObject>(AField, Sub) then Exit;
  Result:= Format('%.1f s', [Sub.GetValue<Double>('seconds', 0)], TFormatSettings.Invariant);
end;

{ AObj.<AField>.status, or ''. }
function StatusOf(const AObj: TJSONObject; const AField: string): string;
var
  Sub: TJSONObject;
begin
  Result:= '';
  if (AObj <> nil) and AObj.TryGetValue<TJSONObject>(AField, Sub) then Result:= Sub.GetValue<string>('status', '');
end;

{ '<recipe> cut <edge>', or '<recipe>' when the recipe has no single edge. }
function RecipeCut(const ACycle: TJSONObject): string;
var
  Edge: string;
begin
  Result:= ACycle.GetValue<string>('recipe', '');
  Edge  := ACycle.GetValue<string>('edge', '');
  if Edge <> '' then Result:= Result + ' cut ' + Edge;
end;

{ 'refused: <kind> -- <reason>'; dirty-baseline names the first dcc line. }
function RefusalText(const ARoot, ARefusal: TJSONObject): string;
var
  Kind, Why: string;
  Errs     : TArray<string>;
  Base     : TJSONObject;
begin
  Kind:= ARefusal.GetValue<string>('kind', '');
  Why := ARefusal.GetValue<string>('reason', '');
  if SameText(Kind, CCycleFixDirty) and ARoot.TryGetValue<TJSONObject>('baseline', Base) then
  begin
    Errs:= StringsOf(Base, 'errors');
    if Length(Errs) > 0 then Why:= Errs[0];
  end;
  Result:= Format('refused: %s -- %s', [Kind, Why]);
end;

{ 'rolled back: <reason>' from a top-level error 'rolled back, project not changed: <reason>'. }
function RolledBackText(const AError: string): string;
begin
  Result:= CCycleFixRolled + ': ' + (if Pos(': ', AError) > 0 then Copy(AError, Pos(': ', AError) + 2, MaxInt) else AError);
end;

{ 'rolled back: <reason>' for a group whose rolled_back is true: the first compile error, else
  the verify reason. }
function GroupRolledBackText(const ACycle: TJSONObject): string;
var
  Comp: TJSONObject;
  Errs: TArray<string>;
  Why : string;
begin
  Errs:= nil;
  if ACycle.TryGetValue<TJSONObject>('compile', Comp) then Errs:= StringsOf(Comp, 'errors');
  Why:= if Length(Errs) > 0 then Errs[0] else ACycle.GetValue<string>('verify_reason', '');
  Result:= CCycleFixRolled + ': ' + (if Why <> '' then Why else 'the change did not build');
end;

{ 'applied: <units> -- <recipe> cut <edge>; N file(s) written, M new; compile ok (s); verified'. }
function AppliedText(const ACycle: TJSONObject): string;
begin
  Result:= Format('applied: %s -- %s; %d file(s) written, %d new; compile %s (%s)',
    [string.Join(', ', StringsOf(ACycle, 'units')), RecipeCut(ACycle), Length(StringsOf(ACycle, 'written')),
     Length(StringsOf(ACycle, 'new_files')), StatusOf(ACycle, 'compile'), SecondsOf(ACycle, 'compile')]);
  if ACycle.GetValue<Boolean>('verified', False) then Result:= Result + '; verified'
  else Result:= Result + '; not verified: ' + ACycle.GetValue<string>('verify_reason', '');
end;

{ 'dry run: <verdict> -- <recipe> cut <edge>; baseline ok (s); add --apply'. }
function DryRunText(const ARoot, ACycle: TJSONObject): string;
begin
  Result:= Format('dry run: %s -- %s; baseline %s', [ACycle.GetValue<string>('verdict', ''), RecipeCut(ACycle),
    StatusOf(ARoot, 'baseline')]);
  if SameText(StatusOf(ARoot, 'baseline'), CCycleFixOk) then Result:= Result + ' (' + SecondsOf(ARoot, 'baseline') + ')';
  Result:= Result + '; add --apply';
end;

function CycleFixSummary(const AJson: string): string;
var
  Root: TJSONObject;
  Cyc : TJSONObject;
  Ref : TJSONObject;
  Err : string;
begin
  Root:= ParseCycleFix(AJson);
  if Root = nil then Exit(CCycleUnreadable);
  try
    Err:= Root.GetValue<string>('error', '');
    Cyc:= LastCycle(Root);
    { a top-level refusal (dirty-baseline) outranks the group's own }
    Ref:= FirstRefusal(Root);
    if (Ref = nil) and (Cyc <> nil) then Ref:= FirstRefusal(Cyc);
    if StartsText(CCycleFixRolled, Err) then Result:= RolledBackText(Err)
    else if Err <> '' then Result:= 'failed: ' + Err
    else if Ref <> nil then Result:= RefusalText(Root, Ref)
    else if Cyc = nil then Result:= 'cycle fix: no circular group to fix'
    else if Cyc.GetValue<Boolean>('rolled_back', False) then Result:= GroupRolledBackText(Cyc)
    else if SameText(Root.GetValue<string>('mode', ''), CCycleFixApply) then Result:= AppliedText(Cyc)
    else Result:= DryRunText(Root, Cyc);
  finally
    Root.Free;
  end;
end;

function CycleFixCanApply(const AJson: string): Boolean;
var
  Root: TJSONObject;
  Cyc : TJSONObject;
begin
  Root:= ParseCycleFix(AJson);
  if Root = nil then Exit(False);
  try
    Cyc:= LastCycle(Root);
    var RunClean: Boolean:= SameText(Root.GetValue<string>('mode', ''), CCycleFixDryRun)
         and (Root.GetValue<string>('error', '') = '') and (FirstRefusal(Root) = nil);
    var BaselineOk: Boolean:= SameText(StatusOf(Root, 'baseline'), CCycleFixOk);
    var GroupOk: Boolean:= (Cyc <> nil) and (FirstRefusal(Cyc) = nil)
         and SameText(Cyc.GetValue<string>('verdict', ''), CCycleMechanical);
    Result:= RunClean and BaselineOk and GroupOk;
  finally
    Root.Free;
  end;
end;

{ The distinct edits[].file of ACycle (nil-safe), sorted, case-insensitive. }
function EditedFilesOf(const ACycle: TJSONObject): TArray<string>;
var
  Arr  : TJSONArray;
  Files: TStringList;
begin
  Result:= nil;
  if ACycle = nil then Exit;
  Files:= TStringList.Create;
  try
    Files.Sorted       := True;
    Files.Duplicates   := dupIgnore;
    Files.CaseSensitive:= False;
    if ACycle.TryGetValue<TJSONArray>('edits', Arr) then
      for var V in Arr do
        if V is TJSONObject then Files.Add(TJSONObject(V).GetValue<string>('file', ''));
    Result:= Files.ToStringArray;
  finally
    Files.Free;
  end;
end;

function CycleFixEditedFiles(const AJson: string): TArray<string>;
var
  Root: TJSONObject;
begin
  Root:= ParseCycleFix(AJson);
  if Root = nil then Exit(nil);
  try
    Result:= EditedFilesOf(LastCycle(Root));
  finally
    Root.Free;
  end;
end;

function CycleFixConfirmText(const AJson: string): string;
var
  Root : TJSONObject;
  Cyc  : TJSONObject;
  Arr  : TJSONArray;
  News : TArray<string>;
  Edge : string;
begin
  Result:= '';
  Root:= ParseCycleFix(AJson);
  if Root = nil then Exit;
  try
    Cyc:= LastCycle(Root);
    if Cyc = nil then Exit;
    News:= nil;
    if Cyc.TryGetValue<TJSONArray>('new_units', Arr) then
      for var V in Arr do
        if V is TJSONObject then News:= News + [TJSONObject(V).GetValue<string>('unit', '')];
    Edge:= Cyc.GetValue<string>('edge', '');
    Result:= string.Join(#13#10, [
      Format('Apply the cycle fix to %s?', [string.Join(', ', StringsOf(Cyc, 'units'))]),
      '',
      'Recipe: ' + Cyc.GetValue<string>('recipe', '') + (if Edge <> '' then ', cutting ' + Edge else ''),
      Format('Files edited: %d', [Length(EditedFilesOf(Cyc))]),
      'New units: ' + (if Length(News) > 0 then string.Join(', ', News) else 'none'),
      Format('Baseline build: %s (%s)', [StatusOf(Root, 'baseline'), SecondsOf(Root, 'baseline')]),
      '',
      'Every edited file is backed up first; the project is rolled back when the build after the edit fails.']);
  finally
    Root.Free;
  end;
end;

function CycleFixWrittenFiles(const AJson: string): TArray<string>;
var
  Root: TJSONObject;
begin
  Root:= ParseCycleFix(AJson);
  if Root = nil then Exit(nil);
  try
    Result:= StringsOf(LastCycle(Root), 'written');
  finally
    Root.Free;
  end;
end;

end.
