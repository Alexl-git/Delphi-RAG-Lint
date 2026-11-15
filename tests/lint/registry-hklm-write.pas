unit RegistryHklmWrite;

interface

implementation

uses
  Winapi.Windows, System.Win.Registry;

procedure WriteMachine;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKey('Software\Vendor\App', True) then // MUST-FIRE create below HKLM
      Reg.WriteString('Language', 'de');
  finally
    Reg.Free;
  end;
end;

procedure WriteMachineWinApi;
var
  Key: HKEY;
begin
  RegCreateKeyEx(HKEY_LOCAL_MACHINE, 'Software\Vendor', 0, nil, 0, KEY_WRITE, nil, Key, nil); // MUST-FIRE
end;

procedure ReadMachine;
var
  Reg: TRegistry;
  S: string;
begin
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKey('Software\Vendor\App', False) then // read only: silent
      S := Reg.ReadString('Language');
  finally
    Reg.Free;
  end;
end;

procedure WriteUser;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Vendor\App', True) then // HKCU: silent
      Reg.WriteString('Language', 'de');
  finally
    Reg.Free;
  end;
end;

end.
