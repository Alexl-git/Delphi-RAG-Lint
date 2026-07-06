unit if_expr;
interface
{$IF CompilerVersion >= 37}
const Modern = True;
{$ELSE}
const Legacy = True;
{$IFEND}
implementation
end.