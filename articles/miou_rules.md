---
date: 2023-10-09
title: Rules of Miou!
description:
  A description of the Miou design and its rules
tags:
  - OCaml
  - Scheduler
  - Community
breaks: false
---

In our previous article, we explained the essence of Miou: a round-robin
scheduler and how it was implemented in OCaml. We also clarified preemption and
suspension and how we wanted to make our application "available" to system
events. In short, we recommend you read this article before this one.

Here, we're going to talk about Miou's rules! Once again, an API isn't just a
set of types and functions, it's a "design" that enforces a certain use. So Miou
imposes rules that must be respected, otherwise it fails.

## The benefits of rules

This is where we venture to formulate a certain vision of how to develop an
application. These rules can be quite strict (as the OCaml compiler can be when
it comes to types), but they ensure that we don't fall into pitfalls that our
future selves would hate us for!

As you know, Robur does have some experience of libraries and services. As
proof, this site (which is a unikernel) is still alive! And while questions of
memory consumption or application longevity are essential (otherwise this site
wouldn't work), so are questions of maintainance (there aren't (unfortunately?)
3 dinosaurs in existence... I don't even think there are any...). In short, if
we can have tools that help us in development and enable us to solve certain
problems upstream, then I'm all for it.

Miou imposes rules that are directly derived from our experience:
1) avoid memory leaks
2) more generally, resource leaks
3) always check for errors
4) always have control over what our tasks do

More generally, Miou lets you play with a whole host of objects
(file-descriptors, domains, exceptions, etc.), but requires you to have
everything tidied up by the end!

## Rule number 1: don't forget your children

This rule is perhaps the most restrictive for the OCaml community. Indeed, when
developing applications with `lwt` or `async`, we were used to using:
`Lwt.async`. This little function is literally the small coin you give Charon to
cross the river Lethe: you literally forget the task exists.

The problem is that a task may never finish (just as a program may never
finish). So what happens if a task launched with `Lwt.async` doesn't finish?
Well, you'll have a task (which takes up a certain amount of memory) that will
exist forever! You've got a leak.

It can be radical to say that you have a leak. Indeed, it's possible to imagine
that you've taken all the necessary steps to confirm (contrary to Turing) that
your task will end well. Unfortunately, our experience has shown us that the
confidence we had in ourselves to believe we could write good code turns out to
be a little presumptuous and that, in truth, we do leak.

As such, this code with Miou fails:

```ocaml
# let _ = Miou.run @@ fun () ->
  Miou.call_cc (Fun.const ()) (* we create a new task *)
;;
Exception: Miou.Still_has_children.
```

We forgot our child! In this code, we try to create a concurrently running task
(`Miou.call_cc`) that does nothing. `Miou.call_cc` returns what we usually call
a _promise_: in other words, the fulfillment of a promise that, in the future,
you'll get a value.

What Miou requires here is that you commit yourself to obtaining this value
(just as you should commit yourself to ensuring that the promises made to you
are kept). If you don't, Miou considers that you've forgotten "a child" (the
task that does nothing) which, in itself, is a resource!

### Implications

The implication here is that a task has a beginning, but more importantly,
always an end! A task can be complex, even very complex. It can be the umbrella
for a multitude of subtasks, which themselves have resources. The final idea is
that Miou forces you to put all this in order: it forces you to wait for the
results of ALL your tasks.

Above all, it forces you to know in what state these tasks have stopped. Indeed,
they can:
- stop normally and release all the resources they were using
- throw an exception - and you'll know.

The correct code would be:

```ocaml
# let _ = Miou.run @@ fun () ->
  match Miou.await (Miou.call_cc (Fun.const ())) with
  | Ok () -> ()
  | Error exn -> raise exn
;;
- : unit = ()
```

### Background tasks

There is, however, one (and only one) legitimate case where we would like to
"forget" a task: launching a task in the background where, precisely, we would
like it to run forever!

In truth, a task (or program) never runs forever. They can run for a long time
(even a very long time), but pragmatically, there will always be the moment of
an update or an unpaid server bill that brings your program to a halt.

As such, we maintain that: yes, you must imagine the end of your application.
However, Miou can help you set tasks in the background: we're not going to
forget our children, we're just going to put them in an orphanage:

```ocaml
let server ~handler file_descr =
  let rec go orphans =
    let peer, _ = Miou_unix.accept file_descr in
    let _ = Miou.call ~orphans @@ fun () -> handler peer in
    go orphans in
  go (Miou.orphans ())
```

An orphanage is just a set of tasks that we keep. It can be manipulated so that
it returns completed tasks. This way, using `Miou.await_exn` on these tasks
won't block (because, basically, `Miou.await_exn` awaits the result of the
task). Thus, the use of `Miou.orphans` is often associated with a simple
"cleanup" function:

```ocaml
let rec cleanup orphans = match Miou.care orphans with
  | None -> () (* The orphanage has no tasks. *)
  | Some None -> (* The orphanage has tasks, but none of them are finished. *)
  | Some (Some prm) ->
    (* A task has just been completed, and can be "consumed". *)
    Miou.await_exn prm;
    cleanup oprhans
```

It's a matter of _periodically_ "cleaning up" the tasks we may have created
previously (to manage our clients) and which have been completed (concurrently
or in parallel).

```ocaml
let server ~handler file_descr =
  let rec go orphans =
    cleanup orphans; (* Cleaning up old clients. *)
    let peer, _ = Miou_unix.accept file_descr in
    let _ = Miou.call ~orphans @@ fun () -> handler peer in
    go orphans in
  go (Miou.orphans ())
```

#### The kinship of this design

This design has already been tried out with [awa-ssh][awa-ssh] and `lwt`, where
the use of `Lwt.async` has been prohibited - in place of a list that keeps track
of all necessary tasks and is periodically cleaned up.

It's at this point that we need to explain a very important point: it would be
difficult for us to have near-equivalence between `lwt` applications and Miou
applications. Some aim to offer a quasi-transparent transition between an `lwt`
application and their schedulers. This is not the case with Miou, which forces
you to _rethink_ your implementations, in particular with this rule.

The advantage of this rule is that you can be sure that the application will
soon release all its resources. This was the case with [httpcats][httpcats]. We
wanted to go back to what we'd already done with [`paf-le-chien`][paf-le-chien]
or [`http-lwt-client`][http-lwt-client], but we were content to remake a new
implementation which ensured that at the end of an HTTP request, all resources
(tasks, file-descriptor, buffers, etc.) were released. Another aspect is error
handling: Miou, by forcing us to commit the result of a task, forces us to
consider the execution path in the event of an abnormal termination.

These questions are often relegated to the back burner when it comes to
implementing software that meets our objectives. Miou forces you to take the
lead (to ask yourself these upstream questions) that aren't absolutely necessary
for your objective (you can leak but still make an HTTP request) so you can
sleep soundly.

## Rule number 2: no one can get your children's results

This rule is interesting because it's a simplification of our scheduler in order
to relegate an essential question to the user: how to share information between
tasks. Let's go straight to the wrong code:

```ocaml
# Miou.run @@ fun () ->
    let prm0 = Miou.call (Fun.const 1) in
    let prm1 = Miou.call @@ fun () ->
      Miou.await_exn prm0 + 1 in
    Miou.await_all [ prm0; prm1 ]
    |> List.map (function Ok v -> v | Error exn -> raise exn)
    |> List.fold_left (+) 0
    |> print_int ;;
Exception: Miou.Not_a_child
```

This example shows that we want to share the information calculated by `prm0` in
`prm1`. The problem is that it wasn't `prm1` that launched `prm0` (`Miou.run`
directly launched `prm0`). So Miou will throw a `Not_a_child` exception
to inform you that the `Miou.await_exn` in `prm1` is illegal.

The idea is simple: with Miou, the only way to transmit information between
tasks is between children and their parents (a child can only have one parent).

Above all, this reveals an essential point when it comes to concurrent and/or
parallel programming: how to share information between tasks. There are a
multitude of solutions to this question:
1) using `Atomic`
2) protect information with a `Mutex` or `Semaphore`
3) take advantage of concurrent programming, where only one task can run at a
   time
4) implement an "atomic" structure
5) transmit via a system resource (FIFO, socket, files, etc.)

Point 3 is interesting because this technique was often used with `lwt`/`async`
(a `Stdlib.Queue` can be shared between several tasks), but its limits are
details specific to the scheduler's behavior. But what we really need to
understand here is that, if we have to answer the question of how to share
information between tasks, the only correct answer at this stage is: it depends.

In this respect, Miou's restriction to sharing the result of a task only with
its direct relative opens up a space for you to find the right solution for your
context. Indeed, the use of `Atomic` can help, but the use of a FIFO can just as
well be interesting: for the example, `Miou` and `Miou_unix` use both in
specific cases, which we'll detail in another article.

### The semantics of synchronization points & the scheduler

Beyond the solutions, there's also the subtlety of their implementation. OCaml's
`Condition` module is a good example, where the documentation is very clear and
specifies a behavior, known as ["spurious wakeup"][spurious-wakeup], that the
user must take into account. A fairly common behavior, but one that can be
avoided by using other mechanisms. Another example concerns `Mutex`. In a
concurrent programming context, you may well come across the Mutex exception
`Sys_error "Mutex.lock: Resource deadlock avoided"` where one task has locked
the Mutex, suspends itself and another task tries to lock the same Mutex... The
use of a ["Nano\_mutex"][nano-mutex] or a Semaphore may then be more
interesting.

In truth, the conclusion remains fatal if we're intellectually honest:
information transfer between tasks is a complicated matter. We need to look at
both the implementations and the behavior of the scheduler itself!

We could offer a whole panoply of solutions with their advantages and
disadvantages as integrated parts of Miou to make life easier for users.
However, we have chosen to ensure only one very specific type of transfer, and
leave this question open to the community: collective intelligence is always
more valuable than the pretension of supposed omniscience on these issues.

### Simpler scheduler implementation

From these rules, we can extract some fairly simple assertions about the
handling of our promises in our scheduler. In particular, we can suggest that
only the domain executing a task can modify the associated promise. This simple
assertion avoids complex synchronization points between domains when it comes to
promise manipulation.

But more on these aspects in another article.

## Rule number 3: Ownership

The two previous rules allow for an equally interesting extension: attaching
"resources" to tasks. Indeed, the basic idea behind these two fundamental rules
is that a task is a resource in itself. So, when it comes to manipulating
"resources" (the definition of which would be more conventional, like a
file-descriptor), all you have to do is "attach" them to the task in order to
extend the above checks:
- am I the owner of this file-descriptor?
- have I released (`Unix.close`) this file-descriptor as soon as my task ends?

The first check derives from our second rule: am I the parent of the task I'm
waiting for? Just as `Not_a_child` can occur if you're waiting for the child of
another parent, there's also the `Not_owner` exception whenever you manipulate a
resource of which you are not the owner. Let's take the example of a
file-descriptor:

```ocaml
type fd = Unix.file_descr * Miou.Ownership.t

let socket ?cloexec domain ty proto =
  let socket = Unix.socket ?cloexec domain ty proto in
  let finally = Unix.close in
  let owner = Miou.Ownership.own ~finally socket in
  socket, owner

let read (socket, owner) buf off len =
  Miou.Ownership.check owner;
  Unix.read socket buf off len

let () = Miou_unix.run @@ fun () ->
  let fd = socket domain Unix.SOCK_STREAM 0 in
  let buf = Bytes.create 0x1000 in
  let prm = Miou.call @@ fun () -> read fd buf 0 (Bytes.length buf) in
  Format.printf "%S" (Bytes.sub_string buf 0 (Miou.await_exn prm))
```

This code raises the `Not_owner` exception because the `prm` task is trying to
manipulate the file-descriptor (using `read`) while the resource is attached to
the main task (using `Miou.Ownership.own`). The only way to make this code work
is to "pass" ownership to our `prm` task:

```diff
-  let prm = Miou.call @@ fun () -> read fd buf 0 (Bytes.length buf) in
+  let prm = Miou.call ~give:[ snd fd ] @@ fun () ->
+    read fd buf 0 (Bytes.length buf) in
```

However, if this code is executed, the `Resource_leak`  exception appears. In
fact, we need a way to free our file-descriptor.

```ocaml
let close (socket, owner) =
  Unix.close socket;
  Miou.Ownership.disown socket
```

Finally, our main code becomes:

```ocaml
let () = Miou_unix.run @@ fun () ->
  let fd = socket domain Unix.SOCK_STREAM 0 in
  let buf = Bytes.create 0x1000 in
  let prm = Miou.call ~give:[ snd fd ] @@ fun () ->
    let len = read fd buf 0 (Bytes.length buf) in
    Miou.Ownership.disown (snd fd) in
  Format.printf "%S" (Bytes.sub_string buf 0 (Miou.await_exn prm));
  close fd
```

### Disgression on static and dynamic analysis

At this point, some may have noticed that the idea of ownership is very similar
to that found in the Rust language. As such, and even though promising
experiments have been made to extend OCaml's type system in order to oxidize it,
we don't want to embark on experiments (using OCaml 5, given its current status,
is already an experiment for us).

So, yes, Miou offers a "poor" version of a (dynamic) resource utilization check.
A poor version which, in many respects, is subtly different from what one might
imagine Rust can offer (notably, ownership can appear for several tasks as in
the example above - for both the main task and the `prm` task). But this poor
version has the merit of existing!

## Implication and conclusion

Finally, there's one thing to recognize and understand about Miou: the
methodology for creating applications with Miou is **different** from that of
`lwt` and `async`. The result of these rules is that for some (if not all)
implementations with `lwt`, we have to rethink the whole design in order to
achieve a result that is correct with regard to these rules.

Some might consider that a quasi-transparent transition from one `lwt`
application to another scheduler would be an advantage. This is, of course, a
productivist advantage when it comes to producing this transition as quickly as
possible. But what about quality? What new issues does multicore and/or its
effects bring? In this respect, we think we need to **rethink**.

In this respect, Miou is a synthesis of our experience. A synthesis whose
choices may be inconvenient to our readers in many respects, but - and this is
Miou's objective - which is a satisfactory response to the problems we've had to
face over a decade of maintaining software with `lwt`.

I'd also like to warn the user that these rules, while our various applications
have shown some validity to their "real-world" applications, are subject to
change. At the very least, we've made it clear that Miou is _experimental_.
Discussion forums exist, notably on the notion of ownership. The answers we
provide (and we would never claim to) are not absolute. We therefore invite our
readers to give Miou a try, and to take part in this reflection on what a good
scheduler could be, in the light of the history of the OCaml community.

At least we've managed to develop an HTTP client/server with TLS support
[httpcats][httpcats], and we invite you to have fun (as [we did][twitter]) with
it.

[awa-ssh]: https://github.com/mirage/awa-ssh
[httpcats]: https://github.com/robur-coop/httpcats
[twitter]: https://twitter.com/Dinoosaure/status/1710320603113095538
[nano-mutex]: https://ocaml.janestreet.com/ocaml-core/v0.12/doc/core/Nano_mutex/index.html
[spurious-wakeup]: https://en.wikipedia.org/wiki/Spurious_wakeup
[paf-le-chien]: https://github.com/dinosaure/paf-le-chien
[http-lwt-client]: https://github.com/robur-coop/http-lwt-client
