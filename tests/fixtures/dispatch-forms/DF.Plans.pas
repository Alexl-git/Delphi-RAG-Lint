unit DF.Plans;

interface

uses
  DF.Base;

type
  TPlanA = class(TPlanBase)
  public
    procedure EditForm; override;
  end;

  TPlanB = class(TPlanBase)
  public
    procedure EditForm; override;
  end;

  { reintroduce without override: no dispatch edge. }
  TPlanR = class(TPlanBase)
  public
    procedure EditForm; reintroduce;
  end;

implementation

uses
  System.SysUtils, DF.FormA;

procedure TPlanA.EditForm;
var
  F: TfrmA;
begin
  F:= TfrmA.Create(nil);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure TPlanB.EditForm;
begin
  raise Exception.Create('plan B is not editable');
end;

procedure TPlanR.EditForm;
begin
end;

end.
