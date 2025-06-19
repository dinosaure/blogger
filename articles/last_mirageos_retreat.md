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
   [dream-mirage][dream-mirage], **@gasche**'s [hyperfine][hyperfine] project,
   discussions on the MirageOS scheduler (with lwt) for **@gasche** and
   **@Armael**, a [uxn][uxn] interpreter made by **@profpatsch**, and a little
   bit of [mollymawk][mollymawk] with **@PizieDust**.

So I definitely didn't slack off during this retreat!

## A new HTTP stack, [httpcats][httpcats], [vif][vif] & [hurl][hurl]

I haven't talked much about this project at the retreat, but I think the work
done with [**swrup**][swrup] and myself deserves a little explanation.

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
unikernels and our applications). To this end, I resumed the work that
**@hannesm** had started on [http-lwt-client][http-lwt-client], which, in my
opinion, remains the most _efficient_ HTTP client. In addition, Kate started
using `httpcats` and gave me some feedback so that she could implement a
unikernel for [downloading torrents][mirage-torrent]. As development continued,
I started offering a tool similar to `httpie` but in OCaml, called [hurl][hurl]
(first proposed by Hannes).

<style type="text/css">
.ansi2html-content { white-space: pre-wrap; word-wrap: break-word; font-size: 0.8em; }
.body_foreground { color: #DCDCCC; }
.body_background { background-color: #000000; }
.inv_foreground { color: #000000; }
.inv_background { background-color: #AAAAAA; }
.inv_foreground { color: #000000; }
.inv_background { background-color: #AAAAAA; }
.ansi1 { font-weight: bold; }
.ansi32 { color: #60B48A; }
.ansi34 { color: #506070; }
.ansi35 { color: #DC8CC3; }
.ansi36 { color: #8CD0D3; }
</style>

<pre class="ansi2html-content">
<span class="body_foreground">$ hurl https://httpbin.org/post -m POST foo=bar foor==bar -p ish</span>
<span class="ansi35">3.89.78.94</span>:<span class="ansi32">443</span>
<span class="ansi34">TLS 1.2</span> (<span class="ansi36">h2</span>) with <span class="ansi35">ECDHE RSA AEAD AES128 GCM</span>
<span class="ansi36">:status</span>: 200
<span class="ansi36">date</span>: Tue, 03 Jun 2025 09:07:02 GMT
<span class="ansi36">content-type</span>: application/json
<span class="ansi36">content-length</span>: 449
<span class="ansi36">server</span>: gunicorn/19.9.0
<span class="ansi36">access-control-allow-origin</span>: *
<span class="ansi36">access-control-allow-credentials</span>: true
 
<span class="body_foreground">$ hurl https://httpbin.org/post -m POST foo=bar foo==bar -p b | jq</span>
<span class="ansi1">{</span>
  <span class="ansi1 ansi34">"args"</span><span class="ansi1">:</span> <span class="ansi1">{</span>
    <span class="ansi1 ansi34">"foo"</span><span class="ansi1">:</span> <span class="ansi32">"bar"</span>
  <span class="ansi1">}</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"data"</span><span class="ansi1">:</span> <span class="ansi32">"{\n  \"foo\": \"bar\"\n}"</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"files"</span><span class="ansi1">:</span> <span class="ansi1">{}</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"form"</span><span class="ansi1">:</span> <span class="ansi1">{}</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"headers"</span><span class="ansi1">:</span> <span class="ansi1">{</span>
    <span class="ansi1 ansi34">"Content-Length"</span><span class="ansi1">:</span> <span class="ansi32">"18"</span><span class="ansi1">,</span>
    <span class="ansi1 ansi34">"Content-Type"</span><span class="ansi1">:</span> <span class="ansi32">"application/json"</span><span class="ansi1">,</span>
    <span class="ansi1 ansi34">"Host"</span><span class="ansi1">:</span> <span class="ansi32">"httpbin.org"</span><span class="ansi1">,</span>
    <span class="ansi1 ansi34">"User-Agent"</span><span class="ansi1">:</span> <span class="ansi32">"hurl/0.0.1-30-g2f2a549"</span><span class="ansi1">,</span>
    <span class="ansi1 ansi34">"X-Amzn-Trace-Id"</span><span class="ansi1">:</span> <span class="ansi32">"Root=1-683ebb46-486e6acb3c21a3cc5f802d8a"</span>
  <span class="ansi1">}</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"json"</span><span class="ansi1">:</span> <span class="ansi1">{</span>
    <span class="ansi1 ansi34">"foo"</span><span class="ansi1">:</span> <span class="ansi32">"bar"</span>
  <span class="ansi1">}</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"origin"</span><span class="ansi1">:</span> <span class="ansi32">"213.245.183.59"</span><span class="ansi1">,</span>
  <span class="ansi1 ansi34">"url"</span><span class="ansi1">:</span> <span class="ansi32">"https://httpbin.org/post?foo=bar"</span>
<span class="ansi1">}</span>
</pre>

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
an HTTP connection to this protocol. This is where **@swrup** did [an excellent
job][h1-ws]! We met up several times in Paris and worked together, then shared
a beer in a small bar near Bastille.

An interesting point is the various benchmarks I ran with `httpcats` and the
comparisons with `eio+http/af`. The [latest one from April][benchmark] proves
that `httpcats` (and Miou) offers an HTTP server with the lowest latency. It
would probably take another article to explain this, but the choices that
structured Miou with the goal of having a scheduler that could implement
services and unikernels are increasingly being confirmed!

<style>
.bench table, th, td {
  border: 1px solid black;
  border-collapse: collapse;
}
</style>
<table class="bench">
<tr><th></th><th>http/af+lwt</th><th>httpun+eio</th><th>httpcats</th></tr>
<tr><td>8 clients, 8 threads</td><td>19.05us</td><td>327.14us</td><td>32.54us</td></tr>
<tr><td>512 clients, 32 threads</td><td>8.5ms</td><td>1.88ms</td><td>1.07ms</td></tr>
<tr><td>16 clients, 16 threads</td><td>29.75us</td><td>808.30us</td><td>39.22us</td></tr>
<tr><td>32 clients, 32 threads</td><td>39.21us</td><td>1.23ms</td><td>64.83us</td></tr>
<tr><td>64 clients, 32 threads</td><td>425.44us</td><td>1.26ms</td><td>124.32us</td></tr>
<tr><td>128 clients, 32 threads</td><td>250.84us</td><td>1.15ms</td><td>263.56us</td></tr>
<tr><td>256 clients, 32 threads</td><td>2.51ms</td><td>1.25ms</td><td>471.59us</td></tr>
<tr><td>512 clients, 32 threads</td><td>10.83ms</td><td>1.89ms</td><td>0.98ms</td></tr>
</table>

In short, we have completed `httpcats` with websocket support, and now we want
to offer a kind of _framework_ for developing websites. We are therefore
currently developing [Vif][vif].

The latter is a web framework, but it has the particularity of using Miou. As
such, and for the sake of completeness, I have started working with
**@paukerdal** [Miou support][caqti-miou] for [caqti][caqti]. The idea that
Miou can easily execute tasks in parallel has also allowed **@paukerdal** to
find [some bugs][caqti-bugs], as was the case for us with `mirage-crypto`.

Another unique feature of Vif is that it takes advantage of recent work by OCaml
to offer a native [`ocamlnat`][ocamlnat] REPL. The idea is to be able to write
an OCaml script that acts as a web server and simply run that script with Vif.
Of course, Vif is also (and above all) a library that offers several functions
for implementing your web server.

```ocaml
#require "vif" ;;

open Vif ;;

let default req server () =
  let field = "content-type" in
  let* () = Response.add ~field "text/html; charset=utf-8" in
  let* () = Response.with_string req "Hello World!\n" in
  Response.respond `OK
;;

let routes =
  let open Vif.U in
  let open Vif.R in
  let open Vif.T in
  [ get (rel /?? nil) --> default ]
;;

let () = Miou_unix.run (Vif.run routes) ;;
```

```shell
$ vif --pid vif.pid main.ml &
$ hurl http://localhost:8080 -p b
Hello World!
$ kill -SIGINT $(cat vif.pid)
```

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

## [`miou-solo5`][miou-solo5] & unikernels

Two years ago, we started the [Miou][miou] project: a simple scheduler to
implement our services and unikernels. Now, [miou-solo5][miou-solo5] has
appeared: a specialisation of the Miou core for [Solo5][solo5]. The idea is to
"plug Miou's scheduler with Solo5's _hypercalls_". In itself, this work is not
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

This is ultimately an opportunity to use [utcp][utcp], **@hannesm**' library
whose state machine has been proven using [HOL4][hol4].

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

```ocaml
let () = Miou_solo5.(run []) @@ fun () ->
  print_endline "Hello World!"
```

```shell
$ cat dune-workspace
(lang dune 3.0)
(context (default))
(context (default
 (name solo5)
 (host default)
 (toolchain solo5)
 (merlin)
 (disable_dynamically_linked_foreign_archives true)))
$ cat dune
(executable
 (name main)
 (modules main)
 (modes native)
 (link_flags :standard -cclib "-z solo5-abi=hvt")
 (libraries miou-solo5)
 (foreign_stubs (language c) (names manifest)))

(rule
 (targets manifest.c)
 (deps manifest.json)
 (enabled_if (= %{context_name} "solo5"))
 (action (run solo5-elftool gen-manifest manifest.json manifest.c)))

(rule
 (targets manifest.json)
 (enabled_if (= %{context_name} "solo5"))
 (action
  (with-stdout-to manifest.json (run %{exe:main.exe}))))
$ dune build ./main.exe
$ solo5-hvt _build/solo5/main.exe --solo5:quiet
Hello World!
```

In short, `miou-solo5` is still a trial balloon, but it remains very
interesting. I therefore proposed a [short talk][miou-solo5-talk] during the
retreat and continued to experiment with the workflow, notably with
**@MisterDA** and **@zapashcanon** on two different projects.

We will therefore continue in this direction and ask ourselves the right
questions based on our experience in developing unikernels in order to propose a
better workflow. At some point, we will propose a unikernel using OCaml 5 and
`miou-solo5` that can offer a service (and a service such as NTP remains a
feasible objective) and test it in a real context.

### Benchmark & profiling

**@cfcs**, who used to work at Robur, is back! I've been enjoying the long
conversations I used to have with **@cfcs** at night, just before going to bed.
We talked a lot about `miou-solo5` and some considerations on the workflow that
such a project can now offer in terms of unikernel development.

However, one issue we had already encountered with **@reynir** is the profiling
of a unikernel. How can we identify functions that could potentially slow down
the execution of a unikernel? The problem is that a unikernel exists and runs in
a different space than the host system, and tools such as `perf` are unusable.

My first attempt was to also provide an executable during the compilation of
the unikernel that could _act_ as a unikernel. All you have to do is specify
the devices needed for execution and launch the "unikernel" with `perf`. We have
metrics, but the problem is that we need to differentiate between the
`miou-solo5` used in our executable and the one used in our unikernel, as they
do not behave in the same way. However, it is essentially the metrics relating
to our application that interest us, rather than the scheduler itself.

```shell
$ cat profiling.json
{ "devices": [],
  "type": "miou.solo5.profiling",
  "version": 1 }
$ MIOU_PROFILING=profiling.json perf record dune exec ./main.exe
$ perf report
```

However, **@cfcs** and I discovered the existence of `perf-kvm`! **@cfcs** set
to work finding a way to make the unikernel addresses correspond to symbols and
let `perf-kvm` collect the metrics and finally render the results of these
metrics understandable to humans according to the layout of the unikernel. He
ended up with a convincing result with `miou-solo5` and a series of black magic
commands such as `nm` and a particularly well-ordered set of options for
`perf-kvm`.

## A WebAssembly interpreter as a unikernel

**@zapashcanon** has just finished his [thesis][leo-thesis] on the symbolic execution of WebAssembly (Wasm) OCaml. I invite you to read his thesis and watch [and old talk][leo-talk]. He gave us a more recent talk where he explains how he found a bug in Rust and [Typst][typst] concerning floats.

During his thesis, he implemented an interpreter that performs concrete, symbolic, or concolic execution of Wasm: in other words, you can execute Wasm in OCaml thanks to [Owi][owi].

The idea was to integrate this interpreter into an unikernel. We would pass the Wasm code through a "block device" and let our unikernel execute the code. The idea is very interesting, so we first tried to link the `owi` code with an unikernel.

This took us a day because we had to remove all instances of the `Unix` module (**@zapashcanon** had already done most of the work, only a few functions were missing).

Then **@zapashcanon** was able to execute some fairly simple Wasm code in the unikernel! I think it was a factorial. This confirmed that:
1) the concrete execution was working;
2) we could start thinking about running slightly more complex code.

So we went for [SQLite][sqlite]! Perhaps a little too complex, but there is an
[export of the SQLite code to Wasm][sqlite-wasm], and we wanted to see:
1) what SQLite needs (`malloc(3)`, `mmap(3)`, `read(3)`, etc.);
2) what SQLite exports for use.

```shell-session
$ wasm2wat sqlite3.wasm > sqlite3.wat
$ rg "import" sqlite3.wat
(import "env" "__syscall_faccessat" (func (;0;) (type 6)))
(import "wasi_snapshot_preview1" "fd_close" (func (;1;) (type 1)))
(import "env" "emscripten_date_now" (func (;2;) (type 39)))
(import "env" "_emscripten_get_now_is_monotonic" (func (;3;) (type 15)))
(import "env" "emscripten_get_now" (func (;4;) (type 39)))
(import "env" "__syscall_fchmod" (func (;5;) (type 0)))
(import "env" "__syscall_chmod" (func (;6;) (type 0)))
(import "env" "__syscall_fchown32" (func (;7;) (type 2)))
(import "env" "__syscall_fcntl64" (func (;8;) (type 2)))
(import "env" "__syscall_openat" (func (;9;) (type 6)))
(import "env" "__syscall_ioctl" (func (;10;) (type 2)))
(import "wasi_snapshot_preview1" "fd_write" (func (;11;) (type 6)))
(import "wasi_snapshot_preview1" "fd_read" (func (;12;) (type 6)))
(import "env" "__syscall_fstat64" (func (;13;) (type 0)))
(import "env" "__syscall_stat64" (func (;14;) (type 0)))
(import "env" "__syscall_newfstatat" (func (;15;) (type 6)))
(import "env" "__syscall_lstat64" (func (;16;) (type 0)))
(import "wasi_snapshot_preview1" "fd_sync" (func (;17;) (type 1)))
(import "env" "__syscall_ftruncate64" (func (;18;) (type 11)))
(import "env" "__syscall_getcwd" (func (;19;) (type 0)))
(import "wasi_snapshot_preview1" "environ_sizes_get" (func (;20;) (type 0)))
(import "wasi_snapshot_preview1" "environ_get" (func (;21;) (type 0)))
(import "wasi_snapshot_preview1" "fd_seek" (func (;22;) (type 21)))
(import "env" "__syscall_mkdirat" (func (;23;) (type 2)))
(import "env" "_tzset_js" (func (;24;) (type 8)))
(import "env" "_localtime_js" (func (;25;) (type 64)))
(import "env" "_munmap_js" (func (;26;) (type 35)))
(import "env" "_mmap_js" (func (;27;) (type 47)))
(import "env" "__syscall_readlinkat" (func (;28;) (type 6)))
(import "env" "__syscall_rmdir" (func (;29;) (type 1)))
(import "env" "__syscall_unlinkat" (func (;30;) (type 2)))
(import "env" "__syscall_utimensat" (func (;31;) (type 6)))
(import "wasi_snapshot_preview1" "fd_fdstat_get" (func (;32;) (type 0)))
(import "env" "emscripten_resize_heap" (func (;33;) (type 1)))
```

**@zapashcanon** extracted the functions needed by SQLite, and now it was a matter of implementing them. The concrete execution of the code would therefore need a module implementing the functions required by SQLite (basically POSIX), and these are typed using a GADT (thanks **@chambart**). We first implemented these functions with an `assert false`.

Finally, thanks to `owi` again, we can request to execute a specific function that SQLite exports, so we tried [`sqlite3_open`][sqlite3-open]. We also needed to prepare some allocations for SQLite, so we used `malloc(3)`.

At this point, we started to see something interesting. We observed what SQLite wanted to do and implemented the entire execution path so that SQLite could generate a random number using [mirage-crypto][mirage-crypto] under the hood.

Due to time constraints, we couldn't go any further. But we did the bulk of the work. Now we need to implement the functions required by SQLite one by one. In total, SQLite only requires about thirty functions. That's not very many, and even though there are functions like `ioctl` and `mkdir`, SQLite3 ultimately only needs one file. The idea of a file system is not fundamentally required.

The project is available here: [weed][weed]. The prospects for this project are very interesting. It is conceivable to execute Wasm code _on demand_ in a closed environment such as a unikernel. We will therefore try to take this further with **@zapashcanon**!

## [`ocaml-git`][ocaml-git], [`git-kv`][git-kv] and the old version of me

It can be quite dizzying at times to see the work you've done after 10 years in the OCaml community. One of the projects I've worked on the most is [ocaml-git][ocaml-git].

My first task was to generate a PACK file so that we could clone, fetch or push to a Git repository. This also involved implementing the [Smart protocol][smart] and negotiation between two Git instances.

This work was interesting but probably driven by all kinds of experiments so that [ocaml-git][ocaml-git] could still be integrated into a unikernel. There were several abstraction issues:
- abstraction of the scheduler
- abstraction of the hash algorithm
- abstraction of the protocol underlying the transmission of Smart packets

As such, `ocaml-git` was more of a space for iterating on several abstraction techniques (functors, first class modules, record as first class modules, [HKT][hkt] or [mimic][mimic]). Some of these techniques proved their usability, while others did not. This is particularly the case for functors and [High Kinded Polymorphism][hkt].

The problem is that I recently decided to update [carton][carton] (which manages PACK files) and it got rid of functors and HKT. So I had to extend this work to `ocaml-git` in order to deploy our unikernel [opam-mirror][opam-mirror] for the retreat.

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

```ocaml
let or_fail = function
  | Ok value -> value
  | Error (#Git_kv.error as err) -> Fmt.failwith "%a" Git_kv.pp_error err

(* How to push a new file [/foo] into a Git repository. *)
let run () =
  let* ctx = Git_net_unix.ctx (Happy_eyeballs_lwt.create ()) in
  let* store = Git_kv.connect ctx "git@github.com:robur-coop/git-kv.git" in
  let* result = Git_kv.change_and_push store @@ fun store ->
    let* result = Git_kv.set store (k "/foo") "Hello World!" in
    let () = or_fail result in
    Lwt.return_unit in
  let () = or_fail result in
  Lwt.return_unit
```

In the end, I avoided the regression that I could have easily convinced myself
would happen if it were just `ocaml-git`. I also removed the functors and HKT
without any problems. So now we have a small library, `git-kv`, which does the
essentials: clone, fetch, push, and keep a Git repository in memory in the
context of unikernels.

**@hannesm** and I finally tried `opam-mirror` again with the new version of
`git-kv` and, after a few minor bugs, everything worked! It was just a shame
that we couldn't launch `opam-mirror` until the end of the retreat. We use it
in particular to limit Internet consumption when downloading software via OPAM.

This experience also confirms that I am much more comfortable with OCaml and
have more confidence in myself when it comes to making design and API choices.
So thank you, [ocaml-git][ocaml-git]!

## UDP, NTP protocol & unikernel

One unikernel that could be interesting is a secondary NTP server. The NTP
protocol is fairly simple, consisting of a UDP packet that can take the form of
a request (between a client and a server) or a response (between a server and a
client).

```ocaml
type t =
  { flags : int
  ; stratum : stratum
  ; poll : int
  ; precision : int
  ; root_delay : int32
  ; root_dispersion : int32
  ; refid : int32
  ; reference_ts : Ptime.t option
  ; origin_ts : Ptime.t option
  ; recv_ts : Ptime.t option
  ; trans_ts : Ptime.t option }
```

This requires implementation of the UDP protocol, which is also fairly simple.
If you have followed my article [on TCP and miou-solo5][miou-solo5-ip], the
layers underlying UDP are already available. All that remains is to specify the
ports and build the packet.

```ocaml
type state

val create : IPv4.t -> state

val recvfrom :
     state
  -> ?src:Ipaddr.V4.t
  -> port:int
  -> ?off:int
  -> ?len:int
  -> bytes
  -> int * (Ipaddr.V4.t * int)

val sendto :
     state
  -> dst:Ipaddr.V4.t
  -> ?src_port:int
  -> port:int
  -> ?off:int
  -> ?len:int
  -> string
  -> (unit, [> `Route_not_found ]) result

val handler : state -> IPv4.packet * IPv4.payload -> unit
```

The difficulty with the NTP protocol lies not so much in the protocol itself
but in how the results are interpreted. The basic idea is quite simple. It
consists of recording the time the NTP packet is sent (\\(t_{1}\\))and the time
it is received (\\(t_{4}\\)). This received NTP packet contains the time
according to the primary server, and a calculation must be made to determine our
time difference (where \\(t_{2}\\) and \\(t_{3}\\) correspond to `rx.recv_ts`
and `rx.trans_ts`).

$${\displaystyle \theta ={\frac {(t_{1}-t_{0})+(t_{2}-t_{3})}{2}}}$$

Now, there may be several issues with this method, which is the main one for
recalibrating our clock (a task I had already started [here][utime]). Since the
packet comes from the network, there may be delays (dividing by 2 is based on
the idea that the sending time is equal to the receiving time, which is not
really the case).

Furthermore, we may not necessarily trust the time given by a primary server,
but rather multiply the sources of information and combine them.

In this regard, a comparative analysis of the sources via linear regression
would allow us to choose the best source of information. This shows above all
that the complexity of the NTP protocol mainly concerns the underlying
algorithms for choosing the right source and recalibrating the unikernel clock.
I will therefore continue working on this topic and will certainly write an
article about it later.

At least the UDP protocol is implemented, which was necessary for my initial
goal of implementing QUIC.

## Others projects

The retreat is also (and above all) a time for mutual support. Even though I am
focused on project development, I have also helped people around me (as best I
can) to move forward with their projects.

### mirage-www and dream

Having partly [supported Mirage for Dream][dreamos], I worked with **@hannesm**
to help **@Willenbrink** revive the [`mirage-www`][mirage-www] project and
ensure that it compiles. I hope that **@Willenbrink** has a clear understanding
of the current state of `mirage-www`, but above all, he has shown patience and
a willingness to listen in order to achieve his goal without getting
discouraged.

The problems encountered are well known and concern
[`opam-monorepo`][opam-monorepo] in particular. I should perhaps write an
article on this subject to explain its origins...

In any case, his work was completed after quite a battle with `opam-monorepo`,
and he finally managed to compile a unikernel with Dream!

### [`progress`][progress] and **@gasche**

**gasche** is developing a small tool, a bit like [`hyperfine`][hyperfine], to
obtain metrics on the execution time of a program. One aspect of `hyperfine` is,
of course, the way it displays the work in progress via a progress bar!

That's when I advised him to use [`progress`][progress], a library developed by
**@CraigFe** that I maintain today. He quickly found some bugs (as always) and
proposed [a patch][progress-patch].

### [UXN][uxn] and Solo5

**@profpatsch** alrady did some retreats before. However, he is not actively
involved in OCaml. That's also part of the magic of retreats: talking to people
who are somewhat outside the world of OCaml.

In fact, he had an idea in mind when he saw the work **@zapashcanon** and I were
starting on a WebAssembly interpreter in the form of a unikernel, and he
started interpreting [UXN][uxn] (which I discovered thanks to him).

So I gave him a few pointers about Solo5, and he ended up creating a C
unikernel that can interpret UXN with Solo5!

## Conclusion

This article is clearly not exhaustive of everything that happened during the
retreat. Several people gave talks on topics not necessarily related to OCaml,
which were very interesting.

Others worked on projects that I didn't necessarily participate in, but I'll
leave them the opportunity to write an article like mine.

What is certain is that everyone was satisfied at the end. The retreat remains
a very good experience, and we can thank Hannes and Hana for taking the time to
organise it. In short, we will continue this experience in the coming years.
There are some challenges ahead (such as renting a venue), but we can work
together to find a solution — at least, that would be in keeping with the spirit
of the retreat.

[quic]: https://datatracker.ietf.org/doc/rfc9000/
[miou-solo5]: https://github.com/robur-coop/miou-solo5
[weed]: https://github.com/dinosaure/weed
[carton]: https://github.com/robur-coop/carton
[email-archive]: https://blog.robur.coop/articles/2025-01-07-carton-and-cachet.html
[ocaml-git]: https://github.com/mirage/ocaml-git
[git-kv]: https://github.com/robur-coop/git-kv.git
[dream-mirage]: https://github.com/mirage/dream/pull/1
[hyperfine]: https://github.com/sharkdp/hyperfine
[uxn]: https://100r.co/site/uxn.html
[mollymawk]: https://github.com/robur-coop/mollymawk
[httpcats]: https://github.com/robur-coop/httpcats
[vif]: https://github.com/robur-coop/vif
[hurl]: https://github.com/robur-coop/hurl
[ocsigen]: https://github.com/ocsigen
[cohttp]: https://github.com/mirage/ocaml-cohttp
[httpaf]: https://github.com/inhabitedtype/httpaf
[h2]: https://github.com/anmonteiro/ocaml-h2
[paf-le-chien]: https://github.com/dinosaure/paf-le-chien
[multipart_form]: https://github.com/dinosaure/multipart_form
[dream]: https://github.com/aantron/dream
[spiros]: https://github.com/seliopou
[ocaml-h1]: https://github.com/robur-coop/ocaml-h1
[http-lwt-client]: https://github.com/robur-coop/http-lwt-client
[mirage-torrent]: https://github.com/kit-ty-kate/mirage-torrent
[http-pros-cons]: https://discuss.ocaml.org/t/simple-modern-http-client-library/11239/14?u=dinosaure
[conduit]: https://github.com/mirage/ocaml-conduit
[conduit-is-dead]: https://blog.osau.re/articles/blog_requiem.html#conduit-tuyau-cohttp-httpaf-and-paf
[swrup]: https://github.com/swrup
[h1-ws]: https://github.com/robur-coop/httpcats/pull/27
[benchmark]: https://discuss.ocaml.org/t/lwt-multi-processing-much-more-performant-than-eio-multi-core/16395/3?u=dinosaure
[caqti]: https://github.com/paurkedal/ocaml-caqti
[caqti-miou]: https://github.com/paurkedal/ocaml-caqti/pull/117
[ocamlnat]: https://github.com/ocaml/ocaml/pull/355
[jsont]: https://github.com/dbuenzli/jsont
[multipart-stream]: https://discuss.ocaml.org/t/ann-release-of-multipart-form-0-2-0/7704
[furl]: https://github.com/Drup/furl
[drup]: https://github.com/Drup
[vif-examples]: https://github.com/robur-coop/vif/tree/master/test/examples
[builder-web]: https://github.com/robur-coop/builder-web
[miou]: https://github.com/robur-coop/miou
[solo5]: https://github.com/Solo5/solo5
[eio-solo5]: https://github.com/TheLortex/eio-solo5
[mirage-tcpip]: https://github.com/mirage/mirage-tcpip
[mirage-crypto-cstruct]: https://blog.robur.coop/articles/speeding-ec-string.html
[utcp]: https://github.com/robur-coop/utcp
[hol4]: https://hol-theorem-prover.org/
[miou-solo5-ip]: https://blog.robur.coop/articles/utcp_and_effects.html
[miou-solo5-talk]: https://github.com/robur-coop/miou-solo5/blob/main/slides/retreat.md
[leo-thesis]: https://arxiv.org/abs/2412.06391
[typst]: https://typst.app/
[owi]: https://github.com/OCamlPro/owi
[sqlite]: https://www.sqlite.org/
[sqlite-wasm]: https://sqlite.org/wasm/doc/trunk/demo-123.md
[sqlite3-open]: https://www.sqlite.org/c3ref/open.html
[mirage-crypto]: https://github.com/mirage/mirage-crypto
[hkt]: https://www.cl.cam.ac.uk/~jdy22/papers/lightweight-higher-kinded-polymorphism.pdf
[irmin]: https://github.com/mirage/irmin
[opam-mirror]: https://github.com/robur-coop/opam-mirror
[mimic]: https://github.com/dinosaure/mimic
[caqti-bugs]: https://github.com/paurkedal/ocaml-caqti/issues/127
[dreamos]: https://github.com/aantron/dream/pull/119
[mirage-www]: https://github.com/mirage/mirage-www
[opam-monorepo]: https://github.com/tarides/opam-monorepo
[mirage-www]: https://github.com/mirage/mirage-www
[progress]: https://github.com/CraigFe/progress
[progress-patch]: https://github.com/craigfe/progress/pull/48
[leo-talk]: https://www.youtube.com/watch?v=x6V-NJ9agjg
[smart]: https://github.com/git/git/blob/master/Documentation/gitprotocol-pack.adoc
