unit GenHost;

// Plan fixture (lane CYC3, case 15): the host names the widget class as a generic type argument in its interface.

interface

uses
  System.Generics.Collections, GenWidget;

type
  /// <summary>Holds widgets.</summary>
  TGenHost = class
  public
    /// <summary>Says hello to every widget.</summary>
    /// <param name="pList">The widgets.</param>
    procedure ShowAll(const pList: TList<TGenWidget>);
  end;

implementation

procedure TGenHost.ShowAll(const pList: TList<TGenWidget>);
begin
  for var W in pList do W.Hello;
end;

end.
