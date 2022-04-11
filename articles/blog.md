---
date: 2020-08-24
article.title: All the way down, my blog is re-up!
article.description:
  How the blog works?
tags:
  - OCaml
  - MirageOS
  - Blog
---

My blog was down for a long time, something like 4 months and this article will
explain why?! As a simple introduction, I started to re-implement
[Conduit][conduit] (see this article about [Tuyau][tuyau]). From this breaking
change, it was needed to update libraries such as [Cohttp][cohttp] or
[Git][ocaml-git] to be able to use this new version needed by my library
[Paf][paf] (which provides an *HTTPS* service from [HTTP/AF][http/af]).

In an other side, I decided to deeply update Git to integrate some others
updates such as [Carton][carton] or
[the last version of Decompress][decompress]. I took the opportunity to fix
some bugs and I finally came with a *new* version of Git.

So the blog was redeployed with the new stack! It uses HTTPS at any points and
SSH to get articles from [my repository][blog.x25519.net]. Finally, update is
substantial and it does not change a lot from the point of view of the user
(before my update, we was able to use HTTP with TLS and SSH) - and this is what
we tried to provide.

But I think it paves the way for a better MirageOS ecosystem. Let's start with
a deep explanation.

## Tuyau / Conduit

For many people, Conduit is a mystery but the goal, with its new version, is
clear: it wants to *de-functorize* your code. Indeed, into the MirageOS
ecosystem, we mostly want to abstract everything. Let's talk about HTTP for
example, an implementation of a HTTP server must need:
- a TCP/IP implementation
- a possible TLS implementation

The problem is not the ability to abstract the TCP/IP implementation,
[mirage-stack][mirage-stack] gives to us such abstraction, but it's mostly
about the *hell-functor*. In first instance, we probably should provide
something like:

```ocaml
module Make_HTTP (TCP : Mirage_stack.V4) (TLS : TLS) = struct

end
```

Now, imagine an other *protocol* such as Git which needs an HTTP
implementation. To keep the ability of the abstraction, we should provide
something like:

```ocaml
module Make_GIT (Hash : HASH) (HTTP : HTTP) = struct

end

module Git = Make_GIT (SHA1) (Make_HTTP (TCP) (TLS))
```

Finally, think about `irmin` which uses Git and expects some others
implementations such as the format of values, an implementation of branches and
an implementation of keys:

```ocaml
module Make_IRMIN
  (Hash : HASH)
  (Key : KEY)
  (Value : VALUE)
  (Git : GIT) = struct

end

module Irmin = Make_IRMIN
  (SHA1) (Key) (Value)
  (Make_GIT (SHA1) (Make_HTTP (TCP) (TLS)))
```

Now, if I tell you that `TCP` is the result of a
[*functor*][mirage-tcpip-functor]... Finally, we have a *functor-hell*
situation and we should not ask to the user to write such code (which can lead
several errors - type incompatibility when you use `SHA256` for irmin` with an
implementation of Git which uses `SHA1` for example).

Though, this situation is already fixed with [Functoria][functoria] which
handles for application of *functors* according to a graph (and depending on
your target).

However, we can not ask to people to use Functoria for any of our projects.
And, I think, this is where Conduit becomes useful. The idea is:

> Instead to *functorize* your implementation with a [Flow][flow], you probably
> want something *at top* (so, something available without *functors*) which is
> able to *communicate* with a peer.

And this is the goal of Conduit. It permits to use `recv`, `send` and `close`
as we expect from an implementation of a *flow*. Then, dynamically and
generally at your first entry-point, you will *inject* such implementation into
Conduit.

For example, HTTP, Git and Irmin can expect only one value, a
`Conduit.resolvers`, which represents *flow* implementation. From this
`Conduit.resolvers`, HTTP, Git and Irmin are able to make a new connection.
Then, the user must fill this value with a TCP implementation of a TCP + TLS
implementation if he/she wants - or with something else.

Finally, `Conduit.{recv,send,close}` **is** your *functor* argument `FLOW`!

### An example into this blog

As you may be know, this blog is self-contained - I store articles and the
unikernel into the same Git repository. If you look into `unikernel.ml`, you
will see how I can fill the `Conduit.resolvers`:

```ocaml
let start stack =
  let resolvers =
    let tcp_resolve ~port =
      DNS.resolv stack ?nameserver:None dns ~port in
    match ssh_cfg with
    | Some ssh_cfg ->
      let ssh_resolve domain_name =
        tcp_resolve ~port:22 domain_name >>= function
        | Some edn -> Lwt.return_some (edn, ssh_cfg)
        | None -> Lwt.return_none in
      Conduit_mirage.empty
      |> Conduit_mirage.add
          ~priority:10 ssh_protocol ssh_resolve
      |> Conduit_mirage.add
           TCP.protocol (tcp_resolve ~port:9418)
    | None ->
      Conduit_mirage.add
        TCP.protocol (tcp_resolve ~port:9418)
        Conduit_mirage.empty in
  Sync.pull ~resolvers store >>= fun () ->
```

In this code, I want to fill the `Conduit.resolvers` with, at least, one
implementation, the `TCP.protocol`. If I'm able to get an SSH configuration
(like the private RSA key), I inject an SSH implementation, `SSH.protocol`, and
give the priority on it.

Nothing will change for Irmin or Git (they don't want to be applied with a
*flow* implementation) but when these implementations will try to start a
connection, they will start a SSH or (if it fails) a TCP connection. So, with
Conduit, we *de-functorized* Irmin and Git!

### The final result

The new version of Conduit does not do a big deal for the end-user. Conduit is
an underlying library used by some others such as Cohttp or Git. Finally, from
a certain perspective, nothing will change for many users.

However, when we want to go to details, the new version of Conduit comes with a
huge feature: the ability to give your configuration value. For a long time,
Conduit initialised values such as the TLS configuration. It did that without
any trust anchor and just accept any TLS certificates. Now, the end-user is
able to pass its own TLS configuration and this is what several people
requested about the next version of Conduit.

This detail does not really appear from the point of view of the Git
implementer or the Irmin implementer who wants only a common way to communicate
with a peer. It's not very useful for people who use ``lwt_ssl`` which, by
default, uses host's trust anchor. But it seems very useful for `ocaml-tls`
which does not have a (file-system dependent) strategy to get trust anchors.
And it is very useful for SSH where the configuration of it depends
specifically on the user (because it's about its own private RSA key).

## New version of Git

This summer, I decided to rewrite `ocaml-git`! More seriously I wrote a big
explanation about the new version of Git [here][pr]. The idea is to take the
opportunity to:
1) Use the new version of Conduit
2) Update to the new version of Decompress (1.0.0)
3) Integrate `carton` as the library to handle PACK files
4) Fix the negotiation engine
5) Fix the support of ``js_of_ocaml``
6) Pave the way to implement shallow commits and a garbage-collector

### Carton

Most of these goals are pretty old. I started to talk about [carton][carton] in
August 2019 (one year before ...) and finalised globally the API
[6 months before][pr-ocaml-git]. The real upgrade is about the internal
organisation of `ocaml-git` where I did well the logic of the PACK file
independently of the Git logic.

In fact, the PACK file does not care too much about format of Git objects and
it's just a format to store 4 kinds of objects. However, the process to extract
or generate a PACK file is a bit complex and the idea was to push outside Git
all of this logic.

By this way, `carton` is a little library which depends only on few
dependencies such as [Duff][duff] (re-implementation of `libXdiff` in OCaml)
and, of course, [Decompress][decompress]. I took the opportunity to use the
last ([faster][decompress-article]) version of this library -
and mechanically improved performances on `ocaml-git`!

This underground split unlocked the ability for me to start to play with
[Caravan][caravan] to be able to *inject* a read-only KV-store into an
unikernel. In fact, a special work was done about what `carton` needs to
extract an object. Finally, we just need `mmap` (extraction) and `append`
(generation) *syscalls* to be able use `carton`. This last improvement wants to
fix a bad underground design into `ocaml-git` where the `Git.Store`
implementation required an `FS` implementation which was too *POSIX-close* -
and unavailable for MirageOS.

Finally, an *append-only* underlying view of a block device compatible with
MirageOS will be enough for `Git.Store` now!

### The new version of Conduit and the new package Not-So-Smart

In my previous article about [Tuyau / Conduit][tuyau], I took Git as a example
of the need to be abstracted about the protocol. So, of course, the article
still is true and I finally did a real application of what I was thinking.

The new API of Conduit unlocked to me the ability to integrate nicely the new
feature requested by Hannes, [the support of SSH][git-ssh]. Of course, Hannes
did not wait me to use his PR. However, from the old version of `ocaml-git` we
duplicated the implementation of the protocol 3 times for each underlying
protocols (TCP, SSH and HTTP). So, I was not very happy with that and the
biggest bottleneck was about the negotiation engine.

Good (or bad) news was that the old negotiation engine [was buggy][git-buggy]!
So it was mostly about [a full-rewrite][not-so-smart] of the Smart protocol and
it's why I created the `nss` (Not-So-Smart) package. [Colombe][colombe] gave me
a good experience about how to properly implement a *simple* protocol with a
*monad* and GADT. So, I retook the design to incorporate it into `ocaml-git`
and re-implement the negotiation engine - I mostly followed what Git does.

This rewrite highlighted to me what the `fetch`/`push` process really needs
about a Git store and I synthesised requirements to:
1) the PACK file
2) a function to get commits and its parents
3) a function to get local references
4) a function to get the commit given by a reference (*de-reference*)

And that's all! In fact, we just need to walk over commits to get the common
ancestor between the client and the server and we just need to process a PACK
file (to save it in the store then).

So, `nss` requires:
```ocaml
type ('uid, 'ref, 'v, 'g, 's) access = {
  get     : 'uid -> ('uid, 'v, 'g) store -> 'v option Lwt.t;
  parents : 'uid -> ('uid, 'v, 'g) store -> 'v list Lwt.t;
  locals  : ('uid, 'v, 'g) store -> 'ref list Lwt.t;
  deref   : ('uid, 'v, 'g) store -> 'ref -> 'uid option Lwt.t;
}
```

`'uid` is specialised to hash used by the Git repository. `'v` depends on what
the process needs. About *fetching* we need a mutable integer used by the
negotiation engine (to mark commits) and the date of the commit (to walk from
the most recent to the older one). Of course, we have a type `store` which
represents our Git store and even `'ref` is abstracted!

From it, you surely can plug an `ocaml-git` store but we can directly use a
simple Git repository and implement these actions with some `execve` of `git`!
Finally, this part of `ocaml-git` is **not** tested with the implementation in
OCaml of the Git store but with `git` directly!

By this way, we can ensure that we talk well with Git! Again, the idea is to
split well underlying logic in `ocaml-git`. It does not change too much for the
end-user but the core (the Git store implementation) is less complex than
before because it does not have anymore the protocol logic.

This rewrite helps me to rework on the negotiation engine and ensure that we
use the same negotiation engine for TCP, SSH and HTTP. By this way, I deleted
duplication of this process - so it's easier to maintain then this part.

### Support of ``js_of_ocaml``

Most of libraries used by `ocaml-git` are in pure OCaml, no C stubs. However,
one of them use C stubs: [encore][encore]. The goal of this library comes from
an old project: [finale][finale]. The idea of such project is to *derive* a
decoder **and** an encoder from one and unique description. By this way, we can
ensure the *isomorphism* between the encoder and the decoder such as:

```ocaml
val desc : my_object Encore.t

let decoder = Encore.to_angstrom desc
let encoder = Encore.to_lavoisier desc

assert (Lavoisier.to_string encoder
  (Angstrom.parse_string decoder str) = str)
```

For the Git purpose, we must ensure that when we extract a Git object, we are
able to re-store it without alteration. Encore ensures that *by construction*.

However:
1) The internal encoder of Encore was too complex
2) It used *functor* which expects the description such as:

```ocaml
module Make (Meta : Encore.META) = struct
  val desc : my_object Meta.t
end

module A = Make (Encore.Angstrom)
module B = Make (Encore.Lavoisier)

assert (Lavoisier.to_string B.desc
  (Angstrom.parse_string A.desc str) = str)
```

*functor* was not the best solution and I decided to use GADT instead to be
able to describe a format. The documentation of Encore was upgraded, so if you
want more details, you can look [here][encore-example].

Then, the internal encoder to be able to *serialise* an OCaml value was too
complex and it used a trick on `bigarray`. It appeared for me that it was not
so good, so I decided to de-complexify the encoder and I provided something
much more easier to maintain and use.

By this way, I deleted C stubs and this was the only dependency of `ocaml-git`
which requires C stubs. So, now, users are free to use `ocaml-git`/Irmin in a
web-browser as [CueKeeper][CueKeeper]!

### Next things about `ocaml-git`

So all these works does not change too much for end-user or Irmin. However,
from what Hannes told me when he tried the new version with its unikernels:
- We are faster (thanks to Decompress)
- We use less memory

It's difficult to really explain why and if these points come from what I did -
we can talk about [the new GC strategy][gc-strategy], Decompress, the new
strategy given by `carton` to process a PACK file, etc. At this level, it's
hard to really understand which layer did the difference (may be all).

But the real upgrade is for me! I was thinking about shallow and garbage
collection on `ocaml-git` for a long time. But, for that, I needed a cleaner
play area where I don't need to figure out about some details such as the
protocol, the PACK format, intrinsic dependence between all of these logic. 

So it's mostly a way to pave my way to implement shallow (partial `git clone`)
and a proper garbage collector between 2 different heaps (minor-heap which
stores *loose* objects and major-heap which stores PACK files). So we will see
if I can finish these tasks :p.

## My Blog, Pasteur, my MirageOS ecosystem

A good way to test and see that all work is to upgrade my blog and some others
services such as [my primary DNS server][dns-primary-git] or
[pasteur][pasteur]. And, as you can see, IT WORKS!

More concretely, due to the renaming of Tuyau into Conduit, I had an
incompatibility between my new version of Conduit and the old one where Git, at
this time, still continued to use the old version. So it was impossible for me
to try to coexist Tuyau and the old version of Conduit where both wanted to use
the same name: Conduit.

I decided to upgraded all the stack at any layers:
- from the `mirage-tcpip` implementation
- to my [HTTP/AF][http/af] server [Paf][paf]
- with `ocaml-tls`
- including the way to synchronise an Irmin store
- over [SSH][awa-ssh]
- including [Cohttp][cohttp]

All of this work is done in one Git repository:

https://github.com/dinosaure/conduit-dev

It's an OPAM repository which includes of slightly modified version of all
packages.

From that, I was able to COMPILE my unikernels and start to really use the
[letsencrypt][letsencrypt] unikernel with my primary DNS unikernel to load TLS
let's encrypt certificates. I took the opportunity to only use SSH and HTTPS
(even if into my private network) too.

And finally, with some bugs, some weird behaviours, some upgrade of APIs and
banishment from let's encrypt because I tried hard to deploy my unikernels,
pasteur is up:

https://paste.x25519.net/

## Conclusion

It's a bit frustrating to see that all of these updates don't change a lot for
the end-user, [patch is not huge][pasteur-patch] finally but I think it was
needed to deeply upgrade the stack. Several peoples started to complain about
Conduit and I started to have some regrets about some decision looking at my
stack.

I think it's about our responsibilities to *lean* the MirageOS ecosystem. Of
course, we can say that we have something else to do which is more interesting
than rewrite an pretty-old project but I don't want to have regrets about what I
did into the MirageOS ecosystem. So, I'm still aware about a global view of
that and I tried to do my best effort to simplify (a bit) the life of
unikernel's fellow (I hope).

Of course, I learned a lot too when I walked across all of these libraries. But
I started to think that we started to have
[our own Babylon tower now][conference]!

Finally, this article convince me to write and explain how to properly deploy
an unikernel. I started to really understand all points. So, next time will be
about the deployment of Pasteur!

[conduit]: https://github.com/mirage/ocaml-conduit/
[tuyau]: ../articles/tuyau.html
[cohttp]: https://github.com/mirage/ocaml-cohttp
[ocaml-git]: https://github.com/mirage/ocaml-git
[paf]: https://github.com/dinosaure/paf-le-chien
[http/af]: https://github.com/inhabitedtype/httpaf
[carton]: https://github.com/dinosaure/carton
[decompress]: https://github.com/mirage/decompress
[blog.x25519.net]: https://github.com/dinosaure/blog.x25519.net
[mirage-stack]: https://github.com/mirage/mirage-stack
[mirage-tcpip-functor]: https://github.com/mirage/mirage-tcpip/blob/master/src/stack-direct/tcpip_stack_direct.mli#L27-L36]
[functoria]: https://github.com/mirage/functoria/
[flow]: https://github.com/mirage/mirage-flow
[pr]: https://github.com/mirage/ocaml-git/pull/395
[pr-ocaml-git]: https://github.com/mirage/ocaml-git/issues/375
[duff]: https://github.com/mirage/duff
[decompress-article]: https://tarides.com/blog/2019-09-13-decompress-experiences-with-ocaml-optimization
[caravan]: https://github.com/dinosaure/caravan
[git-ssh]: https://github.com/mirage/ocaml-git/pull/362
[git-bug]: https://github.com/mirage/ocaml-git/issues/364
[not-so-smart]: https://github.com/dinosaure/not-so-smart
[colombe]: https://github.com/mirage/colombe
[encore]: https://github.com/mirage/encore
[finale]: https://github.com/takahisa/finale
[encore-example]: https://mirage.github.io/encore/encore/Encore/index.html
[CueKeeper]: https://github.com/talex5/cuekeeper
[gc-strategy]: https://www.ocamlpro.com/2020/03/23/ocaml-new-best-fit-garbage-collector/
[dns-primary-git]: https://hannes.nqsb.io/Posts/DnsServer
[pasteur]: https://github.com/dinosaure/pasteur
[awa-ssh]: https://github.com/mirage/awa
[letsencrypt]: https://github.com/roburio/dns-letsencrypt-secondary
[pasteur-patch]: https://github.com/dinosaure/pasteur/pull/5/files#diff-f2ac29fe75a77a0e3bd20224cf8e2bfcR305-R385
[conference]: https://www.youtube.com/watch?v=urG5BjvjW18
