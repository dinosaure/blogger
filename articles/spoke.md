---
date: 2022-06-02
article.title: Spoke, how to implement a little cryptographic protocol
article.description:
  A simple how-to to understand how we implement protocols for MirageOS
tags:
  - OCaml
  - Cryptography
  - Protocol
  - MirageOS
---

I recently discovered [PAKE for Password-Authenticated Key Agreement][pake]. It
is a method of initiating a secure connection based on a password known between
the two people. The key thing to remember here is that the password will never
be disclosed to an attacker through the protocol. A known algorithm is used to
derive a strong shared key from this password.

Of course, to perform this derivation, we still need to share some information.
This is where a feature of the protocol must be ensured: transmitted
information between Alice & Bob must "look" like random content.

Indeed, an attacker can recognise the content (this chunk looks suspiciously
like something used by a well-known  protocol), they can also recognise the
algorithm behind - and they can attempt a brute-force attack of some weak
passwords to regenerate the exchanged chunks.

The exchange must therefore seem random, but it is determined - so that both
parties can finally agree on a strong shared key. Then, from the latter, a
protocol can be established using a symmetric cryptographic method such as
[GCM][gcm] or [ChaCha20 Poly1305][chacha20-poly1305].

<hr />

**Disclaimer**: All the code in this article is for illustrative purposes, a
copy/paste will probably not work and I have deliberately omitted some details
to make it easier to read. The code should therefore be understandable and this
can be a good opportunity to read an implementation (as I usually do) without
referring to its interface.

<hr />

## SPAKE2+EE

There are quite a few implementations of PAKE with subtleties, other guarantees
and specific contexts of use. During my research, the one that interested me
the most was SPAKE2+EE which is similar to SPAKE2+ (for which an [RFC][SPAKE2+]
is being written) but with a small variation that allows us to no longer
require necessary constants during the exchange between Alice & Bob: indeed, if
you look into SPAKE2+, it requires to fix 2 element `M` and `N` in the
primer-order subgroup of a group `G` in which [CDH problem is hard][CDH].

Unfortunately, I am not a crypto-guy and it is certainly difficult for me to go
into details about the security of SPAKE2+ and SPAKE2+EE. However, my research
started with [this resource][SPAKE2+EE] which, in my opinion, explains well the
difference between these two protocols.

For more information about [Elligator 2][elligator] (the EE of SPAKE2+EE, the
Elligator Edition), the idea is to allow group elements to be serialized in a
way that is indistinguishable from uniformly random strings of the same size.
This ensures that it is difficult to recognise, from the point of view of an
attacker, the true meaning of the information exchanged between Alice and Bob.

In this respect, this protocol seems to be very interesting to initiate a
secure connection from a weak password. We will see here how:
1) implement what are called cryptographic primitives 
2) implement the handshake
3) how we end up with a protocol implementation like `Mirage_flow.S` for ease
   of use

## Primitives

Of course, the first step in implementing our protocol are the cryptographic
primitives. We are talking about "primitives" here because it only consists in
doing some very complicated calculations and getting a result.

From the experience we have with [mirage-crypto][mirage-crypto] but also
[digestif][digestif], implementing cryptographic primitives in OCaml remains a
non-option as far as performance is concerned because it is essentially about
manipulating uniform arrays containing `uint32` or `uint64`. Even if OCaml
(flambda?) can optimise this kind of code, C (unfortunately) remains the best
option as far as expressiveness and performance is concerned - indeed, we
wouldn't want the GC to intervene in the middle of a computation...

However, C is still very bad at one thing: allocation and, as far as OCaml is
concerned, interaction between C and the OCaml GC - this is where errors are
most common. So our design is to let OCaml allocates, go into the C world to do
the calculations on what has already been allocated, and then come back into
the OCaml world without us having made a single side-effect.

```ocaml
external xor_into
  : string -> src_off:int -> bytes -> dst_off:int -> len:int -> unit
  = "caml_xor_into" [@@noalloc]

let xor str0 str1 =
  let len = min (String.length str0) (String.length str1) in
  let buf = Bytes.of_string (String.sub str1 0 len) (* allocation *) in
  xor_into str0 ~src_off:0 buf ~dst_off:0 ~len ;
  Bytes.unsafe_to_string buf
  (* [buf] has been allocated locally and never been shared, thus it is safe to
     treat it as string before returning. *)
```

```c
static inline void xor_into (const uint8_t *src, uint8_t *dst, size_t n) {
#ifdef ARCH_SIXTYFOUR
  uint64_t s;
  for (; n >= 8; n -= 8, src += 8, dst += 8)
    *(uint64_t*) dst ^= *(uint64_t*)memcpy(&s, src, 8);
#endif

  uint32_t t;
  for (; n >= 4; n -= 4, src += 4, dst += 4)
    *(uint32_t*) dst ^= *(uint32_t*)memcpy(&t, src, 4);

  for (; n --; ++ src, ++ dst) *dst = *src ^ *dst;
}

#define Bytes_off(buf, off) ((uint8_t*) Bytes_val (buf) + Long_val (off))
#define String_off(str, off) ((uint8_t*) Bytes_val (str) + Long_val (off))

CAMLprim value
caml_xor_into (value src, value src_off, value dst, value dst_off, value len) {
  xor_into (String_off (src, src_off),
            Bytes_off (dst, dst_off),
            Long_val (len));
  return Val_unit;
}
```

This small code shows the design that takes place mostly within mirage-crypto
and digestif. As you can see, the allocation is on the caml side. This allows
us to tag our C function with `[@@noalloc]` (and avoid the generation of the
ceremony necessary to pass from the C world to the Caml world by the compiler)
<sup>[1](#fn1)</sup>. It also allows us to take only what is interesting in the
C world, the computation - that's all we do. Embedding all this in a nice API
shows us what I think is the best thing about OCaml: hiding ugly things behind
a nice interface with much more interesting expressiveness than C.

<hr />

<tag id="fn1">**1**</tag>: We can go even further, since it can be a
side-effect-free calculation, we can notify the GC that this function can
run in parallel with other caml code. Indeed, if the calculation takes place in
a "bigarray", it means above all that this array will never move (by the GC)
and therefore we can "release" the GC lock. This is what was done for
[digestif][digestif-lock] - so it is possible to really run a thread in
(true) parallel to compute a hash to something else.

<hr />

Back to SPAKE2+EE, we need some primitives which we will get from
[libsodium][libsodium]. We'll do the bindings by hand as for `xor_into`:
```ocaml
external ed25519_from_uniform
  : bytes -> dst_off:int -> string -> src_off:int -> unit
external ed25519_scalarmult_base
  : bytes -> dst_off:int -> string -> src_off:int -> unit
external ed25519_add
  : bytes -> dst_off:int -> string -> string -> unit
external ed25519_sub
  : bytes -> dst_off:int -> string -> string -> unit
external ed25519_scalarmult
  : bytes -> string -> src_off:int -> point:string -> bool
```

## SPAKE2+EE handshake, higher primitives

Let's start with a step-by-step explanation of SPAKE2+EE.

Let `G` be a group in which the computational Diffie-Hellman problem is hard.
Suppose `G` has order `p*h` where `p` is a large prime; `h` will be called
the cofactor. We fix a generate `P` of (large) prime-order subgroup of `G`.
More concretely, `x * P = ed25519_scalarmult_base(x)`. `KDF` is a key
derivation function that take our password (and a _salt_) and it generates
few values: `m`, `n`, `k` and `l`. Finally, `E` maps a 32-bytes vector to a
point of which it is guaranteed to be on the main subgroup `G`.

Alice starts to generate our _salt_ and retransmit it to Bob to let him to
regenerate `m`, `n`, `k` and `l` with the shared password. This will be our
first _packet_. This may contain more information such as the algorithm used by
our `KDF` function. We can also take the opportunity to specify at this point
the symmetric encryption algorithms that will be used later.

Bob selects `x` uniformly at random, computes the public share `X`, and
transmits it to Alice. More concretely, `X` will be generate with:
```ocaml
let bob () =
  let x = random () in
  let gx = ed25519_scalarmult_base x in
  let _X = ed25519_add gx (ed25519_from_uniform m) in
  send _X
```

Upon receipt of `X`, Alice checks the received element for group membership and
aborts if `X` is not in the large prime-order subgroup of `G`. We do this check
_via_ `ed25519_scalarmult` which returns a `bool`. Alice then selects `y`
uniformly at random, computes the public share `Y`, and transmits it to the
Bob:
```ocaml
let alice _X =
  let _L = ed25519_scalarmult_base l in
  let y = random () in
  let gy = ed25519_scalarmult_base y in
  let _Y = ed25519_add gy (ed25519_from_uniform n) in
  let gx = ed25519_sub _X (ed25519_from_uniform m) in
  let _Z = scalar () and _V = scalar () in
  (* [scalar] allocates a zero-ed buffer which can be use
     by [ed25519_scalarmult_into] then. *)
  if ed25519_scalarmult_into _Z y gx = true
  && ed25519_scalarmult_into _V y _L = true
  then send _Y
  else abort
```

Upon receipt of `Y`, Bob checks the received element for group membership and
aborts if `Y` is not in the large prime-order subgroup of `G`:
```ocaml
let bob _Y =
  let gy = ed25519_sub _Y (ed25519_from_uniform n)
  if ed25519_scalarmult_into _Z x gy = false
  || ed25519_scalarmult_into _V l gy = false
  then abort
```

Below, you can see all the steps described and what is transmitted. If
everything went well, at the end, we can generate a strong key (with our
function `H`) using `X`, `Y` (which have been on the network), `k` (which is
known only to Bob and Alice), `Z`, `V` (which have been calculated):
```shell
                  Bob                   |                 Alice               
                                        |
                                        | salt <- random()
                                        | m, n, k, l = KDF(password, salt)
                                        |
                               <= transmit salt <=
                                        |
       m, n, k, l = KDF(password, salt) |
                          x <- random() |
                            g^x = x * P |
                     X = g^x + h * E(m) |
                                        |
                                => transmit X =>
                                        |
                                        | L = l * P
                                        | y <- random()
                                        | g^y = y * P
                                        | Y = g^y + h * E(n)
                                        | g^x = x - (h * E(m))
                                        | Z = h * y * g^x
                                        | V = h * y * L
                                        |
                                <= transmit Y <=
                                        |
                   g^y = Y - (h * E(n)) |
                        Z = h * x * g^y |
                        V = h * l * g^y |
                                        |
                              sk = H(X, Y, Z, k, V)
```

### Serialization / de-serialization and isomorphism

Throughout the process, information such as `m`, `n`, `l` and `k` must be kept.
This information may be stored into a database. Such use cases require the
ability to serialise and deserialise this information.

More specifically, as we have said, the first packet can (and should) contain
much more than just the `salt`, it should also contain information such as the
`KDF` function used. Alice's first operation is therefore:
1) generate this "public" packet which will be forwarded to Bob
2) generate an easily serialized/deserialized value to be able to manipulate it
   throughout the handshake, a "secret" value

```ocaml
type 'k aead =
  | GCM : Mirage_crypto.Cipher_block.AES.GCM.key aead
  | ChaCha20_Poly1305 : Mirage_crypto.Chacha20.key aead

type hash = Hash : 'k Digestif.hash -> hash
type cipher = AEAD : 'k aead -> cipher
type 'a algorithm = Pbkdf2 : int algorithm

type secret and public

val generate :
  ?hash:hash ->
  ?ciphers:cipher * cipher ->
  ?g:Random.State.t ->
  password:string ->
  algorithm:'a algorithm -> 'a ->
  secret * public

val public_to_string : public -> string
val public_of_string : string -> (public, [> `Msg of string ]) result
```

Serialization is the very "error-prone" moment (little-endian, big-endian, how
to handle error cases, `x = decode(encode(x))`?) and it is often a matter of
using a tool to help us implement the `of_string`/`to_string` pair without
pain.

For this, and especially when we are looking for isomorphism as a property,
there is [encore][encore]! It allows you to describe a format and derive the
`parse_string`/`emit_string` pair. Thus, **by construction**,
`x = parse_string (emit_string x))`!
```ocaml
val public_format : public Encore.t

let public_to_string v =
  Encore.(Lavoisier.emit_string v (to_lavoisier public_format)

let public_of_string str =
  Angstrom.parse_string ~consume:All (Encore.to_angstrom public_format) str

let assert_encore v =
  assert (v = (Result.get_ok (public_of_string (public_to_string v))))
```

Of course, the definition of the format goes through combinators (in the same
way as [angstrom][angstrom]) which are a bit restrictive (applicative) because
we have to ensure the bijection of each component of the format.
```ocaml
open Encore
open Syntax

let uint16be = Bij.v
  ~fwd:(fun str -> string_get_uint16_be str 0)
  ~bwd:uint16_be_to_string

let uint64be = Bij.v
  ~fwd:(fun str -> string_get_uint64_be str 0)
  ~bwd:uint64_be_to_string

let version = uint16be <$> fixed 2

let algorithm_and_arguments = choice
  [ const "pbkdf2" <*> (uint64be <$> fixed 8) ]

let cipher =
  let cipher = Bij.v
    ~fwd:cipher_of_int
    ~bwd:int_of_cipher in
  (Bij.compose uint16be cipher) <$> fixed 2
  
let hash =
  let hash = Bij.v
    ~fwd:hash_of_int
    ~bwd:(fun (Hash hash) -> int_of_hash hash) in
  (Bij.compose uint16be hash) <$> fixed 2

let salt = fixed 16

let public_format
  : (int * (string * int64) * (cipher * cipher) * hash * string) Encore.t
  = Bij.obj5 <$> (version
                  <*> algorithm_and_arguments
                  <*> (cipher <*> cipher)
                  <*> hash
                  <*> salt)
```

Of course the same applies to "secret" which contains much more information
than "public". "secret" should contain the same information as "public" as well
as the values `E(m)`, `E(n)`, `k`, `L = l * P`.

Finally, one can implement `generate` quite simply without worrying about these
serialization issues. Of course, as far as "secret" is concerned, it is not
strictly necessary to have the `secret_to_string`/`secret_of_string` pair,
but it may be more conventional to provide these functions, especially if you
are storing "secret" in a database.
```ocaml
let keys
  : type a. salt:string -> hash:hash -> string ->
    algorithm:a algorithm -> a -> keys * int64
  = fun ~salt ~hash password ~algorithm arguments ->
  let Hash hash = hash in
  let mnkl = match algorithm with
    | Pbkdf2 ->
      let count = arguments in
      Pbkdf2.generate hash ~password
        ~salt ~count (Int32.of_int (32 * 4)) in
  let h_k = String.sub mnkl 64 32 in
  let h_l = String.sub mnkl 96 32 in
  let _M = ed25519_from_uniform mnkl ~off:0 in
  let _N = ed25519_from_uniform mnkl ~off:32 in
  let _L = ed25519_scalarmult_base mnkl ~off:96 in
  let arguments = match algorithm with
    | Pbkdf2 -> Int64.of_int arguments in
  (_M, _N, _L, h_k, h_l), arguments

type public = string
type secret = string

let generate : type a.
  ?hash:hash -> ?ciphers:cipher * cipher -> ?g:Random.State.t ->
  password:string -> algorithm:a algorithm -> a -> public * secret
  = fun ?(hash= Hash Digestif.SHA256)
        ?(ciphers= AEAD GCM, AEAD ChaCha20_Poly1305)
        ?g ~password ~algorithm arguments ->
  let salt = random_bytes ?g 16 in
  let (_M, _N, _L, _k, _), arguments =
    keys ~salt ~hash password ~algorithm arguments in
  let Hash hash = hash in

  let secret = Format.secret_to_string
    ((version, (pbkdf2, arguments), ciphers, Hash hash, salt),
     (_M, _N, _k, _L)) in
  let public = Format.public_to_string
    (version, ("pbkdf2", arguments), ciphers, Hash hash, salt) in
  secret, public
```

### Others primitives

Let's put aside the question of transmission over the network for a moment and
concentrate again on what is our _handshake_. Alice is able to create a
"public" packet. It is then a matter of letting Bob deserialise it so that he
generates `E(m)`, `E(n)`, `k` and `L = l * P` on its own way. According to what
we have just described, Bob will also have to generate a random `X` value and
send it to Alice.
```ocaml
type ctx =
  { _k      : string
  ; _l      : string
  ; _N      : string
  ; x       : string
  ; _X      : string
  ; ciphers : cipher * cipher }

let hello ?g ~public password : (ctx * string, [> error ]) result =
  match Format.public_of_string public with
  | Error _ -> Error `Invalid_public_packet
  | Ok (_version, (algorithm, arguments), ciphers, Hash hash, salt) ->
    let (_M, _N, _, _k, _l), _arguments =
      match algorithm_of_int (string_get_uint16_be algorithm 0), arguments with
      | Algorithm Pbkdf2, count ->
        let count = Int64.to_int count in
        let algorithm = Pbkdf2 in
        keys ~salt ~hash:(Hash hash) password ~algorithm count in
    let x = random_scalar ?g () in
    let gx = ed25519_scalarmult_base x ~off:0 in
    let _X = ed25519_add gx keys._M in
    Ok ({ _k; _l; _N; x; _X; ciphers },
        _X)
```

On her side, Alice receives `X` and checks that it still belongs to our
subgroup. She generates `Y` and sends it to Bob. This is also where the
handshake can fail. Indeed, `X` must belong to our subgroup and if this is not
the case, it certainly means that we were not expecting such an exchange
between Alice and Bob (and that there could be an attacker). On the other hand,
if all goes well, Alice is now able to generate the shared key - at this point
she has all the information. However, we will initiate a final exchange where
the generation of the shared key will propose "validators" that Bob can check
on his side as well to make sure they both have the same shared key.
```ocaml
let server_compute ?g ~secret ~identity packet =
  match Format.secret_of_string secret with
  | Error _ -> Error `Invalid_secret_packet
  | Ok ((_version, (_algorithm, _arguments), ciphers, _hash, _salt),
        (_M, _N, _k, _L)) ->
    let y = random_scalar ?g () in
    let gy = ed25519_scalarmult_base y ~off:0 in
    let _Y = ed25519_add gy _N in
    let _X = packet in
    let gx = ed25519_sub _X _M in
    let* _Z = ed25519_scalarmult y ~off:0 ~point:gx in
    let* _V = ed25519_scalarmult y ~off:0 ~point:_L in
    let shared_key, validators = shared_key_and_validators
      ~identity _X _Y _Z _k _V in
    Ok ((shared_key, snd validators, ciphers),
        (_Y ^ (fst validators)))
```

Bob can therefore retrieve `Y` and also generate the shared key. `Y` arrives
with the "validator" which allows us to check that Bob has done everything
right. The latter will send the other "validator" to Alice in order to finish
the handshake on the agreement of a shared key!
```ocaml
let client_compute ~ctx ~identity packet =
  let client_validator = String.sub packet 32 (String.length packet - 32) in
  let _Y = String.sub packet 0 32 in
  let gy = ed25519_sub _Y ctx._N in
  let* _Z = ed25519_scalarmult ctx.x ~off:0 ~point:gy in
  let* _V = ed25519_scalarmult ctx._l ~off:0 ~point:gy in
  let shared_key, validators = shared_key_and_validators
    ~identity ctx._X _Y _Z ctx._k _V in
  if Eqaf.compare_le (fst validators) client_validator = 0
  then Ok (shared_key, snd validators)
  else Error `Invalid_client_validator

let server_finalize ~server:(shared_key, validator, ciphers) packet =
  if Eqaf.compare_le validator packet = 0
  then Ok (shared_key, ciphers)
  else Error `Invalid_server_validator
```

That's it! We have just implemented what is the heart of our SPAKE2+EE
protocol, the _handshake_. As you can see, we are not talking about the network
at all but just about a `string` exchange where the serialization issue is very
important.

The abstraction of operating the _handshake_ without any network notion allows:
1) focus on what is essential in terms of the exchange between Alice and Bob
   (and spare us the "details" of socket, TCP/IP, etc.)
2) abstract our _handshake_ beyond any network - and God knows that in the
   context of MirageOS, this abstraction is important

```ocaml
val generate :
  ?hash:hash ->
  ?ciphers:cipher * cipher ->
  ?g:Random.State.t ->
  password:string ->
  algorithm:'a algorithm -> 'a ->
  secret * public

val public_to_string : public -> string
val public_of_string : string -> (public, [> error ]) result

val hello :
  ?g:Random.State.t ->
  public:public ->
  string ->
  (client * string, [> error ]) result

val server_compute :
  ?g:Random.State.t ->
  secret:secret ->
  identity:string * string ->
  string ->
  (server * string, [> error ]) result

val client_compute :
  client:client ->
  identity:(string * string) ->
  string ->
  (shared_key * string, [> error ]) result

val server_finalize :
  server:server ->
  string ->
  (shared_key, [> error ]) result
```

## Handshake implementation

However, it may be worthwhile to assist and direct the end user as to the order
in which the information (`salt`, `X`, `Y` and validators) enters Bob and
Alice. So, if we could have something that could be composed quite easily with
a `socket`, it would allow us to avoid some mistakes in the use of our
cryptography library.

The same is true for TLS, but I suspect that many [ocaml-tls][ocaml-tls] users
don't know the details of what happens during the handshake (and all the
details like 0-RTT that can literally complicate an implementation that hasn't
abstracted so well from the network...).

More pragmatically, a handshake is still a particular order of information
exchange between Alice and Bob where it is essentially just a matter of reading
or writing to a `socket`. If we could encode this order using OCaml without
strictly depending on the `socket`, that would be great. Of course, you can
imagine that for someone involved in MirageOS, this question has been asked
many times before (HTTP, Git, SMTP, etc.)...

### Continuation-passing style

A particularly interesting style for describing an execution chain is CPS. In
our case, our chaining would return our basic actions (read and write) as well
as the `k`ontinuation that will execute the rest of our chain.

This kind of design is quite common and you can see an example with
[Colombe][colombe]. It is mostly an extension of the API offered by
[ocaml-tls][ocaml-tls] or [decompress][decompress]<sup>[2](#fn2)</sup>- whose
"patent" would come more from Daniel Bünzli's libraries.

<hr />

<tag id="fn2">**2**</tag>: with the difference that the continuation remains
internal to the `state`, these libraries offer
`state -> [ Rd of state | Wr of state ]` but this is an API detail.

<hr />

```ocaml
type 'a t =
  | Read  of { buf : bytes; off : int; len : int
             ; k : [ `Len of int | `Eof ] -> 'a t }
  | Write of { buf : string; off : int; len : int
             ; k : int -> 'a t }
  | Done  of 'a
  | Fail  of error

let rec go f m len = match m len with
  | Done v -> f v
  | Fail err -> Fail err
  | Read { buf; off; len; k } ->
    Rd { buf; off; len; k= go f k }
  | Write { str; off; len; k } ->
    let k0 = function `End -> k 0 | `Len len -> k len in
    let k1 = function
      | 0 -> go f k0 `End | len -> go f k0 (`Len len) in
    Wr { str; off; len; k= k1; }

let ( let* ) =
  fun m f -> match m with
  | Done v -> f v
  | Fail err -> Fail err
  | Rd { buf; off; len; k; } ->
    Rd { buf; off; len; k= go f k }
  | Wr { str; off; len; k; } ->
    let k0 = function `End -> k 0 | `Len len -> k len in
    let k1 = function 0 -> go f k0 `End | len -> go f k0 (`Len len) in
    Wr { str; off; len; k= k1; }
```

It is then a question of having a "state" on which we can work and according to
it, issue the right actions. Our protocol remains quite simple: it is a matter
of reading packets whose size is predetermined - there are variants such as:
- a "line-directed" protocol where the end of a "packet" is notified with a
  `\r\n` (like SMTP)
- a "packet-length" protocol where a header informing the size of the packet is
  expected at the very beginning (like TLS or Git)

But these protocols want to make variable packet size possible, which is not
our case. The _salt_ packet will always be the same size and `X` and `Y` are
always the same size. `validators` also have a predefined size too.

We therefore need essentially 2 functions:
```ocaml
val recv : state -> len:int -> string t
val send : state -> string -> unit t
```

This is probably the most crucial moment in the implementation of a protocol.
Indeed, if we're talking strictly about performance, we need to be able to
issue the `Read` or `Write` only at times when we really need it - because, as
far as our `'a t` type is concerned, it's when we receive these actions that
our real _syscalls_ (`Unix.read` and `Unix.write` for example) take place, and
it's then that we can't optimise - the kernel comes into play.

As far as we are concerned, we can take the advantage of 2 points:
- our packets are relatively small, we don't need to have a big intermediate
  buffer to handle them<sup>[3](#fn3)</sup>
- as we said, the packets have a certain size. We can therefore adopt a policy
  of "read until we have `N` bytes" rather than "process until we have no more
  bytes" (which is the [angstrom][angstrom] politic)

<hr />

<tag id="fn3">**3**</tag>: We can even go further here and make the state
containing our intermediate buffers small enough to use OCaml's super-fast
minor heap allocation policy - though I wouldn't claim that this will make your
program consistently faster. It all depends on how long the buffers live, a
long life would mean copying the buffers... As Xavier Leroy said:

> You see, the Caml garbage collector is like a god from ancient mythology

<hr />

```ocaml
exception Leave of error

let safe k ctx =
  try k ctx
  with Leave err -> Fail err

let always x = fun _ -> x

type ctx =
  { a_buffer : bytes
  ; mutable a_pos : int
  ; mutable a_max : int
  ; b_buffer : bytes
  ; mutable b_pos : int }

let ctx () =
  { a_buffer= Bytes.create 64
  ; a_pos= 0
  ; a_max= 0
  ; b_buffer= Bytes.create 64
  ; b_pos= 0 }

let flush k0 ctx =
  if ctx.b_pos > 0
  then
    let rec k1 n =
      if n < ctx.b_pos
      then Write { str= Bytes.unsafe_to_string ctx.b_buffer
                 ; off= n
                 ; len= ctx.b_pos - n
                 ; k= (fun m -> k1 (n + m)) }
      else ( ctx.b_pos <- 0
           ; k0 ctx ) in
    k1 0
  else k0 ctx

let write str ctx =
  let max = Bytes.length ctx.b_buffer in
  let rem = max - ctx.b_pos in
  if String.length str > rem
  then invalid_arg "Packet is too big" ;
  let len = String.length str in
  Bytes.blit_string str j ctx.b_buffer ctx.b_pos len ;
  ctx.b_pos <- ctx.b_pos + len

let send ctx str =
  write str ctx ;
  flush (always (Done ())) ctx

let prompt ~required k ctx =
  if ctx.a_pos > 0
  then
    ( let rest = ctx.a_max - ctx.a_pos in
      Bytes.blit ctx.a_buffer ctx.a_pos ctx.a_buffer 0 rest ;
      ctx.a_max <- rest ;
      ctx.a_pos <- 0 ) ;
  let rec go off =
    if off = Bytes.length ctx.a_buffer
    then Fail `Not_enough_space
    else if off - ctx.a_pos < required
    then let k = function
           | `Len len -> go (off + len)
           | `End -> Fail `End_of_input in
         Read { buf= ctx.a_buffer
              ; off= off
              ; len= Bytes.length ctx.a_buffer - off
              ; k= k }
    else ( ctx.a_max <- off
         ; safe k ctx ) in
  go ctx.a_max

let recv ctx ~len =
  let k ctx =
    let str = Bytes.sub_string ctx.a_buffer ctx.a_pos len in
    ctx.a_pos <- ctx.a_pos + len ;
    Done str in
  prompt ~required:len k ctx
```

### Our handshake implementation

We now have a mini-protocol in which we can describe the sending and receiving
of our packets and execute our primitives in the order we want.
```ocaml
type cfg = Cfg : 'a algorithm * 'a -> cfg

let ( let+ ) x f = match x with
  | Ok v -> f v
  | Error err -> Fail (`Spoke err)

let handshake_client ctx
  ?g ~identity password =
  (* <= (1) salt <= *)
  let* public = recv ctx ~len:34 in
  let+ public = public_of_string public in
  let+ ciphers = ciphers_of_public public in
  let+ client, packet = hello ?g ~public password in
  (* => (2) X => *)
  let* () = send ctx packet in
  (* <= (3) Y + validator <= *)
  let* packet = recv ctx ~len:96 in
  let+ shared_key, packet = client_compute
    ~client ~identity packet in
  let* () = send ctx packet in
  (* => (4) validator => *)
  return (ciphers, shared_key)

let handshake_server ctx
  ?g ~password ~identity (Cfg (algorithm, arguments)) =
  let secret, public = generate ?g ~password
    ~algorithm arguments in
  let+ ciphers = ciphers_of_public public in
  let* () = send ctx (public_to_string public) in
  (* => (1) salt => *)
  let* packet = recv ctx ~len:32 in
  (* <= (2) X <= *)
  let+ server, packet = server_compute ~secret ~identity
    packet in
  let* () = send ctx packet in
  (* => (3) Y + validator => *)
  let* packet = recv ctx ~len:64 in
  (* <= (4) validator <= *)
  let+ shared_key = server_finalize ~server packet in
  return (ciphers, shared_key)
```

We can now plug our handshakes with an implementation that allows us to read
and write to a peer. The simplest and most common is of course `Unix` with a
`socket`:
```ocaml
let run socket flow =
  let rec go = function
    | Done v -> Ok v
    | Fail err -> Error err
    | Read { buf; off; len; k; } ->
      ( match Unix.read socket buf off len with
      | 0 -> go (k `End)
      | len -> go (k (`Len len)) )
    | Write { str; off; len; k; } ->
      let len = Unix.write_substring socket str off len in
      go (k len) in
  go flow

let connect_client sockaddr =
  let domain = Unix.domain_of_sockaddr sockaddr in
  let socket = Unix.socket domain Unix.SOCK_STREAM 0 in
  Unix.connect socket sockaddr ;
  socket

let connect_server sockaddr =
  let domain = Unix.domain_of_sockaddr sockaddr in
  let socket = Unix.socket domain Unix.SOCK_STREAM 0 in
  Unix.bind socket sockaddr ;
  Unix.listen socket 40 ;
  ( match sockaddr with
  | Unix.ADDR_UNIX path ->
    Stdlib.at_exit (fun () -> try Unix.unlink path with _ -> ())
  | _ -> () ) ;
  socket

let do_client sockaddr ?g ~identity password =
  let ctx = ctx () in
  let socket = connect_client sockaddr in
  match run socket (handshake_client ctx ?g ~identity password) with
  | Ok (ciphers, shared_key) -> ...
  | Error err -> abort

let do_server sockaddr ?g ~identity ~password cfg =
  let ctx = ctx () in
  let socket = connect_server sockaddr in
  match run socket (handshake_server ctx ?g ~password ~identity cfg with
  | Ok (ciphers, shared_key) -> ...
  | Error err -> abort
```

We have finally made our mini protocol that manages our handshake! The last
piece of code is a concrete implementation (with `Unix`) of everything we have
just implemented. The way I see this whole development process is like that of
an onion where you specialise at each level in relation to a very precise
objective:
1) to make our cryptographic primitives
2) use them to implement the SPAKE2+EE logic (without the network logic)
3) implement our handshake with network logic (reception & transmission)

Each level tries (and narrows down) to solve a problem that is constantly being
specified: a good solution depends essentially on the way the problem is posed!
This way of doing things allows especially to take some possible advantages
(`[@@noalloc]`, isomorphism, small allocation, etc.) about performance and
security.

Finally, it is essentially a matter of keeping in mind the abstractions that
you want. The job is ultimately to come up with a good API, again (and
forever), but only experience (as far as a craft job is concerned) counts :) !

## Finally, a flow, ciphers and MirageOS!

For a MirageOS project, one of the constraints we have regarding the ecosystem
is to respect certain interfaces in order to compose our implementation with
other projects. As far as protocols are concerned, a fairly common interface is
[Mirage\_flow.S][mirage-flow]. It describes what can be seen as a way to
communicate with arbitrary content with a peer.

Our last objective is to propose, like [ocaml-tls][ocaml-tls], an
implementation that respects this interface so that it can be used to implement
a slightly higher-level protocol (such as HTTP and definitely put the S for
Secure at the end of it).

Still in the context of an abstraction, our implementation will wait (still
like ocaml-tls) for the implementation of a Mirage\_flow.S so that we can
inject the TCP/IP implementation of `Unix` or [mirage-tcpip][mirage-tcpip].
```ocaml
module Make (Flow : Mirage_flow.S) : sig
  include Mirage_flow.S

  val client_of_flow : ?g:Random.State.t
    -> identity:(string * string) -> password:string -> Flow.flow
    -> (flow, [> write_error ]) result Lwt.t

  val server_of_flow : ?g:Random.State.t -> cfg:cfg
    -> identity:(string * string) -> password:string -> Flow.flow
    -> (flow, [> write_error ]) result Lwt.t
end
```

`client_of_flow` and `server_of_flow` will do the _handshake_. Then they will
return a new `type flow` on which a transmission with GCM or ChaCha20 will be
done between the two peers. The objective is to go a little further than the
handshake in order to really propose a final way to communicate in a secure way
with a weak password.

First, we need to implement a `run` function that uses the _syscalls_ in our
`Flow` module to execute our _handshake_. The function is very similar to what
we could do with the `Unix` module, except that we have to use the
[Lwt monad][lwt]. We will notice that it is quite simple to change the 
underlying implementation that will take care of the network.
```ocaml
let ( >>? ) = Lwt_result.bind
let reword_error f = function
  | Ok v -> Ok v
  | Error err -> Error (f err)

let run queue flow fiber =
  let cs_wr = Cstruct.create 128 in
  let allocator len = Cstruct.sub cs_wr 0 len in
  let rec go = function
    | Done v -> Lwt.return_ok v
    | Fail (#error as err) -> Lwt.return_error err
    | Read { buf; off; len; k; } as fiber ->
      if Ke.Rke.is_empty queue
      then
        Flow.read flow >|= reword_error (fun err -> `Flow err) >>? function
        | `Eof -> go (k `End)
        | `Data cs ->
          Ke.Rke.N.push queue ~blit ~length:Cstruct.length cs ;
          go fiber
      else
        ( let len = min len (Ke.Rke.length queue) in
          Ke.Rke.N.keep_exn queue ~blit ~length:Bytes.length ~off ~len buf ;
          Ke.Rke.N.shift_exn queue len ;
          go (k (`Len len)) )
    | Write { str; off; len; k; } ->
      let cs = Cstruct.of_string ~allocator ~off ~len str in
      Flow.write flow cs >|= reword_error (fun err -> `Flow_write err)
      >>? fun () -> go (k len) in
  go fiber
```

### Ciphers

Our goal now is to initiate communication through GCM or ChaCha20. We will look
at the possibility of the client communicating with a specific cipher and the
server communicating with a cipher that may be different (just to confuse an
attacker).

[mirage-crypto][mirage-crypto] already offers an implementation of these
ciphers (for TLS) and we essentially need two functions:
```ocaml
val encrypt : cipher_state -> sequence:int64 -> Cstruct.t -> Cstruct.t
val decrypt : cipher_state -> sequence:int64 -> Cstruct.t -> Cstruct.t option
```

The `sequence` number allows a block to be tagged with a number that should
only increment. In this way, we can check the order of our blocks (and be sure
that we haven't forgotten one). This number is also shared between the client
and the server to ensure that an attacker does not insert data arbitrarily (at
least, that would be more difficult).

Finally, the `cipher_state` contains the extra elements that will also be
shared between the client and the server. There is of course our famous shared
key but also the `nonce` (which will contain the `sequence`) as well as the
`adata` which is a data external to the content we want to encrypt/decrypt
allowing us to check the integrity of the block - generally, the size of the
content to be encrypted is encoded.

```ocaml
module type CIPHER_BLOCK = sig
  type key

  val authenticate_encrypt : key:key -> nonce:Cstruct.t -> ?adata:Cstruct.t
    -> Cstruct.t -> Cstruct.t
  val authenticate_decrypt : key:key -> nonce:Cstruct.t -> ?adata:Cstruct.t
    -> Cstruct.t -> Cstruct.t option

  val of_secret : Cstruct.t -> key
  val tag_size : int
end

let module_of : type k. k aead -> k cipher_block = function
  | GCM -> (module Mirage_crypto.Cipher_block.AES.GCM)
  | ChaCha20_Poly1305 ->
    let module M = struct
      include Mirage_crypto.Chacha20
      let tag_size = Mirage_crypto.Poly1305.mac_size
    end in (module M)

type 'k cipher_block = (module CIPHER_BLOCK with type key = 'k)

type cipher_state =
   State : { key : 'k; nonce : Cstruct.t
           ; impl : 'k cipher_block } -> cipher_state

let make_nonce nonce seq =
  let seq =
    let len = Cstruct.length nonce in
    let seq =
      let buf = Cstruct.create 8 in
      Cstruct.BE.set_uint64 buf 0 seq ; buf in
    let pad = Cstruct.create (len - 8) in
    Cstruct.append pad seq in
  xor nonce seq

let make_adata len =
  let buf = Cstruct.create 4 in
  Cstruct.BE.set_uint16 buf 0 Spoke.version ;
  Cstruct.BE.set_uint16 buf 0 len ; buf

let encrypt (State { key; nonce; impl= (module Cipher_block); }) sequence buf =
  let nonce = make_nonce nonce sequence in
  let adata = make_adata (Cstruct.length buf + Cipher_block.tag_size) in
  Cipher_block.authenticate_encrypt ~key ~adata ~nonce buf

let decrypt (State { key; nonce; impl= (module Cipher_block); }) sequence buf =
  let nonce = make_nonce nonce sequence in
  let adata = make_adata (Cstruct.length buf) in
  Cipher_block.authenticate_decrypt ~key ~adata ~nonce buf
```

### From a `Flow.flow` to our flow

Finally, we can define our flow type which will contain the states of our
ciphers and ring-buffers. You can observe several times the use of [ke][ke], a
library that implements a ring-buffer [à la Xen][ringbuffer-xen]. The latter
will serve as an intermediate buffer between encryption and decryption, it will
make us 2 since, as we said, the algorithm may not be the same between the
client and the server (depending on the direction).

One detail that is important in our new protocol is the ability for the client
or server to know the size of the incoming blocks. Several policies can be
implemented, we can set a size and add a tag (the `adata`) informing us if it
is the last block we receive or not. We can also decide to transmit the block
with its size (at the very beginning) to the TLS in order not to manage the
previous logic (which can be complicated). We will therefore send 2 bytes at
the very beginning (as a kind of header) which will inform the receiver of the
number of bytes it should receive next - the famous "packet-length" directed
protocol.

Finally, it will be a question of executing our previous `run` function with
the handshake (depending on whether we are the server or the client) in order
to obtain either an error (which we will report to the user), or the shared key
and the expected ciphers.
```ocaml
let remaining_bytes_from_ctx ctx =
  if ctx.a_pos >= ctx.a_max then ""
  else Bytes.sub_string ctx.a_buffer a_pos (a_max - a_pos)

type flow =
  { flow : Flow.flow
  ; recv : cipher_state
  ; send : cipher_state
  ; recv_record : Cstruct.t
  ; send_record : Cstruct.t
  ; mutable recv_seq : int64
  ; mutable send_seq : int64
  ; recv_queue : (char, Bigarray.int8_unsigned_elt) Ke.Rke.t
  ; send_queue : (char, Bigarray.int8_unsigned_elt) Ke.Rke.t }

let client_of_flow ?g ~identity ~password flow =
  let ctx = ctx () in
  let queue = Ke.Rke.create ~capacity:128 Bigarray.char in
  run queue flow (handshake_client ctx ?g ~identity password)
  >>? fun ((cipher0, cipher1), sk) ->
  let recv = cipher_state_of_key_nonce_and_cipher sk cipher0 in
  let send = cipher_state_of_key_nonce_and_cipher sk cipher1 in
  let recv_queue = Ke.Rke.create ~capacity:0x10000 Bigarray.char in
  let send_queue = Ke.Rke.create ~capacity:0x10000 Bigarray.char in
  (* We can pre-allocate our blocks since they will not be larger than 0xFFFF
     (our 2 bytes which gives the size of the next block). *)
  let recv_record =
    let State { impl= (module Cipher_block); _ } = recv in
    Cstruct.create (2 + max_record + Cipher_block.tag_size) in
  let send_record =
    let State { impl= (module Cipher_block); _ } = send in
    Cstruct.create (2 + max_record + Cipher_block.tag_size) in
  (* Finally, our `run` function may, "by mistake", consume more than the
     handshake. We must therefore copy these possible bytes into our queue (so
     as not to lose anything). *)
  let rem = remaining_bytes_from_ctx ctx in
  Ke.Rke.N.push recv_queue ~blit ~length:String.length rem ;
  Lwt.return_ok { flow
                ; recv; send
                ; recv_record; send_record
                ; recv_seq= 0L; send_seq= 0L
                ; recv_queue; send_queue; }
```

The implementation of `server_of_flow` is almost the same except for the
_handshake_ used. So we can tackle the last few operations, namely `read` &
`write` (and `close` but the latter will only call `Flow.close`).

### Intermediate buffers and _syscalls_

Our role is essentially to "parse" a record (a block) and decrypt it. However,
we may find ourselves in a state where we have not yet received the entire
block - so we will apply the same policy as when we implemented our
_handshake_: read until we have `N` bytes (initially, we will need to get at
least 2 bytes, then the size given in those two bytes.

For sending, it's even simpler, fill our intermediate buffer/queue and then
flush `0xFFFF` blocks until there is nothing left - the last block will
probably be smaller than 0xFFFF of course.
```ocaml
let get_record record queue cipher_state =
  let State { impl= (module Cipher_block); _ } = cipher_state in
  match Ke.Rke.length queue with
  | 0 -> `Await_hdr
  | 1 -> `Await_rec 1
  | 2 | _ ->
    Ke.Rke.N.keep_exn queue ~blit ~length:Cstruct.length record ~len:2 ;
    let len = Cstruct.BE.get_uint16 record 0 in
    if Ke.Rke.length queue >= len
    then ( Ke.Rke.N.keep_exn queue ~blit ~length:Cstruct.length record ~len
         ; Ke.Rke.N.shift_exn queue len
         ; `Record (Cstruct.sub record 2 (len - 2)) )
    else `Await_rec (len - Ke.Rke.length queue)

let rec read flow =
  match get_record flow.recv_record flow.recv_queue flow.recv with
  | `Record buf ->
    ( match decrypt flow.recv flow.recv_seq buf with
    | Some buf (* copy *) ->
      (* Don't forget to increment [seq] to keep the same state as our peer. *)
      flow.recv_seq <- Int64.succ flow.recv_seq ;
      Lwt.return_ok (`Data buf)
    | None -> Lwt.return_error `Corrupted )
  | (`Await_hdr | `Await_rec _) as await ->
    ( Flow.read flow.flow >>= function
    | Error err -> Lwt.return_error (`Flow err)
    | Ok `Eof ->
      (* If the connection is closed by peer and we did not receive our
         "header", we safely can say that nothing left. *)
      if await = `Await_hdr
      then Lwt.return_ok `Eof
      else Lwt.return_error `Corrupted
    | Ok (`Data buf) ->
      Ke.Rke.N.push flow.recv_queue ~blit ~length:Cstruct.length buf ;
      read flow )

let record ~dst ~sequence queue cipher_state =
  let len = min 0xffff (Ke.Rke.length queue) in
  Ke.Rke.N.keep_exn queue ~length:Cstruct.length ~blit ~off:2 ~len dst ;
  let buf (* copy *) = encrypt cipher_state sequence (Cstruct.sub dst 2 len) in
  Ke.Rke.N.shift_exn queue len ;
  let len = 2 + Cstruct.length buf in
  Cstruct.BE.set_uint16 dst 0 len ;
  Cstruct.blit buf 0 dst 2 (Cstruct.length buf) ;
  Cstruct.sub dst 0 len 

let rec flush flow =
  if not (Ke.Rke.is_empty flow.send_queue)
  then let record = record
         ~dst:flow.send_record ~sequence:flow.send_seq
         flow.send_queue flow.send in
       ( flow.send_seq <- Int64.succ flow.send_seq
       ; Flow.write flow.flow record >>? fun () ->
         flush flow )
  else Lwt.return_ok ()

let write flow data =
  Ke.Rke.N.push flow.send_queue ~blit:blit0 ~length:Cstruct.length data ;
  flush flow >>= function
  | Ok () -> Lwt.return_ok ()
  | Error err -> Lwt.return_error (`Flow_write err)

let close flow = Flow.close flow.flow
```

That's it! We finally have a [Mirage_flow.S][mirage-flow] protocol that uses
our _handshake_ and then uses symmetric encryption from a key shared with a
peer.

More concretely, the idea of TLS is quite similar except that what is common
between the different parties (instead of our weak password) are the
authorities (like let's encrypt) that issue the certificates. However, we find
this notion of handshake which, finally, remains the most important since it is
at this moment that there can be leaks which can help the attacker.

In the end, the abstraction remains very close to what [ocaml-tls][ocaml-tls]
and especially `tls.mirage` offers, making it easy to compose protocols
(with [mimic](https://github.com/dinosaure/mimic)).

Like `mirage-tcpip`, `Unix` or `Tls_mirage.Make`, we can now imagine a higher
level protocol because we have just implemented a security layer rather than an
actual protocol (like HTTP). And on this question, I already have an idea of
what I want to implement - but that will be the order of another article!

## Conclusion

The article may seem a bit long (compared to the others) but it does show one
aspect, or at least a systematic reflection that one can have on MirageOS
projects. The pragmatism of utility may be good but then choices are made whose
basis is not so clear - like wanting to absolutely send and receive information
from the start, which involves Unix without realising the inherent
incompatibility with MirageOS afterwards.

The example of dependency on Unix remains fairly obvious - especially if you
read my articles - but there are other finer choices as well. This "onion"
method especially allows you to backtrack when what you want is not so obvious.
You can always find solutions to specific problems, it's just a matter of
finding the right solutions sometimes.

OCaml offers an environment which is not very helpful in this respect, the type
system is still essential to direct the development - and to realise sometimes
our little mistakes in the scope of our information, its uses, etc.

Finally, if I have proposed 3 steps to the creation of a mini protocol, it is
to focus each part on what is essential to them. I sometimes use the term
'essentialiser' (from the French) to describe my approach and often people
misunderstand me - which is normal given my level of English. And yet, this is
what it is all about, reducing the problem to its strict minimum.

An interesting effect of this approach is then the re-appropriation of my work
by others on several levels. Some will choose simplicity while others (I often
refer to them as the other 10%) will, like me, want to go into details even if
it means looking at the code.

And if you find this work interesting, you can make a donation to
[robur.coop][robur.coop-donate]. You can find the project [here][spoke].

[elligator]: https://elligator.cr.yp.to/
[SPAKE2+]: https://tools.ietf.org/id/draft-bar-cfrg-spake2plus-00.html
[SPAKE2+EE]: https://moderncrypto.org/mail-archive/curves/2015/000424.html
[CDH]: https://en.wikipedia.org/wiki/Computational_Diffie%E2%80%93Hellman_assumption
[mirage-crypto]: https://github.com/mirage/mirage-crypto
[digestif]: https://github.com/mirage/digestif
[digestif-lock]: https://github.com/mirage/digestif/blob/fc510e57bbb27ceb020ca73b1067e79a1b933f47/src-c/native/stubs.c#L42-L56
[libsodium]: https://github.com/jedisct1/libsodium
[ocaml-tls]: https://github.com/mirleft/ocaml-tls
[colombe]: https://github.com/mirage/colombe
[decompress]: https://github.com/mirage/decompress
[gcm]: https://perdu.com
[chacha20-poly1305]: https://perdu.com
[encore]: https://github.com/mirage/encore
[angstrom]: https://github.com/inhabitedtype/angstrom
[mirage-flow]: https://perdu.com
[mirage-tcpip]: https://github.com/mirage/mirage-tcpip
[ringbuffer-xen]: https://perdu.com
[ke]: https://github.com/mirage/ke
[robur.coop-donate]: https://robur.coop/Donate
[spoke]: https://github.com/dinosaure/spoke
[pake]: https://en.wikipedia.org/wiki/Password-authenticated_key_agreement
[lwt]: https://github.com/ocsigent/lwt
