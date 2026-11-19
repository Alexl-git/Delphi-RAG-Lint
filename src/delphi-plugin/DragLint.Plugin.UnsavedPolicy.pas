unit DragLint.Plugin.UnsavedPolicy;

{ What an editable plugin page does with unsaved changes (1.51.2 N5).

  1.51.1 asked "Save them now?" from TLintOptionsFrame.Destroy. The dock frame
  is destroyed while the IDE tears down, so the question appeared late and a
  Yes ran Save -- an engine spawn plus file writes -- against IDE services that
  were already freed, which flashed 5-6 IDE error boxes. No IDE hook fires
  early enough at exit for a dock page, so the page asks only while it is
  interactive, and at teardown discards and logs one line.

  No VCL and no ToolsAPI here, so tests\UnsavedPolicyTests.dpr pins it. }

interface

type
  /// <summary>When the unsaved-changes decision is being made.</summary>
  /// <remarks>upInteractive: a user action on a live page (Reload, switching
  /// profile) -- a dialog is safe. upTeardown: a destructor or finalization --
  /// the IDE may already be freeing its services; no UI, no file writes.</remarks>
  TUnsavedPhase = (upInteractive, upTeardown);

  /// <summary>What the page does about unsaved changes.</summary>
  /// <remarks>uaNothing: nothing to lose. uaAsk: show a Yes/No question.
  /// uaDiscard: drop the changes without UI and log one line.</remarks>
  TUnsavedAction = (uaNothing, uaAsk, uaDiscard);

/// <summary>Decides what to do about a page's unsaved changes.</summary>
/// <param name="pDirty">True when the page was edited since its last load or save.</param>
/// <param name="pHasData">True when the page finished loading; a page that never
/// loaded has nothing worth saving.</param>
/// <param name="pPhase">Whether the page is live or being torn down.</param>
/// <returns>uaNothing unless dirty and loaded; then uaAsk when interactive and
/// uaDiscard at teardown. Never uaAsk at teardown.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function DecideUnsaved(pDirty, pHasData: Boolean; pPhase: TUnsavedPhase): TUnsavedAction;

/// <summary>The one log line written when unsaved changes are discarded at teardown.</summary>
/// <param name="pPage">The page caption, e.g. 'Lint Options'.</param>
/// <returns>A single line (no CR/LF) naming the page and saying the changes were discarded.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function UnsavedDiscardLogLine(const pPage: string): string;

implementation

function DecideUnsaved(pDirty, pHasData: Boolean; pPhase: TUnsavedPhase): TUnsavedAction;
begin
  if not (pDirty and pHasData) then Exit(uaNothing);
  Result:= if pPhase = upTeardown then uaDiscard else uaAsk;
end;

function UnsavedDiscardLogLine(const pPage: string): string;
begin
  Result:= 'drag-lint ' + pPage + ': unsaved changes discarded at IDE shutdown (no prompt at teardown)';
end;

end.
