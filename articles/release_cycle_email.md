---
date: 2020-03-31
title: Release cycle about SMTP stack
description:
  A description of the incoming SMTP stack.
tags:
  - OCaml
  - MirageOS
  - SMTP
  - libraries
---

If you follow a bit my work, you should know about a huge work started few
months (years?!) ago about the SMTP stack. As a MirageOS developer, I mostly
want to use it to replace some usual services such as a DNS resolver, a blog or
a [primary DNS service][dns-primary-git].

But I really would like to replace an old but widely used service, the email
service.

## Mr. MIME at the beginning

One of my biggest project is [mrmime][mrmime]. It's a *little* library to parse
and generate an email according several RFCs. The most difficult part was to
handle *encoding* and *multipart*.

This library wants to solve 2 simple problems:
- How to read/introspect an email
- How to generate an email with OCaml

### How to read everything!

An email is easily understandable by a human as a *rich document* but it can be
hard to extract useful information from it by a computer. Indeed, an email can
be really complex such as a [RFC822][rfc822]'s date or, more obviously who
should receive the email.

Mr. MIME wants to solve this first problem and it provides an
[angstrom][angstrom] parser to extract *metadata* and represent them by OCaml
values. Then, the user is able to introspect them and implement something like
a /filter/, an organizer, etc.

#### FWS and `unstrctrd`

The main problem about email is the *folding-whitespace*. It permits the user
to extend a value of a field to multiple lines such as:

```text
To: A Group(Some people)
   :Chris Jones <c@(Chris's host.)public.example>,
     joe@example.org,
 John <jdoe@one.test> (my dear friend); (the end of the group)"
```

As long as the next line starts with a *whitespace*, it's a part of the current
value. At the first time, I tried to *parse* it with `ocamllex` but I failed
when I got a `too big automaton` error. Then, I switched to `angstrom` but I
was not really happy with results.

Recently, with @let-def, we agreed that an `ocamllex` still is possible. At the
end, we should be more faster than `angstrom`. So we did
[unstrctrd][unstrctrd]. The project is a bit more general than emails. In fact,
some formats such as some used by Debian or HTTP/1.1 headers follow the same
rule. `unstrctrd` wants to *flat* kind of value.

Into details, `unstrctrd` is a nice mix between `ocamllex` and `angstrom`.

With this project, we handle `FWS` described by RFC5322 and obsolete form
described by RFC822. It does some post-processes (like it removes useless
comments as described by `CFWS`) and provides a well abstracted API to be able
to parse and construct an `unstructured` form.

To understand the babel tower, any values available into your email as the
date, email addresses or subject of your email should respect, at least, the
`unstructured` form. Any of them will be processed, at least, by `unstrctrd`.

The goal is to hide such complexity to an other lower layer. In fact, before
this library, 2 of mine libraries want to solve this problem:
- [emile][emile] to parse email addresses
- and of course, `mrmime`

To be able to provide as much as possible light libraries, we did `unstrctrd`
and delete `FWS` handler from `emile`. By that, `mrmime` depends on both to
properly parse email addresses.

#### An email address and `emile`

As you know, we use widely email addresses but the format of them is really
**complex**. We can put more than one domain on it for example (like
`<@gmail.com:romain.calascibetta@x25519.net>`), put a name (which must respect a
special format), use special characters such as `+` or spaces with
*quoted-string*. A domain can directly be an IPv4 or IPv6 or an *extensible*
domain locally specified by the SMTP server. You can use UTF-8 of course since
[RFC6532][rfc6532].

In other words, email addresses are [hard][emile-test] to parse.

With `unstrctrd`, we simplify a bit the library and `emile` does not handle
anymore `FWS`. The goal is to let the user to process the input with
`unstrctrd` at first if the input comes from an email and then try to parse the
result with `emile` to extract the email address - and this is what `mrmime`
does of course.

And, of course, usual user does not care about *folding-whitespace*. The input
comes usually from a form (so, without this such token), so `emile` wants to
provide the most easy (and correct) way to parse an email address.

#### UTF-8, UTF-7, latin1 or [YUSCII][yuscii]?

An other obvious problem about email is the *encoding* used. We talk sometimes
about *charset* but let keep *encoding*. Of course, we have several *encoding*
such as ISO-8859. With a nice discussion with @dbuenzli with beers, the most
interesting way to solve the problem about *encoding* is to arbitrary choose
one and keep it as long as we can.

So, as the [uutf][uutf] author, we chosen UTF-8 of course!

However, we need to provide a way to *normalize* any *encodings* to UTF-8. The
Unicode consortium provides some [translation tables][unicode-tables] and I
picked them to be able to translate some of them to UTF-8. Few projects was
made in this goal:
- [uuuu][uuuu] to handle ISO-8859 encoding
- [coin][coin] to handle KOI8 encoding
- and the most important, [yuscii][yuscii] to handle
  [the famous UTF-7 encoding][UTF-7]

All of them are merged into an other library: [rosetta][rosetta].

This library is used by `mrmime` to try to *normalize* any contents to UTF-8.
From the point of view of the user, he does not need to know all details. The
result is just to say: any contents provided by `mrmime` use UTF-8!

An other OCaml project to handle such things exists: [Camomile][camomile]. But
`rosetta` wants to be the most easier and simpler as we want.

#### Base64 & Quoted-Printable

`mrmime` still wants to be low-level. Even if it wants to extract contents, it
does not handle *format* of contents (this feature should be done by a new
other project [conan][conan] - but we will talk about it in another article).

However, [RFC2045][rfc2045] defines some *standalone* formats independently to
the type of the content. The most know is the [base64][base64] to
encode binary or large files into your email. It's when I discovered that email
has his own base64 *format* that I to deeply [update][base64-release] the
package. decoder of this *special* format.

In other side, RFC2045 describes an other *format*: the quoted-printable
format. At this time, it was not possible to safely send an UTF-8 email. We
still were constrained to encode each byte of our email into [7-bits][7-bits].
To ensure to be able to pass 8-bits values, the quoted-printable was done to
encode such byte into a special form.

From that, we did the library [pecu][pecu] which is able to encode and decode
such contents. This library was well tested with [*fuzzer*][pecu-fuzzer] as we
do usually to check *isomorphism* between encoder and decoder.

Some others formats exist and are created specially for emails such as the
[*flowed* format][rfc2046] but they should be handle by others libraries.

### How to generate everything

The major feature about `mrmime` is not really about all of these libraries
used to parse an email. Indeed, `mrmime` was able to introspect emails at the
beginning (from that, we can look into [an old conference][conference] about
it). The notable update is the *safe* way to emit an email.

Indeed, a large work was done about API to be able to properly emit an email
and try to respect as much as we can rules such as:
- *folding-whitespace*
- 80-columns rule
- `base64` and quoted-printable encoding
- *multipart*

From that, I think we provide a nice interface to construct and emit an email.
Generation of email address for example is pretty-close to what we expect:

```ocaml
let me =
  Local.[ w "romain"; w "calascibetta" ]
        @ Domain.(domain, [ a "x25519"; a "net" ]) ;;
```

Composition with *parts* is also nice:

```ocaml
let content_type_alternative =
  let open Content_type in
  (with_type `Multipart <.> with_subtype (`Iana "alternative")) default

let header =
  Header.empty
  |> Header.add Field_name.content_type (Field.Content, content_type_alternative)

let part0 = Mt.part (stream_of_string "Hello World!")
let part1 = Mt.part (stream_of_string "Salut le monde!")
let m0 = Mt.multipart ~header [ part0; part1; ] |> Mt.multipart_as_part

let m1 = Mt.part stream_of_file
let m = Mt.(make multi (multipart [ m0; m1; ]))
```

Then, `mrmime` handles 80 columns such as when it reaches the limit, it tries
to break with a `FWS` token the value where is permitted such as:

```rfc822
To: thomas@gazagnaire.org, anil@recoil.org, hannes@mehnert.org, gemma.t.gordon@gmail.com
```

becomes:

```rfc822
To: thomas@gazagnaire.org, anil@recoil.org, hannes@mehnert.org,
  gemma.t.gordon@gmail.com
```

## SMTP then!

Of course, even if some people are really interested by `mrmime` mostly to pave
a way to be able to create yet another email client (in OCaml!), my goal is a
bit offbeat. So I mostly focused on the implementation of a SMTP server.

The first notable library is [colombe][colombe] - a low-level implementation of
the SMTP protocol.

### How to describe a state machine?!

The real goal of `colombe` is to provide an API which is able to let the user
to describe a state machine to communicate to a peer. By this fact, `colombe`
does not want to implement the `sendmail` command or does not want to implement
a SMTP relay or a SMTP submission service.

It is the first stone to be able to easily create such programs/libraries.

So most of people should not care about `colombe` - as they mostly want to send
an email. However, as a client such as ~sendmail~ or as a server such as an
SMTP submission service, they should use the same ground and avoid a duplicate
an implementation of how to talk SMTP with a peer.

Another point is the possibility to use `colombe` with MirageOS - and make an
unikernel with it. From that, we started to use an other kind of abstraction of
I/O (such as [LWT][lwt] or [ASYNC][async] - or `Unix`) which uses less
*functor* as we do usually with MirageOS.

But the real good point of `colombe` is the ability to describe the state
machine with *monad* which provides high-level `recv` and `send` operations:

```ocaml
let properly_quit_and_fail ctx err =
  let* _txts = send ctx QUIT () >>= fun () -> recv ctx PP_221 in
  fail err

let authentication ctx username password =
  let* code, txts = send ctx AUTH PLAIN >>= fun () -> recv ctx CODE in
  match code with
  | 504 -> properly_quit_and_fail ctx `Unsupported_mechanism
  | 538 -> properly_quit_and_fail ctx `Encryption_required
  | 534 -> properly_quit_and_fail ctx `Weak_mechanism
  | 334 ->
    let* () = match txts with
      | [] ->
        let payload = Base64.encode_exn (Fmt.strf "\000%s\000%s" username password) in
        send ctx PAYLOAD payload
      | x :: _ ->
        let x = Base64.decode_exn x in
        let payload = Base64.encode_exn (Fmt.strf "%s\000%s\000%s" x username password) in
        send ctx PAYLOAD payload in
    ( recv ctx CODE >>= function
        | (235, _txts) -> return `Authenticated
        | (501, _txts) -> properly_quit_and_fail ctx `Authentication_rejected
        | (535, _txts) -> properly_quit_and_fail ctx `Authentication_failed
        | (code, txts) -> fail (`Unexpected_response (code, txts)) )
  | code -> fail (`Unexpected_response (code, txts))
```

As you can see, we use [monadic operators][monadic-operators] to simplify the
lecture of the code. `send` and `recv` take values described by the user with a
GADT:

```ocaml
type 'x send =
  | QUIT : unit send
  | AUTH : auth send
  | PAYLOAD : string send

type 'x recv =
  | PP_220 : string list recv
  | PP_221 : string list recv
  | CODE : (int * string list) recv
```

Then, the user just needs to describe how to process such commands with a given
`ctx`:
- how to *send* `'x recv` to the `ctx`
- how to *recv* `'x send` from the `ctx`

Of course, this where `colombe` comes. It already defines few *primitives* to
emit and parse such commands into the `ctx`.

At another layer (which needs *syscalls*), a composition between the `ctx` and
a `fiber` (like `authentication`) returns a process `t` such as:

```ocaml
type ('a, 'err) t =
  | Read   of { buffer : bytes
              ; off : int
              ; len : int
              ; k : int -> ('a, 'err) t }
  | Write  of { buffer : string
              ; off : int
              ; len : int
              ; k : int -> ('a, 'err) t }
  | Return of 'a
  | Fail   of 'err

let run socket username password =
  let ctx = Context.create () in
  let fiber = authentication ctx username password in

  let rec go = function
    | Read { buffer; off; len; k; } ->
      let len = Unix.read socket buffer off len in
      go (k len)
    | Write { buffer; off; len; k; } ->
      let len = Unix.write socket buffer off len in
      go (k len)
    | Return v -> Ok v
    | Fail err -> Error err in
  go m
```

And you have a fully implemented and available way on `Unix` to communication
with a SMTP peer - and be authenticated.

### Implement `sendmail`, the client side

At least, from this core, it should be easy to implement `sendmail` command.
And of course, the distribution of `colombe` provide such library:
- `sendmail` which is free about lwt, async or unix
- `sendmail.tls` which uses `STARTTLS`
- `sendmail-lwt` a specialisation of `sendmail` with lwt

All of them wants to provide the most easy way to send an email. Indeed, it
exists 2 ways to submit an email:
- over a TLS flow available on `*:465`
- over a simple TCP flow but mostly of them require to start a TLS flow
  *in-the-fly* on `*:587` with `STARTTLS`

#### `facteur`

From all of that, we developed a little *proof-of-concept* to see if `colombe`
and `sendmail` correspond to what we expect: [facteur][facteur].

This is a simple tool which wants to send an email as the `sendmail` command
but the complete stack is in OCaml! It's a merge of `mrmime` and `sendmail` to
be able to produce a well formed email with file attachments.

It still is an experimental software and it requires a bad dependency
[libmagic][libmagic] to be able to recognise MIME type of file attachments.
However, I started to implement something else, [conan][conan], to
automatically do this job and be MirageOS compatible.

### Server side

Finally, I started to implement the server side. `colombe` handles both side.
It can parse response and emit request and /vice-versa/. From the same ground,
we try to implement 2 servers into a single project: [ptt][ptt].

It provides two libraries:
- `lipap` which is an SMTP submission server
- `mti-gf` which is an SMTP relay server

The final goal of them is to provide a full stack to be able to create email
addresses from a given domain. An example is may be more interesting, we will
take my `x25519.net`.

We will provide a first SMTP relay which will receive any incoming emails. It
will be the server notified by my primary DNS server with the `MX` record.

```sh
$ dig +short MX x25519.net
0 163.172.65.89
```

The goal of it is to transmit incoming email to the real destination. For
example, you want to send me an email to `romain@x25519.net` from your
`gmail.com` address. Google will speak with this server. Internally, I
associated `romain@x25519.net` to `romain.calascibetta@gmail.com`. Finally,
`mti-gf` will *retransmit* your email to Google (to
`romain.calascibetta@gmail.com`).

The second server let us to use our `x25519.net` email address to send email.
The goal is to properly configure your [MUA][MUA] to be able to be
authenticated to our `lipap` server. Then, it is able to communicate to others
SMTP servers such as Google and send your email to them (with your
`x25519.net` address).

So from my experiments, all should work and I started to deploy some others
unikernels mostly to get automatically [let's encrypt][letsencrypt]
certificates - and provide `163.172.65.89:587` and `163.172.65.89:465`.

### Other projects

Along my way, I surely developed some others tools (which need an update with
new interfaces or are really experimental) such as:
- [ocaml-dkim][ocaml-dkim] to verify DKIM fields from an email
- [received][colombe] to generate a graph from `Received:` fields from an email
  or generate one of them

## Conclusion

The stack is huge and it is not really finished. But I believe that I reached a
point where all libraries compose nicely and let me to provide something much
more complex such as an SMTP server!

All of that is possible of course with the work from others peoples such as
[ocaml-tls][ocaml-tls] or, more generally, MirageOS people.

I believe that this year will be the year where such service will be exist as a
MirageOS unikernel! And may be do an anarchist revolution and do a self
re-appropriation of the means of production.

[dns-primary-git]: https://hannes.nqsb.io/Posts/DnsServer
[mrmime]: https://github.com/mirage/mrmime
[rfc822]: https://tools.ietf.org/html/rfc822
[angstrom]: https://github.com/inhabitedtype/angstrom
[unstrctrd]: https://github.com/mirage/unstrctrd
[emile]: https://github.com/dinosaure/emile
[rfc6532]: https://tools.ietf.org/html/rfc6532
[emile-test]: https://github.com/dinosaure/emile/blob/master/test/test.ml
[yuscii]: https://en.wikipedia.org/wiki/YUSCII
[uutf]: https://github.com/dbuenzli/uutf
[unicode-tables]: ftp://ftp.unicode.org/Public/MAPPINGS/
[uuuu]: https://github.com/mirage/uuuu
[coin]: https://github.com/mirage/coin
[UTF-7]: https://crawshaw.io/blog/utf7
[rosetta]: https://github.com/mirage/rosetta
[camomile]: https://github.com/yoriyuki/Camomile
[conan]: https://github.com/dinosaure/conan/
[rfc2045]: https://tools.ietf.org/html/rfc2045
[base64]: https://github.com/mirage/ocaml-base64
[base64-release]: https://tarides.com/blog/2019-02-08-release-of-base64
[7-bits]: https://en.wikipedia.org/wiki/8-bit_clean
[pecu]: https://github.com/mirage/pecu
[pecu-fuzzer]: https://github.com/mirage/pecu/blob/master/fuzz/iso.ml
[rfc2046]: https://tools.ietf.org/html/rfc2646
[conference]: https://www.youtube.com/watch?v=kQkRsNEo25k
[colombe]: https://github.com/mirage/colombe.git
[lwt]: https://github.com/ocsigen/lwt
[async]: https://github.com/janestreet/async
[monadic-operators]: https://jobjo.github.io/2019/04/24/ocaml-has-some-new-shiny-syntax.html
[facteur]: https://github.com/dinosaure/facteur/
[libmagic]: https://linux.die.net/man/5/magic
[ptt]: https://github.com/dinosaure/ptt
[MUA]: https://fr.wikipedia.org/wiki/Mail_Transfer_Agent
[letsencrypt]: https://letsencrypt.org/
[ocaml-dkim]: https://github.com/dinosaure/ocaml-dkim
[ocaml-tls]: https://github.com/mirleft/ocaml-tls
