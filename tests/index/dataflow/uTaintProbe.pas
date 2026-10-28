unit uTaintProbe;

{ data_flows probe (taint wave T1, plan docs\superpowers\plans\
  2026-10-27-taint-interprocedural-plan.md section 9). One routine per shape;
  tests\autotest\run_dataflow_facts.ps1 indexes this file and asserts the rows.
  The runner locates sites by the marker comments, never by line number. }

interface

uses
  System.SysUtils, System.Classes;

type
  TShellInfo = record
    lpFile: PChar;
    nShow : Integer;
  end;

  TQueryStub = class
    SQL: TStringList;
    procedure ExecSQL;
  end;

  TEditStub = class
    Text: string;
  end;

  TProbe = class
  private
    FSql: string;
    Edit1: TEditStub;
  public
    function TrimParam(const A: string): string;
    procedure SinkParam(Q: TQueryStub; const A: string);
    procedure ViaLocal(Q: TQueryStub);
    procedure Killed(Q: TQueryStub);
    procedure Branch(C: Boolean; const A, B: string);
    procedure Loop(Lines: TStrings);
    procedure LiteralOnly;
    function Quoted(const A: string): string;
    function NumericOnly(X, Y: Integer): Integer;
    procedure WithBody(Q: TQueryStub);
    function ExitValue(const A: string): string;
    procedure SelfIndex(const A, B: string);
    procedure SetField(const A: string);
    procedure ReadField;
    procedure SetGlobal(const A: string);
    procedure GetName(out S: string);
    procedure UseOut;
    procedure ListCarrier(const A: string);
    procedure ShellRecord(const A: string);
    procedure LambdaCapture(const A: string);
    procedure ArgValueOnly;
    procedure ArgRtlValue;
    procedure ArgUnresolved;
    procedure ArgTryGet(D: TObject);
    procedure HardCast(O: TObject; const A: string);
  end;

procedure Sink(const S: string);
function ShellExecuteEx(P: Pointer): Boolean;

var
  GConn: string;

implementation

procedure Sink(const S: string);
begin
end;

function ShellExecuteEx(P: Pointer): Boolean;
begin
  Result:= P <> nil;
end;

procedure TQueryStub.ExecSQL;
begin
end;

function TProbe.TrimParam(const A: string): string;
begin
  Result:= Trim(A); { M-TRIM }
end;

procedure TProbe.SinkParam(Q: TQueryStub; const A: string);
begin
  Q.SQL.Add(A); { M-SINKPARAM }
end;

procedure TProbe.ViaLocal(Q: TQueryStub);
var
  S: string;
begin
  S:= Edit1.Text; { M-VIALOCAL-SRC }
  Q.SQL.Text:= S; { M-VIALOCAL-DST }
end;

procedure TProbe.Killed(Q: TQueryStub);
var
  S: string;
begin
  S:= Edit1.Text; { M-KILL-SRC }
  S:= 'x';
  Q.SQL.Text:= S; { M-KILL-DST }
end;

procedure TProbe.Branch(C: Boolean; const A, B: string);
var
  S: string;
begin
  if C then S:= A else S:= B;
  Sink(S); { M-BRANCH }
end;

procedure TProbe.Loop(Lines: TStrings);
var
  S: string;
  I: Integer;
begin
  S:= '';
  for I:= 0 to Lines.Count - 1 do
    S:= S + Lines[I];
  Sink(S); { M-LOOP }
end;

procedure TProbe.LiteralOnly;
begin
  Sink('select 1 from rdb$database'); { M-LITERAL }
end;

function TProbe.Quoted(const A: string): string;
begin
  Result:= QuotedStr(A); { M-QUOTED }
end;

function TProbe.NumericOnly(X, Y: Integer): Integer;
var
  Z: Integer;
begin
  Z:= X + Y;
  Result:= Z * 2; { M-NUMERIC }
end;

procedure TProbe.WithBody(Q: TQueryStub);
begin
  with Q do
    SQL.Add(Text); { M-WITH }
end;

function TProbe.ExitValue(const A: string): string;
begin
  if A = '' then Exit(A); { M-EXIT }
  Result:= 'none';
end;

procedure TProbe.SelfIndex(const A, B: string);
begin
  Sink(B); { M-SELFINDEX }
end;

procedure TProbe.SetField(const A: string);
begin
  FSql:= A; { M-SETFIELD }
end;

procedure TProbe.ReadField;
begin
  Sink(FSql); { M-READFIELD }
end;

procedure TProbe.SetGlobal(const A: string);
begin
  GConn:= A; { M-SETGLOBAL }
  Sink(GConn); { M-READGLOBAL }
end;

procedure TProbe.GetName(out S: string);
begin
  S:= ParamStr(1); { M-OUTPARAM }
end;

procedure TProbe.UseOut;
var
  N: string;
begin
  GetName(N); { M-ARGOUT-CALL }
  Sink(N); { M-ARGOUT-SINK }
end;

procedure TProbe.ListCarrier(const A: string);
var
  L: TStringList;
begin
  L:= TStringList.Create;
  try
    L.Add(A);
    Sink(L.Text); { M-LIST }
  finally
    L.Free;
  end;
end;

procedure TProbe.ShellRecord(const A: string);
var
  Info: TShellInfo;
begin
  Info.lpFile:= PChar(A);
  ShellExecuteEx(@Info); { M-SHELLREC }
end;

procedure TProbe.LambdaCapture(const A: string);
var
  S: string;
  P: TProc;
begin
  S:= A;
  P:= procedure
      begin
        Sink(S); { M-LAMBDA }
      end;
  P;
end;

{ argout cut (lane ARGOUT): a same-unit callee whose parameter at that position is
  a value / const parameter cannot write the argument -- no argout row. }
procedure TProbe.ArgValueOnly;
var
  N: string;
begin
  N:= ParamStr(1); { M-ARGVAL-SRC }
  TrimParam(N);
  Sink(N); { M-ARGVAL-SINK }
end;

{ a curated RTL routine with no var/out parameter (Trim) -- no argout row }
procedure TProbe.ArgRtlValue;
var
  N, T: string;
begin
  N:= ParamStr(1);
  T:= Trim(N);
  Sink(N); { M-ARGRTL-SINK }
end;

{ a callee this unit does not declare and the RTL list does not know: the argout
  row is KEPT (the linter resolves the callee and decides) }
procedure TProbe.ArgUnresolved;
var
  N: string;
begin
  ExternalFill(N); { M-ARGUNRES-CALL }
  Sink(N); { M-ARGUNRES-SINK }
end;

{ TryGetValue(const Key; out Value): position 1 only }
procedure TProbe.ArgTryGet(D: TObject);
var
  K, V: string;
begin
  K:= ParamStr(1);
  TDictionary<string, string>(D).TryGetValue(K, V); { M-ARGTRY-CALL }
  Sink(K); { M-ARGTRY-K }
  Sink(V); { M-ARGTRY-V }
end;

{ ref-gap G5: a hard-cast receiver. The write must give a 'write' row and the read a src 'ref' row,
  each landing on the parser's member-access refs row }
procedure TProbe.HardCast(O: TObject; const A: string);
var
  X: string;
begin
  TEditStub(O).Text:= A; { M-G5WRITE }
  X:= TEditStub(O).Text; { M-G5READ }
  Sink(X); { M-G5SINK }
end;

end.
