---
date: 2020-02-27
title: Tuyau, the next conduit
description:
  An introduction about `tuyau` which wants to solve the Conduit's problem.  
tags:
  - MirageOS
  - Protocols
  - Libraries
  - Functoria
  - OCaml
---

If you look into the MirageOS ecosystem, you should already see
[conduit][conduit] as a library used by many others projects such as
[cohttp][cohttp]. However, even if it is used by these projects, at this time,
nobody can really explain the goal of Conduit.

Conduit wants to solve 2 problems:
- Start a *transmission* from an URI or, more generally, an *endpoint*
- Be able to compose *protocols*

At this stage, it's mostly a pain to use Conduit for several reasons. But one
of them is the lack of documentation. Conduit still exists because people
copy/paste some piece of codes available in some projects.

However, to understand how Conduit can resolve your URI and give you a way to
communicate to your peer, nobody understands how to extend it, how to trace it
and finally how to use it.

From that, one year ago (at the MirageOS retreat), we decided to make a new
version of Conduit: Tuyau (french word for a *pipe*). Of course, we don't want
to repeat errors of the past. This article want to describe Conduit, and, by
this way, Tuyau.

It can be a good opportunity to see some strange OCaml things!

## Start a *transmission*

In many ways, in some projects, we want to start a *transmission* with a peer.
We would like to communicate with it. However, we don't want to handle by hands
details to start this transmission. We can take an easy example with
[ocaml-git][ocaml-git].

When we want to push/pull to an other peer, we have 4 possibilities:
- Use directly the Smart (Git) protocol over TCP/IP. It appears when you do:
  `git clone git://host/repo`
- Use the Smart (Git) protocol over SSH. It's the usual case when you do:
  `git clone git@host:repo`
- Use the Smart (Git) protocol over HTTP. It's when you do:
  `git clone http://host/repo`
- And final case is over HTTP + TLS or, in other words, HTTPS:
  `git clone https://host/repo`

For all of these cases, we use systematically the same Smart protocol to
communicate with a peer<sup>[1](#fn1)</sup>. So we should abstract all of these cases
behind something like a common interface.

Another aspect is from the point of view of the maintainer of Git:
- we don't want to depend on all of these protocols
- it's sane to not be aware about underlying implementation

The first point is really important. Git is only about Git and we should not
depend on a specific implementation of HTTP or a specific implementation of
SSH. The current version of Git did the choice to use Curl to be able to
communicate with the HTTP protocol. We should be able to be abstracted from
that in OCaml and let the user to choose which implementation of HTTP he/she
wants.

The best is to start a transmission and let the user, at another layer, to
*feed* something which aggregate implementation of protocols. By this way, we
can let the user to *feed* Tuyau *only* with an SSH implementation and, by this
way, ensure that Git will start a *transmission* only with SSH.

The second point is not really valid when we can argue some security points. As
a maintainer, we would be able to enforce a transmission over TLS for example.
But we will see later how we can solve that into Tuyau.

Finally, we want something like:

```ocaml
val resolve : Tuyau.t -> uri -> Unix.socket
```

Where `Unix.socket` is already connected to our peer. Then, we can start to
`Unix.read` and `Unix.write` on the given socket and speak with the Smart
protocol to our peer.

`Tuyau.t` represents globally our possibilities (our available protocols). At
least, the user should depend on that - but it does not imply a dependence to
implementation of available protocols.

<tag id="fn1">**1**</tag>: It's not really true when a transmission over HTTP
must be *stateless*. Smart over SSH differs too when it must expect a
END-OF-LINE (`'\n'`) at the end of each *packet* - this character is optional
over TCP/IP.

## A transmission, a protocol or a flow

The first bad point of Conduit is terms used by it which are not really
defined. A transmission, a protocol or a flow are not very clear and we can not
strictly define the purpose of them with Conduit.

Tuyau wants to be clear on these words and it gives to us a true definition of
them. Then, we will use them as Tuyau defines them.

### A Protocol
    
A communication protocol is a system of rules that allows entities to transmit
information. In the case of Tuyau, this kind of information must not be
arbitrary. The protocol should only solve communication problems such as
*routing*.

When we talk about a protocol, it's only about a standard which is able to
transmit a *payload*. Interpretation of the *payload* is not done by the
*protocol* but by the user of this library.

For example, the Transmission Control Protocol (TCP) *is* a protocol according
to Tuyau because it is able to transmit *payload* without interpreting it. A
counter example is the Simple Mail Transfer Protocol (SMTP) which gives an
interpretation of the *payload* (such as `EHLO` which is different to `QUIT`).

This difference is important to unlock the ability to compose *protocols*. An
other protocol according to Tuyau is Transport Layer Security (TLS) - which
wants to solve privacy and data integrity. Tuyau is able to compose protocols
together like TCP ∘ TLS to make a new protocol. From this composition, the user
is able to implement Secure Simple Mail Transfer Protocol (SSMTP) or HyperText
Transfer Protocol Secure (HTTPS) - both use TCP and TLS.

### A `FLOW`

To be able to do this composition, the protocol must respect (at least) an
interface: the `FLOW` interface. It defines an abstract `type t` and functions
like `recv` or `send`. These functions give to us the *payload*. Rules to solve
communication problems are already processed internally.

In other terms, from a given `FLOW`, the user should not handle *routing*,
privacy or data integrity (or some others problems). The user should only be
able to process the *payload*.

Finally, representation of a TCP protocol is a `FLOW`. VCHAN protocol or User
Datagram Protocol (UDP) can be represented as a `FLOW`. However, TLS is not a
flow as is but *a layer* on top of another protocol/`FLOW`. Composition with it
should look like:

```ocaml
val with_tls : (module FLOW) -> (module FLOW)
```

From a given `FLOW`, we *wrap* it with TLS and return a new `FLOW`. Such a
composition exists also for [WireGuard][WireGuard] or [Noise][Noise] layers.
Tuyau wants to solve this composition by a strict OCaml interface of the
`FLOW`.

### About Conduit

These ideas already exist with `Conduit_mirage.Flow` and
`Conduit_mirage.with_tls`. However, it appears 2 problems:
- extension of implementations
- composition with user-defined `FLOW`

Currently, Conduit delimits implementations by a polymorphic variant
`Conduit.{client,server}`. We should not blame that when
[extensible variants][extensible-variants] appears only on OCaml 4.02.

## Abstract! Abstract everything!

As we said, the most important idea is to be able to:
1) abstract the *flow*
2) still be able to use it to receive and send *payload*

In your first example, we return an `Unix.socket` which is obviously not good,
especially if we want to make an *unikernel* (which can not usually have
anythings from the `Unix` module). In this way, we already did an interface to
be able to easily abstract our implementations: [mirage-flow][mirage-flow].

We say that any protocols like TCP or VCHAN can be described with this
interface where we have the `recv` function and the `send` function. So,
instead to return a concrete type, we return an abstract type like:

```ocaml
module type FLOW = sig
  type t

  val recv : t -> bytes -> int
  val send : t -> string -> unit
end

type flow = Flow : 'flow * (module FLOW with type t = 'flow) -> flow
val resolve : Tuyau.t -> uri -> flow

let () =
  let Flow (flow, (module Flow)) =
    resolve tuyau "https://google.fr/" in
  Flow.send flow "Hello World!"
```

In our example, we use a GADT to keep the type equality between our value
`'flow` and the `type t` of our module `Flow`. We usually call it an
*existential type wrapper*. It allows us to *create* a new type `'flow` and
associate it to an implementation `Flow`.

The idea behind is: the `type t` can concretely be anything. It can be an
`Unix.socket` if we want to make an *unikernel* for Unix but it can be
something else like a `Tcpip_stack_direct.t` (the TCP/IP implementation usually
used by MirageOS).

With the associated module, we still continue to be able to read and write
something as we can do with an `Unix.socket`.

And of course, we can forget about details. You can denote that we already
prepare the concrete value to be able to communicate with our peer. I mean,
`resolve` do something more complex than just create a new resource such as an
`Unix.socket`. It connects the socket to our peer. It's why we talk about
a *resolution* process.

## Resolution

Tuyau can not define by itself the resolution. Resolution is commonly a DNS
resolution to get the IP from a *domain-name*. However, into an *unikernel*,
nothing ensures that we properly have a DNS resolver (such as our
`/etc/resolv.conf`).

In other side, definition of an *endpoint* can not fully exist where it depends
on the returned `'flow`. For example, if we give to you a TCP/IP `Flow`, used
*endpoint* to connect your `'flow` should be an IP and a *port*. However, the
*endpoint* can represent something else like a *serial-port* connected to our
MirageOS or a virtual network kernel interface (TUN/TAP), etc. Finally,
definition of an *endpoint* is *intrinsic* to our implementation of the `Flow`.

Concretely, for an `Unix.socket` flow, we need an `Unix.sockaddr`. For a
`Tcpip_stack_direct.t` flow, we need an `Ipaddr.V4.t` and an `int` as a *port*.

At the end, we agree that the most general (by convention) description of the
*endpoint* is the *domain-name*. By knowing that, we decided to let the user to
construct an *endpoint* from a concrete ``[`host] Domain_name.t`` (as Conduit
decided to construct an `Conduit.endp` from an `Uri.t`).

### How Conduit does that?!

Conduit do the same job where it wants to construct an *endpoint*
(`Conduit.endp`) from an `Uri.t`. To choose which implementation we will use,
it looks at the *scheme* of the `Uri.t`.

From our perspectives, this is not a good choice where the *scheme* is not a
real definition of the underlying protocol used as it's explained into the
[RFC7595][RFC7595]:

> A scheme name is not a "protocol."

However, even if `Conduit.endp` should be extensible as
`Conduit.{client,server}` (because they are *intrinsic* each other), they still
are delimited by an exhaustive list of constructors:

```ocaml
type endp =
  [ `TCP of Ipaddr.t * int
  | `Unix_domain_socket of string
  | `Vchan_direct of int * string
  | `Vchan_domain_socket of string * string
  | `TLS of string * endp ]

type client = [ tcp_client | vchan_client | client tls_client ] 
```

### Abstract, again!

Tuyau comes with an [*heterogeneous* map][hmap] to be able to let the user to
define a `resolve` function which is able to return any (structurally
different) *endpoint*. The user must create a *type witness* which corresponds
to a value `'t Tuyau.key` and represents type of the *endpoint*.

With that, the user can *register* a `resolve` function which returns the same
type as your `'t Tuyau.key`. In others words, we are able to provide:

```ocaml
type resolvers
type 't key

val key : name:string -> 't key
val register
  :  key:'t key
  -> ([ `host ] Domain_name.t -> 't)
  -> resolvers
  -> resolvers
```

By this way, the user is able to implement the resolution process and can use a
DNS resolver or a fixed resolution table (like an `Hashtbl.t`). Tuyau needs to
know who can create a concrete *endpoint* from a ``[ `host ] Domain_name.t`` to
pass it to a protocol implementation. It's why you need to register your
`resolve` function into our `resolvers`.

Finally, Tuyau will execute all of your *resolvers* and create a list of
heterogeneous *endpoints*. Then, from them, it is able to try to start a
transmission to your peer.

#### Give me the priority

Of course, `resolver` can be registered with a priority. By that, not only will
we use your priority resolver, but we will also prioritize initialization of
your associated protocol.

The idea is to let the user to prioritize secure transmission over *unsecure*
transmission even if both are available (like `https` and `http`).

## Tuyau by an example

Tuyau (and Conduit) wants to solve a difficult task which does not appear into
usual cases. If you want to make an UNIX program, all of that is useless
because we can directly use the UNIX environment.

However, for MirageOS where nothing exists (even a DNS resolver), we need a way
to start a transmission according to the context of the compilation. In fact,
the TCP/IP implementation depends on the target, the configuration of your
*unikernel*, what the user wants, etc.

We will see a little example to fully understand the underlying Tuyau stack.
What you should do as the maintainer of Git, as the developer of the protocol
or basically as the user of Tuyau.

### Register your protocol with Tuyau

To play with protocols, we must *register* our protocol to Tuyau. The
registration is global to your program. Indeed, Tuyau is able to extract your
implementation from anywhere - internally, we save it into a global
`Hashtbl.t`.

Let's start to provide an UNIX TCP/IP protocol and register it into Tuyau!

```ocaml
module TCP = struct
  type flow = Unix.file_descr
  type endpoint = Unix.sockaddr

  let make sockaddr =
    let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM in
    Unix.connect socket sockaddr ; socket

  let recv socket buf off len =
    Unix.read socket buf off len

  let send socket buf =
    let len = String.length buf in
    let _ = Unix.write socket (Bytes.unsafe_of_string buf) 0 len
    in ()

  let close socket = Unix.close socket
end
```

We must provide these functions into our module and 2 types:
- the `flow` type
- the `endpoint` type

From that, Tuyau (a specialized version according to your *backend*) provides
a way to *register* your protocol globally. We must create our *type witness*
about our *endpoint* and associate it with your protocol:

```ocaml
let sockaddr : Unix.sockadr Tuyau.key = Tuyau.key ~name:"sockaddr"
let tcp : Unix.file_descr Tuyau.protocol =
  Tuyau.register_protocol ~key:sockaddr (module TCP)
```

And it's enough! You probably should expose `sockaddr` and `tcp`. We will see
where we can use it. But the registration is done into our internal & global
`Hashtbl.t`. Any **link** with this piece of code will make your protocol
available through Tuyau.

### Register your resolver with Tuyau

Into another project/library/executable/unikernel, you are able to define your
resolution process. Of course, you must link with `unix_tcp` to be able to use
`Unix_tcp.sockaddr` and register your *resolver* with this *type-witness* - and
it's why you should expose it into your interface.

Let's use an usual resolver:

```ocaml
let resolve_http domain_name =
  match Unix.gethostbyname (Domain_name.to_string domain_name) with
  | { Unix.h_addr_list; _ } ->
    if Array.length h_addr_list > 0
    then Some (Unix.ADDR_INET (h_addr_list.(0), 80))
    else None
  | exception _ -> None
```

This *resolver* wants to usually resolve a domain-name to an HTTP
endpoint<sup>[2](#fn2)</sup>. Of course, you can use something else like
[ocaml-dns](ocaml-dns) instead `Unix.gethostbyname` to be compatible with
MirageOS.

Then, we must fill `Tuyau.resolvers` with our `resolve_http`:

```ocaml
let resolvers = Tuyau.empty
let resolvers =
  Tuyau.register_resolver ~key:Unix_tcp.sockaddr resolve_http
```

You can not do a mistake between `Unix_tcp.sockaddr` and `resolve_http`.
*type-witness* and returned value by `resolve_http` must correspond -
otherwise, OCaml will complain with a type error which is nice!

<tag id="fn2">**2**</tag>: by *HTTP endpoint*, we enforce the port `80`. Our
UNIX TCP/IP flow is not an HTTP flow. However, an HTTP client must be connected
to the port `80` the TCP/IP protocol.

### Come back to Git!

From the maintainer of Git's perspective, all of previous codes is outside Git.
As we said, we don't want to depend on an implementation of TCP/IP protocol (or
a SSH implementation). However, we should depend on Tuyau.

Finally, the Tuyau core library defines only few things, the `resolvers` type
and the `'a key` type. By this way, in our library we can write something like:

```ocaml
let clone ~resolvers domain_name repository =
  let payload = Bytes.create 0x1000 in
  let Tuyau_unix.Flow (flow, (module Flow)) =
    Tuyau_unix.resolve ~resolvers domain_name in
  Flow.send flow (Fmt.strf "# git-upload-pack /%s.git" repository ;
  Flow.recv flow payload ;
  ... 
```

Of course, we must choose a *backend* like LWT, ASYNC or UNIX to correctly deal
with the scheduler about I/O operations. But for a MirageOS-compatible library,
`Tuyau_lwt` should be enough.

### And run all of that!

Come back to our `main.ml` where we filled your `resolvers`, we properly can
do:

```ocaml
let resolve_http domain_name =
  match Unix.gethostbyname (Domain_name.to_string domain_name) with
  | { Unix.h_addr_list; _ } ->
    if Array.length h_addr_list > 0
    then Some (Unix.ADDR_INET (h_addr_list.(0), 80))
    else None
  | exception _ -> None

let resolvers = Tuyau.empty
let resolvers =
  Tuyau.register_resolver ~key:Unix_tcp.sockaddr resolve_http

let () =
  clone ~resolvers
    (Domain_name.(host_exn <.> of_string_exn) "github.com")
    "decompress"
```

Finally, we manually defined our `resolvers` by hands, we used a specific
implementation of the TCP/IP protocol (the UNIX one) and we
magically/dynamically plug all of that to your Git implementation through
Tuyau.

### Go further with composition!

Of course, we can go further and provide a TCP + TLS implementation:

```ocaml
let sockaddr_and_tls_config, tcp_with_tls =
  Tuyau_tls.with_tls ~key:sockaddr (module TCP)
```

The composition gives to us 2 values:
- the *type-witness* `sockaddr_and_tls_config : Unix.sockaddr * Tls.Config.client`.
  In fact, creation of a TCP + TLS connection is a bit more complex than TCP.
  We need a ~Tls.Config.client~ which verify certificate provided by the peer.
- the *type-witness* `tcp_with_tls : Unix.file_descr with_tls`.

From that, we must provide an other resolver which give to us the
`Tls.Config.client`:

```ocaml
let resolve_https domain_name =
  match resolve_http domain_name with
  | Some sockaddr ->
    let tls_config =
      Tls.Config.client ~authenticator:X509.Authenticator.null () in
    Some (sockaddr, tls_config)
  | None -> None

let resolvers =
  Tuyau.register_resolver ~priority:0 ~key:sockaddr_and_tls_config
    resolve_https
    resolvers
```

With the priority, we can enforce to try at the first time the TCP + TLS
transmission instead the TCP transmission - and by this way, prefer to use the
secure one.

Again, this code still appears outside the Git implementation. We are able to
fill Tuyau with a SSH implementation and fill the `resolvers` with a specific
SSH configuration (like a set of private key like `.ssh/config`).

In our example, we use `X509.Authenticator.null` but we can restrict the
`authenticator` to some internals certificates. Again, the way to resolve a
domain-name is on the responsibility of the user.

#### Composition is not magic!

Composition with TLS or something else is not magic. It seems easy when we
provide `with_tls` but we **wrote** the way to compose TLS with an other
protocol - where we handled *handshake*, etc.

The composition is, at the end, a *functor* which takes a `FLOW`:

```ocaml
module With_tls (Flow : FLOW) = struct
  type endpoint = Flow.endpoint * Tls.Config.client
  type flow = Flow.endpoint * Tls.Engine.state

  ...
end
```

We just hidden it with a nice function and play a bit with
[first-class modules][first-class-module].

### More possibilities on the user-side

One other request about `Tuyau` is to be predictable by the kind of flow used.
Some maintainers want to enforce a secure flow such as SSH. In this case, of
course, the maintainer should be aware about the implementation - and link with
it.

The `resolve` function is much more complex than before on this way:

```ocaml
val resolver
  :  resolvers
  -> ?key:'edn key
  -> ?protocol:'flow protocol
  -> [ `host ] Domain_name.t -> flow
```

Optional arguments let the user to enforce a specific
*endpoint*<sup>[3](#fn3)</sup> or a protocol (or both). When we advised to
expose `val tcp : Unix.file_descr Tuyau.protocol` before, it's for this case.
Imagine an SSH implementation where a ~val ssh : SSH.t Tuyau.protocol~ exists,
the maintainer can write:

```ocaml
let clone ~resolvers domain_name repository =
  let payload = Bytes.create 0x1000 in
  let Tuyau_unix.Flow (flow, (module Flow)) =
    Tuyau_unix.resolve ~resolvers ~protocol:ssh domain_name in
  Flow.send flow (Fmt.strf "# git-upload-pack /%s.git" repository ;
  Flow.recv flow payload ;
  ... 
```

By this way, we ensure to use SSH when we communicate to our peer.

<tag id="fn3">**3**</sup>: A *type-witness* `key` can be used and re-used with
many protocols. We can imagine a TCP/IP protocol and a UDP/IP protocol which
use the same sockaddr` *type-witness*.

## Conclusion

As we said, Tuyau and Conduit a complex problem when we should have an easy way
to start a *transmission* and be able to extend protocol implementations
without a static dependency at the library level.

Composition is done by the possibility to give a nice interface such as
`with_tls` with Tuyau. But, of course, it's not magic when maintainer of
TLS/WireGuard/Noise should provide a way to compose such layers with a given
`FLOW`.

Finally, it's hard to really understand the goal of Tuyau when, from the
library, it's hard to reach the global view over protocols, users and finally
the ecosystem. This article wants to give materials about that.

### Server-side

Tuyau provides something about the server-side which differs a lot from what
Conduit does but we should explain that into an other article.

[conduit]: https://github.com/mirage/ocaml-conduit.git
[cohttp]: https://github.com/mirage/ocaml-cohttp.git
[ocaml-git]: https://github.com/mirage/ocaml-git.git
[WireGuard]: https://en.wikipedia.org/wiki/WireGuard
[Noise]: http://www.noiseprotocol.org/
[extensible-variants]: https://caml.inria.fr/pub/docs/manual-ocaml/extensiblevariants.html
[mirage-flow]: https://github.com/mirage/mirage-flow
[RFC7595]: https://tools.ietf.org/html/rfc7595#section-3.8
[hmap]: https://github.com/dbuenzli/hmap
[ocaml-dns]: https://github.com/mirage/ocaml-dns
[first-class-module]: https://caml.inria.fr/pub/docs/manual-ocaml/firstclassmodules.html#s%3Afirst-class-modules
