---
date: 2024-02-11
title: Cooperation and Lwt.pause
description:
  A disgression about Lwt and Miou
tags:
  - OCaml
  - Scheduler
  - Community
  - Unikernel
  - Git
breaks: false
---

Here's a concrete example of the notion of availability and the scheduler used
(in this case Lwt). As you may know, at Robur we have developed a unikernel:
[opam-mirror][opam-mirror]. It launches an HTTP service that can be used as an
OPAM overlay available from a Git repository (with `opam repository add <name>
<url>`).

The purpose of such an unikernel was to respond to a failure of the official
repository which fortunately did not last long and to offer decentralisation
of such a service. You can use https://opam.robur.coop!

It was also useful at the Mirage retreat, where we don't usually have a
great internet connection. Caching packages for our OCaml users on the local
network has benefited us in terms of our Internet bill by allowing the OCaml
users to fetch opam packages over the local network instead of over the shared,
metered 4G Internet conncetion.

Finally, it's a unikernel that I also use on my server for my software
[reproducibility service][reproducibility] in order to have an overlay for my
software like [Bob][bob].

In short, I advise you to use it, you can see its installation
[here][installation] (I think that in the context of a company, internally, it
can be interesting to have such a unikernel available).

However, this unikernel had a long-standing problem. We were already talking
about it at the Mirleft retreat, when we tried to get the repository from Git,
we had a (fairly long) unavailability of our HTTP server. Basically, we had to
wait ~10 min before the service offered by the unikernel was available.

## Availability

If you follow my [articles][miou-articles], as far as Miou is concerned, from
the outset I talk of the notion of availability if we were to make yet another
new scheduler for OCaml 5. We emphasised this notion because we had quite a few
problems on this subject and Lwt.

In this case, the notion of availability requires the scheduler to be able to
observe system events as often as possible. The problem is that Lwt doesn't
really offer this approach.

Indeed, Lwt offers a way of observing system events (`Lwt.pause`) but does not
do so systematically. The only time you really give the scheduler the
opportunity to see whether you can read or write is when you want to...
read or write...

More generally, it is said that Lwt's **bind** does not _yield_. In other words,
you can chain any number of functions together (via the `>>=` operator), but
from Lwt's point of view, there is no opportunity to see if an event has
occurred. Lwt always tries to go as far down your chain as possible:
- and finish your promise
- or come across an operation that requires a system event (read or write)
- or come across an `Lwt.pause` (as a _yield_ point)

Lwt is rather sparse in adding cooperation points besides `Lwt.pause` and
read/write operations, in contrast with Async where the bind operator is a
cooperation point.

### If there is no I/O, do not wrap in Lwt

It was (bad<sup>[1](#fn1)</sup>) advice I was given. If a function doesn't do
I/O, there's no point in putting it in Lwt. At first glance, however, the idea
may be a good one. If you have a function that doesn't do I/O, whether it's in
the Lwt monad or not won't make any difference to the way Lwt tries to execute
it. Once again, Lwt should go as far as possible. So Lwt tries to solve both
functions in the same way:

```ocaml
val merge : int array -> int array -> int array

let rec sort0 arr =
  if Array.length arr <= 1 then arr
  else
    let m = Array.length arr / 2 in
    let arr0 = sort0 (Array.sub arr 0 m) in
    let arr1 = sort0 (Array.sub arr m (Array.length arr - m)) in
    merge arr0 arr1

let rec sort1 arr =
  let open Lwt.Infix in
  if Array.length arr <= 1 then Lwt.return arr
  else
    let m = Array.length arr / 2 in
    Lwt.both
      (sort1 (Array.sub arr m (Array.length arr - m)))
      (sort1 (Array.sub arr 0 m))
    >|= fun (arr0, arr1) ->
    merge arr0 arr1
```

If we trace the execution of the two functions (for example, by displaying our
`arr` each time), we see the same behaviour whether Lwt is used or not. However,
what is interesting in the Lwt code is the use of `both`, which suggests that
the processes are running _at the same time_.

"At the same time" does not necessarily suggest the use of several cores or "in
parallel", but the possibility that the right-hand side may also have the
opportunity to be executed even if the left-hand side has not finished. In other
words, that the two processes can run **concurrently**.

But factually, this is not the case, because even if we had the possibility of
a point of cooperation (with the `>|=` operator), Lwt tries to go as far as
possible and decides to finish the left part before launching the right part:

```shell
$ ./a.out
sort0: [|3; 4; 2; 1; 7; 5; 8; 9; 0; 6|]
sort0: [|3; 4; 2; 1; 7|]
sort0: [|3; 4|]
sort0: [|2; 1; 7|]
sort0: [|1; 7|]
sort0: [|5; 8; 9; 0; 6|]
sort0: [|5; 8|]
sort0: [|9; 0; 6|]
sort0: [|0; 6|]

sort1: [|3; 4; 2; 1; 7; 5; 8; 9; 0; 6|]
sort1: [|3; 4; 2; 1; 7|]
sort1: [|3; 4|]
sort1: [|2; 1; 7|]
sort1: [|1; 7|]
sort1: [|5; 8; 9; 0; 6|]
sort1: [|5; 8|]
sort1: [|9; 0; 6|]
sort1: [|0; 6|]
```

<hr>

**<tag id="fn1">1</tag>**: However, if you are not interested in availability
and would like the scheduler to try to resolve your promises as quickly as
possible, this advice is clearly valid.

#### Performances

It should be noted, however, that Lwt has an impact. Even if the behaviour is
the same, the Lwt layer is not free. A quick benchmark shows that there is an
overhead:

```ocaml
let _ =
  let t0 = Unix.gettimeofday () in
  for i = 0 to 1000 do let _ = sort0 arr in () done;
  let t1 = Unix.gettimeofday () in
  Fmt.pr "sort0 %fs\n%!" (t1 -. t0)

let _ =
  let t0 = Unix.gettimeofday () in
  Lwt_main.run @@ begin
    let open Lwt.Infix in
    let rec go idx = if idx = 1000 then Lwt.return_unit
      else sort1 arr >>= fun _ -> go (succ idx) in
    go 0 end;
  let t1 = Unix.gettimeofday () in
  Fmt.pr "sort1 %fs\n%!" (t1 -. t0)
```

```sh
$ ./a.out
sort0 0.000264s
sort1 0.000676s
```

This is the fairly obvious argument for not using Lwt when there's no I/O. Then,
if the Lwt monad is really needed, a simple `Lwt.return` at the very last
instance is sufficient (or, better, the use of `Lwt.map` / `>|=`).

#### Cooperation and concrete example

So `Lwt.both` is the one to use when we want to run two processes
"at the same time". For the example, [ocaml-git][ocaml-git] attempts _both_ to
retrieve a repository and also to analyse it. This can be seen in this snippet
of [code][ocaml-git-both].

In our example with ocaml-git, the problem "shouldn't" appear because, in this
case, both the left and right side do I/O (the left side binds into a socket
while the right side saves Git objects in your file system). So, in our tests
with `Git_unix`, we were able to see that the analysis (right-hand side) was
well executed and 'interleaved' with the reception of objects from the network.

### Composability

However, if we go back to our initial problem, we were talking about our
opam-mirror unikernel. As you might expect, there is no standalone MirageOS file
system (and many of our unikernels don't need one). So, in the case of
opam-mirror, we use the ocaml-git memory implementation: `Git_mem`.

`Git_mem` is different in that Git objects are simply stored in a `Hashtbl`.
There is no cooperation point when it comes to obtaining Git objects from this
`Hashtbl`. So let's return to our original advice:

> don't wrap code in Lwt if it doesn't do I/O.

And, of course, `Git_mem` doesn't do I/O. It does, however, require the process
to be able to work with Lwt. In this case, `Git_mem` wraps the results in Lwt
**as late as possible** (as explained above, so as not to slow down our
processes unnecessarily). The choice inevitably means that the right-hand side
can no longer offer cooperation points. And this is where our problem begins:
composition.

In fact, we had something like:

```ocaml
let clone socket git =
  Lwt.both (receive_pack socket) (analyse_pack git) >>= fun ((), ()) ->
  Lwt.return_unit
```

However, our `analyse_pack` function is an injection of a functor representing
the Git backend. In other words, `Git_unix` or `Git_mem`:

```ocaml
module Make (Git : Git.S) = struct
  let clone socket git =
    Lwt.both (receive_pack socket) (Git.analyse_pack git) >>= fun ((), ()) ->
    Lwt.return_unit
end
```

Composability poses a problem here because even if `Git_unix` and `Git_mem`
offer the same function (so both modules can be used), the fact remains that one
will always offer a certain availability to other services (such as an HTTP
service) while the other will offer a Lwt function which will try to go as far
as possible quite to make other services unavailable.

Composing with one or the other therefore does not produce the same behavior.

#### Where to put `Lwt.pause`?

In this case, our `analyse_pack` does read/write on the Git store. As far as
`Git_mem` is concerned, we said that these read/write accesses were just
accesses to a `Hashtbl`. 

Thanks to [Hannes][hannes]' help, it took us an afternoon to work out where we
needed to add cooperation points in `Git_mem` so that `analyse_pack` could give
another service such as HTTP the opportunity to work. Basically, this series of
[commits][commits] shows where we needed to add `Lwt.pause`.

However, this points to a number of problems:
1) it is not necessarily true that on the basis of composability alone (by
   _functor_ or by value), Lwt reacts in the same way
2) Subtly, you have to dig into the code to find the right opportunities where
   to put, by hand, `Lwt.pause`.
3) In the end, Lwt has no mechanisms for ensuring the availability of a service
   (this is something that must be taken into account by the implementer).

### In-depth knowledge of Lwt

I haven't mentioned another problem we encountered with [Armael][armael] when
implementing [multipart_form][multipart_form] where the use of stream meant that
Lwt didn't interleave the two processes and the use of a _bounded stream_ was
required. Again, even when it comes to I/O, Lwt always tries to go as far as
possible in one of two branches of a `Lwt.both`.

This allows us to conclude that beyond the monad, Lwt has subtleties in its
behaviour which may be different from another scheduler such as Async (hence the
incompatibility between the two, which is not just of the `'a t` type).

### Digression on Miou

That's why we put so much emphasis on the notion of availability when it comes
to Miou: to avoid repeating the mistakes of the past. The choices that can be
made with regard to this notion in particular have a major impact, and can be
unsatisfactory to the user in certain cases (for example, so-called pure
calculations could take longer with Miou than with another scheduler).

In this sense, we have tried to constrain ourselves in the development of Miou
through the use of `Effect.Shallow` which requires us to always re-attach our
handler (our scheduler) as soon as an effect is produced, unlike `Effect.Deep`
which can re-use the same handler for several effects. In other words, and as
we've described here, **an effect yields**!

## Conclusion

As far as opam-mirror is concerned, we now have an unikernel that is available
even if it attempts to clone a Git repository and save Git objects in memory. At
least, an HTTP service can co-exist with ocaml-git!

I hope we'll be able to use it at [the next retreat][retreat], which I invite
you to attend to talk more about Lwt, scheduler, Git and unikernels!

[opam-mirror]: https://git.robur.coop/robur/opam-mirror
[reproducibility]: https://blog.osau.re/articles/reproducible.html
[bob]: https://bob.osau.re/
[installation]: https://blog.osau.re/articles/reproducible.html
[ocaml-git]: https://github.com/mirage/ocaml-git
[ocaml-git-both]: https://github.com/mirage/ocaml-git/blob/a36c90404b149ab85f429439af8785bb1dde1bee/src/not-so-smart/smart_git.ml#L476-L481
[hannes]: https://hannes.robur.coop/
[armael]: https://cambium.inria.fr/~agueneau/
[multipart_form]: https://discuss.ocaml.org/t/ann-release-of-multipart-form-0-2-0/7704#memory-bound-implementation
[retreat]: https://retreat.mirage.io/
[commits]: https://github.com/mirage/ocaml-git/pull/631/files
[miou-articles]: https://blog.osau.re/tags/scheduler.html
