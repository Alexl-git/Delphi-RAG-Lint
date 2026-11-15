unit component_missing_free_notification;

{ Fixture for component-missing-free-notification (warning).
  Fires: a setter of a component-typed property of a component that stores the
  parameter in a field and never calls FreeNotification; a published
  component-typed property whose write accessor is the field itself.
  Silent: a setter that calls FreeNotification (directly or through a method of
  the class), a field the class creates itself, a setter that copies with Assign,
  a non-component property, a public field writer, a class that is not a
  component. Markers: a line ending in (+) must fire, (-) must not. }

interface

uses
  Classes, Controls;

type
  TLinker = class(TComponent)
  private
    FLink: TControl;
    FSafe: TControl;
    FOwned: TComponent;
    FCopied: TControl;
    FDirect: TComponent;
    FPublicDirect: TComponent;
    FHelped: TControl;
    FCount: Integer;
    procedure SetLink(const Value: TControl);
    procedure SetSafe(const Value: TControl);
    procedure SetOwned(const Value: TComponent);
    procedure SetCopied(const Value: TControl);
    procedure SetHelped(const Value: TControl);
    procedure SetCount(const Value: Integer);
    procedure Attach(AValue: TControl);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    property PublicDirect: TComponent read FPublicDirect write FPublicDirect; { (-) }
  published
    property Link: TControl read FLink write SetLink;
    property Safe: TControl read FSafe write SetSafe;
    property Owned: TComponent read FOwned write SetOwned;
    property Copied: TControl read FCopied write SetCopied;
    property Direct: TComponent read FDirect write FDirect; { (+) }
    property Helped: TControl read FHelped write SetHelped;
    property Count: Integer read FCount write SetCount;
  end;

  TPlain = class(TObject)
  private
    FLink: TControl;
    procedure SetLink(const Value: TControl);
  published
    property Link: TControl read FLink write SetLink;
  end;

implementation

constructor TLinker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOwned := TComponent.Create(Self);
end;

procedure TLinker.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSafe) then
    FSafe := nil;
end;

procedure TLinker.SetLink(const Value: TControl);
begin
  FLink := Value; { (+) }
end;

procedure TLinker.SetSafe(const Value: TControl);
begin
  if FSafe <> nil then
    FSafe.RemoveFreeNotification(Self);
  FSafe := Value; { (-) }
  if FSafe <> nil then
    FSafe.FreeNotification(Self);
end;

procedure TLinker.SetOwned(const Value: TComponent);
begin
  FOwned := Value; { (-) }
end;

procedure TLinker.SetCopied(const Value: TControl);
begin
  FCopied.Assign(Value); { (-) }
end;

procedure TLinker.Attach(AValue: TControl);
begin
  if AValue <> nil then
    AValue.FreeNotification(Self);
end;

procedure TLinker.SetHelped(const Value: TControl);
begin
  FHelped := Value; { (-) }
  Attach(Value);
end;

procedure TLinker.SetCount(const Value: Integer);
begin
  FCount := Value; { (-) }
end;

procedure TPlain.SetLink(const Value: TControl);
begin
  FLink := Value; { (-) }
end;

end.
