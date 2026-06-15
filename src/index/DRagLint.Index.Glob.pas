unit DRagLint.Index.Glob;

interface

uses
  System.SysUtils;

type
  /// <summary>Glob-pattern matcher for file names and paths.
  /// Supports '*' (any non-separator run), '?' (one char), and '**' (any run
  /// including path separators). Matching is case-insensitive (Windows) and
  /// anchored (whole-string match).</summary>
  TGlob = class
  public
    /// <summary>Match AName against APattern. '*' = any run of non-separator
    /// chars, '?' = one char, '**' = any run incl. path separators.
    /// Case-insensitive (Windows). Anchored (whole-string match).</summary>
    /// <param name="AName">The file name or path to test.</param>
    /// <param name="APattern">The glob pattern (may contain *, ?, **).</param>
    /// <returns>True if AName matches APattern.</returns>
    class function Matches(const AName, APattern: string): Boolean; static;

    /// <summary>Return True if AName matches any pattern in APatterns.</summary>
    /// <param name="AName">The file name or path to test.</param>
    /// <param name="APatterns">Array of glob patterns.</param>
    /// <returns>True if AName matches at least one pattern.</returns>
    class function MatchesAny(const AName: string;
      const APatterns: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.RegularExpressions,
  System.StrUtils;

{ ---- internal helpers ---------------------------------------------------- }

// Normalize path separators in AName to forward slash so that the regex only
// needs to match one separator variant.
function NormalizeSeps(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
end;

// Escape a single literal character for use inside a regex.
// Characters that have special meaning in PCRE are escaped with '\'.
function EscapeRegexChar(C: Char): string;
const
  // All PCRE metacharacters that need escaping in a literal context.
  METAS: array[0..11] of Char =
    ('.', '(', ')', '[', ']', '{', '}', '+', '^', '$', '|', '\');
var
  I: Integer;
begin
  for I := Low(METAS) to High(METAS) do
    if C = METAS[I] then
    begin
      Result := '\' + C;
      Exit;
    end;
  Result := C;
end;

// Translate a glob pattern into an anchored PCRE regex string.
//   '**'  -> '.*'            (cross-separator wildcard)
//   '*'   -> '[^/]*'         (within-segment wildcard; '/' is the normalised sep)
//   '?'   -> '.'             (any single character)
//   '/'   -> '[/\\]'         (accept both sep styles)
//   other -> regex-escaped literal
function GlobToRegex(const APattern: string): string;
var
  I, Len: Integer;
  C:      Char;
  NormPat: string;
begin
  // Normalize separators in the pattern too so the translation is uniform.
  NormPat := NormalizeSeps(APattern);
  Len    := Length(NormPat);
  Result := '^';
  I := 1;
  while I <= Len do
  begin
    C := NormPat[I];
    if (C = '*') and (I < Len) and (NormPat[I + 1] = '*') then
    begin
      // '**' -- cross-directory wildcard
      Result := Result + '.*';
      Inc(I, 2);
      // Skip any trailing separator after '**' so '**/' doesn't force a sep.
      if (I <= Len) and (NormPat[I] = '/') then
        Result := Result + '[/\\]?';
    end
    else if C = '*' then
    begin
      // Single '*' -- any run of non-separator chars
      Result := Result + '[^/\\]*';
      Inc(I);
    end
    else if C = '?' then
    begin
      Result := Result + '.';
      Inc(I);
    end
    else if C = '/' then
    begin
      // Accept both slash variants for flexibility
      Result := Result + '[/\\]';
      Inc(I);
    end
    else
    begin
      Result := Result + EscapeRegexChar(C);
      Inc(I);
    end;
  end;
  Result := Result + '$';
end;

{ TGlob }

class function TGlob.Matches(const AName, APattern: string): Boolean;
var
  NormName: string;
  Pattern:  string;
begin
  NormName := NormalizeSeps(AName);
  Pattern  := GlobToRegex(APattern);
  Result   := TRegEx.IsMatch(NormName, Pattern, [roIgnoreCase]);
end;

class function TGlob.MatchesAny(const AName: string;
  const APatterns: TArray<string>): Boolean;
var
  P: string;
begin
  for P in APatterns do
    if Matches(AName, P) then
      Exit(True);
  Result := False;
end;

end.
