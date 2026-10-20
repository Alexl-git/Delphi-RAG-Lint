unit R1Title;

// E18 T5 fixture: declares the routine on the cuttable edge R1Form -> R1Title.

interface

uses
  System.SysUtils;

/// <summary>Title of one item.</summary>
/// <param name="pId">Item id.</param>
/// <returns>The title text.</returns>
function R1TitleOf(const pId: Integer): string;

implementation

uses
  R1Nav;

function R1TitleOf(const pId: Integer): string;
begin
  Result := Format('title %d via %s', [pId, TR1Nav.Caption]);
end;

end.