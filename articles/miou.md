---
date: 2023-09-08
article.title: Miou, a simple scheduler for OCaml 5
article.description:
  A description of the Miou scheduler
tags:
  - OCaml
  - Scheduler
  - Community
breaks: false
---

As mentioned in my [thread][twitter], we've recently been working on
implementing a scheduler in [Robur][robur].

This short article will attempt to present one essential aspect (there are
several) of Miou: how it schedules tasks and why it schedules tasks in this way.
These questions assume that there can't only be one and only one scheduler: a
scheduler is defined by a "task management policy" which necessarily corresponds
to a particular use. We're going to spell all this out, so that future Miou
users are fully aware of the implications of using Miou.

## Cooperative or preemptive

The implementation of a scheduler meets specific objectives which can be seen in
its design and behaviour. For our part, we would like a scheduler that can
correspond to a fundamentally preemptive world: in other words, a world where
_events trigger tasks_.

This approach should be contrasted with (but not opposed to) optimising the
order in which tasks are carried out in order to obtain the result as quickly as
possible: this is not our objective.

All OCaml schedulers, however, had to deal with one problem. The problem is that
we're **not** able to preempt a task/function in OCaml.<sup>[1](#fn1)</sup>

<hr>

<tag id="fn1">**1**</tag>: Technically, only Garbage Collector is preemptive of
tasks, but we'll look at what this means in more detail.

## Preemption

Preempt is a term found in the implementation of schedulers. It is the opposite
of "cooperate". Preempt means that a scheduler is able to stop a task (for a
multitude of reasons). Cooperating leaves the possibility of _suspension_ to the
tasks themselves: they decide when they can stop.

Stopping a task does not mean that it has finished; stopping is suspending.
Suspension consists of stopping a task at a point. This suspension produces a
state that allows the task to be resumed at the point where it stopped.
Suspension can be caused by the scheduler (it is preemptive), or by the task
itself (they cooperate).

Now, as far as OCaml (and OCaml 5) is concerned, if we consider a task to be a
function, we cannot stop a function. A function can stop itself (thanks to
effects - technically we'll see that) but nobody except the GC can stop a
function. Even the GC can only stop a function at certain points (when
allocating). But it's clear that you can't create a preemptive system on
functions in OCaml.

## The suspension

Even before we talk techniques, we already have problems... But if we insist on
the terms, it's to find out what our implementation is based on (as well as the
choices we've made). If we absolutely want to be preemptive on functions, then a
preemptive scheduler should be able to:
1) launch a task
2) suspend a task: stop it at a point and produce a state
3) manipulate this state (keep it somewhere)
4) restart/continue the task from that state

In OCaml, we're able to do all that, but there's a subtlety:
```ocaml
type 'a t =
  | Launch : (unit -> 'a) -> 'a t
  | Finished of 'a
  | Suspended : ('a, 'b) Effect.Shallow.continuation * 'a Effect.t -> 'b t

let handler =
  let open Effect.Shallow in
  let retc v = Finished v in
  let exnc = raise in
  let effc
    : type c. c Effect.t -> ((c, 'a) Effect.Shallow.continuation -> 'b) option
    = fun effect -> Some (fun k -> Suspended (k, effect)) in
  { Effect.Shallow.retc; exnc; effc }

let continue = function
  | Launch fn ->
    Effect.Shallow.(continue_with (fiber fn) () handler)
  | Finished v -> Finished v
  | Suspended (k, effect) ->
    let v = perform effect in
    Effect.Shallow.(continue_with k v handler)
```

This code shows that a simple function `fn` can be transformed to a _task_ which
can be launched latter. This task can be manipulated (stored, ordered,
etc.) and can be restarted/continued if it is suspended.

The subtlety is in the suspension. We can obtain a suspension, but only if the
task produces an effect: it's not us who decides whether to suspend, it's the
task itself that decides when it can suspend.

Now, why does suspension matter so much? We could be satisfied with this little
code and then implement a scheduler from it (according to our 4 rules),
regardless of whether it's the task that decides to suspend or the scheduler
that decides. Well, it's from here that we need to make our choices explicit.

## System events

Let's draw a parallel with my life. I have a phone and people call me. The
problem is that I don't answer the phone. I do what I have to do and then (and
only then) I deal with the calls. Not that this approach is bad, but it makes me
**unavailable**: it makes me unavailable to my father to help him close up his
house the same day, and unavailable to the deliveryman who wants to drop off the
package. Or unavailable to listen to an after-sales service to subscribe to a
new offer...

The important thing to remember here is that I prioritise my tasks in relation
to external events, and in doing so I make myself **unavailable** to others.

A computer is the same thing! A computer does things (calculations) but it also
responds to external events (receiving a connection, reading a TCP/IP packet,
etc.). So the way a computer manages its tasks is very important when it comes
to the type of applications you want to run. Which leads us to say one essential
thing about our task management (for a computer as for a human): there are no
optimal solutions!

But let's go back to what we wanted: events trigger tasks.

In contrast to my lifestyle, I'd like my computer to be available to respond to
any events (although its job is to do things for me). This is characteristic of
a certain task management policy: it's called a round-robin scheduler.

## A round-robin scheduler

The principle of a round-robin scheduler is very communist^Wsimple. It consists
of having a list of tasks and executing these tasks one after the other.
However, a task cannot monopolise the CPU. It can happen that a task never
finishes, in which case all the other tasks are blocked (including some that
could unblock the first task).

The idea is to limit the execution of a task. This limit is called the _quanta_.
In general, we choose the time: a task can only be executed for 100ms, then we
move on to the next task.

This is where our problem of preemption comes in. We would like to suspend a
task according to a limit (and not have it decide to suspend itself). It's now
that we're going to introduce the most essential thing about Miou (and which
should be explicit to any round-robin scheduler): our _quanta_ is the emission
of an effect. So let's implement the basics of a scheduler, i.e. scheduling and
waiting for a task.

```ocaml
type task = Task : 'a t -> task
type 'a promise = 'a option ref
type _ Effect.t += Spawn : (unit -> 'a) -> 'a promise Effect.t
type _ Effect.t += Await : 'a promise -> 'a Effect.t

let perform
  : type c. task list ref -> c Effect.t -> [ `Continue of c | `Suspend ]
  = fun todo -> function
  | Spawn fn ->
    let value = ref None in
    let task = Launch (fun () -> value := Some (fn ())) in
    todo := !todo @ [ Task task ] ;
    `Continue value
  | Await value ->
    begin match !value with
    | Some value -> `Continue value
    | None -> `Suspend end
  | _ -> invalid_arg "Invalid effect"

let continue todo = function
  | Launch fn ->
    Effect.Shallow.(continue_with (fiber fn) () handler)
  | Finished v -> Finished v
  | Suspended (k, effect) ->
    match perform todo effect with
    | `Continue v -> Effect.Shallow.(continue_with k v handler)
    | `Suspend -> Suspended (k, effect)

let run fn v =
  let result = ref None in
  let rec go = function
    | [] -> Option.get !result
    | Task task :: rest ->
      let todo = ref rest in
      match continue todo task with
      | Finished _ -> go !todo
      | (Launch _ | Suspended _) as task -> go (!todo @ [ Task task ]) in
  let task = Launch (fun () -> result := Some (fn v)) in
  go [ Task task ]
```

Here, we return to our previous code where we specify the `perform` function
which consumes our effects. The `continue` function changes slightly so that it
can modify the TODO list in the case of `Spawn`. According to `perform`, the
`continue` function looks at whether to keep the suspension or continue the
function with the given value. Here's a code example:

```ocaml
let spawn fn = Effect.perform (Spawn fn)
let await prm = Effect.perform (Await prm)

let fiber () =
  let prm = spawn @@ fun () -> print_endline "Hello" in
  print_endline "World";
  await prm

let () = run fiber ()
(* It prints:
   World
   Hello
*)
```

Here, there are 2 things to recognise about a round robin scheduler:
1) only consume a single effect (as our _quanta_) produced by a task
2) add the task to the end of our TODO list

### Availability

The main advantage of a round-robin scheduler is that it shares the quantas
**fairly**. This is one of the reasons why we chose time as a quanta, as we want
to share CPU time fairly above all else. Here, the choice is to share the
production of effects fairly between all the tasks (since this is really the
only way we can do it).

We then have to apply ourselves to respecting this rule and considering the
reception of external events following the production of a quanta. This is where
we open a window of availability for our application in order to receive events
from the system.

This question is central to the objective of considering that events trigger
tasks. It was all the more of a question (and a difference) for `lwt` and
`async`: when do we suspend tasks? More to the point, when do we suspend tasks
so that our application is available to receive system events?

This is the crux of the matter, as this availability has an impact, especially
on the performance of a so-called pure application (which interacts very little,
if at all, with the system). It's also at this point that things need to be as
explicit as possible for the user. Developing a library with a scheduler means
knowing this kind of detail so that it can work well with applications requiring
a high level of availability (typically an HTTP server).

Miou does not (and cannot, in view of what we have said above) offer better or
worse availability than other schedulers. Miou can also be slower when executing
pure applications<sup>[2](#fn2)</sup>, given the task management policy of a
round-robin scheduler. However, Miou **explicitly** states one essential thing:
effects suspend tasks because we want system events to trigger tasks. And its
development will only be guided by this _mantra_.

<hr>

<tag id="fn2">**2**</tag>: Once again, pure applications are those that interact
very little with the system. They do not require a high level of availability,
but above all a "smart" scheduler that prioritises tasks in order to find an
optimum execution order. In this case, something like [moonpool][moonpool] might
be more interesting.

## An API issue

This 'little' introduction to Miou allows us to clarify a point that seems
_spontaneous_ in our explanation. The idea of "quanta", of considering the
latter as the production of an effect, of what is possible with OCaml 5 and
suspension, while considering a certain _preemptibility_ for our scheduler (by
considering that the user knows, _de facto_, that the production of an effect
allows the application to receive events from the system), all this helps to
explain why we use `Effect.Shallow` instead of `Effect.Deep`.

That's right! We have two interfaces for managing effects in OCaml. Why one
would be better than the other, I don't know. What is certain is that if we once
again consider our mantra _"effects suspend tasks and events trigger tasks"_, we
should spontaneously use `Effect.Shallow`.

The latter allows you to manage just **one** effect. It attaches a `handler` to
a function which, depending on what the function does (a simple calculation,
producing an effect, or terminating), produces a state, our `'a t`. The idea is
to remain constrained by what OCaml has to offer in order to systematically
respect our _mantra_: one effect is needed to suspend a task.

Note that we could get away with using `Effect.Deep`. The latter is not
incompatible. However, the aim of `Effect.Deep` is clear: to manage the
production of **several** effects. This is, of course, at odds with our rule.

### The `State` module

In Miou's [documentation][documentation], we sometimes refer to the `State`
module. This defines the most basic task logic.

In our experience, an API isn't just a collection of types and functions; an API
_enforces_ a certain use. From all our iterations on `Effect.Deep` and
`Effect.Shallow`, we weren't that happy with what they offered. Sometimes, the
API was too permissive or could only match our usage after a whole ceremony.
Don't get me wrong, I'm not criticizing the API authors here, I'm just saying
that these APIs shouldn't be used as they are!

So, the `State` module is an abstraction of the `Effect.Shallow` module, which
is better suited to our purposes. And as an API enforces a usage, the aim of the
`State` module is to force us to respect the rules of a round-robin scheduler.

# Conclusion

This article clarifies how our scheduler works. I hope it provides you with an
accessible mental model for thinking about designing an application with Miou.
It also clarifies Miou's "internals", which are the bricks that sediment the
scheduler's behavior.

Particular attention is paid to the `State` module, as it's here that the rules
of the game are set. Miou then adds elements such as domains and resource
management (with the idea of _ownership_), which we'll see in other articles.
It's worth noting that this article allows you to make a mini-scheduler.

Hopefully, it will also demystify a key component of an application. Xavier
Leroy once said that the GC _"is like a god from ancient mythology: mighty, but
very irritable"_. The same can be said of a scheduler if we don't take the
time to explain its task management policy. Let's make sure it doesn't!

## A final note on preemption and cooperation

If you have followed correctly, Miou is not a preemptive scheduler but the use
of effects (defined by Miou or another library) are points (which we will call
synchronisation points) where the application is able to receive system events.
We could spend hours on this question, as it was the initial schism between
`lwt` and `async`. Some will say that all these points make us "waste time"
which, in fact, is a recognised problem with a round-robin scheduler.

However, our experience in implementing protocols and services in Robur tells us
that it's better to have a lot of synchronisation points (even if it means being
slower) than none at all. Again, this depends on the type of application.

You could also reconsider the idea of using effects as synchronisation points
(as the `>>=` could have been this kind of point for `lwt` for example - which
is not the case). This is where usage is important. For example, I've put
`Lwt.pause` in certain places several times just to increase the availability of
my applications. Some people will be satisfied with this, considering that we're
explicitly trying to create this synchronisation point. However, others, like
me, will be a little annoyed at having to make these points explicit.

Once again, Miou is no better or worse. It's just a question of explaining these
_details_ as we do here.
