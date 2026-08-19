unit DragLint.Plugin.StatusLine;

{ A short progress note in the EDITOR window's status bar.

  WHY (owner, 2026-08-19): "Every time you sense there is a need to show hover
  popup, show a message Hover and a symbol in the status line. This way I'll
  know you started thinking about it." A hover that is merely SLOW and a hover
  that is never coming look identical without one.

  WHY ITS OWN UNIT, and not a helper inside DragLint.Plugin.Editor: the status
  bar types live in Vcl.ComCtrls, and adding that unit to Editor's uses changed
  overload resolution there -- three existing `Queue(...)` calls stopped
  compiling. A six-thousand-line unit is exactly where an extra uses entry has
  consequences nobody predicted, so the dependency stays here.

  WE OWN OUR PANEL. Writing into one of the IDE's panels would clobber the caret
  position or the modified flag, and the IDE would overwrite us on the next
  keystroke anyway. So a panel is appended once per edit window and remembered
  BY OBJECT IDENTITY -- TStatusPanel is a TCollectionItem and has no Tag to
  stamp, and matching on text or width would be a guess. }

interface

/// <summary>Writes a note into the active edit window's status bar.</summary>
/// <param name="AText">The note, e.g. 'drag-lint: hover WindowState'. An empty
/// string clears it without removing the panel.</param>
/// <remarks>Main thread only. Guarded: it is called from a 200 ms dwell timer,
/// where an escaping exception surfaces as an IDE crash, so every failure path
/// here is silent by design.</remarks>
procedure SetEditorStatus(const AText: string);

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , Vcl.ComCtrls
  , ToolsAPI
  ;

var
  { StatusBar -> the panel we appended to it. Keyed by the bar because the IDE
    has one per edit window, and a floating window is a second one. }
  GPanels: TDictionary<TStatusBar, TStatusPanel> = nil;

function OurPanel(ASB: TStatusBar): TStatusPanel;
var
  Saved: TStatusPanel;
  i    : Integer     ;
  Found: Boolean     ;
begin
  Result:= nil;
  if GPanels = nil then GPanels:= TDictionary<TStatusBar, TStatusPanel>.Create;

  if GPanels.TryGetValue(ASB, Saved) and (Saved <> nil) then
  begin
    { Confirm the remembered panel is STILL in this bar, by identity. The bar
      may have been rebuilt (desktop reload, window re-dock), in which case the
      saved reference is dangling and must not be written through. }
    Found:= False;
    for i:= 0 to ASB.Panels.Count - 1 do
      if ASB.Panels[i] = Saved then
      begin
        Found:= True;
        Break;
      end;
    if Found then Exit(Saved);
    GPanels.Remove(ASB);
  end;
  Result:= nil;
end;

procedure SetEditorStatus(const AText: string);
var
  ESS  : IOTAEditorServices;
  EV   : IOTAEditView      ;
  EW   : INTAEditWindow    ;
  SB   : TStatusBar        ;
  Panel: TStatusPanel      ;
begin
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EV:= ESS.TopView;
    if EV = nil then Exit;
    EW:= EV.GetEditWindow;
    if EW = nil then Exit;
    SB:= EW.StatusBar;
    if SB = nil then Exit;

    Panel:= OurPanel(SB);

    { Nothing to say and no panel of ours yet -- do not create one just to leave
      it blank. Clearing is common (every popup clears); creating on a clear
      would add a panel to every window the user merely looked at. }
    if (Panel = nil) and (AText = '') then Exit;

    if Panel = nil then
    begin
      Panel:= SB.Panels.Add;
      Panel.Width:= 260;
      Panel.Style:= psText;
      GPanels.AddOrSetValue(SB, Panel);
    end;

    Panel.Text:= AText;
  except
    { Cosmetic. It must never raise -- see the interface remarks. }
  end;
end;

initialization

finalization
  GPanels.Free;

end.
