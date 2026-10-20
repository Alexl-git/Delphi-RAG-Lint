unit R1Title;

// E18 T5 fix round 2 fixture: declares the routine on the cuttable edge R1Form -> R1Title,
// and R1Note, a name TR1Form inherits from TR1Base as well.

interface

uses
  System.SysUtils;

/// <summary>Title of one item.</summary>
/// <param name="pId">Item id.</param>
/// <returns>The title text.</returns>
function R1TitleOf(const pId: Integer): string;

/// <summary>Prints a note (never called: TR1Form's R1Note is its inherited method).</summary>
/// <param name="pText">The note.</param>
procedure R1Note(const pText: string);

implementation

uses
  R1Nav;

function R1TitleOf(const pId: Integer): string;
begin
  Result := Format('title %d via %s', [pId, TR1Nav.Caption]);
end;

procedure R1Note(const pText: string);
begin
  Writeln('[title] ', pText);
end;

end.
