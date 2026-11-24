unit DragLint.Plugin.ReferenceDb;

{ The optional per-user reference index of the IDE plugin.

  A project being ported from an older code base may want that code base's index as one more READ
  database, so hover and Find Usages answer names that live only there. Which index and for which
  projects is a fact about ONE user's machine, so it is read from an INI file beside the roaming
  drag-lint.json and never compiled in. Pure: no ToolsAPI, so tests\ReferenceDbTests.dpr drives it. }

interface

/// <summary>Where the plugin looks for its per-user INI file.</summary>
/// <param name="AAppData">%APPDATA%, the same root the roaming drag-lint.json uses; may be ''.</param>
/// <returns>AAppData\drag-lint\drag-lint-plugin.ini; '' when AAppData is ''.</returns>
function PluginIniPath(const AAppData: string): string;

/// <summary>The extra read-only index to offer beside AProjectDb, as the INI file names it.</summary>
/// <param name="AIniPath">The INI file (PluginIniPath); '' or a missing file = feature off.</param>
/// <param name="AProjectDb">The index database the active project resolved to.</param>
/// <returns>The value of [Databases] ReferenceDb when [Databases] ReferenceDbFor is a non-empty part
/// of AProjectDb (case ignored) and the named file exists; otherwise ''.</returns>
/// <remarks>Never raises and never prompts: a missing, locked or undecodable INI file, a missing key
/// and an absent database all answer ''. Reads the file on each call; thread-safe.</remarks>
function ReferenceDbFor(const AIniPath, AProjectDb: string): string;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.IniFiles
  , System.IOUtils
  ;

const
  INI_SUBPATH = 'drag-lint\drag-lint-plugin.ini';
  INI_SECTION = 'Databases';
  KEY_DB      = 'ReferenceDb';
  KEY_DB_FOR  = 'ReferenceDbFor';

function PluginIniPath(const AAppData: string): string;
begin
  Result:= if AAppData = '' then '' else TPath.Combine(AAppData, INI_SUBPATH);
end;

function ReferenceDbFor(const AIniPath, AProjectDb: string): string;
var
  Ini  : TMemIniFile;
  Scope: string;
begin
  Result:= '';
  if not FileExists(AIniPath) then Exit;
  try
    Ini:= TMemIniFile.Create(AIniPath);
    try
      Scope:= Ini.ReadString(INI_SECTION, KEY_DB_FOR, '').Trim;
      if (Scope = '') or not ContainsText(AProjectDb, Scope) then Exit;
      Result:= Ini.ReadString(INI_SECTION, KEY_DB, '').Trim;
    finally
      Ini.Free;
    end;
  except
    { locked or undecodable: the optional feature is off, the caller's own databases still answer }
    on EStreamError do Exit('');
    on EEncodingError do Exit('');
  end;
  if not FileExists(Result) then Result:= '';
end;

end.
