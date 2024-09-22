---
date: 2020-02-06
title: Hello World!
description:
  My first article which explains the goal of this blog
tags:
  - OCaml
---

Hello World! I'm Romain Calascibetta and this is my blog/notes about what I do
with my computer. It's mostly about MirageOS stuff where I did some work on it
and I want to use it for everything.

Currently, I took a *bare-metal* server to be able to virtualize my unikernel
with KVM. This server uses currently 4 unikernels:

- an intern DNS resolver
- a primary DNS server for <strike>x25519.net</strike>osau.re
- a paste service [pasteur](https://paste.osau.re/)
- this blog

Of course, I'm not an *admin-sys* and even if I trie to use my work, I suspect
that the way to deploy my unikernels is not the best. But, eh, it's work.

### The purpose of this blog

It's hard to follow resources about MirageOS like *"how to make an unikernel"*
or *"how to plug a data-store"*, etc. The MirageOS ecosystem is quite large and
sporadic. My goal is not to provide *the* way to make your unikernel but try to
describe some ways.

### MirageOS & OCaml

Of course, as an OCaml developer, I will talk about OCaml mostly and what we
currently do with this language and MirageOS.

### Some others notes

And because it's my blog, I can write what I want. Excuse me for my english,
I'm french and it can be hard for me to translate all of my mind in english.
