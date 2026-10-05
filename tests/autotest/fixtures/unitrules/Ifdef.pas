unit Ifdef;

interface

uses
  KeepU{$IFDEF FOO}, OldU{$ENDIF};

implementation

end.