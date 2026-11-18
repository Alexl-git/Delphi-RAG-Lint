program HandlersHarness;

{ check-init lane HBEVORD test harness (built and run by tests\autotest\run_check_init_handlers.ps1).

  Usage:
    HandlersHarness --db <db> --handler <QName>   one line per program of the index:
        order program=<P> ordered=<0|1> handler=<QName> class=<C> fired_by=<F> create=<line> run=<line> why=<WhyNot>
        relied=<HbReliedText> (only for an ordered handler)
    HandlersHarness --event <Name>                 event=<Name> unordered=<0|1>
    HandlersHarness --name <Name>                  name=<Name> unordered=<0|1>

  Calls DRagLint.Query.HappensBefore.Handlers directly (no solver), so the ordering rules are tested
  even while the solver hook (INT handover) is not applied. Exit 0; 2 on a usage error. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
, System.Generics.Collections
, DRagLint.Diagnostics.ParseCache
, DRagLint.Charts.Index
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Handlers
  ;

procedure Usage;
begin
  Writeln(ErrOutput, 'usage: HandlersHarness --db <db> --handler <QName> | --event <Name> | --name <Name>');
end;

procedure PrintOrders(const pDb, pHandler: string);
begin
  var Index:= TChartsIndex.Create(pDb);
  try
    var Orderer:= THbHandlerOrderer.Create(Index);
    try
      var H:= Index.Query('SELECT id FROM symbols WHERE qualified_name = ' + QuotedStr(pHandler) +
        ' COLLATE NOCASE ORDER BY id LIMIT 1');
      var P:= Index.Query('SELECT id FROM symbols WHERE kind IN (''program'', ''library'') ORDER BY id');
      try
        var Hid:= if H.Count > 0 then StrToInt64Def(H[0].S('id'), 0) else Int64(0);
        for var Row in P do
        begin
          var O:= Orderer.OrderOf(StrToInt64Def(Row.S('id'), 0), Hid);
          Writeln(Format('order program=%s ordered=%d handler=%s class=%s fired_by=%s create=%d run=%d why=%s',
            [O.ProgramName, Ord(O.Ordered), O.Handler, O.FormClass, O.FiredBy, O.CreateSite.Line, O.RunSite.Line,
             O.WhyNot]));
          if O.Ordered then Writeln('relied=' + HbReliedText(O));
        end;
      finally
        P.Free;
        H.Free;
      end;
    finally
      Orderer.Free;
    end;
  finally
    Index.Free;
  end;
end;

function Run: Integer;
begin
  Result:= 0;
  if (ParamCount = 2) and SameText(ParamStr(1), '--event') then
    Writeln(Format('event=%s unordered=%d', [ParamStr(2), Ord(HbIsUnorderedEvent(ParamStr(2)))]))
  else if (ParamCount = 2) and SameText(ParamStr(1), '--name') then
    Writeln(Format('name=%s unordered=%d', [ParamStr(2), Ord(HbIsUnorderedHandlerName(ParamStr(2)))]))
  else if (ParamCount = 4) and SameText(ParamStr(1), '--db') and SameText(ParamStr(3), '--handler') then
    PrintOrders(ParamStr(2), ParamStr(4))
  else
  begin
    Usage;
    Result:= 2;
  end;
  TAstParseCache.Clear;
end;

begin
  ExitCode:= Run;
end.
