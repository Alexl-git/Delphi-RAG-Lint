unit InheritedBareV1511;

interface

type
  TBase = class
    destructor Destroy; override;
    procedure Assign(pSrc: TObject); virtual;
    procedure AssignTo(pDst: TObject); virtual;
    procedure Paint; virtual;
  end;

  TDerived = class(TBase)
    destructor Destroy; override;
    procedure Assign(pSrc: TObject); override;
    procedure AssignTo(pDst: TObject); override;
    procedure Paint; override;
    procedure Other(pSrc: TObject);
  end;

implementation

destructor TBase.Destroy;
begin
  inherited;
end;

procedure TBase.Assign(pSrc: TObject);
begin
end;

procedure TBase.AssignTo(pDst: TObject);
begin
end;

procedure TBase.Paint;
begin
end;

destructor TDerived.Destroy;
begin
  inherited;
end;

procedure TDerived.Assign(pSrc: TObject);
begin
  if not (pSrc is TDerived) then
    inherited
  else
    Paint;
end;

procedure TDerived.AssignTo(pDst: TObject);
begin
  if pDst is TDerived then
    Paint
  else
    inherited;
end;

procedure TDerived.Paint;
begin
  inherited;
end;

procedure TDerived.Other(pSrc: TObject);
begin
  Paint;
end;

end.
