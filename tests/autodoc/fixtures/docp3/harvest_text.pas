unit harvest_text;

interface

// True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive
// shield and unshield scans; deliberately ASCII-only.
function IsAsciiAlpha(C: Char): Boolean;

// First paragraph becomes the summary.
//
// Second paragraph becomes remarks prose. It mentions A < B & C > D so the
// XML escaping is exercised on real content.
function TwoParagraphs: Integer;

implementation

function IsAsciiAlpha(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

// Calls IsAsciiAlpha so TwoParagraphs renders a facts block at all. Without a
// fact there is no AUTO_BEGIN fence, and "the harvested prose sits ABOVE the
// fence" would be asserted against a fence that does not exist.
function TwoParagraphs: Integer;
begin
  if IsAsciiAlpha('x') then Result := 1 else Result := 0;
end;

end.
