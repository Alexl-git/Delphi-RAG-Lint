unit tnp;
interface
type
  Widget = class            // should fire: class without T prefix
  end;
  TGadget = class           // clean
  end;
  IThing = interface        // clean
  end;
  BadThing = interface      // should fire: interface without I prefix
  end;
implementation
end.
