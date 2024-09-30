---
date: 2024-09-27
title: Happy eyeballs?!
description:
  When connect() hides a lot of details.
tags:
  - unix
  - happy-eyeballs
---

This short article will introduce the benefits of
[happy-eyeballs][happy-eyeballs] when it comes to connecting to a service. We'll
see that behind a simple POSIX function, there are a lot of questions about
latency, resource management and the method of resolving a domain name.

But first of all, how do you connect to a service in OCaml? We're going to try
to connect to amazon.com (I don't like the choice of this domain, but there's a
technical interest behind it).
```shell
$ cat >main.ml <<EOF
let () =
  let { Unix.h_addr_list; _ } = Unix.gethostbyname "amazon.com" in
  if Array.length h_addr_list = 0
  then failwith "amazon.com not found";
  let inet_addr = h_addr_list.(0) in
  let sockaddr = Unix.ADDR_INET (inet_addr, 80) in
  let socket =
    Unix.socket ~cloexec:true (Unix.domain_of_sockaddr sockaddr)
      Unix.SOCK_STREAM 0 in
  Unix.connect socket sockaddr;
  Format.printf "Connected!\n%!";
  Unix.close socket
EOF
$ ocamlopt -I +unix unix.cmxa main.ml
$ ./a.out
Connected!
```

As you can see, connecting to a service (in this case, http) is not easy. First
we need to resolve the ‘amazon.com’ domain name with `gethostbyname`, create a
socket (and don't forget to close it), then specify the http service (with port
80) and try to connect. For POSIX purists, `getaddrinfo` should be used instead.
```ocaml
let () =
  let addrs = Unix.getaddrinfo "amazon.com" "http"
    Unix.[ AI_SOCKTYPE SOCK_STREAM ] in
  if List.length addrs = 0
  then failwith "http service for amazon.com not found";
  let addr = List.hd addrs in
  let sockaddr = addr.Unix.ai_addr in
  let socket =
    Unix.socket ~cloexec:true (Unix.domain_of_sockaddr sockaddr)
      Unix.SOCK_STREAM 0 in
  Unix.connect socket sockaddr;
  Format.printf "Connected!\n%!";
  Unix.close socket
```

This is where, in reality, the system does a lot of things. The first thing is
to resolve the domain name. How does `gethostbyname`/`getaddrinfo` resolve a
domain name?
- does it use an encryption method?
- does it talk to a service (a resolver) over which I have control?
- can anyone from the outside observe (track) this information?

## Domain Name Resolution

`getaddrinfo`/`gethostbyname` are functions that interact with your system. Your
system will then either check its cache to obtain the IP address of amazon.com,
or ask a DNS resolver.

In this case, on Archlinux (my system), `systemd-resolved` is launched. You can
find the DNS resolver you are using (its IP address) in the `/etc/resolv.conf`
file:
```shell
$ cat /etc/resolv.conf
# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
# ...

nameserver 127.0.0.53
```

This is a daemon which will itself ask another DNS resolver. Which is it?
```shell
$ resolvectl -i wlan0 dns
Link 4 (wlan0): 89.2.0.1 89.2.0.2
```

This daemon is currently running to communicate with 89.2.0.1 (and 89.2.0.2).
These resolvers were given to me by my internet box (when an IP address was
assigned via DHCP). They are the SFR/Numericable resolvers.

That's when you realise just how much infrastructure is needed behind a simple
function! Welcome to the Tower of Babel. At this stage, we realise that we do
not have complete control over the resolution of domain names. And, at this
stage, you're supposed to know that such resolvers owned by big corporations are
censoring certain services:
```sh
$ dig +short ygg.re
$ echo "This site doesn't seem to exist!?"
```

It's at this stage that you can see the advantage of choosing your own DNS
resolver. There are currently 2 possibilities:
1) the first is to set up your own DNS resolver that synchronises with ICANN's
   servers. Although this solution has the advantage of giving you an
   uncensored Internet, it is still slow (given the locality of the servers).
   <sup>[1](#fn1)</sup>
2) use an anti-censorship DNS resolver such as
   [uncensoreddns.org][uncensoreddns.org]

```shell
$ dig +short +tls ygg.re @89.233.43.71
104.21.64.76
172.67.178.119
$ echo "SFR lied to me!?"
```

<hr />

**<tag id="fn1">1</tag>**: Note that we offer such a server in the form of a
unikernel, available here. As well as being small, its attack surface is much
smaller than that of competitors such as bind9.

<hr />

So our code from the beginning wouldn't work if we had to connect to a service
like ygg.re. At least, it wouldn't work on some machines (including mine)
depending on the DNS resolver used. So it might be a good idea to _bypass_ the
DNS resolver that we don't control and leave it to the user:
- use a more trusted default DNS resolver
- give the user the option of specifying a DNS resolver

## ocaml-dns

But our cooperative has already taken care of this problem by implementing the
DNS protocol in OCaml! It should also be noted whether or not TLS is used to
encrypt communications. In this sense, we will:
1) force the use of TLS to resolve our domain names
2) force the use of a resolver, in this case uncensoreddns.org.

[ocaml-dns][ocaml-dns] offers several packages that are compatible with lwt,
mirage or [miou][miou]. In the air of OCaml 5, we are going to use Miou:
```ocaml
let time () = Some (Ptime_clock.now ())

let ygg_re = Domain_name.(host_exn (of_string_exn "ygg.re"))

let failwith_error_msg = function
  | Ok value -> value
  | Error (`Msg msg) -> failwith msg

let uncensoreddns_org =
  let ipaddr = Ipaddr.of_string_exn "89.233.43.71" in
  let authenticator = X509.Authenticator.of_string
    "key-fp:SHA256:INSZEZpDoWKiavosV2/xVT8O83vk/RRwS+LTiL+IpHs=" in
  let authenticator = failwith_error_msg authenticator in
  let authenticator = authenticator time in
  let tls = Result.get_ok (Tls.Config.client ~authenticator ()) in
  `Tls (tls, ipaddr, 853)

let pp_sockaddr ppf = function
  | Unix.ADDR_INET (inet_addr, port) ->
      Fmt.pf ppf "%s:%d" (Unix.string_of_inet_addr inet_addr) port
  | Unix.ADDR_UNIX str -> Fmt.pf ppf "<%s>" str

let () =
  Miou_unix.run @@ fun () ->
  let rng = Mirage_crypto_rng_miou_unix.(initialize (module Pfortuna)) in
  let daemon, he = Happy_eyeballs_miou_unix.create () in
  let dns = Dns_client_miou_unix.create
    ~nameservers:(`Tcp, [ uncensoreddns_org ]) he in
  let result = Dns_client_miou_unix.gethostbyname dns ygg_re in
  let ipaddr = failwith_error_msg result in
  let inet_addr = Ipaddr_unix.to_inet_addr (Ipaddr.V4 ipaddr) in
  let sockaddr = Unix.ADDR_INET (inet_addr, 80) in
  let socket = Unix.socket ~cloexec:true
    (Unix.domain_of_sockaddr sockaddr) Unix.SOCK_STREAM 0 in
  Unix.connect socket sockaddr;
  Format.printf "Connected to %a!\n%!" pp_sockaddr sockaddr;
  Unix.close socket;
  Happy_eyeballs_miou_unix.kill daemon;
  Mirage_crypto_rng_miou_unix.kill rng
```

The code immediately becomes a little more complex. We're deliberately not going
to talk about happy-eyeballs yet. However, it is interesting to note that
certain processes are expected for DNS and TLS. Particularly the generation of
random numbers.

We're not going to disgress here and yet, as far as cryptography is concerned,
having control (as is the case here) over the way random numbers are generated
is fundamental. This [very good article][rng] gives a good overview of the
importance of this line<sup>[2](#fn2)</sup>:
```ocaml
let () =
  Miou_unix.run @@ fun () ->
  let rng = Mirage_crypto_rng_miou_unix.(initialize (module Pfortuna)) in

```

<hr />

**<tag id="fn2">2</tag>**: It's worth noting that `Pfortuna`, which was
developed as part of Miou, is the only one to be **domain-safe** - which makes
it all the more difficult to tell the difference between a ‘good’ random number
and the result of a data-race!

<hr />

We can now compile and test the code!
```ocaml
$ ocamlfind opt -linkpkg \
  -package digestif.c,ptime.clock.os,dns-client-miou-unix,mirage-crypto-rng-miou-unix \
  main.ml
$ ./a.out
Connected to 104.21.64.76:80!
```

## Multiple solutions!

At this stage, we have just protected our possible user by forcing the use of
TLS for DNS resolution and at the same time avoided censorship by forcing the
use of a DNS resolver that we trust rather than the one imposed by our ISP.

However, if we go back to the code from the very beginning, there's another
question that arises and it specifically concerns the result of our resolution
and the `connect()` function. Let's go back to the original amazon.com code and
run some benchmarks!
```ocaml
let pp_sockaddr ppf = function
  | Unix.ADDR_INET (inet_addr, port) ->
      Format.fprintf ppf "%s:%d" (Unix.string_of_inet_addr inet_addr) port
  | Unix.ADDR_UNIX str -> Format.fprintf ppf "<%s>" str

let () =
  let addrs = Unix.getaddrinfo "amazon.com" "http"
    Unix.[ AI_SOCKTYPE SOCK_STREAM ] in
  if List.length addrs = 0
  then failwith "http service for amazon.com not found";
  List.iter (fun addr -> Format.printf "- %a\n%!"
    pp_sockaddr addr.Unix.ai_addr)
    addrs;
  let addr = List.hd addrs in
  let sockaddr = addr.Unix.ai_addr in
  let socket = Unix.socket ~cloexec:true (Unix.domain_of_sockaddr sockaddr)
    Unix.SOCK_STREAM 0 in
  let t0 = Unix.gettimeofday () in
  Unix.connect socket sockaddr;
  let t1 = Unix.gettimeofday () in
  Format.printf "Connected to %a (in %fs)!\n%!" pp_sockaddr sockaddr
    (t1 -. t0);
  Unix.close socket
```

Here we're not only going to show our different solutions after solving
amazon.com, but also monitor the time taken to make our `connect()`:
```shell
$ ./a.out
- 54.239.28.85:80
- 52.94.236.248:80
- 205.251.242.103:80
Connected to 54.239.28.85:80 (in 0.085934s)!
```

Note that if you re-execute our code, the IP address chosen is no longer the
same as the previous one. It is said that amazon.com uses [Round-Robin
DNS][rr-dns], a technique that is not recommended. However, it is ‘normal’ for a
service to offer several IPs. As a general rule, the IPs given are those that
are closest geographically speaking:
```shell
$ dig +short google.com @8.8.8.8
142.250.179.78
$ dig +short +tls google.com @89.233.43.71
142.250.74.110
$ dig +short google.com @89.2.0.1
142.250.201.174
```

So there's another question: how do you choose the right IP? The main factor
that will determine our choice is the connection time. We have to admit that
even if we manipulate ideas and concepts, there is always a material reality to
what we do and use!
```shell
$ cat >main.ml <<EOF
let pp_sockaddr ppf = function
  | Unix.ADDR_INET (inet_addr, port) ->
      Format.fprintf ppf "%s:%d" (Unix.string_of_inet_addr inet_addr) port
  | Unix.ADDR_UNIX str -> Format.fprintf ppf "<%s>" str

let () =
  let inet_addr = Unix.inet_addr_of_string Sys.argv.(1) in
  let sockaddr = Unix.ADDR_INET (inet_addr, 80) in
  let socket = Unix.socket ~cloexec:true (Unix.domain_of_sockaddr sockaddr)
    Unix.SOCK_STREAM 0 in
  let t0 = Unix.gettimeofday () in
  Unix.connect socket sockaddr;
  let t1 = Unix.gettimeofday () in
  Format.printf "Connected to %a (in %fs)!\n%!" pp_sockaddr sockaddr
    (t1 -. t0);
  Unix.close socket
EOF
$ ocamlopt -I +unix unix.cmxa main.ml
$ ./a.out 142.250.179.78
Connected to 142.250.179.78:80 (in 0.008921s)!
$ ./a.out 142.250.201.174
Connected to 142.250.201.174:80 (in 0.008082s)!
$ ./a.out 142.250.74.110
Connected to 142.250.74.110:80 (in 0.036401s)!
```

Our first solutions are still 4 times faster than our latest solution! For an
application that attempts several connections (such as chatting with an API),
this can be a real performance factor.

Here, the question has arisen for all our solutions in relation to the
google.com service, but the same question arises for amazon.com. Fortunately,
the 3 servers that amazon.com gives us are located in the same place (Ashburn).
But, even if the geographical location of a server is a determining factor in
the `connect()` time, other factors may come into play, such as the load on the
first server, which could take longer to respond than the second.

In truth, the only solution that seems reasonable is a kind of `connect()`
competition on these multiple solutions. As soon as one of the three finishes,
the others should be _cancelled_.

## Happy-eyeballs!

This is where happy-eyeballs comes in! The idea behind happy-eyeballs is simple:
it consists of performing DNS resolution and attempting several competing
connections. The first (at speed) to establish a connection with the service
will be returned to you, while the others will have to be cancelled cleanly
(including closing the allocated sockets).

This resolution and connection process should run _in the background_. This way,
the user would just have to give it the task of connecting to a specific service
and happy-eyeballs would compete in the background until there was, at least, an
established connection that it would return to you.
```ocaml
let time () = Some (Ptime_clock.now ())

let ygg_re = Domain_name.(host_exn (of_string_exn "ygg.re"))

let failwith_error_msg = function
  | Ok value -> value
  | Error (`Msg msg) -> failwith msg

let uncensoreddns_org =
  let ipaddr = Ipaddr.of_string_exn "89.233.43.71" in
  let authenticator = X509.Authenticator.of_string
    "key-fp:SHA256:INSZEZpDoWKiavosV2/xVT8O83vk/RRwS+LTiL+IpHs=" in
  let authenticator = failwith_error_msg authenticator in
  let authenticator = authenticator time in
  let tls = Result.get_ok (Tls.Config.client ~authenticator ()) in
  `Tls (tls, ipaddr, 853)

let getaddrinfo dns record domain_name = match record with
  | `A ->
    Dns_client_miou_unix.gethostbyname dns domain_name
    |> Result.map (fun ipv4 -> Ipaddr.(Set.singleton (V4 ipv4)))
  | `AAAA ->
    Dns_client_miou_unix.gethostbyname6 dns domain_name
    |> Result.map (fun ipv6 -> Ipaddr.(Set.singleton (V6 ipv6)))

let () =
  Miou_unix.run @@ fun () ->
  let rng = Mirage_crypto_rng_miou_unix.(initialize (module Pfortuna)) in
  let daemon, he = Happy_eyeballs_miou_unix.create () in
  let dns = Dns_client_miou_unix.create
    ~nameservers:(`Tcp, [ uncensoreddns_org ]) he in
  Happy_eyeballs_miou_unix.inject he (getaddrinfo dns);
  begin match Happy_eyeballs_miou_unix.connect he "ygg.re" [ 443; 80 ] with
  | Ok ((ipaddr, port), socket) ->
    Fmt.pr "Connected to %a:%d\n%!" Ipaddr.pp ipaddr port;
    Miou_unix.close socket
  | Error (`Msg err) ->
    Fmt.epr "Got an error: %s" err end;
  Happy_eyeballs_miou_unix.kill daemon;
  Mirage_crypto_rng_miou_unix.kill rng
```

We can now compile and test the code!
```shell
$ ocamlfind opt -linkpkg \
  -package digestif.c,ptime.clock.os,dns-client-miou-unix,mirage-crypto-rng-miou-unix \
  main.ml
$ ./a.out
Connected to 104.21.64.76:443
```

It seems that one solution is much preferred over another in the choice of IPs.
Once again, the reasons for this choice, which revolves around connection speed,
can be found in a number of areas (geolocation, load, etc.).

But we did it! I hope you'll find `connect()` a bit more tedious than usual and
turn to better solutions like happy-eyeballs.

### Ports

There is a slight difference to be made about the ports. As you can see, it is
possible to specify several ports for our service. In our case, we have
specified 80 (http) and 443 (https). Depending on which is the most responsive,
we can use pattern-matching to initiate a simple http connection or an https
connection (tcp + tls).

In my opinion, it is not advisable to leave the choice of secure or insecure
communication solely to the connection speed parameter.

However, there are many cases where we would like to try several ports in order
to talk to similar services. Recently, the question arose for SMTP where:
- port 465 is not standard but offers fully encrypted SMTP communication
- port 587 is standard but only offers STARTTLS encryption

In addition, trying both, one of which is not specified but is generally
offered, is a good solution and only the happy-eyeballs solution could
satisfy me.

### `connect()` can _hangs_

Another, more subtle problem with `connect()` concerns the TCP protocol. The TCP
protocol can attempt to communicate with a service. It should be noted that you
will make several attempts to establish a connection with the service up to a
certain point, which depends on the system. In this case, for Linux, it says:

> **tcp_retries2** (integer; default: 15; since Linux 2.2)
>
>   The maximum number of times a TCP packet is retransmitted in established
>   state before giving up. The default value is 15, which corresponds to a
>   duration of approximately between 13 to 30 minutes, depending on the
>   retransmission timeout. The RFC 1122 specified minimum limit of 100 seconds
>   is typically deemed too short.

In the case of Miou, where `Miou_unix.connect` is asynchronous, this might not
pose too much of a problem. However, having a resource alive for 30min can end
up with an accumulation of several sockets waiting to finish the `connect()` and
can end up with an EMFILE (too many allocated sockets).

This is why it is often advisable to associate a timer with a `connect()` limit
(in our case, 5sec) to avoid this situation.
```ocaml
let connect socket sockaddr =
  let exception Timeout in
  let resource = Miou_unix.Ownership.resource socket in
  let prm0 = Miou.async @@ fun () -> Miou_unix.sleep 5.; raise Timeout in
  let prm1 = Miou.async ~give:[ resource ] @@ fun () ->
    Miou_unix.Ownership.connect socket sockaddr;
    Miou.Ownership.transfer resource in
  Miou.await_first [ prm0; prm1 ] |> function
  | Ok () -> Some socket
  | Error Timeout -> None
  | Error exn -> raise exn

let () =
  Miou_unix.run @@ fun () ->
  let addrs = Unix.getaddrinfo "google.com" "http"
    Unix.[ AI_SOCKTYPE SOCK_STREAM ] in
  if List.length addrs = 0
  then failwith "http service for amazon.com not found";
  let addr = List.hd addrs in
  let socket = Miou_unix.Ownership.tcpv4 () in
  match connect socket addr.Unix.ai_addr with
  | Some socket -> Miou_unix.Ownership.close socket
  | None -> ()
```

## `getaddrinfo()`

The `getaddrinfo` function is a bit mystical. In particular, it's what
introduced me to the `/etc/services` file. A file containing an association of
services with protocols (tcp or udp) and ports. This means above all that,
depending on the system, the use of `getaddrinfo` may differ. The alignment
between the service, the IP address and the port in order to return a convincing
result with a `connect()` can sometimes be... [surprising][surprising]!

## IPv4 & IPv6

One of the problems that has been noted during the transition from IPv4 to IPv6
is the repeated attempts to reach an IPv6 destination that only fail, taking the
user back to an IPv4 destination with a considerable delay (IPv6 brokeness).
There are several solutions to solve this problem (notably at DNS level) but
happy-eyeballs was a solution that helped to eliminate this problem.

The reader might point out that in 2024 almost everything will be IPv6, but
that's still not the case for me. My (dinosaure) ISP doesn't make IPv6 available
in my case, so happy-eyeballs may be more than necessary in my case to avoid
IPv6 brokeness.

## Conclusion

Behind a simple syscall, a lot can happen. Failing to understand, in detail,
what can happen with `gethostbyname`/`getaddrinfo` and `connect` are pitfalls
that only make you lose control over the tool you use every day.

Since, in [our cooperative][robur.coop], we develop unikernels, these questions
must arise as we don't have all these functions for free and have to reimplement
them in OCaml (which is always better than C!).

However, even if these solutions are developed within the framework of
unikernels, we still attach importance to making these solutions available even
to those who do not develop unikernels. In short, follow us and our work.

[surprising]: https://jvns.ca/blog/2022/02/23/getaddrinfo-is-kind-of-weird/
[uncensoreddns.org]: https://uncensoreddns.org
[happy-eyeballs]: https://github.com/robur-coop/happy-eyeballs
[ocaml-dns]: https://github.com/mirage/ocaml-dns
[miou]: https://github.com/robur-coop/miou
[rr-dns]: https://en.wikipedia.org/wiki/Round-robin_DNS
[robur.coop]: https://robur.coop/
[rng]: https://mirage.io/blog/mirage-entropy
