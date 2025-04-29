---
date: 2024-08-23
title: Httpcats, a simple HTTP server/client in OCaml
description:
  Another yet http client/server in OCaml
tags:
  - OCaml
  - HTTP
  - ecosystem
---

I'm delighted to announce the release of httpcats, a new http client/server with
our Miou scheduler. It's available here and is already being used by friends who
have given me some feedback on the API, bugs and performance.

In short, httpcats is the culmination of several attempts by our cooperative to
have even one satisfactory client. This had already begun with our opam-mirror
unikernel, where the use of CoHTTP and Conduit was clearly unsatisfactory for
us. The codebase was complex, the way to build our unikernel was not at all
obvious (depopts & `(select ...)`), there was also a question about the support
of several protocols (notably h2). We also wanted to take advantage of our
happy-eyeballs project to manage domain name resolution and the TCP/IP
connection to these services. http-{lwt,mirage}-client was born.

We also finally found a way of correctly abstracting the protocols underlying
HTTP and Git, namely: TCP/IP, TLS or SSH. This was the case with what was
initially intended to replace Conduit: mimic.

In short, behind the question of the HTTP protocol, there are a number of
experiments on several fronts, such as the development of applications that
simply want to make HTTP requests, but also the abstractions needed for the
development of unikernels.

In this respect, my experience and my evolution in the OCaml community have long
been marked by the subject of the HTTP protocol:
- starting in the Ocsigen team to support CoHTTP
- being actively involved in the development of CoHTTP at one time
- helping companies improve libraries for communicating with AWS
- wishing to improve Conduit in relation to the uses of CoHTTP users as well as
  our own
- having participated in the http/af project (via angstrom & faraday) and also
  contributed to h2
- by developing a precise and satisfactory solution for mirage with paf
- and trying to come up with something satisfactory for the future with httpcats

What I'd like to stress is that I'm clearly no stranger to what's going on in
the community as far as the HTTP protocol is concerned. There have been
attempts, successes and failures but this has enabled us to better describe our
needs and produce solutions that are certainly not perfect but which have the
merit of working, being used and stabilising with the passage of time.

httpcats is perhaps the spearhead of what we are trying to produce through our
cooperative and the work, which may be scattered over several projects (such as
mirage-crypto, ocaml-tls or happy-eyeballs), is quite substantial and is based
at all levels on the needs of the community (and is not limited to our
objectives).


## Functors & performances

### Unikernel & abstraction

### Implications

## Conduit & interface

### Real application & unikernels

### A deterministic choice of protocol implementations

## Web & protocols

### DNS

### Happy-eyeballs

## Fork & community

### Httpaf

## Miou & benchmarks
