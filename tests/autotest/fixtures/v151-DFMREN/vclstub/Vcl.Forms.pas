unit Vcl.Forms;

// NOT part of the project: a miniature platform library for the rename proof.

interface

uses
  System.Classes, Vcl.Controls;

type
  TScrollingWinControl = class(TWinControl)
  end;
  TCustomForm = class(TScrollingWinControl)
  end;
  TForm = class(TCustomForm)
  end;
  TCustomFrame = class(TScrollingWinControl)
  end;
  TFrame = class(TCustomFrame)
  end;

implementation

end.
