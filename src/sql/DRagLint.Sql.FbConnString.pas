unit DRagLint.Sql.FbConnString;

{ The one place that decides which FireDAC connection-string keys a read-only Firebird verb may pass on.
  Pure: no FireDAC, no I/O, no secrets are ever put into a message. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when a Firebird connection string carries a key the read-only verbs refuse.</summary>
  EFbConnStringError = class(Exception);

const
  /// <summary>FireDAC parameters that create, drop or re-open a database in another mode, or pull in a stored definition.</summary>
  FB_FORBIDDEN_KEYS: array[0..4] of string = ('OpenMode', 'CreateDatabase', 'DropDatabase', 'ConnectionDef', 'ConnectionDefName');

/// <summary>The first refused key of a ';' separated key=value connection string.</summary>
/// <param name="pConnection">'Database=..;User_Name=..;Password=..' pairs.</param>
/// <returns>The refused key in its canonical spelling (keys are trimmed and compared case-insensitively; a bare key
/// with no '=' counts too); 'line break' when the string holds a CR or LF; '' when the string is acceptable.</returns>
/// <remarks>Pure and thread-safe. Only a canonical key name or 'line break' is returned, never a value, so the
/// result is safe to print.</remarks>
function FbForbiddenKey(const pConnection: string): string;  // dl:ok unused-public-symbol@7975 -- REVIEWED 2026-11-23 INT-FINAL: the pure key check is the public test seam; tests\fieldrepo\FbConnStringTests.dpr (outside the indexed project) calls it directly, RequireFbConnectionSafe is the production entry

/// <summary>Refuses a connection string with a forbidden key before anything is opened.</summary>
/// <param name="pConnection">The --connection value.</param>
/// <exception cref="EFbConnStringError">Raised, naming the key (never a value, never the password), when the string
/// holds one of FB_FORBIDDEN_KEYS or a line break.</exception>
/// <remarks>Call it before the first TFDConnection is created: nothing is opened when it raises.</remarks>
procedure RequireFbConnectionSafe(const pConnection: string);

implementation

uses
  System.StrUtils;

const
  KEY_LINE_BREAK = 'line break';

function FbForbiddenKey(const pConnection: string): string;
var
  VPair, VKey, VForbidden: string;
begin
  if pConnection.Contains(#13) or pConnection.Contains(#10) then
    Exit(KEY_LINE_BREAK);
  for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
  begin
    VKey := Trim(Copy(VPair, 1, Pos('=', VPair + '=') - 1));
    for VForbidden in FB_FORBIDDEN_KEYS do
      if SameText(VKey, VForbidden) then
        Exit(VForbidden);
  end;
  Result := '';
end;

procedure RequireFbConnectionSafe(const pConnection: string);
var
  VKey: string;
begin
  VKey := FbForbiddenKey(pConnection);
  if VKey <> '' then
    raise EFbConnStringError.CreateFmt('%s is not allowed in --connection: this verb only reads a database and never creates, drops or re-opens one', [VKey]);
end;

end.
