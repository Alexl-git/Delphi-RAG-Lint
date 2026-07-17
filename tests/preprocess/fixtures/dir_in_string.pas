unit U;
s := '{$DEFINE NOPE}';
{$IFDEF NOPE}var bad: Integer;{$ENDIF}
var ok2: Integer;
end.
