unit GenWidget;

// Plan fixture (lane CYC3, case 15): the widget uses its host in the implementation.

interface

type
  /// <summary>A widget.</summary>
  TGenWidget = class
  public
    /// <summary>Writes a line.</summary>
    procedure Hello;
    /// <summary>Shows itself through a host.</summary>
    procedure Reload;
  end;

implementation

uses
  System.Generics.Collections, GenHost;

procedure TGenWidget.Hello;
begin
  Writeln('[gen] hello');
end;

procedure TGenWidget.Reload;
var
  H: TGenHost;
  L: TList<TGenWidget>;
begin
  H := TGenHost.Create;
  L := TList<TGenWidget>.Create;
  try
    L.Add(Self);
    H.ShowAll(L);
  finally
    L.Free;
    H.Free;
  end;
end;

end.
