# Interfaced object set to nil (`interfaced-object-nil-leak`)

An OBJECT reference to a `TInterfacedObject` descendant is set to `nil` while it holds a fresh instance. Only an interface reference counts; an object reference holds no count, so `nil` releases nothing and the instance leaks. OFF by default.

```pascal
function Build: TThing;      // TThing = class(TInterfacedObject, IThing)
begin
  try
    Result := TThing.Create;
    Result.Load;
  except
    Result := nil;           // finding: the instance leaks. Return IThing, or Free it.
  end;
end;
```

## Running it
```
drag-lint lint <file> --rule interfaced-object-nil-leak
drag-lint lint-all --db <project.sqlite> --rule interfaced-object-nil-leak
```

## What stays silent
- `Result := nil` with no instance created before it (the find idiom).
- A reference that may have reached an interface holder first: a bare use (`I := T`, `Sink(T)`) or a method call on it (`T.Subscribe` can hand over Self). In those cases the `nil` only clears an alias.
- A variable typed as an interface.
- `T.Free` before the `nil`.
- `if C then X := T.Create else X := nil`: the two are on different branches.
- A class whose chain to `TInterfacedObject` is unknown. The rule reads the same file, then the index.
- A plain class. That is a different leak, and not what this rule is about.