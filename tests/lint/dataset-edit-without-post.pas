unit DatasetEditWithoutPost;

interface

implementation

uses
  Data.DB, FireDAC.Comp.Client;

procedure BadEditAssign(tblKunde: TFDTable);
begin
  tblKunde.Edit;
  tblKunde.FieldByName('Status').AsInteger := 1;
end;

procedure BadAppendParens(Q: TFDQuery);
begin
  Q.Append();
  Q.Fields[0].AsString := 'x';
  Q.FieldByName('B').AsInteger := 2;
end;

procedure BadWith(Q: TFDQuery);
begin
  with Q do
  begin
    Edit;
    FieldByName('X').AsString := 'a';
  end;
end;

procedure BadPostOnOther(Q, R: TFDQuery);
begin
  Q.Insert;
  Q.FieldByName('A').AsInteger := 1;
  R.Edit;
  R.FieldByName('A').AsInteger := 1;
  R.Post;
end;

procedure GoodPost(Q: TFDQuery);
begin
  Q.Edit;
  Q.FieldByName('A').AsInteger := 1;
  Q.Post;
end;

procedure GoodCancel(Q: TFDQuery);
begin
  Q.Append;
  try
    Q.FieldByName('A').AsInteger := 1;
    Q.Post;
  except
    Q.Cancel;
    raise;
  end;
end;

procedure GoodWithPost(Q: TFDQuery);
begin
  with Q do
  begin
    Edit;
    FieldByName('X').AsString := 'a';
    Post;
  end;
end;

procedure GoodCheckBrowse(Q: TFDQuery);
begin
  Q.Edit;
  Q.FieldByName('A').AsInteger := 1;
  Q.CheckBrowseMode;
end;

procedure GoodEditOnly(Q: TFDQuery);
begin
  // the record is posted by the Save button's handler
  Q.Edit;
end;

procedure GoodNoFieldWrite(Q: TFDQuery);
begin
  Q.Edit;
  ShowMessage(Q.FieldByName('A').AsString);
end;

procedure GoodInsertWithArgs(L: TStringList);
begin
  L.Insert(0, 'x');
  L.Strings[0] := 'y';
end;
end.
