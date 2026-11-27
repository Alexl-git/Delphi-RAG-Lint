program LockSitesDriver;

{ 1.56 lane THR-S test driver (built and run by tests\autotest\run_v156_THRS_lock_sites.ps1).

  Usage: LockSitesDriver --db <db> [--file <path suffix> | --routine <QName> [--held <line>:<col>]]

  Opens the index read-only and prints LockSitesJson of
    LockSitesOfProject                    (no selector),
    LockSitesOfFile                       (--file: the one indexed file whose path ends with the text),
    LockSitesOfRoutine                    (--routine: the one routine with that qualified name).
  --held prints the LockKeys as a JSON object "held": [..] instead: the regions of that routine holding at the position,
  outermost first (TRoutineLockSites.HeldAt).
  Exit code 0; 2 on a usage error or when a selector matches nothing. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
, System.JSON
, DRagLint.Core.Interfaces
, DRagLint.Core.Model
, DRagLint.Storage.SQLite
, DRagLint.Query.LockSites
  ;

const
  EXIT_USAGE = 2;

procedure Usage;
begin
  Writeln(ErrOutput, 'usage: LockSitesDriver --db <db> [--file <path suffix> | --routine <QName> [--held <line>:<col>]]');
end;

function FileIdBySuffix(const pStore: ISymbolStore; const pSuffix: string): Int64;
begin
  Result:= 0;
  for var Id in pStore.GetAllFileIds do
    if pStore.GetFilePath(Id).EndsWith(pSuffix, True) then Exit(Id);
end;

function RoutineIdByQName(const pStore: ISymbolStore; const pQName: string): Int64;
begin
  Result:= 0;
  var Leaf:= Copy(pQName, LastDelimiter('.', pQName) + 1, MaxInt);
  for var Sym in pStore.FindSymbolsByExactName(Leaf) do
    if SameText(Sym.QualifiedName, pQName) then Exit(Sym.Id);
end;

function HeldJson(const pSites: TRoutineLockSites; const pAt: string): string;
begin
  var Parts:= pAt.Split([':']);
  var Keys:= TJSONArray.Create;
  try
    if Length(Parts) = 2 then
      for var K in pSites.HeldAt(StrToIntDef(Parts[0], 0), StrToIntDef(Parts[1], 0)) do
        Keys.Add(pSites.Regions[K].LockKey);
    Result:= '{"held":' + Keys.ToJSON + '}';
  finally
    Keys.Free;
  end;
end;

function Run: Integer;
var
  DbPath, FileSuffix, Routine, Held: string;
begin
  var I:= 1;
  while I < ParamCount do
  begin
    var P:= ParamStr(I);
    Inc(I);
    if SameText(P, '--db') then DbPath:= ParamStr(I)
    else if SameText(P, '--file') then FileSuffix:= ParamStr(I)
    else if SameText(P, '--routine') then Routine:= ParamStr(I)
    else if SameText(P, '--held') then Held:= ParamStr(I)
    else DbPath:= '';
    Inc(I);
  end;
  if (DbPath = '') or Odd(ParamCount) or ((FileSuffix <> '') and (Routine <> ''))
    or ((Held <> '') and (Routine = '')) then
  begin
    Usage;
    Exit(EXIT_USAGE);
  end;
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(DbPath, {AReadOnly=}True);
  if FileSuffix <> '' then
  begin
    var FileId:= FileIdBySuffix(Store, FileSuffix);
    if FileId = 0 then Exit(EXIT_USAGE);
    Writeln(LockSitesJson(LockSitesOfFile(Store, FileId)));
  end
  else if Routine <> '' then
  begin
    var RoutineId:= RoutineIdByQName(Store, Routine);
    if RoutineId = 0 then Exit(EXIT_USAGE);
    var Sites:= LockSitesOfRoutine(Store, RoutineId);
    if Held = '' then Writeln(LockSitesJson([Sites]))
    else Writeln(HeldJson(Sites, Held));
  end
  else
    Writeln(LockSitesJson(LockSitesOfProject(Store)));
  Result:= 0;
end;

begin
  try
    ExitCode:= Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode:= EXIT_USAGE;
    end;
  end;
end.
