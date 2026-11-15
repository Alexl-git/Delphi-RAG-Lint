unit System.Classes;

// NOT part of the project: a miniature platform library for the rename proof.

interface

type
  TObject = class
    procedure Free;
  end;
  TPersistent = class(TObject)
  end;
  TComponent = class(TPersistent)
    function FindComponent(const AName: string): TComponent;
  end;

implementation

end.
