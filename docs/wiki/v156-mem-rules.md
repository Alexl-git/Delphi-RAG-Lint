# Items that nobody frees, instances that nobody owns (lane MEM, 1.56)

Three rules about who frees an object. They run in `lint` and `lint-all`, in the IDE and in VS Code.

```
drag-lint lint <unit.pas> --db <project.sqlite> --rule container-items-leak
drag-lint lint-all --db <project.sqlite> --enable fresh-instance-as-argument,class-passed-as-interface
```

| rule | severity | default | needs the index | page |
|---|---|---|---|---|
| `container-items-leak` | warning | ON | no (classes of other units: yes) | this page |
| `fresh-instance-as-argument` | info | OFF | yes | [v156-instance-argument-rules](v156-instance-argument-rules.md) |
| `class-passed-as-interface` | warning | OFF | yes | [v156-instance-argument-rules](v156-instance-argument-rules.md) |

Turn one off with `"disabled": ["container-items-leak"]` in the lint config or `--disable`, on with `"enabled": [..]` or
`--enable`, or approve one line with a `dl:ok` marker.

## container-items-leak

A `TList<T>` or a `TDictionary<K, V>` does not free what it holds. When a routine fills such a container with new objects
and then frees only the container, every object stays in memory:

```pascal
procedure LoadAll;
var
  L: TList<TFoo>;
  I: Integer;
begin
  L := TList<TFoo>.Create;
  try
    for I := 1 to 3 do
      L.Add(TFoo.Create);      // reported here: nobody frees the three TFoo
    Writeln(L.Count);
  finally
    L.Free;                    // frees the list, not its items
  end;
end;
```

One finding per container, on the first line that adds a new object.

### What the rule looks at

* **The container** is a local variable (a `var` section or an inline `var`) that the routine creates itself as one of:
  `TList<T>`, `TStack<T>`, `TQueue<T>`, `TThreadList<T>`, `TDictionary<K, V>` (the value type), the non-generic `TList`,
  or `TObjectList` / `TObjectList<T>` / `TObjectStack<T>` / `TObjectQueue<T>` created with `Create(False)`.
* **The added value** is new: `L.Add(TFoo.Create)`, or a local that only ever holds a `TFoo.Create`
  (`Item := TFoo.Create; L.Add(Item)`). The calls are `Add`, `Insert`, `Push`, `Enqueue`, `AddOrSetValue` and `TryAdd`; the
  last argument is the item.
* **`TFoo` is known to be a class**: declared in the file, or found in the project index or the library index.

### When it stays silent

| case | example |
|---|---|
| the container owns its items | `TObjectList<TFoo>.Create`, or `OwnsObjects` is touched anywhere in the routine |
| an item is freed in the routine | `for X in L do X.Free`, `TFoo(L[I]).Free`, `Item.Free` |
| the container leaves the routine | `Result := L`, `FItems := L`, `Consume(L)`, `Exit(L)`, `with L do` |
| an item leaves the routine | `Keep(L[0])`, `FFirst := L.First`, `Other.Add(X)` for an `X` read from the container |
| the element cannot leak | `TList<IBar>` (an interface is counted), `TList<TRec>` (a record) |
| the object has an owner | `TButton.Create(Self)`, `TComponent.Create(AOwner)` |
| the value is not new | a parameter, a field, a function result |
| the type is not known | a class of another unit while there is no index: the rule never guesses |
| the container is assigned twice | the rule cannot tell which one is filled |

Reading an item and calling its methods (`for X in L do X.Work`, `L[0].Name`) does not silence the rule: that does not free
anything.

### How to fix it

* Use an owning container: `TObjectList<TFoo>.Create` (owns by default), `TObjectDictionary<K, V>.Create([doOwnsValues])`.
* Or free the items before the container: `for X in L do X.Free;`.

### Limits

* Local containers only. A field filled in one method and freed in another is not judged (that needs the whole class; the
  rule would have to guess which method frees).
* The check is per routine and reads the source of that routine. An item handed to any routine counts as handed on, even
  when that routine only reads it.

## What the rule adds over the compiler

dcc64 37.0 with all warnings and hints on (`-W+ -H+`) compiles both fixture units (`tests/fixtures/v156/MEMA`, 357 lines, six
leaking routines) without a single message. The compiler has no message about ownership of container items.

## Measured

Not measured in the field yet: on 2026-11-26 the machine ran the 1.55 release battery and no real project index was allowed.
The fixture run is `tests/autotest/run_v156_MEMA.ps1` (6 firing lines, 14 silent routines, with and without the index). The
false-positive step of 1.56 measures the rule on copies of the project indexes and decides whether it stays ON.
