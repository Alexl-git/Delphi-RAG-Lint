unit DuplicateInterfaceGuid;

interface

type
  ILoader = interface
    ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
    procedure Load;
  end;

  ISaver = interface
    ['{6c1d2a57-0e3b-4f8a-9b2d-5a7e4c3f1d08}']
    procedure Save;
  end;

  IOther = interface
    ['{11111111-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
    procedure Other;
  end;

  IOtherDisp = dispinterface
    ['{11111111-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
  end;

implementation

end.
