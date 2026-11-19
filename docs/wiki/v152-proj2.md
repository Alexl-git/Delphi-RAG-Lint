# unit-used-by-no-unit, and unit-not-in-dpr outside the project roots (1.52)

Two project-wide answers that `lint-all` gives from the project index.

## unit-used-by-no-unit

**Default:** ON. **Severity:** warning. **Category:** project-wide. **Where:** `lint-all` only
(it needs the whole project).

A unit fires when ALL of these hold:

1. the program file (`.dpr`) lists it in its `uses` clause;
2. no other indexed unit has it in a `uses` clause;
3. the program code never names one of its symbols (`Application.CreateForm(TMainForm, MainForm)`,
   `UnitX.Run`, an `exports` entry all count as a name);
4. it is not a self-registering unit -- see the exemptions.

The finding sits on the unit's `unit` line. It means: the unit is compiled in, but nothing can reach
it. Remove it from the project, or wire it in.

### Exemptions (owner ruling B9e)

| Unit | Result |
|---|---|
| Has an `initialization` section | silent: it registers itself |
| Registers a class in a DI container itself (`GlobalContainer.RegisterType<T>...`) | silent |
| A form (an indexed sibling `.dfm` / `.fmx`) that the program code creates | silent |
| A form whose class another unit names in a string (`FindClass('TNamedForm')`) | silent: opened by name |
| A form with only an `initialization` section (`RegisterClass(TMyForm)`) that nothing opens | **fires**: a form is exempt only when something opens it |
| A `.dpk` member | never a candidate: a package lists its members by design |

To keep one on purpose, add a reviewed marker:
`drag-lint allow <unit.pas> --fix-line <L> --fix-rule unit-used-by-no-unit --apply`, then write the reason in the marker.

### Example

```
C:\App\UDeadUnit.pas:1:1  [warning] unit-used-by-no-unit: Unit "UDeadUnit" is listed only by App.dpr:
no other unit uses it, the program code never names it, and it does not register itself ...
```

## unit-not-in-dpr: closure units outside the project roots (O05)

`lint-all --project` walks only the files under the project's own roots, and drops findings on files
outside them. A unit that a project unit uses, found through the search path in a shared folder
OUTSIDE those roots, and listed in neither the `.dpr` nor the `.dproj`, was therefore never reported
(the `index` run named it; `lint-all` did not). It is now reported with the usual "in NEITHER ...
Add it to both" message, anchored on the program file, and the message ends with the unit's real
path: `Found at <path>, outside the project roots.`

Without `--project` nothing changes: that run already hands the rule every indexed file.

## Tests

`tests\autotest\run_v152_PROJ2.ps1` over the fixture `tests\lint\unit-used-by-no-unit\` (`app\` is the
project root, `shared\` sits outside it). Positive controls: `--disable` of each rule silences it.