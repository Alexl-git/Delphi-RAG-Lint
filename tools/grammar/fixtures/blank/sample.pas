unit sample;
{$DEFINE KEEP_DIRECTIVE_1}
(*$R *.res*)
// COMMENT_TEXT_1 a line comment {$IFDEF LOOKS_LIKE_DIRECTIVE_IN_COMMENT}
/// COMMENT_TEXT_2 a DocInsight line

interface

{ COMMENT_TEXT_3 a brace comment
  spanning two lines }
(* COMMENT_TEXT_4 a star comment
   spanning two lines *)

type
  TKeep1 = class
    { COMMENT_TEXT_5 (* a star opener inside a brace comment } FKeep2: Integer;
    (* COMMENT_TEXT_6 { a brace opener inside a star comment *) FKeep3: Integer;
  end;

const
  SKeep4 = '{not a comment}';
  SKeep5 = '// not a comment either';
  SKeep6 = 'it''s {still} a string'; // COMMENT_TEXT_7 after a string with a doubled quote
  SKeep7 = '(* nor this *)';

implementation

{$IFDEF KEEP_DIRECTIVE_1}
procedure Keep8(const L: TList<{ COMMENT_TEXT_8 } Integer>);
begin
  if L.Count > 0 then // COMMENT_TEXT_9
    Exit;
end;
{$ENDIF}

end.
