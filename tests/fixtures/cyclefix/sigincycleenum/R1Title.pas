unit R1Title;

// CYC-B B3 fixture: the one routine on the cuttable edge R1Form -> R1Title returns an enum
// declared in R1Title, a unit of the cycle: the enum moves into the leaf first, then the
// pointer type there names it.

interface

type
  /// <summary>How a title is shown.</summary>
  TR1TitleKind = (tkPlain, tkBold);

/// <summary>How the title of one item is shown.</summary>
/// <param name="pId">Item id.</param>
/// <returns>tkBold when the navigation caption is longer than pId.</returns>
function R1TitleKind(const pId: Integer): TR1TitleKind;

implementation

uses
  R1Nav;

function R1TitleKind(const pId: Integer): TR1TitleKind;
begin
  if Length(TR1Nav.Caption) > pId then Result := tkBold else Result := tkPlain;
end;

end.