unit uN;

{ No implementation uses, but a comment right below `implementation` shows one:
  the fix must create a clause, not insert into the comment (lane IATOM dogfood). }

interface

uses
  uC;

type
  TN = class
    FC: TC;
  end;

implementation

uses
  uB;

{ Not a clause:
    uses
      Foo;
}

procedure DoN;
begin
  BProc;
end;

end.
