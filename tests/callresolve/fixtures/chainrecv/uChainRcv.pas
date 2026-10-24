unit uChainRcv;

interface

type
  TLeaf = class
  public
    K: Integer;
  end;

  TInner = class
  public
    K: Integer;
    Leaf: TLeaf;
    procedure Ping;
  end;

  TRec = record
    Inner: TInner;
  end;

  TOuter = class
  private
    FInner: TInner;
  public
    property Inner: TInner read FInner;
  end;

  TOther = class
  public
    K: Integer;
  end;

procedure CaseOneSegment;
procedure CaseLocalRecord;
procedure CaseParamProp(O: TOuter);
procedure CaseThreeDeep(O: TOuter);
procedure CaseChainCall(O: TOuter);
procedure CaseUntypedSegment(O: TOuter);
procedure CaseUnknownHead;

implementation

procedure TInner.Ping;
begin
end;

procedure CaseOneSegment;
var
  L: TLeaf;
begin
  L.K := 9;
end;

procedure CaseLocalRecord;
var
  R: TRec;
begin
  R.Inner.K := 1;
end;

procedure CaseParamProp(O: TOuter);
begin
  O.Inner.K := 2;
end;

procedure CaseThreeDeep(O: TOuter);
begin
  O.Inner.Leaf.K := 3;
end;

procedure CaseChainCall(O: TOuter);
begin
  O.Inner.Ping;
end;

procedure CaseUntypedSegment(O: TOuter);
begin
  O.Missing.K := 4;
end;

procedure CaseUnknownHead;
begin
  XUndeclared.Inner.K := 5;
end;

end.