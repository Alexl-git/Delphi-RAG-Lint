unit Multiline;

interface

uses
  KeepU,     // keep me
  OldU in 'OldU.pas', { the old one }
  OtherU;

implementation

uses
  Keep2U,
  OldU;

end.