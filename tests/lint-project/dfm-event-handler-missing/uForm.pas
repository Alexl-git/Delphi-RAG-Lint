unit uForm;

interface

uses
  uBase;

type
  TMainForm = class(TBaseForm)
  published
    procedure FormClick(Sender: TObject);
    procedure BtnClick(Sender: TObject);
  end;

  TOrphanForm = class(TUnknownThing)
  published
    procedure OrphanClick(Sender: TObject);
  end;

implementation

procedure TMainForm.FormClick(Sender: TObject);
begin
end;

procedure TMainForm.BtnClick(Sender: TObject);
begin
end;

procedure TOrphanForm.OrphanClick(Sender: TObject);
begin
end;

end.
