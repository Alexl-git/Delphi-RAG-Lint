unit DragLint.Plugin.Keyboard;

{ Keystroke bindings for the drag-lint IDE plugin.
  Registers Ctrl+Alt+H/C/S/D via IOTAKeyboardServices.AddKeyboardBinding.
  Each binding checks the corresponding Enable* setting before dispatching
  to the matching Invoke* procedure in DragLint.Plugin.Editor.

  Circular-uses note: Editor's implementation uses this unit (to call
  Register/Unregister), and this unit's implementation uses Editor (to call
  Invoke*).  Delphi allows mutual implementation-section references.

  TKeyBindingProc is "of object", so key handlers must be methods of the
  binding object itself, not plain procedures. }

interface

procedure RegisterDragLintKeystrokes;
procedure UnregisterDragLintKeystrokes;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  ToolsAPI,
  DragLint.Plugin.Settings,
  DragLint.Plugin.Editor;

{ ---- IOTAKeyboardBinding implementation ---- }

type
  TDragLintKeyboardBinding = class(TInterfacedObject, IOTAKeyboardBinding)
  public
    { IOTANotifier stubs (required by IOTAKeyboardBinding's parent interface) }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAKeyboardBinding }
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    function  GetBindingType: TBindingType;
    function  GetDisplayName: string;
    function  GetName: string;
    { Key handler methods (TKeyBindingProc = procedure(...) of object) }
    procedure HoverKey(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure CompletionKey(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure SignatureKey(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DiagnosticsKey(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
  end;

{ IOTANotifier stubs }

procedure TDragLintKeyboardBinding.AfterSave;
begin
end;

procedure TDragLintKeyboardBinding.BeforeSave;
begin
end;

procedure TDragLintKeyboardBinding.Destroyed;
begin
end;

procedure TDragLintKeyboardBinding.Modified;
begin
end;

{ IOTAKeyboardBinding }

procedure TDragLintKeyboardBinding.BindKeyboard(
  const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding(
    [ShortCut(Ord('H'), [ssCtrl, ssAlt])], HoverKey,       nil);
  BindingServices.AddKeyBinding(
    [ShortCut(Ord('C'), [ssCtrl, ssAlt])], CompletionKey,  nil);
  BindingServices.AddKeyBinding(
    [ShortCut(Ord('S'), [ssCtrl, ssAlt])], SignatureKey,   nil);
  BindingServices.AddKeyBinding(
    [ShortCut(Ord('D'), [ssCtrl, ssAlt])], DiagnosticsKey, nil);
end;

function TDragLintKeyboardBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TDragLintKeyboardBinding.GetDisplayName: string;
begin
  Result := 'drag-lint Keybindings';
end;

function TDragLintKeyboardBinding.GetName: string;
begin
  Result := 'DragLint.KeyboardBinding';
end;

{ Key handlers — check Enable* settings, then dispatch to Editor.Invoke* }

procedure TDragLintKeyboardBinding.HoverKey(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableHover then Exit;
  InvokeHover(nil);
  BindingResult := krHandled;
end;

procedure TDragLintKeyboardBinding.CompletionKey(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableCompletion then Exit;
  InvokeCompletion(nil);
  BindingResult := krHandled;
end;

procedure TDragLintKeyboardBinding.SignatureKey(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableSignature then Exit;
  InvokeSignatureHelp(nil);
  BindingResult := krHandled;
end;

procedure TDragLintKeyboardBinding.DiagnosticsKey(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableDiagnostics then Exit;
  InvokeDiagnostics(nil);
  BindingResult := krHandled;
end;

{ ---- register / unregister ---- }

var
  GBindingIndex: Integer = -1;
  GBinding: TDragLintKeyboardBinding = nil;

procedure RegisterDragLintKeystrokes;
var
  KS: IOTAKeyboardServices;
begin
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, KS) then Exit;
  GBinding      := TDragLintKeyboardBinding.Create;
  GBindingIndex := KS.AddKeyboardBinding(GBinding);
end;

procedure UnregisterDragLintKeystrokes;
var
  KS: IOTAKeyboardServices;
begin
  if GBindingIndex < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KS) then
    KS.RemoveKeyboardBinding(GBindingIndex);
  GBindingIndex := -1;
  GBinding      := nil;
end;

end.
