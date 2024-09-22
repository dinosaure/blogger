---
date: 2022-11-14
title: Reproducibility!
description:
  How we can manage reproducibility in OCaml
tags:
  - OCaml
  - Reproducible
  - Build
  - MirageOS
---

Reproducibility! You may not have noticed, but [Robur](https://robur.coop) has
done a lot of work on several levels to provide an infrastructure to ensure the
reproducibility of your applications (and our unikernels).

But before going into the details of such an infrastructure, we need to define
what reproducibility is and what problems we are trying to solve.

I would like to say that I am only a user of this infrastructure (available
[here](https://builds.robur.coop)). Since I arrived at Robur (beyond the
countless projects I want to do), one of my goals has been to:
1) really deploy unikernels
2) use them
3) ensure their reproducibility
4) use the artefacts produced in my unikernel infrastructure
5) (bonus) monitor these unikernels (which will be the subject of another
   article)

I would like to give special thanks to Robur and its initial team (to which I
have added myself) who not only created this infrastructure but also helped me
in all the steps of deployment on my server. And if I had to add a small stone
to the edifice, it would of course be this article which is meant to explain
this infrastructure.

# What does reproducibility mean?

Reproducibility is a **deterministic** build process where one ensures, from the
sources and a build environment, to produce the same binary byte per byte.

In fact, the difficulty of reproducibility is not so much in the OCaml code or
in the OCaml compiler (which itself remains very deterministic) but in the build
environment. In particular, variables such as date, language or paths need to be
normalized.

---

### The OCaml compiler

Hannes remarks that "the OCaml compiler" story is a bit longer - and depends on
the definition of reproducibility (with robur and orb, we e.g. always build in
the same path, as the same user -- also intermediate build products
(cma/cmxa/...) are not taken into consideration). There were reproducibility
issues in the OCaml runtime, which have been fixed:
- [Binaries are not reproducible](https://github.com/ocaml/ocaml/issues/7037)
  - [`ocamldoc` fix](https://github.com/ocaml/ocaml/pull/321) (from Debian)
  - [don't put temporary file names into object files](https://github.com/ocaml/ocaml/commit/eef84c432a4fcecc83f02d81b347cf819c69df9f)
  - [fix `Location.input_name` setting](https://github.com/ocaml/ocaml/pull/862)
- Unix `sort` output depends on language set
  - [ocaml/ocaml#898](https://github.com/ocaml/ocaml/pull/898)
  - [ocaml/ocaml#8986](https://github.com/ocaml/ocaml/pull/8986)
  - [ocaml/ocaml#10333](https://github.com/ocaml/ocaml/pull/10333)
- [Custom runtime embed temporary file name](https://github.com/ocaml/ocaml/pull/1845)
- Build path prefix map (to allow reproducible builds with different paths)
  - [ocaml/ocaml#1515](https://github.com/ocaml/ocaml/pull/1515)
  - [ocaml/ocaml#1856](https://github.com/ocaml/ocaml/pull/1856)
  - [ocaml/ocaml#1830](https://github.com/ocaml/ocaml/pull/1930)
- [`*.cma` is not reproducible](https://github.com/ocaml/ocaml/issues/9307),
  fixed by [ocaml/ocaml#9345](https://github.com/ocaml/ocaml/pull/9345) (also
  [ocaml/ocaml#9991](https://github.com/ocaml/ocaml/pull/9991))

All these patches are related to values that cannot be set by the environment
(such as the date), the use of temporary files (such as OCaml-generated assembly
files), the non-deterministic behaviour of some Unix tools (such as `sort`)
which may depend on the system language, or the absolute paths in artefacts
which should be able to be reduced to relative paths (one might want to compile
the same file in `foo/` and then in `bar/` without this altering the
compilation). Finally, the production of *.cma seemed to correspond to
non-deterministic behaviour of the system.

It is worth noting that Debian has been very forward-thinking on the issue of
reproducibility and that most of these patches have been notified from the
Debian bug tracker. Indeed, they have decided to make all Debian packages
reproducible since 2013. The OCaml team has set this goal as well.

From my point of view, and the resulting patches, reproducibility is still a
matter of details. Basically, the majority of these patches don't change what
the compiler does globally, but specify the pipeline a bit more so that it is
reproducible.

---

Nevertheless, if such an environment exists, what really interests the developer
in this phase is not so much the result obtained but a tool that can:
1) verify this reproducibility in their development
2) be notified of sources that may alter the reproducibility of their software

From a "releaser" point of view, it is indeed this reproducibility that
interests us since it is what we want to distribute. But, as I said, the
difficulty is not here, since it is a matter of freezing a build context - of
course, it is still a big job to freeze such a context.

But from the point of view of a developer - who is therefore iterating in their
code - it is mainly a question of recognising what can alter the build process
in order to really identify what it depends on.

In this respect, ensuring a deterministic build and normalising the elements
that can intervene in the build process and thus creating a build context is
only one step. The other step is to be able to identify the elements that can
alter the reproduction process. Indeed, this build context must be exhaustive
but can be extremely broad. Thus, reproducibility does not only concern the
result but also the tools that can help to prove this reproducibility.

Such a tool would ensure that the project is replicable on a daily basis. It
would provide a complete description of a build context. Unfortunately, whether
as a developer or as a user, this context can change (for example, via an
update). In this respect, the tool must be able to:
- disqualify elements that do not alter our build
- notify us if our daily process is no longer reproducible and why (e.g. list
  the elements that have changed compared to the last build to help us
  understand why our software is no longer reproducible)

## Why does reproducibility matter?

There are many reasons for wanting reproducibility and these reasons are not the
same depending on which hat we wear. Indeed, reproducibility does not answer the
same problems for a developer as for a releaser. Nevertheless, if we were to
crystalize the interest in reproducibility into a more general concept, it would
be trust.

As far as a developer is concerned, their job is, among other things, to fix
bugs. The problem is to find the bug: where does it come from? This is where the
archaeological work begins, starting with our code. However, bugs can exist
outside our code. They can appear in the libraries we use. Worse, they can
appear in the libraries that the libraries we use use... But the question
becomes eminently complex when two developers try to find the same bug. This
situation arises when one of them says: "It works for me". In this case, we are
much more likely to consider that the bug does not come from our code but from
the underlying dependencies we use: we can see that the software is not
reproducible since from one computer to another, the behaviour is different for
the same code. This is where the question arises: can we trust our workflow to
build our software?

For a releaser, the problem can be even more serious. The release process
consists of building the software and then distributing it. We talked about
"freezing" this build context above. However, as a releaser, have we really
taken into account all the dependencies (and security patches) in order to
produce a single piece of software? One could legitimately ask the question
whether our build computer would not be infected, or whether it really takes
into account all security updates. The releaser must then make an exhaustive
audit of what they need to build the software. If reproducibility is not
assured, this means that this "frozen" context is not exhaustive and that there
are in fact two larger contexts (of which the first is only a subset) that do
not produce the same software. Where is the difference? Why is there a
difference? What is the impact of this difference (about security)? All these
questions bring us back to the trust that we place in this context, can I trust
such a context to be sure that I have a deterministic production of my software?

Finally, reproducibility also concerns the user. Downloading software or an
executable carries a risk - a risk of infection, piracy, etc. A user who
downloads your software trusts you. Now the question is: where does this trust
come from? It can come from the beers you share together to remake the world, or
it can come from a transparent and repeatable process that the user can repeat
to ensure that your distributed software is the software you built (no added
malicious code, an exhaustive dependency graph that can be audited, etc.).

As we have said, reproducibility reaffirms the bond of trust that can exist in
the software production chain from developer to user. One can legitimately say
that all these steps are not fundamentally necessary (and one could even
question the usefulness of these for an end user) but one must conceive the idea
that the notion of security of a software and particularly the notion of trust
that one grants to a software is above all and for something that is built.

It is certainly not something established (like saying: look! my software is
secure!). It's about giving proofs that will never affirm that our software is
secure but will give signals and reasons why you should trust us.

## `orb`

`orb` is the initial tool that will both launch the build and aggregate the
information to define this famous context. From the latter, the user wants to
restart the build and:
1) show for a different context (an update), the software remains the same
2) ensure that for the same context, the software remains the same
3) notify differences if 2 contexts do not produce the same software

In detail, `orb` expects an OPAM package which is rather straightforward for
OCaml software. Indeed, one can introspect the reproducibility at several
levels. One could aggregate the hashes of all `*.cmx` and be sure that compiling
`N` caml objects produces a deterministic result. But it is above all a notion
of cursor that is at stake. As we said, the OCaml compiler is quite
deterministic, should we really consume computation time for a result that we
already know _a priori_?

Introspecting reproducibility at the level of caml objects would surely be a
waste of time. Where compilation becomes complex is when it interacts with other
elements:
- a C compiler to compile the C files
- an external dependency such as a *.so
- the use of external tools in the construction of our dependencies (like sed,
  awk, etc.)

Thus, the granularity of what can break the reproducibility of our software is
not found in the compiler, nor in `dune` for example but more in the
dependencies: the packages.

It is quite simple to use, only OPAM is needed. `orb` will create a temporary
switch and will try to compile your package in this switch. Let's take the
example of [`hxd`][hxd]:
```shell=bash
$ opam pin add https://github.com/roburio/orb.git -y
$ orb build hxd
[ORB] using root "/home/dinosaure/.opam" and switch "orb228afdtemp"
[ORB] Switch orb228afdtemp created!
[ORB] Install start
[ORB] Install hxd
[ORB] Installed hxd
[ORB] tracking map got locks
[ORB] got tracking map, dropping states
[ORB] writing $PWD/hxd.build-hashes
[ORB] cleaning up
[ORB] Switch orb228afdtemp removed
[ORB] cleaning up
```

This build created several files: `build-environment`, `opam-switch`,
`system-packages` and `hxd.build-hashes`. This is our context and its expected
output (the hash of the various objects installed). We can then rebuild from
this context with `orb rebuild`:
```shell=bash
$ orb rebuild .
[ORB] environment matches
[ORB] Switch orb228afdtemp created!
[ORB] now importing switch
[ORB] Switch orb228afdtemp imported!
[ORB] tracking map got locks
[ORB] got tracking map, dropping states
[ORB] writing $PWD/hxd.build-hashes
[ORB] comparing with old build dir no
[ORB] It is reproducible!!!
[ORB] cleaning up
[ORB] Switch orb228afdtemp removed
```

As we expected, our software is reproducible in a specific context. It is quite
expected that software released in OCaml is reproducible in a general way. `hxd`
is even simpler as it is only OCaml and has very few dependencies.

So reproducibility from a defined state in a fixed time has been assured. But
what is really interesting for us is to know if this reproducibility continues
to exist even though the ecosystem evolves. Indeed, an update of `cmdliner` for
example can lead to an alteration in the code produced and in this case, our
reproducibility is no longer assured. But identifying these elements that evolve
in spite of ourselves and that have an impact on our software requires
meticulous and repetitive work.

`orb` helps us to make this work meticulous by aggregating for us the elements
involved in the compilation of our software. Let's move on to the repetition.

## `builder`

What we are talking about here can be defined as a Continuous Integration
infrastructure where this reproducibility check should take place on a daily
basis. CI is a real problem in itself, but our use of it is quite simple, it can
even be likened to a CRON task that would call `orb` daily.

The question is more about the deployment of such an infrastructure. This is
where [`builder`](builder) comes in. It is basically a daemon that will ask
workers to run `orb`.

The communication between this daemon and the workers is done through the
`ASN.1` protocol (just like `albatross`). Again, Robur has done an excellent job
that goes far beyond creating such software. Indeed, as said, the problem here
is the deployment and distribution of `builder` and `builder-worker`
incorporating the necessary elements to interface well with `systemd` (for
Debian) or FreeBSD. And to enable the launch of `orb`, we simply use `docker` to
launch Ubuntu, install `orb` and run the command. 
```shell=bash
$ curl -fsSL https://apt.robur.coop/gpg.pub | gpg --dearmor > /usr/share/keyrings/apt.robur.coop.gpg
# echo "deb [signed-by=/usr/share/keyrings/apt.robur.coop.gpg] https://apt.robur.coop ubuntu-20.04 main" > /etc/apt/sources.list.d/robur.list
/ replace ubuntu-20.04 with e.g. debian-11 on a debian buster machine
$ sudo apt update
$ sudo apt install builder
$ sudo systemctl start builder
$ sudo systemctl start builder-worker
```

### A local OPAM repository

In what defines your context, it has of course the OPAM deposit. For real use of
`orb` and `builder`, the most interesting thing is to manage your own OPAM
repository to put your software in before releasing it publicly.

One could simply use the OPAM tool, which makes it fairly easy to deploy a new
repository. It would then be a matter of adding this repository to the platforms
that `builder` can handle. But I think you are used to my taste for unikernels:
so why not use a unikernel as an OPAM repository?

[`opam-mirror`][opam-mirror] is a good project that allows, from a Git
repository, to offer an OPAM repository as `opam.ocaml.org`. The unikernel is
very simple, it is an HTTP server with a cache system that synchronizes with a
Git repository. The idea is to create our own Git repository and then deploy our
unikernel. We won't do all the steps and especially the build step, Robur has
its own reproducibility infra in which `opam-mirror` is proposed:
[latest opam-mirror from builds.robur.coop](https://builds.robur.coop/job/opam-mirror/build/latest)

We're not going to play around with `solo5-hvt` either, but directly use
`albatross` which is available from the Robur APT repository:
```shell=bash
$ sudo apt install albatross
$ sudo systemctl start albatross_daemon
```

If you haven't done so, a unikernel needs a virtual "bridge" in order to connect
to it. Usually, you add these lines to `/etc/network/interfaces` (a restart of
the networking service is required afterwards):
```
auto service iface service
  inet manual up ip link add service-master address 02:00:00:00:00:01 type dummy
  up ip link set dev service-master up
  up ip link add service type bridge
  up ip link set dev service-master master service
  up ip addr add 10.0.0.1/24 dev service
  up ip link set dev service up
  down ip link del service
  down ip link del service-master
```

Fortunately, we do not need to communicate with the outside world and the
outside world does not need to communicate with our unikernel (we could, but
that is not the point). The `iptables` rules are therefore not necessary!

Now we need to create a Git "server". In fact, from a Git perspective, only our
SSH server is required. We just need:
1) create a Git user
2) add our public keys to `.ssh/authorized_keys`
3) create a Git repository with `git init --bare` in the $HOME folder of Git

```shell=bash
$ sudo adduser git
$ su git
$ cd
$ mkdir .ssh && chmod 700 .ssh
$ touch .ssh/authorized_keys
$ chmod 600 .ssh/authorized_keys
$ mkdir opam-repository.git
$ cd opam-repository.git
$ git init --bare
```

A [question][ocaml-git-question] was asked about SSH and `ocaml-git` keys. Our
workflow for unikernels is to generate a _in-the-fly_ SSH key (in order to
separate the use of our repository by our unikernels and our own use). By
default, we generate an RSA SSH key with `awa_gen_key` (available via the OPAM
package `awa`). This gives 2 lines:
1) a seed to regenerate the private key from the Fortuna engine
2) the public key in the format expected by SSH

```shell=bash
$ awa_gen_key
seed is pUxPne3bfhuihCPH3VhJtjm2/NIM5ooQndXUc5Ey
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDdwvJJ5Z/GaKWoRJcf5jrY952emqlNao+ZUtzkuUExjEp979YdH0oc/LfWDOJrWHeP64RgpY2CUatDJ1WxVUeDpH8sOH/szNAXbozjKUV9XPUae96rk44M5xABGl/Z5S+uMvOkdeWI3mHrhnjp2apbs1x+qO0J3WGqOZQyryMnkdtu7DSy5Ky1at6FIx/j2ZLO2MVhXrO8lr7EX4dALYJPHSkAwn6t0VqNBe1OCKVphiI2BQMPLeINhq7AQx8DZOyS/d/K8+1nzDFHji2NCBzAEI6pAU/I9xIar5qJzy46qkutZYZ9+755aQDya/CIZeQ7Fq/jeWY06hQowFMHqUYGflQKT+MgZlu+3P7Ipds1vSFUR7nDMzNYIk+2oKAV1cCBvwT0oalV2xZBfrE9RcDKF/TfTjt9FzPNLWXcYafIGlz6I8w2dgLGHxKJUg+Dzqxhts8EjsqcEKPdEUcfByrUwTo/fWN2L+Hc4zhhgiAa4zcszgUjYsvMAZDc4N1Y6YtVXHNoxY1UlEjJY4A+8+TgQAMll8+kLGrBi4XJGwfTP9h6oDYVtb8wnWLQPAUWtJV297HkP1QDhWJrlnZLVbck28QoTJ6yZ6T0aZBKrspJjb689DYChtHAHZZvzwZ6nT5XZKvZQi8H3SMWacvxuGtiWUjJ+CXM3GfNo6joPA2Hxw== awa@awa.local
```

The second line should be copied to the `.ssh/authorized_keys` in Git. The first
one will be transmitted to our unikernel in this way (with `albatross`).
```shell=bash
$ albatross-client-local create --net=service:service --block=tar:opam-mirror --mem=512 \
  mirror mirror.hvt \
  --arg="--ipv4=10.0.0.2/24" \
  --arg="--ipv4-gateway=10.0.0.1" \
  --arg="--remote=git@10.0.0.1:opam-repository.git#master" \
  --arg="--ssh-key=rsa:pUxPne3bfhuihCPH3VhJtjm2/NIM5ooQndXUc5Ey"
```

That's it! All you have to do is add your packages in the OPAM format and the
OPAM repository format. To do this, the root must contain at least a `repo` file
and a `package` folder. Then, to understand the structure of an OPAM repository,
you can take inspiration from [`opam-repository`][opam-repository]. Finally, the
unikernel provides a gateway for it to resynchronise with the Git repository.
```shell=bash
$ git clone git@localhost:opam-repository.git
$ cd opam-repository
$ echo 'opem-version: "2.0"' > repo
$ mkdir packages
$ touch packages/.gitkeep
$ git add repo packages
$ git commit -m "First commit"
$ git push
$ curl http://10.0.0.2/update
```

And yes, there never really was a Git server per se. The idea has always been to
"leave" the authentication management to another protocol (in this case SSH).
There is however a way to have a non-secure Git server with `git daemon` but
this method is deprecated for obvious reasons. This is one of the big changes in
[`ocaml-git` 3][ocaml-git-3], the implementation of the Git protocol is the same
whether it is via TCP/IP, SSH or HTTP. 

## How to launch a reproducible build?

Now we need to inform the templates to build our software from our new OPAM
repository. We will use the `/etc/builder/orb-build.template.ubuntu-20.04`
template for now. 
```diff
diff --git a/a b/b index b3b67a5..f5a99fa 100644 ---
a/a +++ b/b @@ -8,5 +8,5 @@ rm orb.deb
 
 DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends --no-install-suggests -y dh-exec
 
-repos="default:https://opam.ocaml.org"
+repos="default:https://opam.ocaml.org,local:http://10.0.0.2/"
orb build --disable-sandboxing --solver-timeout=600 --switch-name=/tmp/myswitch --date=1589138087 --out=. --repos=$repos %%OPAM_PACKAGE%%
```

Let's say we have released the [`bob`][bob] software with a full description of
its OPAM file in our repository. `builder` provides a `builder-client` tool to
interact with the daemon. Thus, one can add a package to build and reproduce.
The first argument is the name of the software, the second the name of the OPAM
package. 
```shell=bash
$ builder-client orb-build bob bob
```

We can see that a docker image has been launched and is trying to compile our
project now! `builder` will then try to allocate a worker every day to compile
your project. It will keep track of the contexts and compare them to the result
of the build. Thus, as we expected, it will ensure reproducibility and if this
is no longer available, show us the difference that involved altering our
result.

Hannes says: setup this way, orb uses the HEAD of opam-repository, thus it
prepares rolling releases. the output of orb includes exact frozen packages (and
git commits), so they are reproducible.

## `builder-web`

Finally, the last software of this infrastructure is [a website][builder-web] to
make the results available and more digestible through a nice web interface! The
latter will allow to present several information such as:
- the context (a complete description of the required system packages, OPAM
  packages and environment variables)
- the build output (useful when you get a build error)
- the final artifact available for download (very useful for the distribution of
  the software)
- a build history with a diff between each
- a dependency graph
- a graph showing the weight of OCaml modules in the final artifact

This website is also available from the APT repository offered by Robur. Thus,
it can be easily installed and deployed. One particular point should be noted
however.

`builder` just tries to reproduce your software but as far as its distribution
is concerned (notably on the website), it makes us specify where to upload the
artefacts. So we need to change the way `builder` is launched a little.

In this, `builder-web` has a little user management (to protect access to the
upload). So we also create a user for `builder-web` (with a password) and inform
`builder` to use it. 
```shell=bash
$ sudo apt install builder-web
$ sudo builder-db migrate
$ sudo builder-db user-add dinosaure --unrestricted
Password: foo
$ sudo systemctl start builder-web
```

And finally, we must modify `/usr/lib/systemd/system/builder.service` with:
```diff
9c9
< ExecStart=/usr/bin/builder-server
---
> ExecStart=/usr/bin/builder-server --upload http://dinosaure:foo@localhost:3000/upload
```

That's it! You have a website available at `http://localhost:3000/` on which
there is an aggregate of all your builds - with all the information needed to
prove/reproduce your software.

## Conclusion

You will note that all this software is reproducible and available (beyond APT)
on Robur's infra: https://builds.robur.coop/. In fact, the software on APT is
the same as on the Robur's infra. The package repository at `apt.robur.coop` is
fed by the daily builds, and all the above mentioned software (`orb`, `builder`,
`builder-web`, `albatross`) are reproducible and are daily build -- thus
subscribing to the package repository enables you to get the latest package with
an update.

For my part, I deployed the infrastructure on my side in order to be able to
distribute my famous Bob software (and make it reproducible). Then I made a
small update to Contruno so that it could redirect TLS connections from
[`builds.osau.re`](https://builds.osau.re) to `builder-web`. So, my
infrastructure is available here (and 2 unikernels, `contruno` and `opam-mirror`
are involved).

In fact, once you understand how `orb`, `builder`, `builder-worker` and
`builder-web` work, you can see that: 1) these solutions can be composed with
other solutions which does not make them monolithic - this is my preferred
approach 2) it is actually quite easy to deploy these tools - the only barrier
is the lack of documentation and where to start but this article tries to
address that issue 3) the result is nice! It didn't take me long to try to
reproduce Bob (who, however, has a rather complex build because of Cosmopolitan)

For its usefulness, its simplicity and the result, I take the liberty of
advertising it since it is a project that finally brings a lot to the
development of software, its distribution and the release process.

It is a project that can also be articulated with `albatross`. I haven't tested
it yet but imagine: you have packages about your unikernels (which is possible
since `mirage` produces an OPAM file of your project) which you add to your
local repository and then ask `builder` to ensure reproducibility. You could
then ask albatross to get the Solo5 images from this infrastructure! And
apparently this is possible - but I haven't tested it yet.

The issue of APT (and more generally, the distribution of software outside the
OPAM world) becomes just as simple. Again, the process is not clearly identified
but it is clear that Robur is taking advantage of its infrastructure to maintain
an APT repository available on Debian and Ubuntu.

More generally, such an infrastructure helps to build trust between users and
developers. This is all the more true in the case of Bob, which is ultimately
just a big binary. As mentioned in the introduction, one can always wonder about
the risks involved in downloading a binary and running it on one's computer. To
this legitimate question, I answer: reproducibility

[orb]: https://github.com/roburio/orb
[hxd]: https://github.com/dinosaure/hxd
[builder]: https://github.com/roburio/builder
[opam-mirror]: https://github.com/roburio/opam-mirror
[opam-repository]: https://github.com/ocaml/opam-repository
[bob]: https://github.com/dinosaure/bob
[builder-web]: https://github.com/roburio/builder-web
[ocaml-git-question]: https://discuss.ocaml.org/t/irmin-examples-or-pointers-of-interacting-with-remote-repositories-esp-using-authentication-via-ssh/10648
[ocaml-git-3]: https://github.com/mirage/ocaml-git/pull/395
