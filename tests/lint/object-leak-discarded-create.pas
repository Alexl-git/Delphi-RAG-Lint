unit object_leak_discarded_create;

{ v151 WID-FLOW: object-leak widened to a constructor call used as a
  statement. The new object is never stored, so nothing can ever free it. }

interface

uses
  System.Classes, System.SysUtils;

type
  TPlain = class
  public
    constructor Create; overload;
    constructor Create(ACount: Integer); overload;
  end;

  TSelfFreeing = class(TThread)
  protected
    procedure Execute; override;
  end;

  TPart = class(TComponent)
  end;

  TNode = class
  public
    constructor Create(AParent: TNode);
  end;

  TVal = record
    N: Integer;
    constructor Create(AN: Integer);
  end;

  EMine = class(Exception);

procedure Run(AOwner: TComponent; AParent: TNode);

implementation

constructor TPlain.Create;
begin
  inherited Create;
end;

constructor TPlain.Create(ACount: Integer);
begin
  inherited Create;
end;

procedure TSelfFreeing.Execute;
begin
end;

constructor TNode.Create(AParent: TNode);
begin
  inherited Create;
end;

constructor TVal.Create(AN: Integer);
begin
  N := AN;
end;

procedure Run(AOwner: TComponent; AParent: TNode);
var
  P: TPlain;
begin
  TPlain.Create;
  TPlain.Create(3);
  TPlain.Create();
  TSelfFreeing.Create(False);
  TPart.Create(AOwner);
  TNode.Create(AParent);
  TVal.Create(1);
  EMine.Create('x');
  P := TPlain.Create;
  P.Free;
end;

end.
