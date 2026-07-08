unit DragLint.Plugin.Options;

{ INTAAddInOptions implementation: registers the four drag-lint Options
  page frames (DragLint.Plugin.OptionsFrames) as four nested pages under
  Tools > Options > Third Party > drag-lint > General/Indexer/Linter/Editor.

  Registration:   RegisterDragLintOptions
  Unregistration: UnregisterDragLintOptions
  (both called from DragLint.Plugin.Wizard.Register / teardown; the unit
  finalization below is a secondary net in case teardown is skipped) }

interface

procedure RegisterDragLintOptions;
procedure UnregisterDragLintOptions;

implementation

uses
  System.SysUtils
  , System.Classes
  , Vcl.Forms
  , Vcl.Controls
  , ToolsAPI
  , DragLint.Plugin.OptionsFrames
  ;

{ ---- TDragLintOptionsPage: INTAAddInOptions ---- }

type
  /// <summary>INTAAddInOptions page carrying one drag-lint frame class
  /// (General/Indexer/Linter/Editor). One instance per page; the dotted
  /// caption ('drag-lint.Xxx') nests all four under a single 'drag-lint'
  /// node in the Third Party area (GetArea returns '').</summary>
  TDragLintOptionsPage = class(TInterfacedObject, INTAAddInOptions)
    private
      FCaption   : string;
      FFrameClass: TCustomFrameClass;
      FFrame     : TDLPageFrame;
    public
      constructor Create(const ACaption: string; AFrameClass: TCustomFrameClass);
      { INTAAddInOptions }
      function GetArea   : string;
      function GetCaption: string;
      function GetFrameClass: TCustomFrameClass;
      procedure FrameCreated(AFrame  : TCustomFrame);
      procedure DialogClosed(Accepted: Boolean     );
      function ValidateContents   : Boolean;
      function GetHelpContext     : Integer;
      function IncludeInIDEInsight: Boolean;
  end;

constructor TDragLintOptionsPage.Create(const ACaption: string; AFrameClass: TCustomFrameClass);
begin
  inherited Create;
  FCaption   := ACaption;
  FFrameClass:= AFrameClass;
end;

function TDragLintOptionsPage.GetArea: string;
begin
  { Empty string = appear under "Third Party" area in the left tree }
  Result:= '';
end;

function TDragLintOptionsPage.GetCaption: string;
begin
  Result:= FCaption;
end;

function TDragLintOptionsPage.GetFrameClass: TCustomFrameClass;
begin
  Result:= FFrameClass;
end;

procedure TDragLintOptionsPage.FrameCreated(AFrame: TCustomFrame);
begin
  if AFrame is TDLPageFrame then
  begin
    FFrame:= TDLPageFrame(AFrame);
    FFrame.Load;
  end;
end;

procedure TDragLintOptionsPage.DialogClosed(Accepted: Boolean);
begin
  if Accepted and Assigned(FFrame) then FFrame.Save;
  FFrame:= nil;
end;

function TDragLintOptionsPage.ValidateContents: Boolean;
begin
  { No validation }
  Result:= True;
end;

function TDragLintOptionsPage.GetHelpContext: Integer;
begin
  Result:= 0;
end;

function TDragLintOptionsPage.IncludeInIDEInsight: Boolean;
begin
  Result:= True;
end;

{ ---- module-level refs: kept so we can Unregister the exact same instances ---- }

var
  GOptions: array of INTAAddInOptions;

procedure RegisterDragLintOptions;
var
  Svc: INTAEnvironmentOptionsServices;

  procedure Add(const ACap: string; AFC: TCustomFrameClass);
  var
    O: INTAAddInOptions;
  begin
    O:= TDragLintOptionsPage.Create(ACap, AFC);
    Svc.RegisterAddInOptions(O);
    GOptions:= GOptions + [O];
  end;

begin
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then Exit;
  Add('drag-lint.General', TDLGeneralOptionsFrame);
  Add('drag-lint.Indexer', TDLIndexerOptionsFrame);
  Add('drag-lint.Linter' , TDLLinterOptionsFrame );
  Add('drag-lint.Editor' , TDLEditorOptionsFrame );
end;

procedure UnregisterDragLintOptions;
var
  Svc: INTAEnvironmentOptionsServices;
  O  : INTAAddInOptions;
begin
  if Length(GOptions) = 0 then Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then
    for O in GOptions do try Svc.UnregisterAddInOptions(O); except end;
  SetLength(GOptions, 0);
end;

initialization

finalization
  UnregisterDragLintOptions;  // secondary net; Wizard.Destroyed is primary (Task 7)

end.
