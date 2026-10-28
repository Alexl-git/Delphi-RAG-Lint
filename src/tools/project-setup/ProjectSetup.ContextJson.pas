unit ProjectSetup.ContextJson;

{ Setup-form helpers: platform list, built-in defines, namespaces, memo splitting.
  The .dlcontext.json read/write itself lives in DRagLint.Project.ContextFile. No VCL dependency. }

interface

uses
  System.SysUtils, System.Classes;

/// <summary>Delphi platform names the setup form offers.</summary>
function SetupPlatforms: TArray<string>;

/// <summary>Compiler built-in defines for a platform (empty for an unknown name).</summary>
function BuiltInDefines(const pPlatform: string): TArray<string>;

/// <summary>Built-ins for the platform, plus DEBUG when pConfig is Debug (case-insensitive).</summary>
function DefaultDefines(const pPlatform, pConfig: string): TArray<string>;

/// <summary>System;Vcl;Winapi for Windows platforms, System otherwise.</summary>
function DefaultNamespaces(const pPlatform: string): TArray<string>;

/// <summary>Splits a memo text into trimmed, non-empty lines.</summary>
function SplitLines(const pText: string): TArray<string>;

implementation

uses
  DRagLint.Preprocess.Profile;

const
  WIN_PREFIX_LEN = 3;

function Arr(const pItems: array of string): TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, Length(pItems));
  for i := 0 to High(pItems) do
    Result[i] := pItems[i];
end;

function SetupPlatforms: TArray<string>;
begin
  Result := Arr(['Win32', 'Win64', 'Win64x', 'Linux64', 'OSX64', 'OSXARM64',
    'Android', 'Android64', 'iOSDevice64', 'iOSSimARM64']);
end;

function BuiltInDefines(const pPlatform: string): TArray<string>;
var
  Common: TArray<string>;
  i: Integer;
begin
  // Win32 / Win64: the engine's own table, DRagLint.Preprocess.Profile.PlatformBuiltins
  // (src\preprocess), already lowercase, as the context file stores them.
  if SameText(pPlatform, 'Win32') or SameText(pPlatform, 'Win64') then
  begin
    Result := PlatformBuiltins(pPlatform);
    for i := 0 to High(Result) do
      Result[i] := LowerCase(Result[i]);
    Exit;
  end;
  // Every other platform: the engine has NO table (it maps unknown names to Win64),
  // so these lists are NOT from the engine; they are the documented Delphi
  // platform symbols and must be checked against the compiler.
  Common := Arr(['UNICODE', 'CONDITIONALEXPRESSIONS', 'COMPILER_VERSION_37', 'VER370']);
  if SameText(pPlatform, 'Win64x') then
    Result := Arr(['MSWINDOWS', 'WIN64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'Linux64') then
    Result := Arr(['LINUX', 'LINUX64', 'UNIX', 'POSIX', 'POSIX64', 'ELF', 'CPUX64', 'CPU64BITS'])
  else if SameText(pPlatform, 'OSX64') then
    Result := Arr(['MACOS', 'MACOS64', 'OSX', 'OSX64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUX64', 'CPU64BITS'])
  else if SameText(pPlatform, 'OSXARM64') then
    Result := Arr(['MACOS', 'MACOS64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'Android') then
    Result := Arr(['ANDROID', 'LINUX', 'UNIX', 'POSIX', 'POSIX32', 'CPUARM', 'CPUARM32', 'CPU32BITS'])
  else if SameText(pPlatform, 'Android64') then
    Result := Arr(['ANDROID', 'ANDROID64', 'LINUX', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'iOSDevice64') then
    Result := Arr(['IOS', 'IOS64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'iOSSimARM64') then
    Result := Arr(['IOS', 'IOS64', 'IOSSIMULATOR', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else
    Exit(nil);
  Result := Common + Result;
  for i := 0 to High(Result) do
    Result[i] := LowerCase(Result[i]);
end;

function DefaultDefines(const pPlatform, pConfig: string): TArray<string>;
begin
  Result := BuiltInDefines(pPlatform);
  if SameText(Trim(pConfig), 'Debug') then
    Result := Result + Arr(['debug']);
end;

function DefaultNamespaces(const pPlatform: string): TArray<string>;
begin
  if SameText(Copy(pPlatform, 1, WIN_PREFIX_LEN), 'Win') then
    Result := Arr(['System', 'Vcl', 'Winapi'])
  else
    Result := Arr(['System']);
end;

function SplitLines(const pText: string): TArray<string>;
var
  List: TStringList;
  i, N: Integer;
  S: string;
begin
  Result := nil;
  List := TStringList.Create;
  try
    List.Text := pText;
    SetLength(Result, List.Count);
    N := 0;
    for i := 0 to List.Count - 1 do
    begin
      S := Trim(List[i]);
      if S <> '' then
      begin
        Result[N] := S;
        Inc(N);
      end;
    end;
    SetLength(Result, N);
  finally
    List.Free;
  end;
end;

end.
