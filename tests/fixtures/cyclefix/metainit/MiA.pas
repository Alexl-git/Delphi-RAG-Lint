unit MiA;

// Plan fixture (lane CYC3 finisher, FOUND-152c a): MiA's initialization passes the class TMiJob of MiB as a
// VALUE (System.Classes.RegisterClass). The cycle has three units (MiA -> MiC -> MiB -> MiA, plus MiA -> MiB),
// so after the metaclass hand-over MiA still reaches MiB through MiC: the .dpr order proves MiB initializes
// first, and the plan prints the proof instead of "its own initialization section makes none of these calls".

interface

/// <summary>Registers TMiJob and writes its class name.</summary>
procedure MiAStart;

/// <summary>A fixed value.</summary>
/// <returns>4.</returns>
function MiAValue: Integer;

implementation

uses
  System.Classes, MiC, MiB;

procedure MiAStart;
begin
  RegisterClass(TMiJob);
  Writeln('[a] ', GetClass('TMiJob').ClassName);
end;

function MiAValue: Integer;
begin
  Result:= 4;
end;

var
  GPing: procedure;

initialization
  GPing:= @MiCPing;
  Writeln('init MiA');
  MiAStart;

end.
