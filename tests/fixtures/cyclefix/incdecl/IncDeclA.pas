unit IncDeclA;

// Plan fixture (lane CYC3, item 2): IncDeclA declares TIncDeclARec in an include of its interface; IncDeclB
// uses IncDeclA only for that record.

interface

{$I IncDeclTypes.inc}

/// <summary>A fixed record.</summary>
/// <returns>X = 1.</returns>
function IncDeclAMake: TIncDeclARec;

implementation

uses
  IncDeclB;

function IncDeclAMake: TIncDeclARec;
begin
  Result.X:= 1;
  IncDeclBShow(Result);
end;

end.
