unit R1Title;

// CYC-B B3 fixture: one routine AND one constant on the cuttable edge R1Form -> R1Title --
// the constant moves into the leaf, the routine is called through a pointer declared there.

interface

uses
  System.SysUtils;

const
  /// <summary>The largest item id.</summary>
  CR1TitleMax = 9;

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