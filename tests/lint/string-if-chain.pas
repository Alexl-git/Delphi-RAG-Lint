unit StringIfChain;

interface

implementation

procedure P(const Cmd: string);
begin
  if Cmd = 'new' then
    DoNew
  else if Cmd = 'open' then
    DoOpen
  else if Cmd = 'save' then
    DoSave
  else if Cmd = 'close' then
    DoClose;
  if Cmd = 'a' then
    DoNew
  else if Cmd = 'b' then
    DoOpen
  else
    DoSave;
  if Cmd = 'x' then
    DoNew
  else if Cmd = 'y' then
    DoOpen
  else if Other = 'z' then
    DoSave;
  if Cmd = 'x' then
    DoNew
  else if Cmd = 'y' then
    DoOpen
  else if Cmd = 'z' then
    DoSave
  else
    DoClose;
end;

end.
