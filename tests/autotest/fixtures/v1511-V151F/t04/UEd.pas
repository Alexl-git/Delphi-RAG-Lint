unit UEd;

interface

type
  TFrmEd = class
  private
    Q: TObject;
  public
    procedure QChange;
    procedure Save;
  end;

procedure Lone(R: TObject);

implementation

procedure TFrmEd.QChange;
begin
  Q.Edit; {OK}
  Q.FieldByName('A').AsString:= 'x';
end;

procedure TFrmEd.Save;
begin
  Q.Post;
end;

procedure Lone(R: TObject);
begin
  R.Edit; {HIT}
  R.FieldByName('A').AsInteger:= 1;
end;

end.
