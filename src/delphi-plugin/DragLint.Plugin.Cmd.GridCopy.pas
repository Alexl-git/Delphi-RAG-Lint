unit DragLint.Plugin.Cmd.GridCopy;

{ 1.56 command unit, stub (lane FRAME-2): the "Copy Grid Columns" row of the
  Field Repository submenu. Owned later by lane GC-S / GC-R / GC-W / GC-H,
  which replace the body of InvokeGridCopy. The menu row itself is registered
  in DragLint.Plugin.Cmd.FieldRepo (RegisterCommands), so the full menu path
  stays in one place: drag-lint > Field Repository > Copy Grid Columns... }

interface

const
  /// <summary>Command id of the grid-copy row in the 1.52 command table.</summary>
  GRID_COPY_CMD_ID = 'field-repository-10-grid-copy';

/// <summary>Click handler of drag-lint > Field Repository > Copy Grid Columns...</summary>
/// <param name="pSender">The clicked menu item; unused by the stub.</param>
/// <remarks>
/// Stub: shows the "not yet available" message of the command table. Call from
/// the IDE main thread only (menu click). Replaced by the GRIDCOL2 lanes.
/// </remarks>
procedure InvokeGridCopy(pSender: TObject);

implementation

uses
  DragLint.Plugin.Cmd152;

procedure InvokeGridCopy(pSender: TObject);  // dl:ok unused-parameter@1fb2 -- TCmd152Click signature; stub ignores the sender
begin
  Cmd152NotYetAvailable(GRID_COPY_CMD_ID);
end;

end.
