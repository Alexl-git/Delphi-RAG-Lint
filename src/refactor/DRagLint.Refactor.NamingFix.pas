unit DRagLint.Refactor.NamingFix;

interface

type
  /// <summary>Target casing styles, matching TNamingConfig's textual vocabulary.</summary>
  TNameStyle = (nsPascalCase, nsCamelCase, nsUpperCase);

/// <summary>Maps a TNamingConfig case string ('PascalCase' | 'camelCase' |
/// 'UPPER_CASE') to a TNameStyle. Unknown/empty -> nsPascalCase.</summary>
function StyleFromConfigText(const AConfigCase: string): TNameStyle;

/// <summary>Returns AOldName re-cased to AStyle WITHOUT changing its letters or
/// inserting separators (a pure, collision-free re-casing in a case-insensitive
/// language). PascalCase upper-cases the first char; camelCase lower-cases it;
/// UPPER_CASE upper-cases the whole identifier. Idempotent. Empty -> ''.</summary>
/// <param name="AOldName">The offending identifier verbatim.</param>
/// <param name="AStyle">Target style.</param>
/// <returns>The re-cased identifier.</returns>
/// <remarks>DECISION: phase-1 is pure re-casing only -- no separator
/// insertion. UPPER_CASE therefore yields e.g. MAXCOUNT, not MAX_COUNT
/// (word-boundary detection is a phase-2 concern; this keeps phase-1
/// collision-free and mechanical).</remarks>
function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;

implementation

uses
  System.SysUtils;

function StyleFromConfigText(const AConfigCase: string): TNameStyle;
begin
  if SameText(AConfigCase, 'camelCase') then Result := nsCamelCase
  else if SameText(AConfigCase, 'UPPER_CASE') then Result := nsUpperCase
  else Result := nsPascalCase;
end;

function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;
begin
  if AOldName = '' then Exit('');
  case AStyle of
    nsUpperCase : Result := UpperCase(AOldName);
    nsCamelCase : Result := LowerCase(AOldName[1]) + Copy(AOldName, 2, MaxInt);
    else          Result := UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt); // nsPascalCase
  end;
end;

end.
