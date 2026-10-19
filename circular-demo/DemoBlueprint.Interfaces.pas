unit DemoBlueprint.Interfaces;

// CYCLE ROLE: NOT in any cycle. A leaf unit that BOTH DemoBlueprint and
// DemoBlueprint.ViewModel use in their INTERFACE section. It matters for the
// routine-call cycle (see DemoBlueprint.pas): the one routine on the edge
// DemoBlueprint -> DemoBlueprint.ViewModel has the signature
//   function (const pFolderId: Integer): IDemoBlueprintViewModel
// and every type in it is declared OUTSIDE the cycle -- here. That is what
// makes the edge cuttable by a procedural variable living in this unit.

interface

type
  /// <summary>What the drawing (DemoBlueprint) needs from its view model.</summary>
  IDemoBlueprintViewModel = interface
    ['{5D3E0C0A-7B2F-4F1A-9C6E-2A8B4D1E3F70}']
    /// <summary>Folder the view model was created for.</summary>
    function GetFolderId: Integer;
    /// <summary>One-line description shown when the drawing opens.</summary>
    function Caption: string;
    /// <summary>Navigates to the control plan of the same folder.</summary>
    procedure OpenControlPlan;
    /// <summary>Folder the view model was created for.</summary>
    property FolderId: Integer read GetFolderId;
  end;

implementation

end.
