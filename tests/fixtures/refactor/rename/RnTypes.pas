unit RnTypes;

// Fixture of tests\autotest\run_rename_precise.ps1: same-named members on unrelated classes, a library ancestor, an override
// chain, an interface, and names that capture. Compiles; RunAll's output is the proof that a rewrite kept every binding.

interface

uses
  System.Classes, System.Generics.Collections;

type
  TTwoA = class
  private
    FSize: Integer;
  public
    Item: TTwoA;
    function Count: Integer;
    procedure Run; virtual;
    property Size: Integer read FSize write FSize;
  end;

  TTwoB = class
  public
    Other: TTwoB;
    Kind: Integer;
    Capacity: Integer;
    function Count: Integer;
    procedure Run; virtual;
    procedure Zeta;
  end;

  TKid = class(TTwoA)
  public
    procedure Run; override;
    procedure AfterConstruction; override;
    function Twice: Integer;
    function UsesHelper: Integer;
  end;

  TOv = class
  public
    function Go(pA: Integer): Integer; overload;
    function Go(const pA: string): Integer; overload;
  end;

  TListy = class(TList)
  end;

  TIntList = TList<Integer>;

  TRecX = record
    Count: Integer;
    Size: Integer;
  end;

  TNoCount = record
    Size: Integer;
  end;

  IDoer = interface
    ['{7B0B2F6E-5E0E-4C43-9D6B-3A9C7F1E2A10}']
    function Act: Integer;
  end;

  TDoer = class(TInterfacedObject, IDoer)
  public
    function Act: Integer;
  end;

function Compute: Integer;
function Helper: Integer;

implementation

function Compute: Integer;
begin
  Result:= 7;
end;

function Helper: Integer;
begin
  Result:= 40;
end;

function TTwoA.Count: Integer;
begin
  Result:= 1;
end;

procedure TTwoA.Run;
begin
  Writeln('TTwoA.Run');
end;

function TTwoB.Count: Integer;
begin
  Result:= 2;
end;

procedure TTwoB.Run;
begin
  Writeln('TTwoB.Run');
end;

procedure TTwoB.Zeta;
begin
  Writeln('Zeta');
end;

procedure TKid.Run;
begin
  inherited Run;
  Writeln('TKid.Run');
end;

procedure TKid.AfterConstruction;
begin
  inherited;
end;

function TKid.Twice: Integer;
begin
  Result:= Count + Count;
end;

function TKid.UsesHelper: Integer;
begin
  Result:= Helper;
end;

function TOv.Go(pA: Integer): Integer;
begin
  Result:= pA;
end;

function TOv.Go(const pA: string): Integer;
begin
  Result:= Length(pA);
end;

function TDoer.Act: Integer;
begin
  Result:= 11;
end;

end.
