unit DemoBlueprint;

// ---------------------------------------------------------------------------
// CYCLE ROLE: the ROUTINE-CALL cycle (three units, implementation-only).
//
//   DemoBlueprint           -> DemoBlueprint.ViewModel  (implementation: ONE
//                                                        routine call,
//                                                        DemoBlueprintViewModelCreate)
//   DemoBlueprint.ViewModel -> DemoControlPlan          (implementation: class
//                                                        construction + members)
//   DemoControlPlan         -> DemoBlueprint            (implementation: class
//                                                        construction + members)
//
// Modelled on a real client: a drawing form creates its view model through a
// factory function declared in the view-model unit; the view model navigates
// to a sibling form; the sibling navigates back to the drawing. Nothing on any
// edge is a plain constant or variable, so "move the globals into a leaf" does
// not apply. The cheapest cut is the FIRST edge: the routine's signature uses
// only Integer and IDemoBlueprintViewModel (declared in the leaf
// DemoBlueprint.Interfaces), so the drawing can call it through a procedural
// variable declared in that leaf and assigned by DemoBlueprint.ViewModel in
// its initialization section -- "routine-call inversion".
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  DemoBlueprint.Interfaces;

type
  /// <summary>Stand-in for the drawing form: owns one view model per folder.</summary>
  /// <remarks>The real form's FormShow creates the view model; here <c>Show</c> does.</remarks>
  TDemoBlueprint = class
  private
    FFolderId: Integer;
    FViewModel: IDemoBlueprintViewModel;
  public
    /// <summary>Creates a drawing for one folder (the real form's CreateForFolder).</summary>
    /// <param name="pFolderId">Folder whose drawing is opened.</param>
    /// <returns>A new instance; the caller owns it.</returns>
    class function CreateForFolder(const pFolderId: Integer): TDemoBlueprint;
    /// <summary>Remembers the folder; the view model is created by <c>Show</c>.</summary>
    /// <param name="pFolderId">Folder whose drawing is opened.</param>
    constructor Create(const pFolderId: Integer);
    /// <summary>Creates the view model through the factory routine of
    /// DemoBlueprint.ViewModel -- the one call that closes the cycle.</summary>
    procedure Show;
    /// <summary>Asks the view model to navigate to the control plan.</summary>
    procedure OpenControlPlan;
    /// <summary>Folder this drawing shows.</summary>
    property FolderId: Integer read FFolderId;
  end;

implementation

uses
  DemoBlueprint.ViewModel; // <-- the edge to cut: used for ONE routine call

class function TDemoBlueprint.CreateForFolder(const pFolderId: Integer): TDemoBlueprint;
begin
  Result := TDemoBlueprint.Create(pFolderId);
end;

constructor TDemoBlueprint.Create(const pFolderId: Integer);
begin
  inherited Create;
  FFolderId := pFolderId;
end;

procedure TDemoBlueprint.Show;
begin
  // The ONLY symbol this unit takes from DemoBlueprint.ViewModel.
  FViewModel := DemoBlueprintViewModelCreate(FFolderId);
  Writeln(Format('[blueprint] folder %d shown: %s', [FFolderId, FViewModel.Caption]));
end;

procedure TDemoBlueprint.OpenControlPlan;
begin
  if FViewModel <> nil then
    FViewModel.OpenControlPlan;
end;

end.
