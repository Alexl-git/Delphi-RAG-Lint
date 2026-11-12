unit IncDeclB;

// Plan fixture (lane CYC3, item 2): the interface names TIncDeclARec, declared in an include of IncDeclA.

interface

uses
  IncDeclA;

/// <summary>Writes the record.</summary>
/// <param name="pRec">The record.</param>
procedure IncDeclBShow(const pRec: TIncDeclARec);

implementation

procedure IncDeclBShow(const pRec: TIncDeclARec);
begin
  Writeln('[incdecl] ', pRec.X);
end;

end.
