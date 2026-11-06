unit uHiFile;

interface

implementation

uses
  System.IOUtils;

var
  GText: string;

initialization
  GText:= TFile.ReadAllText('config.txt'); // TRIGGER-DIRECT
end.