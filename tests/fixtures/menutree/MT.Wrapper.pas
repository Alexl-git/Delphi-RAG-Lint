unit MT.Wrapper;

{ menu-tree fixture: a click wrapper the reader follows ONE level, the shape
  of the plugin's TMenuActionWrapper. Compiled, never run. }

interface

uses
  System.Classes;

type
  TMenuProc = reference to procedure(Sender: TObject);

  TClickWrapper = class
  private
    FProc: TMenuProc;
  public
    constructor Create(pProc: TMenuProc);
    procedure HandleClick(Sender: TObject);
  end;

implementation

constructor TClickWrapper.Create(pProc: TMenuProc);
begin
  inherited Create;
  FProc:= pProc;
end;

procedure TClickWrapper.HandleClick(Sender: TObject);
begin
  if Assigned(FProc) then FProc(Sender);
end;

end.
