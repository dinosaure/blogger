---
date: 2020-02-17
article.title: Functor, Application and magick!
article.description:
  A little trick about *functor*
tags:
  - OCaml
  - tip
---

While I try to make an SMTP server in OCaml as an *unikernel*, I tried to deal
with `Set.Make`. Imagine a situation where you define your type `elt = string`
into a module `A` and you want to apply `Set.Make` inside the given module.

## Interface

Then, you would like to write a proper interface which describe result of your
*functor*. It should be easy than:

```ocaml
type elt = string

include Set.S with type elt = elt
```

But in my example, ~Set.S~ wants to (re)define `elt`. You probably miss the
[destructive substitution][destructive-substitution] of the type `elt`.

```ocaml
type elt = string

include Set.S with type elt := elt
```

## Implementation

The implementation will be more trickier. Indeed, we probably want to do
something like this:

```ocaml
include Set.Make(struct type t = string let compare = String.compare end)
```

And, fortunately for you, this snippet should work. However, it starts to be
pretty incomprehensible when `type elt` is one of your type (`string` or
`String.t` exists outside the scope of your module). We can take this example:

```ocaml
include Set.Make(struct
  type t = { v : string }
  let compare { v= a; } { v= b; } = String.compare a b
end)
```

Into the interface, by side the redefinition of the type `elt`, nothing should
change. However, the compilation fails with:

```sh
$ ocamlc -c a.ml
Error: The implementation a.ml does not match the interface a.cmi:
       Type declarations do not match:
         type elt
       is not included in
         type elt = { v : string; }
```

Indeed, we should have a definition of `elt` outside the `struct ... end`:

```ocaml
type elt = { v : string }

include Set.Make(struct
  type t = elt
  let compare { v= a; } { v= b; } = String.compare a b
end)
```

However, now, OCaml complains about a multiple definition of the type `elt`.
May be we can play more with the destructive substitution?

```ocaml
type elt = { v : string }

include
  (Set.Make(struct
     type t = elt
     let compare { v= a; } { v= b; } = String.compare a b
   end)
   : Set.S with type elt := elt)
```

And it's work!

## Just a tip

So I leave this trick here to help some people.

[destructive-substitution]: https://caml.inria.fr/pub/docs/manual-ocaml/manual030.html#sec252
