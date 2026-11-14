unit RmmUnknown;

{ review-marker-malformed, widened in v151 RMU: an unknown rule id is
  reported in the legacy drag-lint:ignore directive too, not only in dl:ok.
  This brace comment quotes drag-lint:ignore no-such-rule-here and must stay
  silent: a block comment carries no directive. }

interface

implementation

uses System.SysUtils;

procedure P;
var
  I: Integer;
begin
  I := 0;
  I := I + 1; // dl:ok no-such-rule -- unknown id in a dl:ok
  I := I + 2; // drag-lint:ignore no-such-rule
  I := I + 3; // drag-lint:ignore magic-literal, no-such-rule
  I := I + 4; // drag-lint:ignore
  I := I + 5; // drag-lint:ignore magic-literal -- known id, then prose with-hyphens
  I := I + 6; // drag-lint:ignore magic-literal because of hand-tuned values
  /// drag-lint:ignore no-such-rule in a doc comment is prose
  WriteLn(I);
end;

end.
