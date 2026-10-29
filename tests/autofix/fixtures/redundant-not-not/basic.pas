unit basic;

interface

implementation

procedure P(var B: Boolean; Flag: Boolean);
begin
  B := not not Flag;
end;

end.
