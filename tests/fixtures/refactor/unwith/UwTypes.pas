unit UwTypes;

{ The target types of the unwith fixture. Members deliberately reuse names the cases also declare as locals or
  enclosing-class members: that is how a `with` removal rebinds silently. }

interface

uses
  UwHidden;

type
  TPoint3 = record
    X, Y, Z: Integer;
    function Sum: Integer;
  end;

  TBase = class
  private
    FTag: Integer;
    PrivateName: Integer;
  protected
    ProtName: Integer;
  public
    Count: Integer;
    property Tag: Integer read FTag write FTag;
    function Twice(pV: Integer): Integer;
    function Identity: TBase;
  end;

  TMid = class(TBase)
  public
    Value: Integer;
    Pt: TPoint3;
  end;

  THelped = class(TMid)
  public
    Label1: Integer;
  end;

  THelpedHelper = class helper for THelped
    function HelperOnly: Integer;
  end;

  TOwner = class
  private
    FItem: TMid;
    FCursor: TMid;
    FStable: TMid;
    function GetComputed: TMid;
  public
    Other: TMid;
    constructor Create;
    destructor Destroy; override;
    procedure Advance;
    property Item: TMid read FItem;
    property Computed: TMid read GetComputed;
    property Cursor: TMid read FCursor;
    property Stable: TMid read FStable;
  end;

  TNestedHolder = class
  public
    type
      TKind = (kOne, kTwo);
    const
      CLimit = 5;
    var
      Kind: TKind;
  end;

  TFromHidden = class(THiddenBase)
  public
    Own: Integer;
  end;

  { A variant part: its fields are members like any other. }
  TShape = record
    Tag: Integer;
    case Integer of
      0: (AsInt: Integer);
      1: (Lo, Hi: Word);
  end;

  THasIfdefMember = class
  public
    A: Integer;
    {$IFDEF NEVER_DEFINED}
    B: Integer;
    {$ENDIF}
  end;

implementation

function TPoint3.Sum: Integer;
begin
  Result:= X + Y + Z;
end;

function TBase.Twice(pV: Integer): Integer;
begin
  Result:= pV * 2;
end;

function TBase.Identity: TBase;
begin
  Result:= Self;
end;

function THelpedHelper.HelperOnly: Integer;
begin
  Result:= Label1 + 1;
end;

constructor TOwner.Create;
begin
  inherited Create;
  FItem:= TMid.Create;
  FCursor:= TMid.Create;
  FStable:= TMid.Create;
  Other:= TMid.Create;
end;

destructor TOwner.Destroy;
begin
  Other.Free;
  FStable.Free;
  FCursor.Free;
  FItem.Free;
  inherited Destroy;
end;

procedure TOwner.Advance;
begin
  FCursor:= Other;
end;

function TOwner.GetComputed: TMid;
begin
  Result:= FItem;
end;

end.