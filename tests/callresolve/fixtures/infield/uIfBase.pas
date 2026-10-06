unit uIfBase;

{ Fixture for run_in_class_field_bind.ps1 (DEC-19, resolver 1.12.0-alpha).
  TIfBase -> TIfMiddle -> (uIfUse) TIfLeaf: tblFtrs is declared TWO levels
  above the class whose methods read it, the DMTEST shape. }

interface

uses
  Classes;

type
  TIfTable = class(TComponent)
  public
    procedure Post;
    function State: Integer;
  end;

  TIfBase = class(TDataModule)
    tblFtrs: TIfTable;
  public
    FBaseCount: Integer;
  end;

  TIfMiddle = class(TIfBase)
  protected
    FMid: Integer;
  end;

implementation

{$R *.dfm}

procedure TIfTable.Post;
begin
end;

function TIfTable.State: Integer;
begin
  Result:= 0;
end;

end.
