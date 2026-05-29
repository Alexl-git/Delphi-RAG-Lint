unit DragLint.Plugin.Options;

{ INTAAddInOptions implementation: adds drag-lint as a native page
  under Tools > Options in the IDE.

  Registration:   RegisterDragLintOptions
  Unregistration: UnregisterDragLintOptions
  (both called from DragLint.Plugin.Wizard.Register / teardown) }

interface

procedure RegisterDragLintOptions;
procedure UnregisterDragLintOptions;

implementation

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls,
  ToolsAPI,
  DragLint.Plugin.OptionsFrame;

{ ---- TDragLintOptions: INTAAddInOptions ---- }

type
  TDragLintOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FFrame: TDragLintOptionsFrame;
  public
    { INTAAddInOptions }
    function  GetArea:       string;
    function  GetCaption:    string;
    function  GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function  ValidateContents: Boolean;
    function  GetHelpContext:   Integer;
    function  IncludeInIDEInsight: Boolean;
  end;

function TDragLintOptions.GetArea: string;
begin
  { Empty string = appear under "Third Party" area in the left tree }
  Result := '';
end;

function TDragLintOptions.GetCaption: string;
begin
  Result := 'drag-lint';
end;

function TDragLintOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TDragLintOptionsFrame;
end;

procedure TDragLintOptions.FrameCreated(AFrame: TCustomFrame);
begin
  if AFrame is TDragLintOptionsFrame then
  begin
    FFrame := TDragLintOptionsFrame(AFrame);
    FFrame.Load;
  end;
end;

procedure TDragLintOptions.DialogClosed(Accepted: Boolean);
begin
  if Accepted and Assigned(FFrame) then
    FFrame.Save;
  FFrame := nil;
end;

function TDragLintOptions.ValidateContents: Boolean;
begin
  { No validation in v0.30 }
  Result := True;
end;

function TDragLintOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TDragLintOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ ---- module-level ref: kept so we can Unregister the exact same instance ---- }

var
  GOptions: INTAAddInOptions = nil;

procedure RegisterDragLintOptions;
var
  Svc: INTAEnvironmentOptionsServices;
begin
  if not Supports(BorlandIDEServices,
      INTAEnvironmentOptionsServices, Svc) then Exit;
  GOptions := TDragLintOptions.Create;
  Svc.RegisterAddInOptions(GOptions);
end;

procedure UnregisterDragLintOptions;
var
  Svc: INTAEnvironmentOptionsServices;
begin
  if GOptions = nil then Exit;
  if not Supports(BorlandIDEServices,
      INTAEnvironmentOptionsServices, Svc) then Exit;
  Svc.UnregisterAddInOptions(GOptions);
  GOptions := nil;
end;

end.
