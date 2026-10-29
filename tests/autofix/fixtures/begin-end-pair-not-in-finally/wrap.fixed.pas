unit wrap;

interface

implementation

uses
  System.Classes;

procedure Fill(AList: TStringList);
begin
  AList.BeginUpdate;
  try
    AList.Add('a');
    AList.Add('b');
  finally
    AList.EndUpdate;
  end;
end;

end.
