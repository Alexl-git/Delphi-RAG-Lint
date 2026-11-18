unit uDedup;

{ TAINTDEDUP (1.52): ONE finding per sink site, however many paths reach it.
  Spawn (line 27): four callers pass ParamStr(1..4); CreateProcess takes the value in two
  arguments -- 4 sources, 4 distinct paths (arg 0 and arg 1 walk the same hops).
  SpawnTwo (line 35): one source reaches arg 0 directly and arg 1 through Wrap -- 1 source,
  2 paths. Before 1.52 each path was its own finding. }

interface

procedure FromArg1;
procedure FromArg2;
procedure FromArg3;
procedure FromArg4;
procedure FromArgTwice;

implementation

uses
  Windows;

procedure Spawn(const ACmd: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
begin
  CreateProcess(PChar(ACmd), PChar('run ' + ACmd), nil, nil, False, 0, nil, nil, SI, PI);
end;

procedure SpawnTwo(const AApp, ACmd: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
begin
  CreateProcess(PChar(AApp), PChar(ACmd), nil, nil, False, 0, nil, nil, SI, PI);
end;

function Wrap(const A: string): string;
begin
  Result:= 'run ' + A;
end;

procedure FromArg1;
begin
  Spawn(ParamStr(1));
end;

procedure FromArg2;
begin
  Spawn(ParamStr(2));
end;

procedure FromArg3;
begin
  Spawn(ParamStr(3));
end;

procedure FromArg4;
begin
  Spawn(ParamStr(4));
end;

procedure FromArgTwice;
var
  S: string;
begin
  S:= ParamStr(5);
  SpawnTwo(S, Wrap(S));
end;

end.