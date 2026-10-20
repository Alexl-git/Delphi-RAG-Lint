unit DemoControlPlan;

// CYCLE ROLE: routine-call cycle, edge DemoControlPlan -> DemoBlueprint.
// "Exit to drawing" CONSTRUCTS TDemoBlueprint through a class function and
// reads a member -- again not a mechanical cut. Only the drawing's own edge
// (DemoBlueprint -> DemoBlueprint.ViewModel) is.

interface

uses
  System.SysUtils;

type
  /// <summary>Stand-in for the control-plan form of a folder.</summary>
  TDemoControlPlan = class
  private
    FFolderId: Integer;
  public
    /// <summary>Opens the control plan of a folder (the real form's CreateForFolder).</summary>
    /// <param name="pFolderId">Folder whose plan is opened.</param>
    /// <returns>A new instance; the caller owns it.</returns>
    class function CreateForFolder(const pFolderId: Integer): TDemoControlPlan;
    /// <summary>Remembers the folder.</summary>
    /// <param name="pFolderId">Folder whose plan is opened.</param>
    constructor Create(const pFolderId: Integer);
    /// <summary>Window title of the plan.</summary>
    function Title: string;
    /// <summary>Navigates back to the drawing of the same folder (the real
    /// form's "exit to drawing" button).</summary>
    procedure ExitToDrawing;
    /// <summary>Folder this plan belongs to.</summary>
    property FolderId: Integer read FFolderId;
  end;

implementation

uses
  DemoBlueprint; // constructs TDemoBlueprint and reads FolderId: not a mechanical cut

class function TDemoControlPlan.CreateForFolder(const pFolderId: Integer): TDemoControlPlan;
begin
  Result := TDemoControlPlan.Create(pFolderId);
end;

constructor TDemoControlPlan.Create(const pFolderId: Integer);
begin
  inherited Create;
  FFolderId := pFolderId;
end;

function TDemoControlPlan.Title: string;
begin
  Result := Format('control plan of folder %d', [FFolderId]);
end;

procedure TDemoControlPlan.ExitToDrawing;
var
  LDrawing: TDemoBlueprint;
begin
  LDrawing := TDemoBlueprint.CreateForFolder(FFolderId);
  try
    Writeln(Format('[controlplan] back to the drawing of folder %d', [LDrawing.FolderId]));
  finally
    LDrawing.Free;
  end;
end;

end.
