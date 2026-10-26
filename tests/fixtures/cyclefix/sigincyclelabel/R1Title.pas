unit R1Title;

// CYCC fixture (refusal label): the edge R1Form -> R1Title reads the var GR1Count FIRST, then calls a
// routine returning a record whose method body drags R1Nav: signature-in-cycle names the record, and its
// label must say (record), not the kind of the edge's first need (var).

interface

type
  /// <summary>How a title is shown.</summary>
  TR1TitleKind = record
    K: Integer;
    function Bold: Boolean;
  end;

var
  /// <summary>Read by the form.</summary>
  GR1Count: Integer = 2;

/// <summary>How the title of one item is shown.</summary>
/// <param name="pId">Item id.</param>
/// <returns>tkBold when the navigation caption is longer than pId.</returns>
function R1TitleKind(const pId: Integer): TR1TitleKind;

implementation

uses
  R1Nav;

function TR1TitleKind.Bold: Boolean;
begin
  Result := Length(TR1Nav.Caption) > K;
end;

function R1TitleKind(const pId: Integer): TR1TitleKind;
begin
  Result.K := pId;
end;

end.