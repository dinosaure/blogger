---
date: 2020-12-06
article.title: Deploy an SMTP service (1/3)
article.description:
  How to deploy your own SMTP service
tags:
  - OCaml
  - MirageOS
  - SMTP
  - Deployement
---

In this series of articles, we will see how to "basically" deploy several
unikernels that talk to each other to set up an email service. As you know, for
quite some time now, I've been developing an email stack where we would be able
to send and receive emails from a given domain name.

More generally, email or rather your email address is perhaps the most important
element of your life on the Internet. Indeed, the simple fact of registering
requires an email address and when you lose information, access (a phone...),
it is the ultimate access to recover everything else because almost EVERYTHING
is associated with your email address (except the files sent with [Bob][bob]!).

For such an important and central service in a person's life, it might be better
to have absolute control of it. And this is perhaps what motivates me most about
email development.

## A partial solution

However, and anyone who has wanted to deploy their own email service, an email
service... is complicated. The complexity is on several levels:
- SMTP, email, etc. are historical artifacts of the Internet that have evolved
  very little (in contrast to HTTP). Cultural and historical knowledge is often
  required (much more than purely technical knowledge)
- There is unfortunately a monopoly situation that imposes implicit "rules"
  (outside of RFCs) that are difficult to reappropriate
- being the central element of your identity on the internet, it is perhaps the
  service that needs the most technical attention

In this respect, it is still difficult to offer today, with all the efforts one
can imagine, a viable solution that corresponds to all uses. Nevertheless, and
this concerns especially the last point, we can be satisfied with partial
solutions that can already be used and tested. This is, in my opinion, the only
viable way to finally reappropriate the email service correctly.

Our partial solution is therefore an SMTP relay. This means that under a
specific domain name:
- you can send an email
- you can receive emails **that will be forwarded to your real email address**

In other words, we do not implement an IMAP server. You can get a slightly more
technical but still global description [here][mirage-smtp].

### Unikernels

It is important to understand that such a service can be a milestone for
unikernels. It was always possible to develop unikernels that could talk to more
conventional services (and vice versa).

This is still the case with our SMTP stack, but this time all the necessary
parts can be unikernels! In this series of articles, we will see how to deploy
all these unikernels:
- a primary DNS server
- a DNS resolver
- a secondary DNS server to be able to do Let's encrypt challenges
- a submission server (to submit emails)
- a DKIM signer
- a SMTP server to send incoming emails (from a private network) to Internet
- a SPF verifier
- a spam filter

As you can see, we have several unikernels to deploy. The idea is that each
service can be replaced by a conventional (unix) service. For example, you could
have your own service that does DKIM signing and that would not prevent the
other unikernels from being deployed.

This method is particularly about always offering the end user a way out in what
he/she uses (he/she can't be forced to use all our unikernels) but also about
debugging our infrastructure properly and piece by piece.

This is also why we have divided this article into 3 parts:
1) the first (this one) consists of the deployment of our DNS service
2) the second one is about our ability to send an email
3) finally, it will be about receiving emails

## A provider and a domain-name

This may be the only part where your wallet will be required (unfortunately not
for me). One limitation we have about unikernels is the server.

Indeed, to be able to deploy a unikernel requires access to virtualization
through Xen or KVM. The latter is very popular but usually requires a
_bare-metal_ server: a real physical server.

Of course, Mirage offers other ways like deploying a service with seccomp (which
only requires a basic Linux). But it is common (for Mirage users) to prefer KVM
simply to use [`albatross`][albatross] and to configure the infrastructure well
on all levels (which can be very difficult with Google Cloud for example). In
this respect, a bare-metal server can be (very) expensive. As an example, my
server costs ~40 euros per month which is quite a lot - of course, I have a very
high usage for all my unikernels (9 at the time of writing).

It's quite understandable that some users can't afford to invest in it. There
are however inexpensive solutions. VPS with nested KVM support! The idea is to
offer the user a complete virtualised system that can virtualise (and therefore
run our unikernels).

This offer is never explicit, but if you have a VPS, it doesn't cost you
anything to know if you can have nested virtualisation. In order to explain all
the steps, I found [this provider][launchvps] that offers nested virtualization
and where the prices are affordable. A VPS with 2 cores seems to be sufficient
for our use.

Another necessary element for the emails is a domain name. You probably know
better providers than me. The special thing here is that we will not let these
providers take care of our domain name but we will do it ourselves! **Be careful
though**, it is clear that using a domain name for emails can then lead to it
being registered in deny-lists!

Indeed, I have rather spoken of a monopoly as far as emails are concerned and
this is also the criticism that one finds most often when it comes to managing
one's own email service. It is easy for a domain name to fall into the
deny-lists of Gmail or Outlook for obscure reasons (resulting from those famous
tacit rules explained above). I therefore advise you to take a domain name that
is not very important to you.

For those who have been following me for a long time, I own the domain
x25519.net. The story behind this is that my original domain name (osau.re)
has been taken over by a Chinese construction company... So I used this first
one but having recovered osau.re, it is no longer of much use to me. So we will
use **x25519.net** here to deploy our email service (provided by
[gandi.net][gandi.net])

### Host operating system

I am primarily a Debian/Ubuntu user. So we will use **Debian 11** in this series
of articles. It is perhaps the most used system. However, as far as deploying
unikernels is concerned, FreeBSD or OpenBSD also work.

Indeed, a fairly constant work that I try to maintain is the support of Solo5
for these platforms. The system should clearly not be a limitation (as is KVM
support for example).

## Bridge, `albatross` and user

Many people don't understand this black magic, but for the deployment of a
unikernel, we need a bridge. The aim is to connect "virtual cables" between our
unikernels and this bridge so that they can at least communicate with each
other. 
```sh
            [ bridge:service ] 10.0.0.1
	     |    |    |    |
	.----'    |    |    '----.
[ tap100 ] [ tap101 ][ tap102 ] [ tap103 ]

 10.0.0.2   10.0.0.3  10.0.0.4   10.0.0.5
```

It's really like having a [bridge][bridge] and having 4 computers connected to
that bridge with an ethernet cable. The _tap_ interfaces will be created by
`albatross` and our unikernels will connect to them. We will associate an IP
address for each unikernel.

This is the way to create a private network. Unikernels can communicate with
each other but the Internet cannot communicate with them and they cannot
communicate with the Internet.

To make the bridge, the best way is to install `bridge-utils` and modify the
`/etc/network/interfaces` file to add it:
```sh
$ apt install bridge-utils
$ cat >/etc/network/interfaces <<EOF


auto service
iface service inet static
  address 10.0.0.1
  netmask 255.255.255.0
  broadcast 10.0.0.255
  bridge_ports none
  bridge_stp off
  bridge_fd 0
  bridge_maxwait 0
EOF
$ reboot
$ ip a
3: service: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 42:ea:2f:4e:99:33 brd ff:ff:ff:ff:ff:ff
    inet 10.0.0.1/24 brd 10.0.0.255 scope global service
       valid_lft forever preferred_lft forever
```

### `iptables`

We have our own private network but we would like to communicate with the
outside world and make sure that the outside world communicates with us. This
is where we will use `iptables` to configure our "nat" to forward:
1) some incoming connections (notably our emails but also our DNS requests)
2) let the host system handle outcoming packets between the unikernels and the
   Internet. This requires the host system to rewrite the TCP/IP packets to
   replace the unikernel private IP with your public IP. This mechanism is
   called `MASQUERADE`

[launchvps]: https://cp.launchvps.com/index.php
[gandi.net]: https://gandi.net/
