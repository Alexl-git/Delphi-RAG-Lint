unit R1Title;

// CYC-B B3 fixture: TWO routines on the cuttable edge R1Form -> R1Title -- R1 for N routines.

interface

uses
  System.SysUtils;

/// <summary>Title of one item.</summary>
/// <param name="pId">Item id.</param>
/// <returns>The title text.</returns>
function R1TitleOf(const pId: Integer): string;
/// <summary>Length of the title of one item.</summary>
/// <param name="pId">Item id.</param>
/// <returns>The title length.</returns>
function R1TitleLen(const pId: Integer): Integer;

implementation

uses
  R1Nav;

function R1TitleOf(const pId: Integer): string;
begin
  Result := Format('title %d via %s', [pId, TR1Nav.Caption]);
end;
function R1TitleLen(const pId: Integer): Integer;
begin
  Result := Length(R1TitleOf(pId));
end;

end.