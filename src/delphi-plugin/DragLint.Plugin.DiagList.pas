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
/// <returns>The text after 'autofix: ' on the LAST such line -- e.g.
/// 'applied 2 edit(s) across 1 file(s) (.bak written)' or
/// 'no fixable findings (of 14 finding(s))' -- or '' when there is none.</returns>
function AutofixSummary(const AOutput: string): string;

/// <summary>Tells whether an autofix summary reports at least one applied edit.</summary>
/// <param name="ASummary">A value returned by AutofixSummary.</param>
/// <returns>True for 'applied N edit(s)' with N above zero.</returns>
function AutofixApplied(const ASummary: string): Boolean;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.RegularExpressions
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
  Line: string;
begin
  Result:= '';
  for Line in AOutput.Split([#13#10, #10]) do
    if Line.Trim.StartsWith(CTag) then Result:= Line.Trim.Substring(Length(CTag));
end;

function AutofixApplied(const ASummary: string): Boolean;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ASummary, '^applied (\d+) edit');
  Result:= M.Success and (StrToIntDef(M.Groups[1].Value, 0) > 0);
end;

end.
