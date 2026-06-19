unit DRagLint.Index.Glob;

interface

uses
  System.SysUtils
  ;

type
  /// <summary>Glob-pattern matcher for file names and paths.
  /// Supports '*' (any non-separator run), '?' (one char), and '**' (any run
  /// including path separators). Matching is case-insensitive (Windows) and
  /// anchored (whole-string match).</summary>
  /// <remarks>v0.46: matching is performed by a direct, linear two-pointer
  /// wildcard algorithm (no regex translation, no per-call regex compilation,
  /// no backtracking-stack recursion). This makes a single match allocation-
  /// free and worst-case O(name*pattern), which is what keeps the .gitignore /
  /// .hgignore tree walk from degrading to a multi-minute hang (or crashing the
  /// process) on large trees where Matches is invoked tens of millions of
  /// times. Not thread-safe state is involved: Matches is a pure function.</remarks>
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
      class function MatchesAny(const AName: string; const APatterns: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.Character
  ;

{ ---- internal helpers ---------------------------------------------------- }

// Normalize a string for matching: lower-case (case-insensitive on Windows)
// and fold backslashes to forward slashes so the matcher only deals with '/'.
function Normalize(const S: string): string;
var
  I: Integer;
  C: Char   ;
begin
  SetLength(Result, Length(S));
  for I:= 1 to Length(S) do
  begin
    C:= S[I];
    if C = '\' then C:= '/'
    else C:= C.ToLower;
    Result[I]:= C;
  end;
end;

// Direct, linear glob matcher operating on already-normalized (lower-case,
// forward-slash) strings. Implements the classic two-pointer wildcard algorithm
// extended with '**'.
//
// Semantics (matching the previous regex translation 1:1):
//   '**' -> matches any run of characters INCLUDING '/'.
//   '*'  -> matches any run of characters NOT including '/'.
//   '?'  -> matches exactly one character (any character, including '/').
//   '/'  -> matches a single '/'.
//   else -> literal character match.
//
// The algorithm is anchored (whole-string match). The only backtracking is the
// single-star "remember last star position" technique, which is O(n*m) in the
// worst case and uses no recursion and no heap allocation -- so it cannot blow
// the native stack or spin pathologically the way nested regex quantifiers can.
function GlobMatch(const AName, APattern: string): Boolean;
var
  N   : Integer; // 1-based cursors into AName / APattern
  P   : Integer;
  NLen: Integer;
  PLen: Integer;
  // Backtrack anchors for a single '*':
  StarP   : Integer; // pattern pos just AFTER the '*', and name pos to resume
  StarN   : Integer;
  HaveStar: Boolean;
  // Backtrack anchors for a '**':
  DStarP   : Integer;
  DStarN   : Integer;
  HaveDStar: Boolean;
  PC       : Char   ;
begin
  NLen:= Length(AName   );
  PLen:= Length(APattern);

  N:= 1;
  P:= 1;
  HaveStar := False; StarP := 0; StarN := 0;
  HaveDStar:= False; DStarP:= 0; DStarN:= 0;

  while N <= NLen do
  begin
    if P <= PLen then
    begin
      PC:= APattern[P];

      if PC = '*' then
      begin
        // Distinguish '**' (cross-separator) from '*' (within-segment).
        if (P < PLen) and (APattern[P + 1] = '*') then
        begin
          // '**' : consume both stars; collapse a following '/' so that
          // '**/x' also matches 'x' at the root (mirrors the old '[/\\]?').
          Inc(P, 2);
          if (P <= PLen) and (APattern[P] = '/') then Inc(P);
          // Remember this '**' so we can extend its match (across '/') on
          // a later mismatch. Clear any pending single-star anchor: '**' is
          // the more permissive backtrack point from here on.
          HaveDStar:= True;
          DStarP   := P;
          DStarN   := N;
          HaveStar := False;
          Continue;
        end
        else
        begin
          // single '*' : remember resume point; match zero chars for now.
          Inc(P);
          HaveStar:= True;
          StarP   := P;
          StarN   := N;
          Continue;
        end;
      end; // if

      if (PC = '?') then
      begin
        // '?' matches exactly one char (any char, including '/').
        Inc(P);
        Inc(N);
        Continue;
      end;

      // Literal (including '/'): compare. (Both sides already normalized.)
      if PC = AName[N] then
      begin
        Inc(P);
        Inc(N);
        Continue;
      end;
    end; // if

    // Mismatch (or pattern exhausted while name remains). Try to extend the
    // most recent active wildcard.
    //
    // Prefer extending a single '*' first when it is "inside" a '**' region;
    // but a '*' may NOT consume a '/'. If the char we would consume is '/',
    // the single '*' is done -- fall through to the '**'.
    if HaveStar and (N <= NLen) and (AName[N] <> '/') then
    begin
      // Extend the single '*' by one char and retry from just after it.
      Inc(StarN);
      N:= StarN;
      P:= StarP;
      Continue;
    end;

    if HaveDStar then
    begin
      // Extend the '**' by one char (may include '/') and retry.
      Inc(DStarN);
      N:= DStarN;
      P:= DStarP;
      // A '**' supersedes any stale single-star anchor that could not advance.
      HaveStar:= False;
      Continue;
    end;

    // No wildcard available to absorb the mismatch.
    Exit(False);
  end; // while

  // Name fully consumed; skip any trailing wildcards that can match empty.
  while (P <= PLen) and (APattern[P] = '*') do Inc(P);

  Result:= (P > PLen);
end; // function

{ TGlob }

class function TGlob.Matches(const AName, APattern: string): Boolean;
begin
  // Normalize both operands once (lower-case + '/' separators), then run the
  // allocation-free linear matcher.
  Result:= GlobMatch(Normalize(AName), Normalize(APattern));
end;

class function TGlob.MatchesAny(const AName: string; const APatterns: TArray<string>): Boolean;
var
  NormName: string;
  P       : string;
begin
  // Normalize the name once and reuse it across every pattern.
  NormName:= Normalize(AName);
  for P in APatterns do
    if GlobMatch(NormName, Normalize(P)) then Exit(True);
  Result:= False;
end;

end.
