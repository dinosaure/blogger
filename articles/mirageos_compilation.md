---
date: 2020-02-08
article.title: MirageOS compilation
article.description:
  A little explanation about the MirageOS compilation design
tags:
  - OCaml
  - MirageOS
---

MirageOS is not only one software but many libraries and tools which want to
provide a good *user-experience* about developing a full operating system. By
this way, they want to solve many problems with patterns and designs used by
the core team. However, as I said in my previous article, documentation or
materials don't really exist about these details.

So let's start with one about the compilation of an *unikernel*.

## Abstraction, interface and *functor*

The biggest goal of MirageOS is to provide a set of *interfaces*. Go back to
the OCaml world, we separate two things, the implementation (`.ml`) and the
interface (`.mli`). An implementation can declare lot of things where an
interface wants to restrict access to some underlying
functions/constants/variables.

The interface can *abstract* definition of type where, inside (into the
implementation), the underlying structure is well-known and outside, the
ability to construct the value must be done by described functions into the
`.mli`.

### A simple module with its interface

```ocaml
type t = string

let v x = String.lowercase_ascii x
let compare = String.compare
```

```ocaml
type t

val v : string -> t
val compare : t -> t -> int
```

In your example, our `type t` is a `string`. However. to make a `t`, we must
use `v` which applies `String.lowercase_ascii`. Then, we provide the `compare`
function to be able to make a `Set` or a `Map` of `t`. On that, we can express
a simple idea: 

> a *field-name* is a `string` where the comparison of them is
> case-insensitive, such as `Received` and `received` are equivalent.

Then, for any who wants to use this module, he/she must use `v` to *create* a
field-name and be able to use it with `compare`. Generally, we provide a `pp`
(Pretty-Printer) to debug, and the couple `to_string`/`of_string`.

But the point is to able, by the interface, to restrict the user about what
he/she can do and define about what he/she can rely when he/she uses such
value.

### Trust only on the given interface

MirageOS did the choice to trust only on the interface. For us, a *device*, a
protocol or a server can be well defined by an interface. This is the purpose
of `mirage-types` which provides such things.

The key now is: because for each *artifact* we have, we use them with their
interfaces, how to compose them into on a specific computation?

This is the purpose of MirageOS: a tool to compose implementations (`.ml`)
according expected interfaces (`.mli`) and produce then a operating system (the
specific computation).

## A MirageOS project

Indeed, the global idea of an *unikernel* is: develop the main computation of
your operating system and be able to abstract it over protocols, devices and,
at the end, *targets*.

Let's start to talk about the TCP/IP stack. Usually, on UNIX, we create a
`socket` and we use it to receive and send data. Then, the role of your
operating system is to handle it with your ethernet/wlan card.

We can abstract the idea of the `socket` by this interface:

```ocaml
type t
type error

val recv : t -> bytes -> ([ `Eoi | `Data of int ], error) result
val send : t -> string -> (int, error) result
```

Then, we can trust over this interface to represent the way to send and receive
data over TCP/IP. Of course, at this stage, we don't know details about
implementation - and this is what we want.

```ocaml
module Make (Flow : FLOW) = struct
  let start flow =
    Flow.send flow "Hello World!"
end
```

The abstraction is done. Now, we have our main computation which can be use
with something implements our `socket`. 

And it comes with another tool, `Functoria` to orchestrate, depending on the
target, which implementation will be use to apply the final *functor*. For
UNIX, we will apply the *functor* with `mirage-tcpip.stack-socket` and for
Solo5/Xen, we apply with `mirage-tcpip.stack-direct`.

## *functor* everywhere

*Functorize* the code seems to be a good idea where:
- the cost at the *runtime* is minimal
- abstraction is powerful (we can define new types, constraints, etc.)

## An example

We can show what is really going on about MirageOS about a little example on
the abstraction of the `Console` to be able to write something. Imagine this
*unikernel*:

```ocaml
module type CONSOLE = sig
  type t

  val endline : t -> string -> unit
end

module Make (Console : CONSOLE) = struct
  let start console =
    Console.endline console "Hello World!"
end
```

This *unikernel* expects an implementation of the *Console*. The idea behind
the *Console* is to be able to write something on it. In MirageOS, the
interface should provide something to represent the console (the `type t`) and
what you can do with it (the function `val endline`).

Then, usually, `Functoria` will generate a `main.ml` according the chosen
target and apply our *functor* with the right implementation. But let's talk
about implementations.

### Implementations

We probably should have 2 implementations:
- an UNIX implementation which will use the *syscall* `write`
- a *standalone* implementation which should work on any targets (like Solo5) -
  and it should depend only on the *caml* runtime

```ocaml
type t = Unix.file_descr

let endline fd str =
  let _ = Unix.write_substring fd str 0 (String.length str) in
  let _ = Unix.write_substring fd "\n" 0 1 in
  ()
;;
```

```
type t = out_channel

let endline oc str =
  output_string oc str ;
  output_string oc "\n"
;;
```

### Orchestration

As I said, then, `Functoria` will take the place and will generate a `main.ml`
which will:
- apply `Unikernel.Make`
- call the `start` function with the representation of the *Console*

Concretely, this file appears when you do `mirage configure` where you can
specify the target. So, imagine we want to use the UNIX target (the default
one), `Functoria` will generate:

```
include Unikernel.Make(Console_unix)

let () = start Unix.stdout
```

### Compilation

The compilation can be separated into 2 steps where we compile object files
first and we do the link according the target:

```sh
$ ocamlopt -c unikernel.ml
$ ocamlopt -c console_unix.ml
$ ocamlopt -c main.ml
```

```sh
$ ocamlopt -o main -c unix.cmxa \
  console_unix.cmx unikernel.cmx main.cmx
```

We can see that the most specific command according the target is the link step
where `unix.cmxa` appears. Of course, for another target like Solo5, we will
use `console_caml.ml`. The link step will be a bit complex where we will
produce a `main.o` (with `-output-obj` option). Then, the `mirage` tool will
properly call `ld` with a specific link script according the target.

### Results

Of course, all of this process is done by the `mirage` tool but it's
interesting to understand what is going on when we do the usual:
- `mirage configure`
- `mirage build`

### Implementation according the target

For some others targets - much more specials targets - implementation can
directly use the *syscall* available on the target (like `solo5_console_write`)
with `external`.

```ocaml
external solo5_console_write : string -> unit = "solo5_console_write"

type t = unit

let endline () str =
  solo5_console_write str ;
  solo5_console_write "\n"
;;
```

As you can see, we still continue to follow the interface `CONSOLE` even if the
representation of `t` is `unit` (so, nothing).

## The power of the abstraction

The goal of all of that is to be able to switch easily from an implementation
to another one - like, switch from `socket` given by the Unix module to our own
implementation of the TCP/IP stack.

Finally, the end user can completely discard details about underlying
implementations used for his purpose and he/she can focus only on what he/she
wants - of course, he/she must trust on what he/she uses. But if he/she does
correctly the job, then others users can go further by composition and *hijack*
underlying implementations by something else without any update of the main
computation.

An example of that is to make a website and plug without any headache a TLS
support. It should only be a composition between the TCP/IP flow with TLS to
emit the same abstraction as before:

```ocaml
val with_tls
  :  (module Flow with type t = 'flow)
  -> (module Flow with type t = 'flow * Tls.t)
```

Globally, each piece of your *unikernel* can be replaced by something else
(more fast, more secure, etc.). MirageOS is not a monolithic software at end,
it's a real framework to build your operating system.
