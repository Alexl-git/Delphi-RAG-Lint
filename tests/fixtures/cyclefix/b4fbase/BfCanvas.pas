unit BfCanvas;

// CYCC B4-f fixture: paints any object; only a TBfShape gets its name printed. The two overloads
// of one arity keep R1 off the edge BfShape -> BfCanvas.

interface

/// <summary>Paints pShape with a pen width.</summary>
/// <param name="pShape">Any object.</param>
/// <param name="pWidth">The pen width.</param>
procedure BfCanvasPaint(pShape: TObject; pWidth: Integer); overload;
/// <summary>Paints pShape with a pen style.</summary>
/// <param name="pShape">Any object.</param>
/// <param name="pStyle">The pen style.</param>
procedure BfCanvasPaint(pShape: TObject; const pStyle: string); overload;

implementation

uses
  BfShape;

procedure BfCanvasPaint(pShape: TObject; pWidth: Integer);
begin
  if pShape is TBfShape then
    Writeln('paint ', (pShape as TBfShape).Name, ' width ', pWidth);
end;

procedure BfCanvasPaint(pShape: TObject; const pStyle: string);
begin
  if pShape is TBfShape then
    Writeln('paint ', (pShape as TBfShape).Name, ' style ', pStyle);
end;

end.