{ unit header block }
unit uCommentKinds;

interface

uses
  System.Generics.Collections;

type
  /// <summary>A documented class.</summary>
  TKinds = class
  public
    FCount: Integer; // trailing on a field
    /// <summary>Doc for Run.</summary>
    procedure Run;
    function Pick(AList: TList<{x} Integer>): Integer; (* paren trailing *)
  end;

const
  K1 = 1; /// one
  K2 = 2; /// two

{$IFDEF NEVER_DEFINED}
  KHidden = 3;
{$ENDIF}
(*$HINTS OFF*)
{ $NOT_A_DIRECTIVE }

implementation

const
  SLASHES = 'http://example.com { not a comment }';
  QUOTED = 'it''s // still a string';

(* outer { inner } still outer *)
procedure TKinds.Run;
var
  S: string;
begin
  // a statement comment
  S:= SLASHES + QUOTED; // dl:ok magic-literal@0000 -- fixture marker
  S:= '''
    multi // line { string
    ''';
  // dl:bk7 -- fixture bookmark
  FCount:= Length(S);
end;

function TKinds.Pick(AList: TList<Integer>): Integer;
begin
  Result:= AList.Count; {trailing brace}
end;

// loose block comment, not above a declaration

end.
