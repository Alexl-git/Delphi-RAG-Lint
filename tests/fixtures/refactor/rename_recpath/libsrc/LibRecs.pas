unit LibRecs;

// NOT part of the project: the miniature platform library of run_rename_recpath.ps1.

interface

type
  TLibPoint = record
    X: Integer;
    Y: Integer;
  end;

  TLibShape = record
    Pts: array[0..1] of TLibPoint;
  end;

implementation

end.