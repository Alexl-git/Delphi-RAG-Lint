unit uResRecv;

interface

type
  TJob = class
  public
    Streaming: Boolean;
    procedure Start;
  end;

  TOtherJob = class
  public
    Streaming: Boolean;
  end;

function MakeJob: TJob;
procedure UseLocal;
function MakeWithAnon: TJob;
procedure TwoInline;
procedure LateLocal;

var
  GPeer: TJob;

type
  TOtherFn = reference to function: TOtherJob;

implementation

procedure TJob.Start;
begin
end;

function MakeJob: TJob;
begin
  Result := TJob.Create;
  Result.Streaming := False; // POS-WRITE
  if Result.Streaming then // POS-READ
    Result.Start(); // POS-CALL
end;

procedure UseLocal;
var
  Result: TOtherJob;
begin
  Result := nil;
  Result.Streaming := True; // NEG-LOCAL
end;

function MakeWithAnon: TJob;
var
  F: TOtherFn;
begin
  F := function: TOtherJob
    begin
      Result := TOtherJob.Create;
      Result.Streaming := True; // NEG-ANON
    end;
  Result := TJob.Create;
  Result.Streaming := False; // POS-AFTER-ANON
end;

procedure TwoInline;
begin
  begin
    var J: TJob := TJob.Create;
    J.Streaming := True; // RCV-DUP-FIRST
  end;
  begin
    var J: TOtherJob := TOtherJob.Create;
    J.Streaming := True; // RCV-DUP-SECOND
  end;
end;

procedure LateLocal;
begin
  GPeer.Streaming := True; // RCV-LATE
  begin
    var GPeer: TOtherJob := nil;
    GPeer.Streaming := False; // RCV-INNER-LATE
  end;
end;

end.