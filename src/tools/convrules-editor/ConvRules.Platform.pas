unit ConvRules.Platform;

{ Pure platform model for the conversion editor: which library index each side
  (FROM / TO) draws its component types from. Headless + unit-tested; no UI, no
  file I/O. The editor and its .dpr both consume this so platform reasoning lives
  in exactly one place. }

interface

uses
  System.SysUtils;

type
  /// <summary>Which platform library a picker side resolves component types
  /// against. cpBoth lists both libraries, Win32 first (see LibDbsFor).</summary>
  /// <remarks>cpBoth is offered but is NOT the default for either side. It was
  /// intended as a FROM safety net for components indexed under only one
  /// platform; measured 2026-07-29 against the libraries on disk that net was
  /// empty (Win64 alone gave the same 6180 TComponent descendants as the union,
  /// Orpheus TOvcTable included), while library-Win32.sqlite was a 9.5 MB
  /// fragment of the ~1.9 GB corpus. Because a consumer such as `proptree`
  /// resolves a qname from the FIRST --db that answers, listing a fragment ahead
  /// of a healthy index can shadow it. Use cpBoth deliberately, not by
  /// default.</remarks>
  TConvPlatform = (cpWin32, cpWin64, cpBoth);

const
  /// <summary>The platform each picker side uses when the user passes no
  /// --from-platform / --to-platform. Single-sourced here because the editor's
  /// .dpr and the form's globals must not be able to disagree.</summary>
  /// <remarks>FROM was cpBoth until 2026-07-29. It is cpWin64 because the union
  /// added nothing measurable (same 6180 TComponent descendants either way) while
  /// listing a 9.5 MB fragment of the corpus ahead of the healthy index, which a
  /// first-DB-wins consumer such as `proptree` could resolve from. Ord() of these
  /// is also the platform combo boxes' initial ItemIndex, so any value here must
  /// stay inside TConvPlatform's ordinal range.</remarks>
  DEFAULT_FROM_PLATFORM = cpWin64;
  DEFAULT_TO_PLATFORM   = cpWin64;

/// <summary>Parse a platform token (case-insensitive: 'win32' | 'win64' |
/// 'both'). Returns ADefault for '' or any unrecognized token.</summary>
function ParsePlatform(const AText: string; ADefault: TConvPlatform): TConvPlatform;

/// <summary>The canonical lowercase token for a platform
/// ('win32' | 'win64' | 'both').</summary>
function PlatformToStr(APlatform: TConvPlatform): string;

/// <summary>The library-index DB paths a platform selects, each under ALibDir.
/// cpWin32 -> [ALibDir\library-Win32.sqlite]; cpWin64 -> [...library-Win64...];
/// cpBoth -> [Win32, Win64] in that order. Pure: does not check existence.</summary>
function LibDbsFor(APlatform: TConvPlatform; const ALibDir: string): TArray<string>;

implementation

uses
  System.IOUtils;

function ParsePlatform(const AText: string; ADefault: TConvPlatform): TConvPlatform;
var
  T: string;
begin
  T := LowerCase(Trim(AText));
  if T = 'win32' then Result := cpWin32
  else if T = 'win64' then Result := cpWin64
  else if T = 'both' then Result := cpBoth
  else Result := ADefault;
end;

function PlatformToStr(APlatform: TConvPlatform): string;
begin
  case APlatform of
    cpWin32: Result := 'win32';
    cpWin64: Result := 'win64';
  else
    Result := 'both';
  end;
end;

function LibDbsFor(APlatform: TConvPlatform; const ALibDir: string): TArray<string>;
begin
  case APlatform of
    cpWin32: Result := [TPath.Combine(ALibDir, 'library-Win32.sqlite')];
    cpWin64: Result := [TPath.Combine(ALibDir, 'library-Win64.sqlite')];
  else
    Result := [TPath.Combine(ALibDir, 'library-Win32.sqlite'),
               TPath.Combine(ALibDir, 'library-Win64.sqlite')];
  end;
end;

end.
