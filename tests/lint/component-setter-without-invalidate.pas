unit component_setter_without_invalidate;

{ Fixture for component-setter-without-invalidate (hint).
  Fires at the field assignment of a setter whose field Paint reads (directly,
  through a property, or in a method Paint calls) when the setter repaints by no
  route. Silent: Invalidate in the setter, a helper of the class that repaints,
  a field Paint never reads. (+) must fire, (-) must not. }

interface

uses
  Classes, Controls, Graphics;

type
  TGauge = class(TCustomControl)
  private
    FColorA: TColor;
    FColorB: TColor;
    FText: string;
    FHidden: Integer;
    FMargin: Integer;
    procedure SetColorA(const Value: TColor);
    procedure SetColorB(const Value: TColor);
    procedure SetText(const Value: string);
    procedure SetHidden(const Value: Integer);
    procedure SetMargin(const Value: Integer);
    procedure UpdateView;
    procedure DrawFrame;
  protected
    procedure Paint; override;
  published
    property ColorA: TColor read FColorA write SetColorA;
    property ColorB: TColor read FColorB write SetColorB;
    property Text: string read FText write SetText;
    property Hidden: Integer read FHidden write SetHidden;
    property Margin: Integer read FMargin write SetMargin;
  end;

implementation

procedure TGauge.Paint;
begin
  Canvas.Brush.Color := FColorA;
  Canvas.Pen.Color := FColorB;
  Canvas.TextOut(0, 0, FText);
  DrawFrame;
end;

procedure TGauge.DrawFrame;
begin
  Canvas.Rectangle(Margin, Margin, Width - Margin, Height - Margin);
end;

procedure TGauge.UpdateView;
begin
  Repaint;
end;

procedure TGauge.SetColorA(const Value: TColor);
begin
  FColorA := Value; { (+) }
end;

procedure TGauge.SetColorB(const Value: TColor);
begin
  if FColorB <> Value then
  begin
    FColorB := Value; { (-) }
    Invalidate;
  end;
end;

procedure TGauge.SetText(const Value: string);
begin
  FText := Value; { (-) }
  UpdateView;
end;

procedure TGauge.SetHidden(const Value: Integer);
begin
  FHidden := Value; { (-) }
end;

procedure TGauge.SetMargin(const Value: Integer);
begin
  FMargin := Value; { (+) }
end;

end.
