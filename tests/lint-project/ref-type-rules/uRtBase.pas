unit uRtBase;

interface

type
  TRtBase = class
  public
    Tag: Integer;
  end;

  TRtMid = class(TRtBase)
  end;

  TRtLeaf = class(TRtMid)
  public
    Link: TRtLeaf;
    Base: TRtBase;
    function Self2: TRtLeaf;
  end;

  TRtOther = class
  end;

function MakeBase: TRtBase;
function MakeLeaf: TRtLeaf;

implementation

function TRtLeaf.Self2: TRtLeaf;
begin
  Result:= Link;
end;

function MakeBase: TRtBase;
begin
  Result:= nil;
end;

function MakeLeaf: TRtLeaf;
begin
  Result:= nil;
end;

end.
