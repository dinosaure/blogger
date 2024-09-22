---
date: 2022-04-12
title: optint, 32-bits, 64-bits architecture and optimization
description:
  An introduction about optint, a little library to help you to support 32-bits
  architecture and 64-bits architecture
tags:
  - OCaml
  - Optimization
---

When I tried to implement [zlib][zlib] in OCaml, I ran into a thorny issue
regarding the *checksum* of the document requiring a 32-bit integer. Indeed, we
need to explain OCaml a bit to understand where the problem lies. This article
is a good opportunity to explain `optint`, a small library that wants to solve
an optimization problem between 32-bit and 64-bit architectures.

## An OCaml integer

OCaml provides an *immediate* integer `int` which has the particularity of not
being *boxed* (hence the immediate). Indeed, OCaml has a unified representation
of values. Some kind of values are represented through a pointer but it's not
the case of `int` and `bool` which directly use a simple word (a 32-bits word
or a 64-bits word depending on the architecture).

However, to differentiate a pointer from an *immediate* value (such as an
`int`), a *tag* bit is used. That mostly means that an `int` in OCaml is
encoded into 31-bits or 63-bits and we must let the least significant bit for
the runtime to be able to differentiate this immediate value from a pointer.

From this simple description, in the problem stated in the introduction, how do
we handle a 32-bit checksum for all platforms? We could use an `int32' which,
unlike an `int', is *boxed*. The advantage is that the code manipulating this
checksum is portable regardless of the architecture. The disadvantage of course
is the indirection inherent in this boxed value.

We could use the immediate type `int` but in that case, our code would not work
for a 32-bit architecture since our checksum could only be encoded on 31-bits
(and a checksum really needs 32-bits).

## A conditional compilation

Perhaps the solution would be to propose a module with a `type t` whose true
representation depends on the target architecture and which proposes, at least,
32-bits in any case.

In this case, for a 64-bit architecture, we would use an immediate type and for
a 32-bit architecture, we would use the boxed type `int32`.

This is what [`optint`][optint] tries to provide.

**NOTE**: [@CraigFe][craigfe] went further and proposed the `int63` type. The
logic remains more or less the same, for a 32-bit architecture one would use
the boxed type `int64` and for 64-bit architectures one would use the immediate
type `int` (containing 63-bits).

The first draft of the conditional compilation was made _via_ a `select.ml`
script which informs `jbuild` (yeah, `jbuild`...) to select the right
implementation for a given interface.

```ocaml
let invalid_arg fmt = Format.ksprintf (fun s -> invalid_arg s) fmt

let () =
  let is_x64, output =
    try match Sys.argv with
        | [| _; "--x64"; is_x64; "-o"; output; |] ->
           let is_x64 = match is_x64 with
             | "true" | "!true" -> true
             | "false" | "!false" -> false
             | v -> invalid_arg "Invalid argument of x64 option: %s" v in
           is_x64, output
        | _ -> invalid_arg "%s --x64 (true|false) -o <output>" Sys.argv.(0)
    with _ -> invalid_arg "%s --x64 (true|false) -o <output>" Sys.argv.(0) in
  let oc = open_out output in
  let backend =
    if is_x64 then "Int_x64_backend" else "Int_x86_backend" in
  Printf.fprintf oc "include %s\n%!" backend;
  close_out oc
```

```scheme
(jbuild_version 1)

(rule
 ((targets (optint.ml))
  (deps    (select/select.ml))
  (action  (run ${OCAML} ${<}
             --x64 ${ARCH_SIXTYFOUR} -o ${@}))))

(library
 ((name        optint)
  (public_name optint)))
```

In this example, we keep the same interface regardless implementations. By this
(bad) design, we must abstract `Optint.t`. Of course, we can generate an
`optint.mli` depending on the architecture - but we did not take this choice
at this time. This version of `optint` (with the `Optint.t` abstracted) shows
us another point, another disadvantage: the cross-module optimisation
with OCaml.

Because the type is abstract, a library using `optint` cannot really know
structurally whether the type is immediate or not. It is therefore unable to
optimise its use and will box the value _à priori_.

It was not obvious at the outset that the problem with the use of `optint` only
concerned [checkseum][checkseum]. The aim was to produce a C function
`digest_crc32` according to the architecture. One taking a boxed value and the
other taking an immediate value. We then had, all the same, a cheaper FFI
depending on the architecture.

## Optimization & propagation

Now the question is: how do we propagate the information that `Optint.t` is
immediate in the case of a 64-bit architecture and thus let the compiler
properly optimize our use of `Optint.t`?

Something interesting was in OCaml about this:
[Add support for [@@immediate64]][ocaml-immediate64]

The trick is in this code where you can see the use of an `Obj.magic`:
```ocaml
module type Immediate = sig
  type t [@@immediate]
end

module type Non_immediate = sig
  type t
end

type t [@@immediate64]

type 'a repr =
  | Immediate : Immediate.t repr
  | Non_immediate : Non_immediate.t repr

external magic : _ repr -> t repr = "%identity"

let repr =
  if word_size = 64 then
    magic Immediate
  else
    magic Non_immediate
```

Such trick is possible because, on the runtime, `Immediate` and `Non_immediate`
have the same representation (but not the same value), an *immediate* value!
Even if we use an `Obj.magic`, it's a "safe" usage according to what we know
about how OCaml can represent these values.

But the most important part is the GADT. Indeed, `type 'a repr` comes with a
**type information** that can inform us (from the point of view of the type
system) if the type is immediate or not!

Most importantly, it means that we can introspect `Optint.t` and thus propagate
the information to produce better performing code!

```ocaml
module Conditional = struct
  type ('t, 'u, 'v) t =
    | True : ('t, 't, _) t
    | False : ('t, _, 't) t
end

let is_immediate : (Optint.t, int, int32) Conditional.t = match repr with
  | Immediate -> Conditional.True
  | Non_immediate -> Conditional.False
```

This code is completely safe! Even though we know that `'a repr` comes from an
`Obj.magic`, this code is correct for all architectures and therefore allows us
to structurally introspect what `Optint.t` is. We can start propagating this
information.

### `checkseum` and propagation

Back to the original problem, the aim is to have an FFI with a C code that is
as inexpensive as possible. Even if we use an abstract type, OCaml passes the
value back as it should be represented.

```ocaml
external digest_crc32
  : Optint.t -> string -> int -> int -> Optint.t
  = "checkseum_digest_crc32"
```

So, for the C side, we have to do, again, a conditioned compilation that
expects either an immediate value or a boxed value.

```c
#ifdef ARCH_SIXTYFOUR
CAMLprim value
checkseum_digest_crc32(value t, value src, value off, value len)
{
  intnat res = digest_crc32(Int_val (t), String_val (src) + Long_val (off),
                            Long_val (len)) ;
  return (Val_int (res)) ;
}
#else
checkseum_digest_crc32(value t, value src, value off, value len)
{
  uint32_t res = digest_crc32(Int32_val (t), String_val (src) + Long_val (off),
                            Long_val (len)) ;
  return (caml_copy_int32 (res)) ;
}
#endif
```

Again, one can see another disadvantage, since we were not able to introspect
`Optint.t`, we could not tag our externals with `[@noalloc]` - and for sure,
for a 32-bit architecture, there is an allocation (with `caml_copy_int32`).

However, we now have propagation available using our `Conditional.t`. The trick
is to offer 2 implementations in OCaml (one for 64-bits and one for 32-bits)
and to create a module that will result from introspection of 'a Optint.repr'.
On the C side, we can keep the multiple implementations (*tagged*, *boxed*,
*untagged* and *unboxed*):

```c
CAMLprim value
checkseum_digest_crc32_tagged(value t, value src, value off, value len)
{
  intnat res = digest_crc32(Int_val (t), String_val (src) + Long_val (off),
                            Long_val (len));
  return (Val_int (res));
}

intnat
checkseum_digest_crc32_untagged(intnat t, value src, intnat off, intnat len)
{
  intnat res = digest_crc32(t, String_val (src) + off, len);
  return res;
}

CAMLprim value
checkseum_digest_crc32_boxed(value t, value src, value off, value len)
{
  uint32_t res = digest_crc32(Int32_val (t), String_val (src) + Long_val (off),
                             Long_val (len));
  return (caml_copy_int32 (res));
}

uint32_t
checkseum_digest_crc32_unboxed(uint32_t t, value src, intnat off, intnat len)
{
  uint32_t res = digest_crc32(t, String_val (src) + off, len);
  return res;
}
```

```ocaml
module Optint : sig
  type t [@@immediate64]

  val is_immediate : (t, int, int32) Conditional.t
end

module CRC32_64 = struct
  type t = int

  external digest
    : (t[@untagged]) -> string ->
      (int[@untagged]) -> (int[@untagged]) -> (t[@untagged)
    = "checkseum_digest_crc32_tagged" "checkseum_digest_crc32_untagged"
    [@@noalloc]
end

module CRC32_32 = struct
  type t = int32

  external digest
    : (t[@unboxed]) -> string ->
      (int[@untagged]) -> (int[@untagged]) -> (t[@unboxed])
    = "checkseum_digest_crc32_boxed" "checkseum_digest_crc32_unboxed"
    [@@noalloc]
end

module CRC32 = struct
  let impl : (module type S with type t = Optint.t) =
    match Optint.is_immediate with
    | True -> (module CRC32_64 : S with type t = Optint.t)
    | False -> (module CRC32_32 : S with type t = Optint.t)

  include (val impl : S with type t = Optint.t)
end
```

Finally, all the information that can help the compiler generate the cheapest
FFI with C is there:
- `[@untagged]` to directly use an `intnat` rather than `Int_val`/`Val_int`
- `[@unboxed]` to directly debox an `int32` and not use
  `Int32_val`/`Val_int32`/`caml_copy_int32`
- `[@@noalloc]` (which only applies to the C function for native compilation)
  which avoids generating the ceremony for the GC to pass into the C world

So we have a library that can take part of the possible optimizations in
64-bits (and use immediate values instead of boxed ones) while keeping the
support consistent with 32-bits architecture!

Note that the choice of implementation in OCaml is no longer made using a
*meta* tool such as `dune` but directly in OCaml using a GADT to ensure and
reassure the type system!

### Special thanks

I would especially like to thank [@CraigFe][craigfe] for taking the time to
revive this old library by adding the support of `int63` _via_ this trick.

[zlib]: https://zlib.net/
[optint]: https://github.com/mirage/optint
[craigfe]: https://github.com/CraigFe
[checkseum]: https://github.com/mirage/checkseum
[ocaml-immediate64]: https://github.com/ocaml/ocaml/pull/8806
