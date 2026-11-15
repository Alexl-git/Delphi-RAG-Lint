unit TodoCommentFixture;

interface

procedure Work;

implementation

// TODO: handle the empty case
procedure Work;
begin
  { FIXME broken on Win64 }
  (* TODO(alex) later *)
  { TODO 1 -oOwner -cGUI : set focus }
end;

end.
