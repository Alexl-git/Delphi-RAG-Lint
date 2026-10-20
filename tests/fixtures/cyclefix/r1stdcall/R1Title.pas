unit R1Title;

// E18 T5 fix round 1 fixture: r1extend with the routine declared stdcall -- the
// procedural type of the inversion must carry the calling convention (E2010 without it).

interface

uses
  System.SysUtils;

/// <summary>Title of one item.</summary>
/// <param name="pId">Item id.</param>
/// <returns>The title text.</returns>
function R1TitleOf(const pId: Integer): string; stdcall;

implementation

uses
  R1Nav;

function R1TitleOf(const pId: Integer): string; stdcall;
begin
  Result := Format('title %d via %s', [pId, TR1Nav.Caption]);
end;

end.