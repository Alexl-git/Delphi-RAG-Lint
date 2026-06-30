unit tnp;
interface
type
  Widget = class            // should fire: class without T prefix
  end;
  TGadget = class           // clean: T + uppercase G
  end;
  TfrmMain = class          // clean: T + lowercase f (form-style name, accepted)
  end;
  IThing = interface        // clean
  end;
  BadThing = interface      // should fire: interface without I prefix
  end;
implementation
end.
