---
date: 2022-04-11
title: Again, re-update of my blog after 2 years.
description:
  A setting in abyme about this blog!
tags:
  - OCaml
  - MirageOS
  - Blog
---

It's been 2 years since my blog has been updated. The first reason is that I
had a lot of work to do on [MirageOS 4][mirageos]. The second reason is a
simple question: how to deploy several sites with one IP address? The third is
to use ONLY OCaml.

Behind these innocent questions and staking out between futile and necessary
projects, I took the time to finally finish the deployment of my blog getting
closer and closer to what I wanted to do in terms of deployments.

## Generate everything _via_ OCaml

This was my first problem with my old blog. The workflow required emacs and
produced HTML from [Org][org] files. I still like the organization possible
with Org files, but depending on a workflow that I don't control was a problem.
I tried to find alternatives knowing that there were some researchers who had
fun manipulating Org files in OCaml but this reality belongs to a distant
memory that was finally irrelevant in view of the evolution of the OCaml
ecosystem.

In the end, and only recently, several people set out to make a sort of
"haskelian" toolkit *from hell* in order to offer a blog engine whose
production is described in OCaml. The name of these libraries are:
- [Preface][preface]
- [YOCaml][yocaml]

The idea of being able to describe an engine with the help of a
[free monad][free-monad] to which we can associate a "runtime" that will decide
how to produce the blog was very appealing. Especially because the idea fits
well with MirageOS where we want to separate the tasks.

My initial idea was to generate the blog with
[ocaml-git][ocaml-git]/[Irmin][irmin] in order to push the production into a
Git repository and then add [unipi][unipi] as a simple HTTP server to serve
what is ultimately a static website. 

So, for the same code, I have as much the possibility to test and view my blog
locally as to decide to push the result on a Git repository. The only
difference is in the runtime chosen:

```ocaml
val my_blog : unit Yocaml.Effect.t

let local_build target =
  Yocaml_unix.execute my_blog

let build_and_push target =
  let module Store = Irmin_unix.Git.FS.KV (Irmin.Contents.String) in
  let module Sync = Irmin.Sync.Make (Store) in
  Store.remote ~ctx remote >>= fun remote ->
  Store.Repo.v config >>= fun repository ->
  Store.of_branch repository branch >>= fun active_branch ->
  Sync.pull active_branch upstream `Set >>= fun _ ->

  Yocaml_irmin.execute (module Yocaml_unix)
    (module Store)
    ~author ~author_email
    ~branch
    repository
    my_blog >>= fun () ->

  Sync.push active_branch upstream
```

The real advantage is that `my_blog` is used by 2 different runtimes without a
*functor*!

Of course, YOCaml goes further. It offers support for [markdown][markdown],
[yaml][yaml] as well as [jingoo][jingoo] (there is also [mustache][mustache]).
I confess that this part doesn't interest me too much and we could have some
criticisms from the point of view of a release manager (or OCaml purist - where
is [TyXML][tyxml]?) but the most important is that the blog works and it's
especially this ease of extension to YOCaml that is really interesting.

I mostly took what [xhtmlboi][xhtmlboi] mainly did and made some (minor)
changes to the design and really wanted to go further about `yocaml_irmin` - so
I proposed [some][patch01] [patches][patch02].

## Conduit, tuyau, CoHTTP, http/af and paf...

This story is less famous than the first one. Indeed, it is first of all part
of a disagreement concerning the evolution of Conduit. As you may know, I spent
too much time on the evolution of Conduit, keeping in mind a certain
retro-compatibility that made me lose a lot of patience.

But let's go back to the basic problem: in the context of MirageOS, we need to
be able to inject implementations at other "higher" levels. For example, we
need to be able to inject **a** TLS implementation into what an HTTP
implementation uses. This is the basic example, but the same applies to a
TCP/IP implementation.

This kind of injection is normally done by *functor*. We have an implementation
that waits for another implementation that respects a certain interface. Then,
`functoria` helps us in the application of these *functors* according to what
we want to produce.

#### The usual MirageOS design

So we are talking about interfaces describing what implementations require.
Beyond the problem of using *functors* too much, MirageOS has a very particular
but pragmatic design when it comes to interfaces and implementations. An
interface should never describe how to allocate/create the resource `type t`. A
resource like a "socket" or a "block device" or something which represents the
POSIX clock is, all the time, abstract. At the HTTP level (and this is already
the case), we don't need to know structurally how a socket is defined. We just
need actions like `read` or `write` to manipulate this abstraction - this is
actually a fairly common design in OCaml:

```ocaml
module type SOCKET = sig
  type t

  val read : t -> bytes -> int -> int -> int
  val write : t -> string -> int -> int -> int
end
```

However, how do you get a value of `type t`? Usually, in a MirageOS project, an
implementation implements an interface plus a `connect` function. Then,
`functoria` allows to call this `connect` function to allocate the resource.
The problem is that this connect function is implementation-dependent! Indeed,
`lwt_ssl` and `ocaml-tls` should offer the same interface, `read` and `write`
with TLS. However, one handles a `socket` and an `Ssl.context`, the other a
`Mirage_flow.S` and a `Tls.Config.client`. Their `connect` is fundamentally
different (in terms of what they require).


That's why the `connect` is never described in the interface, an implementation
only provides that interface plus a `connect` intrinsic to what it wishes to
implement:

```ocaml
module Lwt_ssl = sig
  include SOCKET

  val connect : Lwt_unix.socket -> Ssl.context -> t
end

module OCaml_TLS = sig
  include SOCKET

  val connect : Mirage_flow.t -> Tls.Config.client -> t
end
```

So how to allocate/initiate a TLS connection with MirageOS. Functoria will
simply, according to the arguments, emit a sequence of `connect` (into the
`main.ml`) with what they require and pass the allocated values to the
`Unikernel.start` function. These will be taken and there is no way to know
structurally how they were allocated. For resources needed by the unikernel
from the start, this is not a problem. But in the context where we need one of
these resources only on a specific execution path, we would not be able to
allocate them (since we don't know how to `connect` them).

This is the specific problem that Conduit wants to solve: allocate a
resource/socket to initiate a client HTTP connection according to a particular
condition:

```ocaml
module Make (Flow : Mirage_flow.t) =
  val do_some_stuffs : Flow.t -> unit Lwt.t

  let start stdin = match input_line stdin with
    | "google.com" ->
      Flow.connect "8.8.8.8" >>= fun socket -> do_some_stuffs flow
    | "localhost" ->
      Flow.connect "127.0.0.1" >>= fun socket -> do_some_stuffs flow
end
```

We can see the problem here:
1) `Flow.connect` is not really provided by `Mirage_flow.S`, the code can not
   compile
2) `Flow.connect` expects a `string` but what happen when we want to pass a
   specific `Tls.Config.client`, or an `Ipaddr.t` or something else?
3) this code shows what I mean about "initiate a connection according to a
   particular condition" or a "specific execution path". The `connect` depends
   on an **user input**

### Mimic

That's why I decided to make [Mimic][mimic]. This project is just an improved
version of [Conduit 3.0.0][conduit-3.0.0] with good documentation and an
[example][mimic-tutorial]. It provides the `Mirage_flow.S` that we expect for
any type of connection (TLS, SSH, TCP/IP, etc.) and especially the
`Mimic.resolve` function that corresponds to our `connect`.

The latter requires a context that you can manipulate directly. This context
can contain values of any type. It's a [heterogeneous map][hmap], quite simply.
The key is that a ceremony that Functoria can do is needed to *register* these
protocols (again, TLS, SSH, TCP/IP, etc.). These protocols can be initiated if,
in the given context, there are the necessary values to allocate the said
resource (`Tls.Config.client`, `Awa.private_key`, `Ipaddr.t`, etc.). If Mimic
can resolve the link between these values and what the protocols expect, it
tries to initiate these connections:

```ocaml
module Make (...) = struct
  val do_some_stuffs : Mimic.flow -> unit Lwt.t

  let start stdin = match input_line stdin with
    | "google.com" ->
      let ctx = Mimic.add mimic_ipaddr
        (Ipaddr.of_string_exn "8.8.8.8") Mimic.empty in
      Mimic.resolve ~ctx >>= fun flow -> do_some_stuffs flow
    | "localhost" ->
      let ctx = Mimic.add mimic_ipaddr
        Ipaddr.localhost Mimic.empty in
      Mimic.resolve ~ctx >>= fun flow -> do_some_stuffs flow
end
```

### What is wrong with Conduit?

The first problem with Conduit is that it wants to solve the issue of
instantiating a connection for client **AND** server use. The second issue, as
Hannes points out, is that we wouldn't want an abstraction for the server side.
We would like to be fully aware of what implementation we are using to initiate
a server. In this, Conduit is irrelevant.

The second problem is the extension of protocols handled by Conduit. This
extension is strict (if we want to extend the possibilities, we have to
re-release Conduit) and we had a lot of trouble integrating SSH into
[`ocaml-git`][ocaml-git].

Finally, the last problem is maintainability. Conduit is an old software and
nobody really understands what's going on (not even me). As such, it is bound
to die one way or another. Again, this criticism is factual and can be
explained by the date of creation of Conduit where the features used by Mimic
were not available at that time.

Finally, the non-agreement to move to Conduit 3.0.0 led me to really integrate
my solution outside of CoHTTP (the only Conduit user). And finally, I decided
to make another CoHTTP from [http/af][http/af] that is compatible with MirageOS
and therefore uses Mimic. The performance is good and so are the abstractions.
This allowed me to go a little bit further and to handle version 2 of the HTTP
protocol as well (and ALPN negotiation). Finally, this work ended up being
integrated in [unipi][unipi-paf] (so in this blog) which earned me 2 years of
work! But the result is perfect - even the mirage.io website uses
Mimic/[Paf][paf] as I went further and offered MirageOS support to
[Dream][dream] through these libraries.

## Contruno, the TLS termination proxy

Finally, one question remained for me. How do you deploy multiple websites on a
single IP address? The basic solution is to use `nginx`, let it take care of
the TLS certificates and forward the connections to my unikernels. But I wanted
everything to be unikernels! So I made a unikernel called [contruno][contruno]
which is a TLS termination proxy.

It plays the same role. It manages the TLS certificates of several domain names
and forwards the connections to a specific destination within my network:

```ocaml
                                     .- 10.0.0.1:80 [ blog.osau.re ]
[ Internet ] -> *:443 [ Contruno ] -|
                            |        `- 10.0.0.2:80 [ paste.osau.re ]
                            |
                   [ Git repository ]
```

The problem with TLS certificates with MirageOS is long-standing. Hannes made
the choice to use the primary DNS server to manage the Let's encrypt challenges
and to keep the certificates in another unikernel
[dns-letsencrypt-secondary][dns-letsencrypt-secondary]. This way, a unikernel
can request a TLS certificate from the latter and even if it goes down, the
`dns-letsencrypt-secondary` keeps the requested certificates. This avoids
reaching the Let's encrypt's request limit quite quickly when debugging.

On my side I preferred to do the challenges with HTTP. Contruno is therefore a
simple HTTP server that can do Let's encrypt challenges. Finally, it saves the
certificates in a Git repository. If it goes down, it can retrieve the
certificates again - they are not lost! Finally, it is an HTTPS server that
will simply look at the host and redirect the connection to the correct IP
address.

In this way, when you connect to my blog, you go through 2 unikernels! They are
still a test period but for now, they work quite well.

## Some _futile_ projects

### Conan

Of course, I was involved in a lot of other projects that allowed me to go
further in the deployment. The first of these remains experimental but
interesting. As an HTTP server, one must, sometimes, give the MIME type of the
static files available. For a long time, this information was available through
the extensions of the said files. However, this information can be erroneous.
So I made [Conan][conan] which is a reimplementation of `file` in OCaml. It
will read the contents of the file and try to recognize the MIME type. You can
get a detailed explanation [here][conan-discuss].

### Git

Git has evolved a lot too. Indeed, one of Hannes' expectations was to be able
to compose the protocols available to initiate a connection with a Git
repository. Of course, thanks to Mimic, this was possible and I found the
common core of what is the Smart protocol with TCP/IP, SSH, HTTP and HTTPS.
This means less maintenance work for me since I only have one implementation of
the Smart protocol that works for all these protocols! The first draft was a
duplicate of the Smart implementation with some details for SSH and HTTP.
The second draft was a duplicate between TCP/IP or SSH and HTTP. The last one
proposes a single implementation of Smart independently of TCP/IP, SSH or HTTP
(or any protocol!)

### The MirageOS ecosystem

Finally, I've been working with Hannes on several releases to clean up our
ecosystem and provide a better MirageOS experience! Of course, there is also
MirageOS 4 but that will be explained in another article.

## How to deploy?!

Deploying unikernels requires a bare-metal server with KVM and a bridge on
10.0.0.1 (a private network). We will use a Debian 10:

```sh
$ cat /etc/network/interface
auto br0
iface br0 inet static
  address 10.0.0.1
  netmask 255.255.255.0
  broadcast 10.0.0.255
  bridge_ports none
  bridge_stp off
  bridge_fd 0
  bridge_maxwait 0
$ ls /dev/kvm
crw-rw---- 1 root kvm 10, 232 Apr 11 20:03 /dev/kvm
```

### Albatross

To help us to deploy our unikernels, we will use [albatross][albatross] which
provides a simple daemon which create TAP interfaces and launch unikernels
with Solo5:

```sh
$ git clone https://github.com/roburio/albatross
$ cd albatross
$ opam pin add -y .
$ dune subst
$ dune build
$ ./packaging/debian/create_package.sh
$ sudo dpkg -i albatross.deb
$ sudo systemctl enable albatross_daemon.service
```

### Git repository

We need to create 2 private Git repositories:
1) A git repository which contains our website
2) A git repository which contains TLS certificates from Let's encrypt

```sh
$ su git
$ cd
$ mkdir blog.osau.re.git
$ cd blog.osau.re.git
$ git init --bare
$ git read-tree --empty
$ FIRST_COMMIT=`git commit-tree $(git write-tree) -m .`
$ git update-ref "refs/heads/master" $FIRST_COMMIT
$ cd ..
$ mkdir certificates.git
$ git init --bare
$ git read-tree --empty
$ FIRST_COMMIT=`git commit-tree $(git write-tree) -m .`
$ git update-ref "refs/heads/master" $FIRST_COMMIT
$ cd ..
$ exit
```

So we create 2 Git repositories with one commit. Now, we need to generate an
SSH key which can be used by unikernels:

```sh
$ opam install awa
$ awa_gen_key > awa.gen.key
$ tail -n1 awa.gen.key | ssh git@localhost 'cat >> ~/.ssh/authorized_keys'
$ head -n1 awa.gen.key
seed is svIdyO8boxNQP03NrUgfwDxk4iPaURukAyKl1cx8
```

You must keep the seed of the RSA key. We will use it for unikernels then.

### `blogger`

Finally, we can re-generate this blog with https://github.com/dinosaure/blogger
and push the result into our private Git repository:

```sh
$ git clone https://github.com/dinosaure/blogger
$ cd blogger
$ opam pin add -y .
$ dune exec src/blogger.exe -- push \
  --author "Romain Calascibetta" \
  --email "romain.calascibetta@gmail.com" \
  --branch "gh-pages" \
  -r git@localhost:blog.osau.re.git
```

Feel free to update/change `blogger` to be able to generate something closer
to what you want. The structure is pretty good to play and run:
- `dune exec src/blogger.exe -- watch` builds and runs a local website. By this
  way you can check the result
- `dune exec src/blogger.exe -- build` just builds the website into the default
  `_site` directory. Then, you are able to do what you want on it

### Contruno and Let's encrypt

Let's prepare and deploy our first unikernel (with MirageOS 4). Contruno
provides a simple tool to populate the Git repository and the unikernel. We
will populate our `certificates.git` with a first Let's encrypt certificate
asked by hands - `contruno` will handle next challenge to renew certificates -
and push it into our Git repository _via_ our `contruno.add` tool.

```sh
$ git clone https://github.com/dinosaure/contruno
$ cd contruno
$ opam pin add -y .
$ sudo certbot certonly --standalone \
  --server https://acme-staging-v02.api.letsencrypt.org/directory \
  --register-unsafely-without-email \
  -d <DOMAIN>
$ sudo cp /etc/letsencrypt/live/<DOMAIN>/* .
$ contruno.add --cert cert.pem -h <DOMAIN> -i <IP1> -p privkey.pem \
  --pass <PASSWORD> -r git@localhost:certificates.git \
  -t <IP0>
```

- `<IP1>` is where you want to deploy your website, let's say 10.0.0.3
- `<IP0>` is where you want to deploy `contruno`, let's say 10.0.0.2
- `<PASSWORD>` is a password to ask the deployed `contruno` unikernel to
  update its internal certificates
- `<DOMAIN>` is your domain name

**NOTE**: `certbot` currently asks a non-production certificate. If you want a
*real* TLS certificate, you should delete the `--server` argument.

And let's compile and deploy `contruno`:

```sh
$ cp -r contruno/unikernel contruno-unikernel/
$ cd contruno-unikernel/
$ mirage configure -t hvt
$ make depends
$ mirage build
$ albatross-client-local create --mem=512 --net=service:br0 contruno \
  dist/contruno.hvt \
  --arg="-r git@10.0.0.1:certificates.git" \
  --arg="--production true" \
  --arg="--ssh-key=rsa:svIdyO8boxNQP03NrUgfwDxk4iPaURukAyKl1cx8" \
  --arg="--pass=<PASSWORD>" \
  --arg="--ipv4=10.0.0.2/24" \
  --arg="--ipv4-gateway=10.0.0.1"
```

### Unipi

And the last one, we will deploy our [unipi][unipi] unikernel:

```sh
$ git clone https://github.com/dinosaure/unipi#mirage-4
$ cd unipi
$ mirage configure -t hvt
$ make depends
$ mirage build
$ albatross-client-local create --mem=512 --net=service:br0 <DOMAIN> \
  dist/unipi.hvt \
  --arg="--remote git@10.0.0.1:blog.osau.re.git#gh-pages" \
  --arg="--ssh-key=rsa:svIdyO8boxNQP03NrUgfwDxk4iPaURukAyKl1cx8" \
  --arg="--hostname <DOMAIN>" \
  --arg="--tls=false" \
  --arg="--ipv4=10.0.0.3/24" \
  --arg="--ipv4-gateway=10.0.0.1"
```

### `iptables`

The last configuration is about the `iptables`. This is the hard one to let
unikernels to communicate with Internet - specially `contruno`, `unipi` can
stay into our private network. We will follow what `docker` does when you want
to bridge our containers with Internet:

```sh
$ sudo iptables -A FORWARD -o br0 -m conntrack --ctstate RELATED,ESTABLISHED \
  -j ACCEPT
$ sudo iptables -A FORWARD -i br0 ! -o br0 -j ACCEPT
$ sudo iptables -A FORWARD -i br0 -o br0 -j ACCEPT
$ sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 ! -o br0 -j MASQUERADE

$ sudo iptables -N CONTRUNO
$ sudo iptables -A CONTRUNO -d 10.0.0.3/32 ! -i br0 -o br0 \
  -p tcp -m tcp --dport 443 -j ACCEPT
$ sudo iptables -A CONTRUNO -d 10.0.0.3/32 ! -i br0 -o br0 \
  -p tcp -m tcp --dport 80 -j ACCEPT
$ sudo iptables -A FORWARD -o br0 -j CONTRUNO
$ sudo iptables -t nat -N CONTRUNO
$ sudo iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j CONTRUNO
$ sudo iptables -t nat -A CONTRUNO ! -s 10.0.0.3/32 ! -i docker0 \
  -p tcp -m tcp --dport 443 -j DNAT --to-destination 10.0.0.3:443
$ sudo iptables -t nat -A CONTRUNO ! -s 10.0.0.3/32 ! -i docker0 \
  -p tcp -m tcp --dport 80 -j DNAT --to-destination 10.0.0.3:80
```

## Conclusion

I hope this article gives a little more clarity about my blog, MirageOS and
OCaml and all the efforts everyone has made to come up with solutions that use
OCaml to generate a static blog. There are other solutions like
[sesame][sesame] or [stone][stone]. None of them would be ultimate and only the
diversity of solutions is king - which is not bad. I hope I can keep this blog
going for a long time and that it will help newcomers to OCaml and MirageOS to
understand the ecosystem a bit more.

[mirageos]: https://mirage.io/
[org]: https://www.orgmode.org/
[preface]: https://github.com/xvw/preface
[yocaml]: https://github.com/xhtmlboi/yocaml
[free-monad]: https://hackage.haskell.org/package/free
[ocaml-git]: https://github.com/mirage/ocaml-git
[irmin]: https://github.com/mirage/irmin
[unipi]: https://github.com/roburio/unipi
[markdown]: https://daringfireball.net/projects/markdown/syntax
[yaml]: https://yaml.org/
[jingoo]: https://github.com/tategakibunko/jingoo
[mustache]: https://mustache.github.io/
[tyxml]: https://github.com/ocsigen/tyxml
[xhtmlboi]: https://xhtmlboi.github.io/
[patch01]: https://github.com/xhtmlboi/yocaml/pull/26
[patch02]: https://github.com/xhtmlboi/yocaml/pull/29
[mimic]: https://github.com/dinosaure/mimic
[conduit-3.0.0]: https://github.com/mirage/ocaml-conduit/pull/311
[mimic-tutorial]: https://dinosaure.github.io/mimic/mimic/index.html
[hmap]: https://github.com/dbuenzli/hmap
[http/af]: https://github.com/inhabitedtype/httpaf
[unipi-paf]: https://github.com/roburio/unipi/pull/4
[paf]: https://github.com/dinosaure/paf-le-chien
[dream]: https://github.com/aantron/Dream
[contruno]: https://github.com/dinosaure/contruno
[dns-letsencrypt-secondary]: https://github.com/roburio/dns-letsencrypt-secondary
[conan]: https://github.com/mirage/conan
[conan-discuss]: https://discuss.ocaml.org/t/ann-first-release-of-conan-the-detective-to-recognize-your-file/8655
[albatross]: https://github.com/roburio/albatross
[sesame]: https://github.com/patricoferris/sesame
[stone]: https://github.com/Armael/stone
