unit PreferCase;

interface

implementation

procedure P(Kind: Integer; const S: string);
begin
  if Kind = 1 then
    DoNew
  else if Kind = 2 then
    DoOpen
  else if Kind = 3 then
    DoSave
  else
    DoClose;
  if Kind = 1 then
    DoNew
  else if Kind = 2 then
    DoOpen
  else
    DoSave;
  if S = 'a' then
    DoNew
  else if S = 'b' then
    DoOpen
  else if S = 'c' then
    DoSave;
  if Kind = 1 then
    DoNew
  else if Kind > 2 then
    DoOpen
  else if Kind = 3 then
    DoSave;
end;

end.
