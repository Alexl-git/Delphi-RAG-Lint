unit nested_if;
interface
{$IFDEF A}
const OuterA = 1;
{$IFDEF B}
const InnerB = 2;
{$ELSE}
const InnerNotB = 3;
{$ENDIF}
{$ELSE}
const NoA = 4;
{$ENDIF}
implementation
end.