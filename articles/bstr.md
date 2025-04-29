---
date: 2025-04-29
title: Bstr, a synthetic library for bigstrings
description:
  A small library to manipulate bstr
tags:
  - OCaml
  - Ecosystem
---

Based on our experience with cstruct and the various improvements we have made,
it was time to synthesise our experience into two libraries, paving the way for
a more consolidated ecosystem.

Indeed, our various feedback in terms of performance and usage led me to
seriously reconsider cstruct and propose a library that would be the synthesis
of everything I have learned about bigarrays.

## Why bigarrays?

We could take a radical approach to bigarrays and simply remove them from all
our libraries, reconsidering the use of bytes instead, as we did for
[mirage-crypto][mirage-crypto-0.11.3].

However, this overlooks the advantages of bigarrays and the context in which we
might need to use them.

At the time, I gave [an exhaustive answer][bigstring-vs-bytes] on the value of
bigarrays, concluding that the context in which we should use them depends on
each individual's objectives. Four years later, I still maintain that the use
of bigarrays really depends on what you want to do.

In reality, we always need bigarrays. The fact that they cannot move during a GC
cycle is very interesting, particularly when it comes to multicore OCaml:
bigarrays can literally be seen as spaces shared between domains (as is the case
with [parmap][parmap]).

When it comes to unikernels (and system programming in general), it is quite
common to want to communicate with ‘devices’ in a specific memory area, which
in the OCaml world can only be achieved with a bigarray.

Finally, we can also mention [io_uring][io_uring], for which only bigarrays can
be committed to the kernel for reading and writing.

The approach, as we have [said][tar-cstruct] several times, is actually to
clarify the use of bigarrays rather than systematise it. In other words, use
them when there is a real advantage to doing so, but switch to manipulating
bytes and strings as soon as possible when the opportunity arises.

## Bigstringaf & Astring

In the world of OCaml, when it comes to byte sequences, two libraries remain
fairly widely used: [Bigstringaf][bigstringaf] and [Astring][astring]. The
first is specifically for bigarrays, while the second offers a whole host of
useful functions for manipulating byte sequences.

I started working on Cstruct by adding many of Astring's functions [to the
Cstruct] library in order to make it easier to manipulate bytes (and possibly
parse a byte sequence).

However, I had two criticisms of these two libraries:
- `astring` does not support bigarrays (hence the integration of these functions
  into Cstruct)
- `bigstringaf` has some gaps in the functions it offers and also lacks an
  interesting function: [overlap][overlap].

On a more personal note, `Bigstringaf` is quite long to write, but that is
purely subjective.

The fact is that a mix of these libraries specifically for bigarrays (without
necessarily including the idea of Slice introduced by Cstruct) could be
interesting. That's why, when developing [Cachet][cachet], a synthesis of
Bigstringaf and Astring would have been perfect, because I could have just
copied the code I had already written for [decompress][decompress] when it came
to providing a way to manipulate bigarrays in OCaml.

That's how I came up with the idea of developing Bstr. It's a very small
library that attempts to provide everything that Bigstringaf lacks and
everything that Astring offers, but for bigarrays. Bstr also offers an
`overlap` function and even attempts to be more efficient than Bigstringaf,
since other annotations concerning FFI have appeared since Bigstringaf was
released.

<table>
  <tr>
    <th></th>
    <th>bigstringaf</th>
    <th>bstr</th>
    <th>cstruct</th>
  <tr>
    <td><code>blit_from_string</code</td>
    <td>5.1ns</td>
    <td>4.3ns</td>
    <td>4.7ns</td>
  </tr>
</table>

One last thing I wanted to offer is the ability to do a memmove/memcpy while
notifying the GC that this operation can be executed in parallel with a cycle
without any problems, as we integrated [into digestif][gc-digestif] a long time
ago.

Bstr is therefore a synthesis of what can be obtained from bigarrays and what
the OCaml ecosystem has to offer. Ultimately, I hope that this library will
become part of the standard OCaml library. Significant work has been done on
testing (coverage is 81%) and documentation.

## Cstruct

Currently, we still use Cstruct quite extensively, but we would like to use it
less and less. We have a few walls such as mirage-tcpip, but overall, since our
experience with mirage-crypto, we are aware of how to properly replace Cstruct
with bytes and strings.

However, as a major contributor to Cstruct, this library remains a good library
offering several functions that can help with manipulating Cstructs and
bigarrays. But fundamentally, Cstruct is really necessary because `Cstruct.sub`
is perhaps the most interesting (but also the fastest) function that this
library has to offer.

The problem is that Cstruct, more generally recognised as a _Slice_, only
applies to bigarrays, where we might want to replace it with bytes, as Hannes
[attempted][hannes-no-bigarray] to do.

There are several possible solutions to this question:
1) we can functorise the code
2) we can use an ADT
3) or a GADT

But in practice, and given what can be done with OCaml in terms of
optimisation, having abstract code in a module and replicating it for bigarrays
and bytes (a poor man's functor, in essence) remains the most interesting
solution.

Slice is therefore a small library offering an implementation with bigarrays
and an implementation with bytes. It is then possible to switch from one to the
other, provided that Slice.map exists.

Several experiments have been conducted in this regard and are available here:
[buffet][buffet]. Thanks to our [Bechamel][bechamel] project, it is now fairly
easy to produce micro-benchmarks and compare implementations. Furthermore,
`Slice.sub` remains as efficient as `Cstruct.sub`, which is perhaps the most
important factor.

<table>
  <tr>
    <th></th>
    <th>bigstringaf</th>
    <th>bstr</th>
    <th>cstruct</th>
    <th>slice</th>
  <tr>
    <td><code>sub</code</td>
    <td>20.0ns</td>
    <td>17.8ns</td>
    <td>2.8ns</td>
    <td>2.4ns</td>
  </tr>
</table>

Thus, combining Bstr and Slice once again provides an interesting synthesis of
what Bigstringaf, Astring and Cstruct have to offer, with the advantage of also
offering this Slice type for bytes without any performance cost (due to
functorisation).

## Conclusion

The next step consists mainly of going back and forth on the API in order to
offer something that is essentially useful in all the cases we have encountered
since the development of unikernels and our libraries. This API work may
therefore take some time.

But the ultimate goal is to be able to offer at least one Bstr module for
`ocaml/ocaml`. This will involve making a proposal in the form of an RFC and
reaching a consensus with everyone.

This short article presents not only this library but also its long-term goal.

[bigstring-vs-bytes]: https://discuss.ocaml.org/t/buffered-io-bytes-vs-bigstring/8978/3?u=dinosaure
[mirage-crypto-0.11.3]: https://discuss.ocaml.org/t/ann-mirage-crypto-0-11-3-with-more-speed-for-elliptic-curves-and-the-future-roadmap-of-mirage-crypto/14200#release-0113-2
[parmap]: https://github.com/rdicosmo/parmap
[tar-cstruct]: https://blog.robur.coop/articles/tar-release.html#conclusion-about-cstruct
[io_uring]: https://en.wikipedia.org/wiki/Io_uring
[hannes-no-bigarray]: https://github.com/hannesm/ocaml-cstruct/tree/no-bigarray
[cstruct-astring]: https://github.com/mirage/ocaml-cstruct/pull/277
[overlap]: https://github.com/dinosaure/overlap
[decompress]: https://github.com/mirage/decompress
[cachet]: https://github.com/robur-coop/cachet
[gc-digestif]: https://github.com/mirage/digestif/pull/70
[buffet]: https://github.com/dinosaure/buffet
[bechamel]: https://github.com/mirage/bechamel
[astring]: https://github.com/dbuenzli/astring
[bigstringaf]: https://github.com/inhabitedtype/bigstringaf
