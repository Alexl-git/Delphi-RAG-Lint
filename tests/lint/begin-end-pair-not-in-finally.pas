unit begin_end_pair_not_in_finally;

{ begin-end-pair-not-in-finally fixture.  HIT marker = rule fires on the Begin
  call, OK marker = silent.  Known FP shape: a Begin whose End sits in a finally of
  an unrelated, later try is accepted. }

interface

implementation

uses
  System.Classes;

procedure EndInBody(AList: TStringList);
begin
  AList.BeginUpdate; {HIT}
  AList.Add('x');
  AList.EndUpdate;
end;

procedure EndMissingLocal;
var
  L: TStringList;
begin
  L:= TStringList.Create;
  try
    L.BeginUpdate; {HIT}
    L.Add('x');
  finally
    L.Free;
  end;
end;

procedure EndInFinally(AList: TStringList);
begin
  AList.BeginUpdate; {OK}
  try
    AList.Add('x');
  finally
    AList.EndUpdate;
  end;
end;

procedure BeginInsideTry(AList: TStringList);
begin
  try
    AList.BeginUpdate; {OK}
    AList.Add('x');
  finally
    AList.EndUpdate;
  end;
end;

procedure EndInOtherMethod(AList: TStringList);
begin
  AList.BeginUpdate; {OK}
end;

end.
