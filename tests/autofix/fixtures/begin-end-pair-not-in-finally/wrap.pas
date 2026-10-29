unit wrap;

interface

implementation

uses
  System.Classes;

procedure Fill(AList: TStringList);
begin
  AList.BeginUpdate;
  AList.Add('a');
  AList.Add('b');
  AList.EndUpdate;
end;

end.
