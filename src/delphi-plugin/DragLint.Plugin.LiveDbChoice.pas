unit DragLint.Plugin.LiveDbChoice;

(* T-05 (2026-10-23): which index DB(s) the live lint passes as --db.

   ManifestDbForFile answers by FOLDER, and a shared unit -- ORM3\COMMON\BASICS.PAS
   is in the closure of four projects -- sits in no section's folder, so it got ''
   and the live lint ran with NO --db: every store-backed check silently degraded.
   `drag-lint resolve-dbs --in <file>` knows the real candidates (by membership);
   this unit holds the pure half: parsing that answer and choosing from it.

   ASSUMPTION (recorded for the owner): the manifest has no "owner" / "primary"
   notion for a shared unit (checked 2026-10-23: no such key in drag-lint.json,
   .drag-lint.json or drag-lint-project.json). The nearest thing it declares is the
   folder-section DB (ManifestDbForFile), so that is used as the "declared owner"
   rung. Pure: no file system, no OTAPI -- safe from any thread. *)

interface

/// <summary>Chooses the --db list the live lint passes for one file.</summary>
/// <param name="ACandidates">DBs that contain the file, in the engine's order
/// (the output of `resolve-dbs --in`). May be empty.</param>
/// <param name="AActiveProjectDb">The manifest's unique DB for the IDE's ACTIVE
/// project, or '' when there is none or it is ambiguous.</param>
/// <param name="AOwnerDb">The manifest's declared (folder-section) DB for the file,
/// or '' when no section covers it.</param>
/// <returns>In rule order: the only candidate when there is one; the active
/// project's DB when it is a candidate; the declared owner when it is a candidate;
/// otherwise ALL candidates. With no candidates, the declared owner alone, or an
/// empty array only when nothing at all is known.</returns>
/// <remarks>Never narrows several candidates to none: a shared unit with no
/// tiebreak gets every candidate (--db is repeatable), because an index that
/// contains the file beats no index. Paths compare case-insensitively.
/// Pure; safe to call from any thread.</remarks>
function ChooseLiveLintDbs(const ACandidates: TArray<string>;
  const AActiveProjectDb, AOwnerDb: string): TArray<string>;

/// <summary>Extracts the DB list from `drag-lint resolve-dbs --in X --json`
/// output that may have stderr text merged into it.</summary>
/// <param name="AOutput">Captured process output (stdout and stderr interleaved).</param>
/// <returns>The paths of the first JSON string array in AOutput; empty when
/// there is none, it is empty, or it does not parse.</returns>
/// <remarks>The engine writes notes such as "(loaded defaults from ...)" and
/// "NOTE: no index covers ..." to stderr, and a merged capture can splice them
/// into the same line as the JSON, so the array is located by its opening
/// bracket rather than by line. Pure; never raises.</remarks>
function ParseResolveDbsJson(const AOutput: string): TArray<string>;

implementation

uses
  System.SysUtils
  , System.JSON
  ;

function ContainsPath(const AList: TArray<string>; const APath: string): Boolean;
begin
  Result:= False;
  if APath = '' then Exit;
  for var S in AList do
    if SameText(S, APath) then Exit(True);
end;

function ChooseLiveLintDbs(const ACandidates: TArray<string>;
  const AActiveProjectDb, AOwnerDb: string): TArray<string>;
begin
  if Length(ACandidates) = 0 then
  begin
    Result:= nil;
    if AOwnerDb <> '' then Result:= [AOwnerDb];
    Exit;
  end;
  if Length(ACandidates) = 1 then Exit(Copy(ACandidates));
  if ContainsPath(ACandidates, AActiveProjectDb) then Result:= [AActiveProjectDb]
  else if ContainsPath(ACandidates, AOwnerDb) then Result:= [AOwnerDb]
  else Result:= Copy(ACandidates);
end;

function ParseResolveDbsJson(const AOutput: string): TArray<string>;
var
  StartPos: Integer;
  EndPos  : Integer;
  Val     : TJSONValue;
begin
  Result:= nil;
  StartPos:= Pos('["', AOutput);
  if StartPos = 0 then Exit;
  EndPos:= Pos('"]', AOutput, StartPos);
  if EndPos = 0 then Exit;
  Val:= TJSONObject.ParseJSONValue(Copy(AOutput, StartPos, EndPos + 2 - StartPos));
  try
    if not (Val is TJSONArray) then Exit;
    for var Item in TJSONArray(Val) do
      if (Item is TJSONString) and (Item.Value <> '') then Result:= Result + [Item.Value];
  finally
    Val.Free;
  end;
end;

end.
