unit uRnTyped;

{ Fixture of read-never-assigned on F1 + ref_receivers (lane 145 L-E): a write of a field's
  NAME through a receiver the resolver cannot bind (the receiver's class does not declare the
  member). Typed as a class unrelated to the field's class, it no longer hides the field; typed
  as an ancestor of the field's class, or untyped, it still does. }

interface

type
  TRnTAlpha = class
  private
    FCount: Integer;   // TRIGGER-UNRELATED
  public
    function Total: Integer;
  end;

  TRnTOther = class
  public
    FPlain: Integer;
  end;

  TRnTParent = class
  public
    FPlain: Integer;
  end;

  TRnTChild = class(TRnTParent)
  private
    FLevel: Integer;   // CONTROL-RELATIVE
  public
    function Level: Integer;
  end;

  TRnTZeta = class
  private
    FTag: Integer;   // CONTROL-UNKNOWNTYPE
  public
    function Tag: Integer;
  end;

procedure RnTWrite(pOther: TRnTOther; pParent: TRnTParent);

implementation

uses
  uRnTMissing;

function TRnTAlpha.Total: Integer;
begin
  Result:= FCount;
end;

function TRnTChild.Level: Integer;
begin
  Result:= FLevel;
end;

function TRnTZeta.Tag: Integer;
begin
  Result:= FTag;
end;

procedure RnTWrite(pOther: TRnTOther; pParent: TRnTParent);
begin
  pOther.FCount:= 1;
  pParent.FLevel:= 3;
  RnTMystery.FTag:= 4;
end;

end.
