unit uOverloadImpl;

{ Fixture for run_interface_dispatch_generic.ps1 (P3) -- an interface whose
  OVERLOADS share an arity and differ only by parameter TYPE. Arity alone ties
  every pair, so before resolver 1.17.0-alpha each interface method got an
  'ambiguous' implements edge to EVERY same-arity overload of the class.
  The implementing method must repeat the parameter types, so the type list
  picks exactly one. }

interface

type
  IReader = interface
    ['{2C3A1B10-0000-4000-8000-00000000C003}']
    function Read(var A: Integer): Boolean; overload;
    function Read(var A: string): Boolean; overload;
    function Seek(Offset: Longint; Origin: Word): Longint; overload;
    function Seek(const Offset: Int64; const Origin: Word): Longint; overload;
  end;

  TReader = class(TInterfacedObject, IReader)
  public
    function Read(var A: Integer): Boolean; overload;
    function Read(var A : string): Boolean; overload;
    function Seek(Offset: Longint; Origin: Word): Longint; overload;
    function Seek(const Offset: Int64; const Origin: Word): Longint; overload;
  end;

implementation

function TReader.Read(var A: Integer): Boolean;
begin
  Result:= A <> 0;
end;

function TReader.Read(var A: string): Boolean;
begin
  Result:= A <> '';
end;

function TReader.Seek(Offset: Longint; Origin: Word): Longint;
begin
  Result:= Offset + Origin;
end;

function TReader.Seek(const Offset: Int64; const Origin: Word): Longint;
begin
  Result:= Origin;
end;

end.