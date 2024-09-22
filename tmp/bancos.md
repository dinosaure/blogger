---
date: 2024-08-19
title: Bancos, a persistent KV-store in OCaml
description:
  How to implement a persistent KV-store in OCaml 5
tags:
  - database
  - parallelism
  - persistent
---

I've been interested in datastructures for quite some time now, and in
particular in their application to databases. Indeed, from my experience with
Git, Irmin or what I've seen with littlefs or even ocaml-tar, I've always wanted
to have a high-performance KV-store that could be used for other purposes
(linked both to email indexing and to the implementation of services such as IRC
with the implementation of a distributed database with Raft). In short, dreams
that require a certain amount of work to become reality.

With this in mind, I initially came across this research paper which gives a
fairly global view of KV-stores today (in terms of performance on several
aspects: memory usage, speed, etc.) and I was particularly interested in the ART
structure, of which I've made an OCaml implementation available here.

The latter did its job (having already tried other structures) by outperforming
search and insertion compared with a simple Hashtbl.t - some will note that the
key must absolutely be a string, but others will choose a way of serializing any
value to use it as a key.

In short, I put this project on the back burner for a while, but since I had
funding to implement a mailing-list where keyword-based e-mail searches were
necessary, I threw myself back into it, which enabled me to produce bancos: a
simple KV-store allowing parallel read and write access.

## Adaptive Radix Tree
