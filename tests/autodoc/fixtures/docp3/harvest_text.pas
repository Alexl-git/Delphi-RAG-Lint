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

// --- BannerLed ---------------------------------------------------------

// Real prose that must become the summary.
//
// Second paragraph stays remarks prose.
function BannerLed: Integer;

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

// Same device as TwoParagraphs: a call so the symbol has a fact and therefore a
// doc block. The BANNER above its INTERFACE declaration is the point of this
// shape -- a separate banner comment, ONE blank line, then the real prose. The
// boundary scan tolerates that single blank line, so it swallows the banner
// too; without a guard the banner becomes paragraph 1 and therefore the
// <summary>. Reproduced on real code first: YADFOT.Wizard.pas's `Register`
// summary read '--- Register ------...'.
function BannerLed: Integer;
begin
  if IsAsciiAlpha('y') then Result := 2 else Result := 0;
end;

end.
