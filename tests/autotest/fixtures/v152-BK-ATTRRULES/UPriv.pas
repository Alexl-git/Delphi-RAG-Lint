unit UPriv;

{ member-could-be-private over the attributes index fact (1.52 BK-ATTRRULES, B48).
  (+) must be reported, (-) must not. The (-) members carry an attribute (split from the member by a
  comment; spread over two lines). AfterParamAttr follows a line that starts with a PARAMETER
  attribute ([ref]): the 1.52 ATLB one-line source peek took that for the member's own attribute and
  stayed silent; the attributes table ties [ref] to the parameter. }

interface

type
  TMyAttribute = class(TCustomAttribute)
  public
    constructor Create(const AText: string);
  end;

  TPriv = class
  public
    [TMyAttribute('one')]
    // a comment between the attribute and the member
    procedure CommentSplit; { (-) }
    [TMyAttribute(
      'two lines')]
    procedure MultiLine; { (-) }
    procedure Plain; { (+) }
    procedure WithRefParam(const A: Integer; { (+) }
      [ref] const B: Integer);
    procedure AfterParamAttr; { (+) }
    procedure Run;
  end;

implementation

constructor TMyAttribute.Create(const AText: string);
begin
end;

procedure TPriv.CommentSplit;
begin
end;

procedure TPriv.MultiLine;
begin
end;

procedure TPriv.Plain;
begin
end;

procedure TPriv.WithRefParam(const A: Integer; [ref] const B: Integer);
begin
end;

procedure TPriv.AfterParamAttr;
begin
end;

procedure TPriv.Run;
begin
  CommentSplit;
  MultiLine;
  Plain;
  WithRefParam(1, 2);
  AfterParamAttr;
end;

end.