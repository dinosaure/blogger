---
date: 2023-05-05
title: The MirageOS retreat (01/05/2023)
description:
  A little overview of this retreat
tags:
  - OCaml
  - MirageOS
  - Community
---

Here I am on a train to Tangier to return to Paris after this retreat! And this
is probably the best time to write an article about this event. I've been
involved in the OCaml community for a few years now and this is once again the
best event I've done in all these years. There are of course events like ICFP,
OUPS in Paris and other larger events like Bobkonf or C3 but the MirageOS
retreat is special because of the atmosphere it gives. Indeed, beyond all the
technical things we can do, the projects we maintain or the objectives we have,
a fundamental problem always exists and concerns the social organisation we wish
to have between us.

From this essential problematic that finally shapes our community (where links
are created and broken, discussions are made, debates are not finished), we can
get something better out of it, where the only constraint remains "to go and
meet the other". What is certain is that the many retreats I have been able to
make have consolidated my idea that the value of a project is only found in what
is socially concrete and palpable.

![gibraltar](../images/tanger01.jpg)

## The idea of retreat

The idea is certainly not written on paper by obscure people who would demand
that rules be followed. It is mainly a question of setting up an anarchist
organisation in which a few people impulse an idea (MirageOS) where exchanges
(even the most elementary ones) can be articulated in a space where the
authorities are no longer important. For example, a "Xavier Leroy" in this
space would not be Xavier Leroy, but just a person who knows OCaml very well.

We share the accommodation, we eat together, we are knocked out by the same sun
and the same beers we just drank<sup>[1](#fn1)</sup>. Let's start by discussing
the place we are in, imagine things and start coding!

We don't really know how the retreat is going to go because the memories it can
produce, the idea we have of it, the result we get from it is only defined by
the people who participate.

It is therefore above all a space in which differences in skills, languages,
know-how leave room for the potential of what a bunch of slightly drunk people
(sometimes like me) can produce in a week. The safeguards against unwanted
behaviour are just as much there, again, authority does not exist and anyone can
impose their limits on others as long as you are nice to others. The "safe"
space<sup>[2](#fn2)</sup> is co-created and crystalized into something that:
1) Is clearly not perfect
2) Cannot be exhaustively described and reapplied in every context
3) Must be recreated at the next retreat according to the participants

<hr>

<tag id="fn1">**1**</tag>: please note that this is not a place where we just
drink alcohol! Tea and coffee are available, it's up to people to choose without
any constraints (even social) on what we consume.

<tag id="fn2">**2**</tag>: As far as I know, everyone (even those who consider
themselves to be in the minority) have been able to find a space in this
retreat. Nevertheless, a perpetual effort is necessary and we are not immune to
making mistakes.

A question that often comes up is the location (Marrakesh). Even if we accept
everyone, the means required to come are substantial (price, time, flying or
taking the train, accessibility, etc.).

So it is not a real safe-place but we strive to make it so.

## What people did?

Of course, coming to the MirageOS retirement allows you to work on the Mirage
projects. However, I would really like to warn the reader that they are not
obliged to do Mirage related things during this retreat! The productivist idea
that I once wanted to apply to myself at one of the retreat is perhaps one of
the biggest mistakes I've made and experience tells me that from now on: I am
under no obligation to do anything for mirage at this retreat. In fact, the 
simple fact of exchanging with the other participants, considering their
opinions and knowing their objectives makes one systematically grow.

And even if there is no evidence of a commitment to a Mirage deposit on your
part, the fact is that the most important thing is to have fun. So, while I'm
impressed with this (non-exhaustive) list of projects myself, it certainly
doesn't negate the time spent discussing, reflecting and sharing on a whole host
of topics.

Another experience where I spent 3 days playing Factorio with some of the
participants also taught me that this exchange, as well as the sudden
appearance of Pierre Chambart on the server, may be a bit more to me than
producing 300 commits in a week.

More seriously, coming with a specific objective and wanting to do it badly can
lead to missed opportunities for exchange. It's cool to come with goals and try
to do them, it's even cooler to deconstruct their importance and put them aside
for a while to share other things with the participants.

![gibraltar](../images/tanger02.jpg)

### [banawá][banawa]

This is probably my favourite project as much for the time it took to do it as
for the result and what such a project can finally fit into. More generally, I
like the idea of microservices that don't require a lot of complex techniques.

Can you use SSH? That's fine. Now you can have a service (a unikernel of course)
where all the people can chat together in a common room. You just have to
connect via SSH. The trick is that the first time you connect (as @dinosaure for
example - ssh dinosaur@banawa), the unikernel registers your public key and
considers you @dinosaure - no one else can take that name afterwards.

The SSH connection produces a UI in your terminal with a nice prompt where you
can start exchanging messages like on IRC. You can now communicate with others
through a unikernel!

This is one of my favourite approaches to the mirage retreat. We often have
limited resources (internet connection and number of beers). The question is
now to find the most optimal method in such a context to: exchange files,
communicate with the other participants (avoiding to climb the 2 floors of the
Riad), have an OPAM mirror (and avoid re-downloading all the tarballs) or even
how to manage a DHCP service ourselves so that everyone can get an IP address.

I'll probably do a more precise article on banawá and I'd like to thank
[@reynir][reynir] for having the idea and implementing it in only 1 day (well,
afterwards, we found some bugs...). You can find a detailed article about the
implementation [here][banawa-article].

### MIDI synthesizer on RPi4

Probably one of the coolest projects of the retreat in the same way that the
Mirleft retreat produced: playing with a Raspberry Pi 4 and making sound!

[@pitag-ha][sonja] and [@Engil][engil] are both very interested in programming
with music (while I'm not sure I understand all the details: I stopped playing
the guitar during my teens...).

They experimented in the past with project such as
[cardio-crumble][cardio-crumble] (to transform OCaml runtime events to MIDI),
and at the last retreat Sonja and [@TheLortex][lucas] successfully implemented a
driver for the jack port on the Raspberry Pi.

This time around, the cardio-crumble pair got together in order to implement a
simple MIDI Drum Machine using bare Metal OCaml code.

During the first day they succesfully wrote the required code to have simple
MIDI I/O, and were able to write simple songs using OCaml code and send it to a
real synthesizer using a MIDI 5 pins cable!

Sadly enough, the MIDI adapter board they used seemed to be non-functioning
(after two days of investigation and help from many different people at the
retreat!), preventing them from receiving MIDI data. No doubt there will be a
round two for this project!

I left before they presented anything but it's still satisfying to see
bare-metal OCaml code handling music on a Raspberry Pi 4! This kind of project
always gives me more reason to "release" [Gilbraltar][gilbraltar] properly with
a mini-tutorial to display text and let people (like Engil and Sonja) do some
really cool stuff.

![gibraltar](../images/tanger04.jpg)

### ocamlrun

[@MisterDA][antonin] was eratic enough to produce a piece of software that has
nothing to do with MirageOS, but which captures the mood of the retreat so well.
His project is available here: [ocamlrun][ocamlrun]. It's a little video with
some really cool music ending with a mysterious "OCameeeeeel". The project is
not overly complex but it did have the merit of putting a smile on everyone's
face - and that's just as important!

### Solo5 improvements

[Solo5][solo5] remains a very important part of the MirageOS project. The
project is of such quality that it is recognised by peers (in the virtualisation
field) as a project that has managed to find the right balance between doing
something highly complicated with clear and simple C code (and God knows that
the intersection of these qualities with such a language is the challenge of a
lifetime!).

I currently maintain Solo5 and try to keep its exceptional quality even though
I suffer from impostor syndrome on every commits. Anyway... Beyond being a
project that needs some work as far as maintenance is concerned, the project is
also a tutorial on what hyper-virtualization is, which I invite you to read.

In this thirst for knowledge that one can have on such complex subjects,
Christiano, Hannes, Reynir or myself have shared our knowledge with Sonja, Kate,
Patrick or Fabrice who have struggled to understand (or even participate in
their capacity) to the project.

![gibraltar](../images/tanger07.jpg)

### ocaml-git server

It's in my TODO list! [ocaml-git][ocaml-git] was my first "big" project where I
started implementing the push command. This story has been worth probably 2
years of my life and I'm now an "expert" on Git internals. It seems however that
the ambition I had in the past about Git has been passed on to
[Paul-Elliot][paul-elliot] and [@Julow][jules] - which is a very good thing.

So they have started to understand my codebase (which is clearly not easy but is
[full of comments][git-comments] - sometimes stating my frustration). And, even
having come out of retirement earlier than expected, I think they're on the
right track to finally implementing a Git server!

The idea would then be to have unikernels that can synchronise with each other.
The only thing that has always stuck with me is how to implement a
"Garbage Collector" that destroys Git objects that are not used. I have a few
ideas in the back of my mind about this but let these 2 good people continue
this little project which may unlock many possibilities.

**EDIT**: from last news, it seems that they implemented a server and they are
able to clone a Git repository from it!

### [codept][codept] improvements

I started participating in codept quite some time ago. The project is quite
discreet and it seems clear that the issue it is trying to solve is one that
many people have had. It is however a wealth of knowledge regarding modules in
OCaml, very special but valid cases of dependency graphs and a very particular
way of using GADTs and functors.

The project is clearly interesting and could go very far. The only big drawback,
and this is the point of my contribution, is that it is difficult to find one's
way around and to understand what is going on. As a complex codebase, codept
remains a difficult one to understand. The objective is therefore to formalise
the library a little more with documentation, type abstraction and clarification
of certain behaviours in the codebase.

At the moment, I'm quite happy. With [@Octachron][octachron], we had a bug where
my PR broke a test (only one!). However, we couldn't find the source of the bug.
Our intuition was led by the notion of order and the use of `Stdlib.compare`.
Given the abstraction of some types, I had to implement - monomorphise - some
`*.compare` and the dependency solver expected a certain order of evaluation in
its "directed" implementation (the implementation used in the tests).

So the bug was all the more complex because `codept` was working! But we
eventually found it and Florian took the time to look at all the changes and
integrate them. We took the time to discuss what to do next but I can't thank
him enough for coming to this retreat and taking the time to look at my work.

![gibraltar](../images/tanger06.jpg)

### [albatross][albatross]

[@hannesm][hannes] has done a lot of work on albatross and has simplified its
use and added good documentation on: how to deploy a unikernel today. This
discussion came up during our meeting about the imaginary that the participants
may have about MirageOS. Even today, it is quite difficult to find good
(up-to-date) resources about unikernels. Only blogs (like mine) and a few
scattered resources do the job but don't appear in what many consider, rightly,
the first entry point: [mirage.io][mirage.io].

It is certain that albatross is perhaps the most pleasant way to deploy a
unikernel with Solo5. The tool offers more and more possibilities and, as far as
I'm concerned, I've been using it for more than a year and a half and I'm very
satisfied. I hope that the tool will finally have a nice documentation to
facilitate the deployment of unikernels.

In any case, Hannes finally presented us the tool, our reproducibility service
(you can read a tutorial [here][reproducibility] written by yours truly) and how
to use it, notably via TLS. And so, orchestrate your unikernels remotely! In
short, I advise you to keep an eye on it!

### [Ca-tty][catty], an IRC client as an unikernel

This is my project! The idea remains quite simple. After SMTP, IRC remains my
second big project that I would like to finalize. Being an IRC user, the
systematic constraint I have is to be able to launch an IRC client on a server
in order to stay connected and to be able to aggregate logs and operate an
asynchronous discussion (even if emails remain the best for this kind of use).
At robur, we also use IRC to communicate with each other.

It's a protocol that stands the test of time quite well and is quite accessible
in terms of resources - you can even chat via IRC directly with `gnutls-cli` if
you want - no need to install an huge application...

From this constraint, I thought that a unikernel that would be launched and act
as an IRC client would be a very interesting use case. The project led me to be
interested in a lot of things that I hadn't really experimented with in the
past. In particular the use of [`notty`][notty] and [`lwd`][lwd] for all things
User Interface. An extension of [awa-ssh][awa-ssh] was also necessary and I got
to PoC very quickly.

I finally managed to connect to a server, join a channel and send (or receive)
messages! I still have to deal with multiple channels and how to integrate this
properly with `lwd` which imposes some (correct) constraints but which can
totally change the way the project is organised!

The project also allows me to complete my implementation of the IRC protocol.
One day I will be able to implement an IRC server as a unikernel!

#### A talk from Profpatsch

Profpatsch did a great talk about IRC and one of its [weechat][weechat] clients.
It was quite interesting for people other than me (who has been using IRC for
too long) who: 1) didn't know about IRC 2) didn't see the point when solutions
like Slack or Discord exist.

And I agreed with everything he said and it's always cool to let others present
what they like and exchange without me, Hannes or Reynir (the robur.io members)
intervening. It's always the idea that the authorities have to disappear to make
room for everyone.

![gibraltar](../images/tanger03.jpg)

### [geohash][geohash]

[mro][mro] gave us a presentation of geohash, its design and the calculation
used to go from a geoposition to a hash. He came with a simple objective: to
package his software. It was quite interesting because he asked a lot of
questions related to the distribution of a software.

For me, the exchange we had focused on a static and portable software
distribution. There are a lot of solutions, we can talk about [musl][musl],
[DKML][dkml] or [Esperanto][esperanto]. I think all these approaches are
different. In my case and **my** objectives, and especially in relation to what
I have done, Esperanto seems to me the right solution. Nevertheless, the
portability cursor is wider than 2 solutions.

What I liked most was the very minimalist vision of what software should be:
running on limited resources, somewhat hostile contexts, etc. This is, in my
opinion, a good approach: the constraint puts forward some very interesting
solutions I think.

More generally, I observed a lot of interaction between mro and the other
participants. This retreat was able to bring in people whose experience could
really help mro - and that's really cool!

### MirageOS & proxmox

I also had quite a few discussions with Patrick. With him and also during the
meeting about the future of MirageOS, one issue came to light: how to deploy
MirageOS. I am still in this situation where my deployment method is a "real
fraud". For example, the series of articles on how to deploy an SMTP server is
clearly not what I consider to be a good solution.

I advised him to look at the MirageOS "virtio" target and try to integrate that
into [proxmox][proxmox]. As it stands, it seems to me that he has managed to do
this, which confirms what we thought was technically possible (although
[Kate][kit-ty-kate] did come back with [a bug][halt-bug] about it!). But from
what I understand, a "turnkey" solution would be perfect given the lack of
documentation on the subject. From my point of view, [robur.io][robur.io] and
more specifically [builds.robur.io][builds.robur.io] offers such documentation -
but it doesn't match the "first entry-point" for new users.

I really hope Patrick can go further on the subject and try to get a DNS
resolver like unikernel<sup>[3](#fn3)</sup>! It is certain, however, that the
problem exists and, in fact, persists.

<hr>

<tag id="fn3">**3**</tag>: At the previous retreat, Jan Midtgaard already had
the idea to make a DNS resolver on RPi4. I really think the idea is good and the
work needed is not that much - as far as support on Solo5 is concerned.

There is clearly something to be done here. As far as RPi4 is concerned, the
story would be more complex as we still don't have an Ethernet driver...

### Irmin fix

Simon came with an idea in mind: to understand Irmin. Since the project is
basically a MirageOS project, one would think that the MirageOS retreat would be
a good place to learn and understand Irmin with the right people. In reality,
and in the unikernels we develop at robur.io, using Irmin may not be our highest
priority (where we would prefer to use [git-kv][git-kv]).

It's also true that at some point, members of the Irmin team came to our
retreats and I myself worked with them on a lot of things. However, at this
session, they were not there.

So we had a discussion about this particular situation where we rather tried to
remove Irmin from our projects (and gain a size on our unikernels).

Nevertheless, he did a pull-request on the project and the Irmin team answered
him quite quickly. I hope he enjoyed the atmosphere and met some good people.

## Conclusion

![gibraltar](../images/tanger05.jpg)

Again, although this list shows all the interesting and challenging work that
came out of this retreat, it does not detract from the fact that we shared a
good time above all. The atmosphere of the Riad, of what Hana and Siam have been
organising for many years with Hannes and even of the regular participants of
the event who are always nice to see again, makes me say that we can be proud of
the result. Anyway, I haven't mentioned everything and everyone involved, but
you can be sure that everyone was necessary and useful to this event.

As a conclusion, I would like to emphasize the idea that the MirageOS retreat is
first and foremost about creating a community. You can put a lot of ideas behind
the word "community". You can also put a lot of goals behind it, including
personal goals that some of us can identify with. But there is a downside to the
word "community": I've seen, in other conferences, other events, different goals
that are more aligned with something credulous than social. This is clearly not
the case at the MirageOS retreat where, from the feedback I've had, it's
particularly relaxing, informative and above all fun.

I hope in any case that all the participants have found their place during this
particular moment and can have a good memory of it saying later: I was there!

I invite all people who basically also want to meet us, meet other people from
other backgrounds, open up to something else interesting that will certainly not
make you rich, you can come to the next retreat and we will be delighted to have
you participate in this community :) !

[banawa]: https://github.com/reynir/banawa-chat/
[reynir]: https://github.com/reynir
[engil]: https://github.com/Engil
[sonja]: https://github.com/pitag-ha
[lucas]: https://github.com/TheLortex
[gilbraltar]: https://github.com/dinosaure/gilbraltar
[antonin]: https://github.com/MisterDA
[ocamlrun]: https://github.com/MisterDA/ocamlwalk
[paul-elliot]: https://github.com/panglesd
[jules]: https://github.com/Julow
[git-comments]: https://bollu.github.io/the-hilarious-commentary-by-dinosaure-in-ocaml-git.html
[codept]: https://github.com/Octachron/codept
[octachron]: https://github.com/Octachron
[albatross]: https://github.com/roburio/albatross
[hannes]: https://hannes.nqsb.io/
[mirage.io]: https://mirage.io
[reproducibility]: reproducible.html
[notty]: https://github.com/pqwy/notty
[lwd]: https://github.com/let-def/lwd
[awa-ssh]: https://github.com/mirage/awa-ssh
[weechat]: https://weechat.org/
[geohash]: https://code.mro.name/mro/geohash
[mro]: https://mro.name/blog
[dkml]: https://github.com/diskuv/dkml-installer-ocaml
[esperanto]: https://github.com/dinosaure/esperanto
[musl]: https://musl.libc.org/
[proxmox]: https://www.proxmox.com/de/
[kit-ty-kate]: https://github.com/kit-ty-kate
[halt-bug]: https://github.com/Solo5/solo5/issues/499
[robur.io]: https://robur.io/
[builds.robur.io]: https://builds.robur.io
[git-kv]: https://github.com/roburio/git-kv
[solo5]: https://github.com/solo5/solo5
[banawa-article]: https://reyn.ir/posts/2023-05-17-banawa-chat.html
[cardio-crumble]: https://github.com/pitag-ha/cardio-crumble
[catty]: https://github.com/roburio/catty
