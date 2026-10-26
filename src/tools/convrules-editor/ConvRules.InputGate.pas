unit ConvRules.InputGate;

{ PURE (N7/N11, 2026-10-23): what the editor does with a queued message that
  reaches its main window while it is busy.

  Root cause this answers: an engine wait (RunWithProgressDialog) and every
  hourglass section that calls Application.ProcessMessages to paint its status
  line are NESTED message pumps. Each one dispatches whatever was queued for the
  main window meanwhile -- a posted BM_CLICK, a posted WM_COMMAND, a real click
  that arrived while the main thread was blocked. ShowModal's disabled windows do
  not stop that: Windows silently drops a BM_CLICK on a button of a disabled
  window (N11: the second Add... lost), and a WM_COMMAND is not checked at all
  (N7/N11: ConvertClick / AddClick re-entrant inside the progress window, the
  Open dialog on top of it). So the editor filters its own queue in ONE place
  (TConvRulesForm.AppMessage on Application.OnMessage, which every VCL pump
  calls) with these decisions: refuse, say so, never queue.

  No Winapi here: the message numbers are named below and pinned to Winapi by
  the model tests. }

interface

const
  /// <summary>Win32 WM_KEYFIRST / WM_KEYLAST: every keyboard message.</summary>
  GATE_WM_KEYFIRST = $0100;
  /// <summary>See GATE_WM_KEYFIRST.</summary>
  GATE_WM_KEYLAST = $0109;
  /// <summary>Win32 WM_COMMAND: a button notification or a menu item.</summary>
  GATE_WM_COMMAND = $0111;
  /// <summary>Win32 BM_CLICK: a click a program posts to a button.</summary>
  GATE_BM_CLICK = $00F5;
  /// <summary>Win32 WM_MOUSEMOVE: the first client mouse message; hovering always passes.</summary>
  GATE_WM_MOUSEMOVE = $0200;
  /// <summary>Win32 WM_LBUTTONDOWN.</summary>
  GATE_WM_LBUTTONDOWN = $0201;
  /// <summary>Win32 WM_LBUTTONDBLCLK.</summary>
  GATE_WM_LBUTTONDBLCLK = $0203;
  /// <summary>Win32 WM_MOUSELAST (WM_MOUSEHWHEEL): the last client mouse message.</summary>
  GATE_WM_MOUSELAST = $020E;
  /// <summary>Win32 WM_NCMOUSEMOVE: the first non-client mouse message; hovering always passes.</summary>
  GATE_WM_NCMOUSEMOVE = $00A0;
  /// <summary>Win32 WM_NCXBUTTONDBLCLK: the last non-client mouse button message.</summary>
  GATE_WM_NCMOUSELAST = $00AD;
  /// <summary>The notice for a refused command; %s = the command, then the busy work.</summary>
  LOST_COMMAND_FMT = '%s was NOT run: it was clicked while the editor was busy (%s). Click it again.';
  /// <summary>The command name when the target has no caption (a list row, a grid cell).</summary>
  LOST_COMMAND_UNNAMED = 'The click';
  /// <summary>The Convert button's command name: LostCommandStatus gives it N1's own text.</summary>
  LOST_COMMAND_CONVERT = 'Convert';

type
  /// <summary>GateVerdict's answer for one queued message.</summary>
  /// <remarks>gvPass: dispatch it. gvDrop: swallow it silently (a key, a wheel, a
  /// title-bar press). gvRefuse: swallow it AND tell the user once the editor is
  /// idle (LostCommandStatus) -- it was an attempt to run a command.</remarks>
  TGateVerdict = (gvPass, gvDrop, gvRefuse);

/// <summary>PURE: whether the editor is busy, i.e. inside a nested message pump that
/// must not run main-window commands.</summary>
/// <param name="AWaitDepth">How many engine waits (RunLongCallTracked) are running,
/// including the 400 ms before the progress window shows; 0 = none.</param>
/// <param name="AHourGlass">Screen.Cursor is crHourGlass: a synchronous section that may
/// call Application.ProcessMessages to paint its status line.</param>
/// <returns>True when either holds.</returns>
function EditorBusy(AWaitDepth: Integer; AHourGlass: Boolean): Boolean;

/// <summary>PURE: what to do with one queued message while the editor may be busy.</summary>
/// <param name="AMsg">The message number (TMsg.message).</param>
/// <param name="ABusy">EditorBusy now.</param>
/// <param name="ATargetInMainForm">The message's window is the main form or one of its
/// child windows (GA_ROOT is the main form). The progress window, a message box, a
/// picker or a common dialog is NOT: their input always passes, so Cancel and Esc work.</param>
/// <returns>gvPass when not busy, when the target is outside the main form, and for every
/// message that is not user input (paint, timers, hovering, registered queries).
/// gvRefuse for BM_CLICK, WM_COMMAND and a left press or double-click in the client
/// area. gvDrop for the rest of the keyboard and mouse-button range (keys, right/middle/X
/// buttons, the wheel, the releases, non-client presses).</returns>
/// <remarks>Report, never queue: a command that arrived during busy work is not run later
/// by itself (a Convert edits units in place).</remarks>
function GateVerdict(AMsg: Cardinal; ABusy, ATargetInMainForm: Boolean): TGateVerdict;

/// <summary>PURE: whether a window class is a selection or navigation control, where a
/// left press picks a row or moves a caret and never runs a command (R6).</summary>
/// <param name="AWndClass">The VCL ClassName of the press target's control, else its Win32 class name; '' = unknown.</param>
/// <returns>True for the Win32 list box, list view, tree view, combo box and edit classes and
/// the VCL class names of the editor's lists, combo, edits, memo and cx grid/text edit (GetClassName of a
/// VCL control is the Delphi class name, e.g. 'TListBox') (case-insensitive); False for anything else, so an unknown target stays a command.</returns>
function IsSelectionClass(const AWndClass: string): Boolean;

/// <summary>PURE: GateVerdict refined by what the press landed on (R6).</summary>
/// <param name="AMsg">The message number (TMsg.message).</param>
/// <param name="ABusy">EditorBusy now.</param>
/// <param name="ATargetInMainForm">As for GateVerdict.</param>
/// <param name="AWndClass">As for IsSelectionClass; '' = unknown.</param>
/// <returns>GateVerdict's answer, except a left press or double-click on a selection
/// control (IsSelectionClass) is gvDrop, not gvRefuse: swallowed quietly, no red notice.
/// BM_CLICK and WM_COMMAND stay gvRefuse whatever the class.</returns>
/// <remarks>Report commands, not selections: a swallowed selection loses nothing the user
/// must repeat deliberately, and a red error for it reads as a failure.</remarks>
function GateVerdictFor(AMsg: Cardinal; ABusy, ATargetInMainForm: Boolean; const AWndClass: string): TGateVerdict;

/// <summary>PURE: the name a refused command is reported by.</summary>
/// <param name="ACaption">The button's or menu item's caption, e.g. '&amp;Add...'.</param>
/// <returns>The caption without its hotkey ampersands ('&amp;&amp;' stays one '&amp;') and
/// without a trailing '...'; LOST_COMMAND_UNNAMED when nothing is left.</returns>
function CommandName(const ACaption: string): string;

/// <summary>PURE: the status line once a refused command is reported -- the current
/// status kept, the notice appended.</summary>
/// <param name="ACurrent">The status on screen when the busy work ended; '' = none.</param>
/// <param name="ACommand">CommandName of what was clicked.</param>
/// <param name="ABusyTitle">What the editor was busy with (the progress window's title,
/// else the status line at the time of the click).</param>
/// <returns>ACurrent + ' | ' + the notice, or the notice alone when ACurrent is ''.
/// Convert keeps its N1 text (LostConvertClickStatus), so a lost Convert reads the same
/// whichever way it was lost.</returns>
function LostCommandStatus(const ACurrent, ACommand, ABusyTitle: string): string;

/// <summary>PURE: what a refused command's notice names as the busy work.</summary>
/// <param name="AWaitTitle">The running engine wait's title (FBusyTitle); '' = none.</param>
/// <param name="AStatus">The status line at the time of the click (an hourglass
/// section writes what it does there before it pumps).</param>
/// <returns>AWaitTitle, else AStatus, else BUSY_TITLE_UNKNOWN.</returns>
function BusyTitleFor(const AWaitTitle, AStatus: string): string;

const
  /// <summary>BusyTitleFor's answer when neither a wait title nor a status names the work.</summary>
  BUSY_TITLE_UNKNOWN = 'another operation';

implementation

uses
  System.SysUtils
  , System.StrUtils
  , ConvRules.ConvertRun
  ;

const
  ELLIPSIS        = '...';
  SELECTION_CLASSES: array[0..14] of string = ('ListBox', 'SysListView32', 'SysTreeView32', 'ComboBox', 'Edit',
    'TListBox', 'TCheckListBox', 'TComboBox', 'TListView', 'TTreeView', 'TEdit', 'TMemo', 'TcxGrid', 'TcxGridSite', 'TcxTextEdit');
  STATUS_JOIN     = ' | '; // ConvertRun's own join, which its implementation keeps private

function EditorBusy(AWaitDepth: Integer; AHourGlass: Boolean): Boolean;
begin
  Result:= (AWaitDepth > 0) or AHourGlass;
end;

function GateVerdict(AMsg: Cardinal; ABusy, ATargetInMainForm: Boolean): TGateVerdict;
begin
  Result:= gvPass;
  if not (ABusy and ATargetInMainForm) then
    Exit;
  var LCommand: Boolean:= (AMsg = GATE_BM_CLICK) or (AMsg = GATE_WM_COMMAND);
  var LPress  : Boolean:= (AMsg = GATE_WM_LBUTTONDOWN) or (AMsg = GATE_WM_LBUTTONDBLCLK);
  var LKey    : Boolean:= (AMsg >= GATE_WM_KEYFIRST) and (AMsg <= GATE_WM_KEYLAST);
  var LMouse  : Boolean:= (AMsg > GATE_WM_MOUSEMOVE) and (AMsg <= GATE_WM_MOUSELAST);
  var LNcMouse: Boolean:= (AMsg > GATE_WM_NCMOUSEMOVE) and (AMsg <= GATE_WM_NCMOUSELAST);
  if LCommand or LPress then
    Result:= gvRefuse
  else if LKey or LMouse or LNcMouse then
    Result:= gvDrop;
end;

function IsSelectionClass(const AWndClass: string): Boolean;
begin
  Result:= MatchText(AWndClass, SELECTION_CLASSES);
end;

function GateVerdictFor(AMsg: Cardinal; ABusy, ATargetInMainForm: Boolean; const AWndClass: string): TGateVerdict;
begin
  Result:= GateVerdict(AMsg, ABusy, ATargetInMainForm);
  if (Result = gvRefuse) and ((AMsg = GATE_WM_LBUTTONDOWN) or (AMsg = GATE_WM_LBUTTONDBLCLK))
    and IsSelectionClass(AWndClass) then
    Result:= gvDrop;
end;

function CommandName(const ACaption: string): string;
begin
  // '&&' is a literal '&': parked on #0 while the hotkey markers go.
  Result:= ACaption.Replace('&&', #0).Replace('&', '').Replace(#0, '&').Trim;
  if Result.EndsWith(ELLIPSIS) then
    Result:= Trim(Copy(Result, 1, Length(Result) - Length(ELLIPSIS)));
  if Result = '' then
    Result:= LOST_COMMAND_UNNAMED;
end;

function LostCommandStatus(const ACurrent, ACommand, ABusyTitle: string): string;
begin
  if ACommand = LOST_COMMAND_CONVERT then
    Exit(LostConvertClickStatus(ACurrent, ABusyTitle));
  Result:= Format(LOST_COMMAND_FMT, [ACommand, ABusyTitle]);
  if ACurrent <> '' then
    Result:= ACurrent + STATUS_JOIN + Result;
end;

function BusyTitleFor(const AWaitTitle, AStatus: string): string;
begin
  if AWaitTitle <> '' then
    Result:= AWaitTitle
  else if Trim(AStatus) <> '' then
    Result:= Trim(AStatus)
  else
    Result:= BUSY_TITLE_UNKNOWN;
end;

end.
