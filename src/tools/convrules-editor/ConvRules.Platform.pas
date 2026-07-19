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
  /// against. cpBoth = the union of both platform libraries -- the FROM safety
  /// net, since some legacy components (e.g. Orpheus TOvcTable) are indexed under
  /// only one platform's library.</summary>
  TConvPlatform = (cpWin32, cpWin64, cpBoth);

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
