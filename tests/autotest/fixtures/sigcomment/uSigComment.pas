unit uSigComment;

interface

type
  TSigHost = class
  public
    procedure MethodWithComment(const pA: Integer; // dl:ok too-many-parameters@0000 reason
      const pB: string);
    function MethodWithBlock(pA: Integer { block note }; pB: Integer): Integer;
  end;

procedure LineCommented(const pA: Integer; // dl:ok too-many-parameters@0000 reason
  const pB: string);
function BlockCommented(pA: Integer { block note }; (* star note *) pB: Integer): Integer;
function DefaultValued(pA: Integer; pB: Integer = 3): Integer;

type
  TProcWithBlock = function(hServer: THandle; Info: DWORD{ TInfoClass }; pB: Integer): BOOL; stdcall;

const
  ArrConst: array[0..1] of Integer = //
  (//
    1, //
    2 //
  );

implementation

procedure TSigHost.MethodWithComment(const pA: Integer; // dl:ok too-many-parameters@0000 reason
  const pB: string);
begin
end;

function TSigHost.MethodWithBlock(pA: Integer { block note }; pB: Integer): Integer;
begin
  Result:= pA + pB;
end;

procedure LineCommented(const pA: Integer; // dl:ok too-many-parameters@0000 reason
  const pB: string);
begin
end;

function BlockCommented(pA: Integer { block note }; (* star note *) pB: Integer): Integer;
begin
  Result:= pA + pB;
end;

function DefaultValued(pA: Integer; pB: Integer = 3): Integer;
begin
  Result:= pA + pB;
end;

end.