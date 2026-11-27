# ask: class-diagram

**One class with its ancestors, its descendants and the classes it holds in fields.** A UML-style class diagram drawn from the index. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask class-diagram --target MyApp.Orders.TOrder --db <project.sqlite>
```

Pass `--project <P.dproj>` or `--in <U.pas>` instead of `--db` to let the engine find the index. `--depth N` bounds how far the ancestor and descendant walks go (default 4); `--cap N` bounds the number of classes drawn (default 20).

## You select

A class, interface or record, by bare or qualified name. A name that is ambiguous or is not such a type is refused with the reason.

## The chart shows

* the type itself (heavy outline);
* **ancestors** above it: one hollow-arrow edge per ancestor, walked up; an ancestor the index does not declare (an RTL or VCL class) is drawn as a node marked "outside this index";
* **descendants** below it: the types that inherit from it, walked down;
* **has-a links**: one diamond edge, labelled with the field name, from the type to every class, interface or record that one of its fields is declared as.

Every class node is anchored to its declaration; clicking opens the line.

## It stands on

The `symbols` table (classes and their `field` members), `type_ancestors` (the ancestor and descendant edges) and the resolved `type_use` reference on the field's line (the field's type). Fields of the ancestors and descendants are not drawn; the diagram is one type deep on has-a links.

## Read it carefully

* A field whose type is not an indexed class (`Integer`, `string`, an RTL type) draws no edge.
* A field declared with a generic type draws an edge only for the generic type argument or type the index resolved on that line.
* Descendants come only from the index you pass; a base class used across several projects shows the descendants of THIS project's closure.
