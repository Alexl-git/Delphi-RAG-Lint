unit CvLib;

interface

uses
  System.Classes;

type
  TScreenCursorOld = (scoDefault, scoWait, scoBusy, scoOther);
  TOldThing = class(TComponent)
  end;
  TOldThing2 = class(TComponent)
  end;
  TOldField = class(TComponent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;
  TNewField = class(TComponent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;

implementation

end.
