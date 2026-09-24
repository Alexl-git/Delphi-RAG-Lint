unit uSelfName;

{ Defect D12 (resolver 1.8.0-alpha). Pascal lets a function assign its result
  through its OWN NAME -- `Greater:= X > Y;` -- exactly as `Result:= X > Y;`.
  The purity stage scored that write as a GLOBAL write ('g'), so a pure
  comparison was never effect-free and every Assert around it was flagged by
  assert-with-side-effect. WritesGlobalToo is the positive control: the own-name
  write is ignored, the real global write is not. }

interface

var
  GLast: Integer;

function Greater(X, Y: Integer): Boolean;
function OuterResult(X: Integer): Integer;
function WritesGlobalToo(X: Integer): Integer;

type
  TCmp = class
  public
    function IsBig(X: Integer): Boolean;
  end;

implementation

function Greater(X, Y: Integer): Boolean;
begin
  Greater:= X > Y;
end;

function OuterResult(X: Integer): Integer;

  procedure Fill;
  begin
    OuterResult:= X * 2;
  end;

begin
  Fill;
end;

function WritesGlobalToo(X: Integer): Integer;
begin
  WritesGlobalToo:= X;
  GLast:= X;
end;

function TCmp.IsBig(X: Integer): Boolean;
begin
  IsBig:= X > 100;
end;

end.
