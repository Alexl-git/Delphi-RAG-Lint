unit PartBB;

// E18 T7 fixture (Part B is R3-aware): see PartBA.

interface

type
  /// <summary>A kind PartBA's interface names.</summary>
  TPartBKind = (pbkOne, pbkTwo);

/// <summary>Prints PartBADouble(CPartBArg).</summary>
procedure PartBBRun;

implementation

uses
  PartBA;

const
  /// <summary>The value PartBBRun doubles.</summary>
  CPartBArg = 21;

procedure PartBBRun;
begin
  Writeln(PartBADouble(CPartBArg));
end;

end.