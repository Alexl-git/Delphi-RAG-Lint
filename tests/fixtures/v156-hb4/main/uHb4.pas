unit uHb4;

{ Fixture of tests\autotest\run_v156_HB4.ps1 (1.56 lane HB4, verb `happens-before`).
  One routine per case; every case has its own unit variable or its own pair of routines, so the
  site set of one event never mixes two cases. uHb4Ext is NOT part of the fixture on purpose:
  every call into it is a call the index cannot resolve. The markers in braces are read by the
  runner to find `site:` lines -- keep one marker per line. }

interface

procedure Forward;
procedure Reversed;
procedure AcrossUnknown;
procedure UnknownAfter;
procedure Branchy(pOn: Boolean);
procedure ViaCallee;
procedure ViaCaller;
procedure CallFwd;
procedure CallRev;
procedure CallCond(pOn: Boolean);
procedure SiteCase;
procedure NeverWritten;

implementation

uses
  uHb4Ext;

var
  GFwd: Integer;
  GRev: Integer;
  GUnk: Integer;
  GUnkAfter: Integer;
  GBr: Integer;
  GVia: Integer;
  GCaller: Integer;
  GNever: Integer;
  GInit: Integer;

procedure Sink(pValue: Integer);
begin
  if pValue > 0 then Exit;
end;

{ W1: write, then read, one routine -> YES }
procedure Forward;
begin
  GFwd:= 1;
  Sink(GFwd);
end;

{ W2: read, then write, one routine -> NO (the first write runs after a read) }
procedure Reversed;
begin
  Sink(GRev);
  GRev:= 1;
end;

{ W3: the only writer is a call the index cannot resolve -> MAY }
procedure AcrossUnknown;
begin
  ExtFill(GUnk);
  Sink(GUnk);
end;

{ W4: read first, the unresolved call after it -> NO (whatever ExtFill does, the read ran first) }
procedure UnknownAfter;
begin
  Sink(GUnkAfter);
  ExtFill(GUnkAfter);
end;

{ W5: write under a condition -> MAY }
procedure Branchy(pOn: Boolean);
begin
  if pOn then GBr:= 1;
  Sink(GBr);
end;

procedure SetVia;
begin
  GVia:= 7;
end;

{ W6: the write is inside a callee that always performs it -> YES }
procedure ViaCallee;
begin
  SetVia;
  Sink(GVia);
end;

procedure ReadCaller;
begin
  Sink(GCaller);
end;

{ W7: the read is inside a callee whose only call site runs after the write -> YES }
procedure ViaCaller;
begin
  GCaller:= 3;
  ReadCaller;
end;

{ W8: nothing writes it, one read -> NO (A never happens) }
procedure NeverWritten;
begin
  Sink(GNever);
end;

procedure Open1;
begin
end;

procedure Work1;
begin
end;

procedure Open2;
begin
end;

procedure Work2;
begin
end;

procedure Open3;
begin
end;

procedure Work3;
begin
end;

{ C1: call, then call -> YES }
procedure CallFwd;
begin
  Open1;
  Work1;
end;

{ C2: reversed -> NO }
procedure CallRev;
begin
  Work2;
  Open2;
end;

{ C3: the first call under a condition -> MAY }
procedure CallCond(pOn: Boolean);
begin
  if pOn then Open3;
  Work3;
end;

{ S1: two plain lines of one routine }
procedure SiteCase;
var
  LCount: Integer;
begin
  LCount:= 1; {SITE-FIRST}
  Inc(LCount); {SITE-SECOND}
  Sink(LCount);
end;

{ D1: written and read at the top of the initialization section: no routine body, so the
  same-routine proof cannot see it -- the answer comes from the check-init solver -> YES }
initialization
  GInit:= 5;
  Sink(GInit);

end.
