---
date: 2025-05-27
title: The 15th MirageOS retreat
description:
  An overview about the last MirageOS retreat
tags:
  - OCaml
  - MirageOS
  - unikernel
---

The 2025 MirageOS retreat may be the last one organised in Riad de Marrakech.
There were more than fifteen participants (which is very good), including old
regulars and newcomers. As for Robur, a small retreat was organised afterwards
between the members of our cooperative.

On this retreat, as usual, I had a fairly ambitious goal: to reimplement
[QUIC][quic]. Even though I was well equipped for the task (I had already
implemented the protocol, all that was missing was the logic), I found myself,
as usual, working on other projects, helping people and discussing all sorts of
things not necessarily related to computing (which is also nice).

And as usual, the stated goals were not achieved, but that's also the charm of
retreats, where there is spontaneous knowledge sharing, reprioritisation of
goals, a return to reality about what is possible and what takes time, as well
as times when we just laugh and chat.

This article will be divided into six sections:
1) First, I would still like to present a project that is taking shape, for
   which I have already established a collaboration, and which lays the
   foundations for what will be necessary next for Robur in the development of
   unikernels.
2) There is, of course, all the work, still experimental, on
   [miou-solo5][miou-solo5], in which I tried to involve Antonin, but we
   preferred to drink beer until we couldn't drink anymore (which, in my
   opinion, is more interesting).
3) There is still a project, not yet finalised but clearly interesting: a
   [webassembly interpreter][weed] integrated into a unikernel.
4) I finally got around to "updating" our Git stack with the recent changes
   made to [carton][carton] (funded for [email archiving][email-archive]). A
   quick review of [ocaml-git][ocaml-git] and [git-kv][git-kv] is necessary.
5) I also embarked on the implementation of the NTP protocol, which mainly
   allowed me to consolidate my knowledge of UDP (necessary for QUIC). A quick
   look back at this small project is also in order.
6) Finally, I helped other people with their projects here and there:
   [dream-mirage][dream-mirage], Gabriel's [hyperfine][hyperfine] project,
   discussions on the MirageOS scheduler (with lwt) for Gabriel and Armaël, a
   [uxn][uxn] interpreter made by Philip, and a little bit of
   [mollymawk][mollymawk] with Pixie.

So I definitely didn't slack off during this retreat!

## A new HTTP stack, [httpcats][httpcats], [vif][vif] & [hurl][hurl]

I haven't talked much about this project at the retreat, but I think the work
done with [spwut][spwut] and myself deserves a little explanation.

I've been hanging around all the HTTP stacks in OCaml for quite some time: I
worked at [Ocsigen][ocsigen], participated in the development of
[CoHTTP][cohttp], and also contributed remotely to the use of [http/af][httpaf]
and [h2][h2], eventually proposing a [paf-le-chien][paf-le-chien] solution that
is still useful today for unikernels. I also participated in the development of
[Dream][dream] and integrated some of my libraries, such as
[multipart_form][multipart_form], into this framework.

In short, I have a fairly comprehensive view of what can be done with HTTP in
OCaml. However, I was never really satisfied with the result, despite my efforts
to participate in the community.

At this point, there were essentially two things that interested me:
1) Unblock the situation with `http/af` and get [Spiros][spiros]'s agreement to
   fork his project and have a maintained HTTP/1.1 implementation that handles
   connection upgrades.
2) Have an HTTP server/client that works with Miou (since that's our scheduler).

On these two points, it was clear that such initiatives could only come from me.
So I asked Spiros if I could fork `http/af`, which resulted in
[ocaml-h1][ocaml-h1]. Spiros and I know each other, and he even participated in
a retreat at the time. In a private discussion, he understood our constraints
and allowed us to fork `http/af`. I wouldn't say that `ocaml-h1` is strictly
speaking a continuation of `http/af`. However, this project was built on a
social agreement that respects everyone's work (which is already quite
something!).

Then I started experimenting with `ocaml-h1` and `ocaml-h2` with Miou in order
to propose [httpcats][httpcats]. This time, the goal was to synthesise
everything we had done at Robur with regard to the HTTP stack (both for our
unikernels and our applications). To this end, I resumed the work that Hannes
had started on [http-lwt-client][http-lwt-client], which, in my opinion, remains
the most _efficient_ HTTP client. In addition, Kate started using `httpcats` and
gave me some feedback so that she could implement a unikernel for
[downloading torrents][mirage-torrent]. As development continued, I started
offering a tool similar to `httpie` but in OCaml, called [hurl][hurl] (first
proposed by Hannes).

At this point, we could argue against the emergence of a new HTTP client. There
are [pros and cons][http-pros-cons]. What is certain is that our cooperative
sees the value in it and is committed to offering something that satisfies us.
Previous contributions to CoHTTP/[Conduit][conduit] did not really bear fruit
(as explained [here][conduit-is-dead]). It was clear to us that we needed
another HTTP client that would work for our applications and unikernels, and
some people simply rejected our collaboration on CoHTTP/Conduit, which led us to
produce our own libraries.

The next step was to implement an HTTP server. My experience with
`ocsigenserver`, `cohttp`, `http/af` and `paf` enabled me to produce something
fairly quickly. However, one piece was still missing: websockets and upgrading
an HTTP connection to this protocol. This is where [spwut][spwut] did [an
excellent job][h1-ws]! We met up several times in Paris and worked together,
then shared a beer in a small bar near Bastille.

An interesting point is the various benchmarks I ran with `httpcats` and the
comparisons with `eio+http/af`. The [latest one from April][benchmark] proves
that `httpcats` (and Miou) offers an HTTP server with the lowest latency. It
would probably take another article to explain this, but the choices that
structured Miou with the goal of having a scheduler that could implement
services and unikernels are increasingly being confirmed!

In short, we have completed `httpcats` with websocket support, and now we want
to offer a kind of _framework_ for developing websites. We are therefore
currently developing [Vif][vif].

The latter is a web framework, but it has the particularity of using Miou. As
such, and for the sake of completeness, I have started working with
[paurkerdal][paukerdal] on Miou support for [caqti][caqti]. The idea that Miou
can easily execute tasks in parallel has also allowed **@paurkerdal** to find
some bugs, as was the case for us with `mirage-crypto`.

Another unique feature of Vif is that it takes advantage of recent work by OCaml
to offer a native [`ocamlnat`][ocamlnat] REPL. The idea is to be able to write
an OCaml script that acts as a web server and simply run that script with Vif.
Of course, Vif is also (and above all) a library that offers several functions
for implementing your web server.

Finally, the last special feature is the (perhaps excessive) use of GADTs to
type the information we want to process in our web server.
Serialising/deserialising information is a fairly repetitive task when
developing a web server. Vif therefore proposes using [jsont][jsont] to obtain
OCaml values from JSON, as well as `multipart_form`, again with the same idea of
being able to [_stream_ files][multipart-stream]. So there are types in the
content, but also types in the routes, which is something I really wanted after
discussing about [furl][furl] with [@Drup][drup]. In short, an entire article
would be needed to present Vif, but the [examples][vif-examples] available in
the repository already show what this framework is capable of.

As such, one of our ambitions for Robur is to update [builder-web][builder-web]
with Vif. The project is still experimental and the API is likely to change, but
the idea is gradually taking shape.

## [`miou-solo5`] & unikernels

Two years ago, we started the [Miou][miou] project: a simple scheduler to
implement our services and unikernels. Now, [miou-solo5][miou-solo5] has
appeared: a specialisation of the Miou core for [Solo5][solo5]. The idea is to
"plugw Miou's scheduler with Solo5's _hypercalls_. In itself, this work is not
fundamentally complex; it consists mainly of FFI (and [eio-solo5][eio-solo5]
already exists).

However, a significant amount of work is required: [mirage-tcpip][mirage-tcpip].
Implementing a unikernel (very) often requires a TCP/IP stack. The problem is
that `mirage-tcpip` is:
1) closely linked to `lwt` in its operation
2) functorised

These are the two points we would like to reconsider, along with a possible
change from `Cstruct.t` to `bytes`, as we have already done with
[mirage-crypto][mirage-crypto-cstruct].

This is ultimately an opportunity to use [utcp][utcp], Hannes' library whose
state machine has been proven using [HOL4][hol4].

So, with the help of **@reynir**, we experimented with implementing an "echo"
TCP/IP server with `miou-solo5`. This involved some groundwork, particularly on
the IP layer, as we described [here][miou-solo5-ip]. We encountered a few bugs,
but the feedback, particularly on the workflow in the development of the
unikernel, seems more interesting than what we are used to with the `mirage`
tool (**@Willenbrink** could confirm the difficulties that can be encountered
when using `mirage` & `opam-monorepo`).

In fact, building a unikernel with `miou-solo5` now only requires `dune`. The
files needed (such as `manifest.json`) to produce the unikernel are generated
automatically with `dune`, and a simple `dune build ./unikernel.exe` is enough
to obtain the unikernel and run it directly with `solo5-hvt`.

In short, `miou-solo5` is still a trial balloon, but it remains very
interesting. I therefore proposed a [short talk][miou-solo5-talk] during the
retreat and continued to experiment with the workflow, notably with
**@MisterDA** and Léo on two different projects.

We will therefore continue in this direction and ask ourselves the right
questions based on our experience in developing unikernels in order to propose a
better workflow. At some point, we will propose a unikernel using OCaml 5 and
`miou-solo5` that can offer a service (and a service such as NTP remains a
feasible objective) and test it in a real context.

## A webassembly interpreter as an unikernel

Léo has just finished his [thesis][leo-thesis] on the symbolic interpretation of
a WebAssembly code in OCaml. I invite you to read his thesis and watch
[his talk][leo-talk] where he explains how he found a bug in Rust and
[Typst][typst] concerning floats.

During his thesis, he implemented a library that performs concrete
interpretation of WebAssembly: in other words, you can execute WebAssembly in
OCaml thanks to [owi][owi].

The idea was to integrate this interpretation tool into an unikernel. We would
pass the WebAssembly code through a "block device" and let our unikernel execute
the code. The idea is very interesting, so we first tried to link the `owi` code
with an unikernel.

This took us a day because we had to remove all instances of the `Unix` module
(Léo had already done most of the work, only a few functions were missing).

Then Léo was able to execute some fairly simple WebAssembly code in the
unikernel! I think it was a factorial. This confirmed that:
1) the concrete interpretation was working
2) we could start thinking about running slightly more complex code

So we went for [SQLite][sqlite]! Perhaps a little too complex, but there is an
[export of the SQLite code to webassembly][sqlite-wasm], and we wanted to see:
1) what SQLite needs (`malloc(3)`, `mmap(3)`, `read(3)`, etc.)
2) what SQLite exports for use

```shell
$ owi export ...
```

Léo extracted the functions needed by SQLite, and now it was a matter of
implementing them. The concrete interpretation of the code would therefore need
a module implementing the functions required by SQLite (basically POSIX), and
these are typed using a GADT (thanks **@chambart**). We first implemented these
functions with an `assert false`.

Finally, thanks to `owi` again, we can request to execute a specific function
that SQLite exports, so we tried [`sqlite3_open`][sqlite3-open]. We also needed
to prepare some allocations for SQLite, so we used `malloc(3)`.

At this point, we started to see something interesting. We observed what SQLite
wanted to do and implemented the entire execution path so that SQLite could
generate a random number using [mirage-crypto][mirage-crypto] under the hood.

Due to time constraints, we couldn't go any further. But we did the bulk of the
work. Now we need to implement the functions required by SQLite one by one. In
total, SQLite only requires about thirty functions. That's not very many, and
even though there are functions like `ioctl` and `mkdir`, SQLite3 ultimately
only needs one file. The idea of a file system is not fundamentally required.

The project is available here: [weed][weed]. The prospects for this project are
very interesting. It is conceivable to execute WebAssembly code _on demand_ in a
closed environment such as a unikernel. We will therefore try to take this
further with Léo!

## [`ocaml-git`][ocaml-git], [`git-kv`][git-kv] and the old version of me

It can be quite dizzying at times to see the work you've done after 10 years in
the OCaml community. One of the projects I've worked on the most is
[ocaml-git][ocaml-git].

My first task was to generate a PACK file so that we could clone, fetch or push
to a Git repository. This also involved implementing the [Smart protocol][smart]
and negotiation between two Git instances.

This work was interesting but probably driven by all kinds of experiments so
that [ocaml-git][ocaml-git] could still be integrated into a unikernel. There
were several abstraction issues:
- abstraction of the scheduler
- abstraction of the hash algorithm
- abstraction of the protocol underlying the transmission of Smart packets

As such, `ocaml-git` was more of a space for iterating on several abstraction
techniques (functors, first class modules, record as first class modules,
[HKT][hkt] or [mimic][mimic]). Some of these techniques proved their usability,
while others did not. This is particularly the case for functors and
[High Kinded Polymorphism][hkt].

The problem is that I recently decided to update [carton][carton] (which manages
PACK files) and it got rid of functors and HKT. So I had to extend this work to
`ocaml-git` in order to deploy our unikernel [opam-mirror][opam-mirror] for the
retreat.

So I started this work, but the more I progressed, the harder it was to see the
benefit for `ocaml-git`. On the other hand, I also developed [git-kv][git-kv],
which offers a much simpler and more practical API. This is the library we use
for `opam-mirror`.

Basically, we have `carton`, which allows us to manipulate PACK files. This
library is used by `ocaml-git`, which implements all the logic of the Smart
protocol as well as the Git object format. Finally, we have `git-kv`, which
offers a much simpler API than `ocaml-git` but is based on `ocaml-git`.

`ocaml-git` has other constraints, such as being used by [Irmin][irmin].
However, in practice, we are only interested in `git-kv`. Ultimately, wouldn't
it be interesting to "remove" `ocaml-git`? So I repatriated the essentials of
`ocaml-git` (the protocol and the Git object format) into `git-kv` so that the
latter no longer depends on `ocaml-git`. It took me quite a bit of time, but
after two days of trying to get the project to compile, I finally got `git-kv`
back without `ocaml-git`, and all the tests we implemented worked like a charm!

In the end, I avoided the regression that I could have easily convinced myself
would happen if it were just `ocaml-git`. I also removed the functors and HKT
without any problems. So now we have a small library, `git-kv`, which does the
essentials: clone, fetch, push, and keep a Git repository in memory in the
context of unikernels.

Hannes and I finally tried `opam-mirror` again with the new version of `git-kv`
and, after a few minor bugs, everything worked! It was just a shame that we
couldn't launch `opam-mirror` until the end of the retreat. We use it in
particular to limit Internet consumption when downloading software via OPAM.

This experience also confirms that I am much more comfortable with OCaml and
have more confidence in myself when it comes to making design and API choices.
So thank you, [ocaml-git][ocaml-git]!

## UDP, NTP protocol & unikernel
