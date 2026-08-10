unit provenance;

interface

function Marked(const AText: string): Integer;

/// <summary>Hand-written and must survive verbatim.</summary>
/// <returns>Observed: this is hand-written prose that merely starts with the word.</returns>
function HandWritten: Integer;

implementation

{ Touch exists so that Marked has a CONTENT-BEARING fact of its own.

  Marked's body used to be `Result := Length(AText);` alone, and its facts block
  was `Calls: Length`. When compiler intrinsics stopped being rendered as
  callees -- Inc and SetLength are syntax, not collaborators -- that block
  became empty, and by the long-standing rule that `Pure` never creates a block
  of its own, Marked stopped getting a managed comment at all. Four assertions
  in run_doc_p3_provenance went red, none of them about intrinsics.

  That rule is deliberate and is not being relaxed here: writing a doc block is
  a file edit, and the bar for making one is "there was something to say". So
  the fixture gives Marked something to say. `Result := Length(AText)` is kept
  exactly as it was, because the mined <returns> ("Observed: Length(AText).") is
  what assertion 2 reads the provenance marker off. }
procedure Touch;
begin
end;

function Marked(const AText: string): Integer;
begin
  Touch;
  Result := Length(AText);
end;

function HandWritten: Integer;
begin
  Result := 1;
end;

end.
