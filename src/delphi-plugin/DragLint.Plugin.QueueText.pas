unit DragLint.Plugin.QueueText;

{ The multi-task progress text under the drag-lint status strip (spec
  docs\superpowers\specs\2026-10-23-ide-help-line-design.md 3.6). Pure: no VCL,
  so tests\autotest\run_plugin_help_line.ps1 pins it on hand-built states. }

interface

uses
  DragLint.Plugin.JobQueue // dl:unit DragLint.Plugin.JobQueue accepted -- TQueueState + DL_QUEUE_NAMED_PENDING are the queue's snapshot contract; this unit renders exactly that
  ;

/// <summary>The task lines the status strip shows while jobs are waiting.</summary>
/// <param name="pState">A queue snapshot (JobQueue.GetState).</param>
/// <returns>Empty when QueueDepth = 0 (the strip stays exactly as it was).
/// Otherwise "Now: &lt;title&gt; - &lt;pct&gt;%  &lt;phase&gt;" (or "Now: &lt;title&gt; ..."
/// when the percent is indeterminate; no Now line while nothing runs), then
/// "Next: &lt;t1&gt;", "Then: &lt;t2&gt;", "Then: &lt;t3&gt;" for the titles present,
/// then "+ N more waiting" when QueueDepth exceeds DL_QUEUE_NAMED_PENDING.</returns>
function DLQueueLines(const pState: TQueueState): TArray<string>;

implementation

uses
  System.SysUtils
  , System.Math
  ;

function NowLine(const pState: TQueueState): string;
begin
  if pState.Percent < 0 then
    Result:= 'Now: ' + pState.CurrentTitle + ' ...'
  else
    Result:= Format('Now: %s - %d%%', [pState.CurrentTitle, pState.Percent]);
  if pState.Phase <> '' then Result:= Result + '  ' + pState.Phase;
end; // function

function DLQueueLines(const pState: TQueueState): TArray<string>;
var
  Named: Integer;
begin
  Result:= nil;
  if pState.QueueDepth <= 0 then Exit;
  if pState.Running and (pState.CurrentTitle <> '') then Result:= Result + [NowLine(pState)];
  Named:= Min(Length(pState.PendingTitles), DL_QUEUE_NAMED_PENDING);
  for var I:= 0 to Named - 1 do
    Result:= Result + [(if I = 0 then 'Next: ' else 'Then: ') + pState.PendingTitles[I]];
  if pState.QueueDepth > DL_QUEUE_NAMED_PENDING then
    Result:= Result + [Format('+ %d more waiting', [pState.QueueDepth - DL_QUEUE_NAMED_PENDING])];
end; // function

end.
