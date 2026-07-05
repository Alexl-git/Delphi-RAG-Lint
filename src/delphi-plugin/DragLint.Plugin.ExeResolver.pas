unit DragLint.Plugin.ExeResolver;

{ v0.86 policy (user ruling 2026-07-05): the IDE BPL is the only 32-bit
  artifact; every process the plugin spawns defaults to the Win64 CLI.
  The Win32 sibling next to the BPL is the "just in case" fallback only. }

interface

/// <summary>Resolves the drag-lint CLI exe for ALL plugin spawn sites.</summary>
/// <returns>Full path when a candidate exists; else the bare name
/// 'drag-lint.exe' (resolved via PATH by CreateProcess).</returns>
/// <remarks>Order: 1) Settings ExePath override (set + exists);
/// 2) &lt;bpl-dir&gt;\..\dll-win64\drag-lint.exe (DEFAULT);
/// 3) &lt;bpl-dir&gt;\drag-lint.exe (Win32 fallback); 4) bare name.
/// Thread-safe: pure function over the settings snapshot + file system.</remarks>
function DragLintExe: string;

implementation

uses
  System.SysUtils
  , Winapi.Windows
  , DragLint.Plugin.Settings
  ;

function DragLintExe: string;
var
  BplDir: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result <> '') and FileExists(Result) then Exit;
  BplDir:= ExtractFilePath(GetModuleName(HInstance));
  Result:= ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\drag-lint.exe';
  if FileExists(Result) then Exit;
  Result:= BplDir + 'drag-lint.exe';
  if FileExists(Result) then Exit;
  Result:= 'drag-lint.exe';
end;

end.
