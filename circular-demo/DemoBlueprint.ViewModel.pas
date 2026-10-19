unit DemoBlueprint.ViewModel;

// CYCLE ROLE: routine-call cycle, edge DemoBlueprint.ViewModel -> DemoControlPlan.
// The view model navigates to the control plan: it CONSTRUCTS TDemoControlPlan
// and reads a member, so this edge is not a mechanical cut (a class cannot
// be handed over through an interface when the consumer constructs it).
// This unit also DECLARES the routine that the drawing calls -- the symbol
// on the cuttable edge -- and is therefore the unit whose initialization
// section would assign the procedural variable after the cut.

interface

uses
  System.SysUtils,
  DemoBlueprint.Interfaces;

type
  /// <summary>View model of one drawing: knows its folder and how to navigate on.</summary>
  TDemoBlueprintViewModel = class(TInterfacedObject, IDemoBlueprintViewModel)
  private
    FFolderId: Integer;
  public
    /// <summary>Binds the view model to a folder.</summary>
    /// <param name="pFolderId">Folder of the drawing.</param>
    constructor Create(const pFolderId: Integer);
    /// <summary>Folder the view model was created for.</summary>
    function GetFolderId: Integer;
    /// <summary>One-line description shown when the drawing opens.</summary>
    function Caption: string;
    /// <summary>Opens the control plan of the folder and lets it navigate back.</summary>
    procedure OpenControlPlan;
  end;

/// <summary>Factory the drawing calls to get its view model. The ONLY symbol
/// DemoBlueprint uses from this unit; note the <c>const</c> parameter -- a
/// procedural type mirroring this signature must keep it.</summary>
/// <param name="pFolderId">Folder of the drawing.</param>
/// <returns>A new view model, reference-counted.</returns>
function DemoBlueprintViewModelCreate(const pFolderId: Integer): IDemoBlueprintViewModel;

implementation

uses
  DemoControlPlan; // constructs TDemoControlPlan: not a mechanical cut

function DemoBlueprintViewModelCreate(const pFolderId: Integer): IDemoBlueprintViewModel;
begin
  Result := TDemoBlueprintViewModel.Create(pFolderId);
end;

constructor TDemoBlueprintViewModel.Create(const pFolderId: Integer);
begin
  inherited Create;
  FFolderId := pFolderId;
end;

function TDemoBlueprintViewModel.GetFolderId: Integer;
begin
  Result := FFolderId;
end;

function TDemoBlueprintViewModel.Caption: string;
begin
  Result := Format('drawing of folder %d', [FFolderId]);
end;

procedure TDemoBlueprintViewModel.OpenControlPlan;
var
  LPlan: TDemoControlPlan;
begin
  LPlan := TDemoControlPlan.CreateForFolder(FFolderId);
  try
    Writeln(Format('[viewmodel] folder %d -> %s', [FFolderId, LPlan.Title]));
    LPlan.ExitToDrawing;
  finally
    LPlan.Free;
  end;
end;

end.
