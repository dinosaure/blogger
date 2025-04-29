---
date: 2024-11-04
title: A cache for mmap() and improve carton
description:
  How we should iterate when it's about optimisation
tags:
  - PACKv2
  - Git
  - Optimisation
  - OCaml
---

This article will be a succession of possible changes in my Carton bookshop. In
our PTT project, we would like to use Git's compression method (PACKv2 format)
to archive emails. There has been talk of updating the libraries that implement
the SMTP protocol. Today we're talking about updating the cardboard package!

## Context

We won't go into detail about the PACKv2 format, but it has a fairly impressive
compression ratio when it comes to documents such as code, HTML or simple text -
in fact, one experiment enabled us to compress the documentation (150 GB)
produced from the OCaml ecosystem into a 250 MB PACK file. We think it would be
interesting to reuse this format for emails with the same type of content (if we
don't take attachments into account).

So we're going to use Carton, which was specially designed to manage Git PACK
files: encode and read them. However, although this library has been doing a
good job for some time now, we may need to update it with a more experienced eye
than the version I wrote 4 years ago.

It mainly involves 2 jobs:
- an API job, which isn't all that necessary as Carton offers everything we need
  (but propose something simpler to use)
- optimisation work in view of the context in which OCaml evolves

This article will focus on optimisation and the choices I can make (or not make)
with regard to Carton and the results I can obtain.

## Int64

This is perhaps the most crucial question: to use or not to use `Int64`. PACK
files can be very large and very quickly exceed the limit of an `Int31` (~ 2
GB). I mention `Int31` because an `Int63` is more than enough to browse through
most of the files you can find (you can manage files of up to 1 TB). `Int31` is
the limit as soon as you use a 32-bit architecture and want to use OCaml.

So we're faced with a fairly simple question: do we want to be able to manage
large files in a 32-bit architecture using OCaml?

In addition, Carton uses an `Int64` as a cursor in the PACKv2 file but tries to
use native integers as much as possible.
```ocaml
type slice =
  { offset : int64
  ; length : int
  ; payload : bigstring }
```

Even if this solution seems to half solve the problem, the fact remains that
going from an `Int64` to a native integer (which can be done without any problem
as long as the conversion is done at the right time) is a real pain.
```ocaml
let offset = Int64.(to_int (sub cursor slice.offset)) (* good *)
let offset = Int64.to_int cursor - Int64.to_int slice.offset (* bad *)
```

In fact, the benefit of `Int64` is becoming increasingly minor, especially when
you consider that OCaml tends to work only on 64-bit architectures.

So let's jump on the bandwagon and get rid of `Int64` and use native integers
that we would consider to be `Int63` by default.
```ocaml
let _max_int31 = 2147483647L (* (1 << 31) - 1 *)

let load_pack_file filename =
  let fd = Unix.openfile filename Unix.[ O_RDONLY ] 0o644 in
  let stat = Unix.LargeFile.fstat fd in
  if Sys.word_size = 32
  && stat.LargeFile.st_size > _max_int31
  then Fmt.failwith "Impossible to handle %a on 32-bits machine" filename;
  ...
```

## Cache

If we look at how the PACK file is implemented in Git, there is a cache system
that loads parts (or 'pages') of the file to decode it and extract the Git
objects.

Initially, Carton uses the Weak module to take advantage of 'weak' pointers in
order to load the pages needed to decode Git objects if we really need them.
```ocaml
type 'fd t =
  { mutable cur : int;
  ; w : slice Weak.t;
  ; max : int
  ; sector : int64 (* 4096 *) }

and slice = { offset : int64; length : int; payload : bigstring }
and 'fd map = 'fd -> pos:int64 -> int -> bigstring

let heavy_load : type fd. map:fd map -> fd t -> int64 -> slice option =
 fun ~map t w ->
  let pos = Int64.(div w t.sector) in
  let pos = Int64.(mul pos t.sector) in
  let payload = map t.fd ~pos (Int64.to_int t.sector) in
  let slice = Some { offset = pos; length = Bigstringaf.length payload; payload } in
  Weak.set t.w (t.cur land 0xffff) slice;
  t.cur <- t.cur + 1;
  slice

let load : type fd. map:fd map -> fd t -> ?len:int -> int64 -> slice option =
 fun ~map ?(len= 1) t cursor ->
  let max = Weak.length t.w in
  let rec go idx =
    if idx = max then heavy_load ~map t cursor
    else match Weak.get t.w idx with
    | Some ({ offset; length; _ } as value) ->
      if cursor >= offset
      && (cursor < Int64.(add offset (of_int length)))
      && (length - Int64.(to_int (sub cursor offset))) >= len
      then value else go (succ idx)
    | None -> go (succ idx) in
  go 0
```

It might be interesting to use the Weak module and it's easy to see how it could
be just what we need for a cache system. However, a cache with Weak can become
problematic when it comes to predictability. This is because the behaviour of
our cache would depend on the GC (which could free resources), whose behaviour
is just as obscure (especially in the case of a library that is integrated into
an application - which itself follows a certain memory management with the GC).

In truth, Weak is interesting for sharing values whose construction can easily
be determined but is not suitable for a cache system where control of its
behaviour and the memory it uses are more important.

Let's try something simpler then!
