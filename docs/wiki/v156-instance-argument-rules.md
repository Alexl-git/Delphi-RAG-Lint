# A new instance in an argument, a class passed as an interface (lane MEM, 1.56)

Two rules about an object that is handed to a routine. Both are OFF by default and both need the project index: they read
the exact callee, its parameter and what the callee does with that parameter.

```
drag-lint lint <unit.pas> --db <project.sqlite> --enable fresh-instance-as-argument,class-passed-as-interface
drag-lint lint-all --db <project.sqlite> --enable fresh-instance-as-argument,class-passed-as-interface
```

| rule | severity | default | needs the index |
|---|---|---|---|
| `fresh-instance-as-argument` | info | OFF | yes |
| `class-passed-as-interface` | warning | OFF | yes |

The third rule of the lane, `container-items-leak`, is on [v156-mem-rules](v156-mem-rules.md).

## fresh-instance-as-argument

The id is not new. Until 1.55 it was a pattern rule that reported every `Use(TFoo.Create)`. From 1.56 it resolves the call:
it reports only when the index names the exact callee and that callee only reads the parameter, so nobody frees the object.

```pascal
procedure Show(AFoo: TFoo);
begin
  Writeln(AFoo.Name);          // reads it, keeps nothing
end;

Show(TFoo.Create);             // reported: nobody frees the TFoo
```

Silent when:

* the callee stores, returns, passes on or frees the parameter (`List.Add(TFoo.Create)`, a setter, a constructor that keeps it);
* the index does not name one exact callee (an overload it cannot pick, a method pointer, a call with more arguments than
  the callee has parameters);
* the object has an owner (`TButton.Create(Self)`), or the class may be a component and the index cannot tell;
* there is no project index, or the index does not know the file.

## class-passed-as-interface

An object of a reference-counted class (`TInterfacedObject` and its descendants that do not replace `_AddRef`) is handed to
an interface parameter. Two shapes:

```pascal
procedure Run(const AJob: IJob);
...
Run(TJob.Create);              // reported: a const parameter takes no reference; the object leaks,
                               // or is freed early when the callee takes one

Job := TJob.Create;            // Job: TJob, an object reference
Run(Job);
Job.Tidy;                      // reported at Run(Job): a reference taken in the call frees the object
                               // when it is released; this line then uses a freed object
```

Silent when:

* the class is not reference counted (it declares its own `_AddRef`, or it does not descend from `TInterfacedObject`);
* the object reference is not used after the call;
* the created instance goes to a parameter that is not `const` (the call takes a reference and releases it);
* the index cannot decide the ancestry or the exact callee.

## Fix

* Hold the object in an interface variable: `var Job: IJob := TJob.Create; Run(Job);`.
* For `fresh-instance-as-argument`: keep the object in a local and free it in `try .. finally`.

## Status of this page

Written by lane MEM-A from lane MEM-B's rule unit while MEM-B was still running (2026-11-26). The measured counts and the
final list of silent cases come from MEM-B's final report.
