unit uGfLeak;

interface

uses
  System.Classes, System.SysUtils, System.RegularExpressions, System.Generics.Collections;

type
  TLocalRec = record
    class function Create: TLocalRec; static;
  end;

  TLocalClass = class
  end;

var
  GLeaked: TStringList;
  GViaRoutine: TList<Integer>;
  GFreed: TStringList;
  GFreedAndNil: TStringList;
  GFreedElsewhere: TStringList;
  GOwned: TComponent;
  GNoOwner: TComponent;
  GIntf: IInterface;
  GSettings: TFormatSettings;
  GFactory: TStringList;
  GHanded: TStringList;
  GRegEx: TRegEx;
  GLocalRec: TLocalRec;
  GLocalClass: TLocalClass;

implementation

uses
  uGfOther;

type
  TKeeper = class
    class procedure Add(AObject: TObject);
  end;

class procedure TKeeper.Add(AObject: TObject);
begin
end;

class function TLocalRec.Create: TLocalRec;
begin
  Result:= Default(TLocalRec);
end;

function MakeList: TStringList;
begin
  Result:= TStringList.Create;
end;

procedure Boot;
begin
  GViaRoutine:= TList<Integer>.Create; // TRIGGER-ROUTINE
end;

initialization
  GLeaked:= TStringList.Create; // TRIGGER-PLAIN
  Boot;
  GFreed:= TStringList.Create; // CONTROL-FREED
  GFreedAndNil:= TStringList.Create; // CONTROL-FREEANDNIL
  GFreedElsewhere:= TStringList.Create; // CONTROL-OTHERUNIT
  GOwned:= TComponent.Create(Owner); // CONTROL-OWNER
  GNoOwner:= TComponent.Create(nil); // TRIGGER-NILOWNER
  GIntf:= TInterfacedObject.Create; // CONTROL-INTF
  GSettings:= TFormatSettings.Create; // CONTROL-RECORD
  GFactory:= MakeList; // CONTROL-FACTORY
  GHanded:= TStringList.Create; // CONTROL-HANDED
  TKeeper.Add(GHanded);
  GRegEx:= TRegEx.Create('x'); // CONTROL-LIBRECORD a record's Create, unproven without a library
  GLocalRec:= TLocalRec.Create; // CONTROL-LOCALRECORD
  GLocalClass:= TLocalClass.Create; // TRIGGER-LOCALCLASS
finalization
  GFreed.Free;
  FreeAndNil(GFreedAndNil);
end.