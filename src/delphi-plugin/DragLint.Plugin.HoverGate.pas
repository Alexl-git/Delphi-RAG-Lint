unit DragLint.Plugin.HoverGate;

(* The show-gate for an ASYNC hover popup (owner spec, 2026-10-29).

   Since the hover request no longer blocks the IDE, its answer can arrive after
   the mouse has moved on. Showing it anyway puts a popup about token A under a
   mouse that now points at token B -- or over the Project Manager. So the
   answer is shown only when the pointer is STILL where the question was asked:

     * over the SAME editor control window the dwell started in (the window
       under the cursor, not a bounding rectangle: a docked Project Manager sits
       inside the editor FORM's rectangle, which is how popups used to appear
       over it), and
     * horizontally anywhere within the hovered identifier's span, and
     * vertically within +-0.6 of a line height around the centre of the
       original line (so a hand drifting a few pixels keeps the popup, while
       the next line's token does not).

   Everything here is pure arithmetic on numbers the caller supplies -- no Open
   Tools API, no VCL -- so it is unit-tested outside the IDE
   (tests\LspNonBlockingTests.dpr). *)

interface

uses
  System.Types
  , Winapi.Windows
  ;

const
  /// <summary>Vertical tolerance, as a fraction of the line height, measured
  /// from the centre of the original line in either direction.</summary>
  HOVER_GATE_Y_TOLERANCE = 0.6;

type
  /// <summary>Where a dwell asked its hover question, in the editor control's
  /// CLIENT coordinates.</summary>
  /// <remarks>Captured on the main thread when the request goes out and
  /// compared with the pointer when the answer arrives. Hwnd = 0 means "no
  /// anchor": the gate then refuses everything.</remarks>
  TDLHoverAnchor = record
    Hwnd       : HWND   ; { the editor control the dwell started in }
    TokenLeftX : Integer; { first client X of the identifier (inclusive) }
    TokenRightX: Integer; { first client X AFTER the identifier (exclusive) }
    LineTopY   : Integer; { client Y of the hovered line's top edge }
    LineHeight : Integer; { pixel height of one editor line; > 0 }
  end;

  /// <summary>Outcome of the show-gate. Only hgvShow shows the popup; the
  /// others name WHY it was discarded, for telemetry.</summary>
  TDLHoverGateVerdict = (
    hgvShow       , { pointer still on the same token of the same control }
    hgvNoAnchor   , { the anchor was never captured (Hwnd = 0 / height <= 0) }
    hgvOtherWindow, { the window under the cursor is not the anchor control }
    hgvOffToken   , { same control, but X left the identifier's span }
    hgvOffLine      { same control and X, but Y left the line band }
  );

/// <summary>Decides whether an arriving hover answer may be shown.</summary>
/// <param name="AAnchor">Where the request was asked (client coordinates).</param>
/// <param name="ANowHwnd">The window under the cursor NOW (WindowFromPoint).</param>
/// <param name="AClientPt">The cursor NOW, in AAnchor.Hwnd's client coordinates.</param>
/// <returns>hgvShow when ANowHwnd = AAnchor.Hwnd, TokenLeftX &lt;= X &lt;
/// TokenRightX and |Y - line centre| &lt;= HOVER_GATE_Y_TOLERANCE * LineHeight;
/// otherwise the first failing rule, checked in the order window, X, Y.</returns>
/// <remarks>Pure; never raises.</remarks>
function DLHoverGate(const AAnchor: TDLHoverAnchor; ANowHwnd: HWND; const AClientPt: TPoint): TDLHoverGateVerdict;

/// <summary>The identifier span containing a 0-based column of one line.</summary>
/// <param name="ALine">The line text.</param>
/// <param name="ACol0">0-based column the pointer maps to.</param>
/// <param name="AStart0">Receives the 0-based first column of the identifier.</param>
/// <param name="AEnd0">Receives the 0-based column just AFTER the identifier.</param>
/// <returns>False when ACol0 is outside the line or not on an identifier
/// character ([A-Za-z0-9_]).</returns>
/// <remarks>Pure; never raises.</remarks>
function DLIdentSpanAt(const ALine: string; ACol0: Integer; out AStart0, AEnd0: Integer): Boolean;

/// <summary>Builds the anchor for a token from the editor grid the gutter
/// painter publishes.</summary>
/// <param name="AHwnd">Editor control the grid belongs to.</param>
/// <param name="ATextLeft">Client X where column 0 of the text begins.</param>
/// <param name="ACharWidth">Pixel width of one (fixed-pitch) cell; &gt; 0.</param>
/// <param name="ALineTopY">Client Y of the hovered line's top edge.</param>
/// <param name="ALineHeight">Pixel height of one line; &gt; 0.</param>
/// <param name="AStart0">0-based first column of the token.</param>
/// <param name="AEnd0">0-based column just after the token.</param>
/// <returns>The anchor; X span = ATextLeft + column * ACharWidth, the exact
/// inverse of the mapping that turned the pointer into a column.</returns>
function DLHoverAnchorFor(AHwnd: HWND; ATextLeft, ACharWidth, ALineTopY, ALineHeight, AStart0, AEnd0: Integer): TDLHoverAnchor;

implementation

uses
  System.SysUtils
  ;

function DLHoverGate(const AAnchor: TDLHoverAnchor; ANowHwnd: HWND; const AClientPt: TPoint): TDLHoverGateVerdict;
begin
  if (AAnchor.Hwnd = 0) or (AAnchor.LineHeight <= 0) then Exit(hgvNoAnchor);
  if ANowHwnd <> AAnchor.Hwnd then Exit(hgvOtherWindow);
  if (AClientPt.X < AAnchor.TokenLeftX) or (AClientPt.X >= AAnchor.TokenRightX) then Exit(hgvOffToken);
  if Abs((AClientPt.Y - AAnchor.LineTopY) - AAnchor.LineHeight / 2) > HOVER_GATE_Y_TOLERANCE * AAnchor.LineHeight then Exit(hgvOffLine);
  Result:= hgvShow;
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function DLIdentSpanAt(const ALine: string; ACol0: Integer; out AStart0, AEnd0: Integer): Boolean;
begin
  AStart0:= -1;
  AEnd0  := -1;
  { Strings are 1-based: column c (0-based) is ALine[c + 1]. }
  if (ACol0 < 0) or (ACol0 >= Length(ALine)) then Exit(False);
  if not IsIdentChar(ALine[ACol0 + 1]) then Exit(False);
  AStart0:= ACol0;
  while (AStart0 > 0) and IsIdentChar(ALine[AStart0]) do Dec(AStart0);
  AEnd0:= ACol0 + 1;
  while (AEnd0 < Length(ALine)) and IsIdentChar(ALine[AEnd0 + 1]) do Inc(AEnd0);
  Result:= True;
end;

function DLHoverAnchorFor(AHwnd: HWND; ATextLeft, ACharWidth, ALineTopY, ALineHeight, AStart0, AEnd0: Integer): TDLHoverAnchor;
begin
  Result.Hwnd       := AHwnd;
  Result.TokenLeftX := ATextLeft + AStart0 * ACharWidth;
  Result.TokenRightX:= ATextLeft + AEnd0   * ACharWidth;
  Result.LineTopY   := ALineTopY;
  Result.LineHeight := ALineHeight;
end;

end.
