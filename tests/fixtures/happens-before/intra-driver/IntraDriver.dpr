program IntraDriver;

{ check-init lane HBINTRA test driver (built and run by tests\autotest\run_check_init_intra.ps1).

  Usage: IntraDriver --db <db> --file <unit.pas> [--entry-done] [--only <RoutineName>]

  For every routine of <unit.pas> in the index whose body carries MARK / QUERY marker comments
  (see tests\fixtures\happens-before\intra-shapes\IntraShapes.pas), calls SolveRoutine with those
  sites and prints one ROUTINE line plus one QUERY line per query site:
    ROUTINE <name> found=<T|F> skipped=<T|F> exit=<T|F> exitReach=<T|F>
    QUERY <name> <n> <line>:<col> done=<T|F> located=<T|F> closure=<T|F>
  then `SUMMARY routines=<n>`. Exit code 2 on a usage error or an empty run. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
, System.IOUtils
, System.Generics.Collections
, System.Generics.Defaults
, DRagLint.Core.Interfaces
, DRagLint.Core.Model
, DRagLint.Storage.SQLite
, DRagLint.Diagnostics.ParseCache
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Intra
  ;

const
  MARK_TAG  = '{M}';
  QUERY_TAG = '{Q}';

function TF(pValue: Boolean): string;
begin
  Result:= if pValue then 'T' else 'F';
end;

procedure CollectSites(const pLines: TArray<string>; pFirst, pLast: Integer; const pTag: string;
  pList: TList<THbSite>);
begin
  for var L:= pFirst to pLast do
  begin
    if (L < 1) or (L > Length(pLines)) then Continue;
    var P:= Pos(pTag, pLines[L - 1]);
    while P > 0 do
    begin
      var S:= Default(THbSite);
      S.Line:= L;
      S.Col:= P + Length(pTag);
      pList.Add(S);
      P:= Pos(pTag, pLines[L - 1], P + Length(pTag));
    end;
  end;
end;

function Run: Integer;
var
  DbPath, FilePath, Only: string;
  EntryDone: Boolean;
begin
  EntryDone:= False;
  var I:= 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--db') and (I < ParamCount) then
    begin
      Inc(I);
      DbPath:= ParamStr(I);
    end
    else if SameText(ParamStr(I), '--file') and (I < ParamCount) then
    begin
      Inc(I);
      FilePath:= ParamStr(I);
    end
    else if SameText(ParamStr(I), '--only') and (I < ParamCount) then
    begin
      Inc(I);
      Only:= ParamStr(I);
    end
    else if SameText(ParamStr(I), '--entry-done') then EntryDone:= True
    else
    begin
      Writeln(ErrOutput, 'usage: IntraDriver --db <db> --file <unit.pas> [--entry-done] [--only <Routine>]');
      Exit(2);
    end;
    Inc(I);
  end;
  if (DbPath = '') or (FilePath = '') then
  begin
    Writeln(ErrOutput, 'usage: IntraDriver --db <db> --file <unit.pas> [--entry-done] [--only <Routine>]');
    Exit(2);
  end;
  FilePath:= TPath.GetFullPath(FilePath);
  var Lines:= TFile.ReadAllLines(FilePath);
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(DbPath, {AReadOnly=}True);
  var Syms:= TList<TSymbol>.Create;
  var Marks:= TList<THbSite>.Create;
  var Queries:= TList<THbSite>.Create;
  try
    for var S in Store.FindSymbolsByFile(FilePath) do
      if (S.Kind in [skProcedure, skFunction]) and ((Only = '') or SameText(S.Name, Only)) then Syms.Add(S);
    Syms.Sort(TComparer<TSymbol>.Construct(
      function(const pLeft, pRight: TSymbol): Integer
      begin
        Result:= pLeft.StartLine - pRight.StartLine;
      end));
    var Count:= 0;
    for var S in Syms do
    begin
      var First:= if S.ImplStartLine > 0 then S.ImplStartLine else S.StartLine;
      var Last:= if S.ImplEndLine > 0 then S.ImplEndLine else S.EndLine;
      Marks.Clear;
      Queries.Clear;
      CollectSites(Lines, First, Last, MARK_TAG, Marks);
      CollectSites(Lines, First, Last, QUERY_TAG, Queries);
      if Queries.Count = 0 then Continue;
      var St:= SolveRoutine(Store, S.Id, Marks.ToArray, Queries.ToArray, EntryDone);
      Writeln(Format('ROUTINE %s found=%s skipped=%s exit=%s exitReach=%s',
        [S.Name, TF(St.Found), TF(St.CfgSkipped), TF(St.ExitDone), TF(St.ExitReachable)]));
      for var Q:= 0 to High(St.Queries) do
        Writeln(Format('QUERY %s %d %d:%d done=%s located=%s closure=%s',
          [S.Name, Q + 1, St.Queries[Q].Site.Line, St.Queries[Q].Site.Col, TF(St.Queries[Q].Done),
           TF(St.Queries[Q].Located), TF(St.Queries[Q].InClosure)]));
      Inc(Count);
    end;
    Writeln(Format('SUMMARY routines=%d', [Count]));
    Result:= if Count = 0 then 2 else 0;
  finally
    Queries.Free;
    Marks.Free;
    Syms.Free;
    TAstParseCache.Clear;
  end;
end;

begin
  try
    ExitCode:= Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode:= 2;
    end;
  end;
end.
