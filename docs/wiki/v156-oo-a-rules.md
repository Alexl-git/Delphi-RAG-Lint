# Object-model rules A (lanes OOA-1 and OOA-2, 1.56)

Four checks for code that depends on something the compiler accepts silently. They run in `lint` and `lint-all`, in the
IDE and in VS Code, and all four are on by default. `lint-all` or a store-backed `lint` is needed: they read the index.

```
drag-lint lint-all --db <project.sqlite> --rule ambiguous-unit-reference
drag-lint lint <unit.pas> --db <project.sqlite> --rule assignment-narrows
```

Turn one off with `"disabled": ["assignment-narrows"]` in the lint config, or approve one line with a `dl:ok` marker.
The fixtures are `tests\fixtures\v156\OOA1` and `\OOA2`; the runners are `tests\autotest\run_v156_OOA1.ps1` and `run_v156_OOA2.ps1`.

## ambiguous-unit-reference (warning, bug-patterns; lint-all)

Two units in one `uses` list declare the same name, and the unit calls it bare. The compiler picks the LAST unit in the list,
so reordering `uses` (or `uses-fix`, or `cycles --fix`) silently changes which routine or type the program uses.
Reported once per unit and name, at the first bare reference; the message names the unit that wins and the other declarers.

Silent when: the name is qualified (`uA.Normalize`); the using unit declares the name itself; the reference is bound to a local,
a parameter or a member; the declarations are an overload set whose signatures differ; the declarations are identical type
aliases; only one of the two units is used; the reference sits in a method and some class (project or library) has a member of that
name. Only directly used PROJECT units are compared: a library unit is not in the project index, so a project unit that shadows
a library name is not reported (1.56 limit).

## assignment-narrows (warning, bug-patterns)

`I32 := I64;` and `B := I32;`: a wider integer assigned to a narrower integer variable by plain assignment. The high bits vanish
silently when range checking is off. The source may be a variable, a field, a property or a function result (also across units,
for example a database key read through `AsLargeInt`). The message says which side to widen.

Silent when: the source is a constant or an enum value; the value is cast (`Integer(I64)`), masked or computed
(`I64 and $FF`, `A + B`); the routine is overloaded; the assignment is inside `with`; the types are not both integer types of known
width (floats, subranges, unknown types); or the line already carries an imported compiler finding. Needs an index with `ref_types`.

## abstract-method-not-overridden (warning, bug-patterns; lane OOA-2)

A concrete class that nothing derives from leaves an abstract method of an indexed ancestor open. Reported at the class
declaration, before anyone constructs it. Silent for a `class abstract`, for a class with descendants (an intermediate class), when
the ancestor is not indexed, for an overloaded name, and for a class in a `dl:shared` unit.

## handler-type-never-raised (warning, bug-patterns; lane OOA-2)

`on EMine do` where no code in the project raises, builds or otherwise mentions EMine or a descendant. Reported at the handled type.
Silent when any reference to the type or a descendant is neither a handler nor a declaration (a `raise`, a constructor call, a factory,
a variable, a cast and a class reference all count), and for a type in a `dl:shared` unit. Library exception types are not judged.

## When ambiguous-unit-reference stays silent (1.56 FP-1)

Two used units that declare the same name are not ambiguous when both declarations mean the same thing: a constant with the same type and value in both, a redirect `X = OtherUnit.X`, or the same `external` export declared in two units. Two functions with the same signature and different bodies are still reported.
