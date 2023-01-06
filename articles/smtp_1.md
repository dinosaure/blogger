---
date: 2022-12-06
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

Finally, we will install `albatross` (and the micro-kernel [Solo5][solo5]) which
allows us to deploy our unikernels correctly:
```sh
$ apt install gnupg
$ wget -qO- https://apt.robur.coop/gpg.pub | sudo apt-key add -
$ echo "deb https://apt.robur.coop ubuntu-20.04 main" >> /etc/apt/sources.list
$ apt update
$ apt install solo5 albatross
$ systemctl enable albatross_stats
$ systemctl enable albatross_daemon
$ systemctl enable albatross_console
$ systemctl start albatross_daemon
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

However, we will do this as we go along to really understand the implications of
our `iptables` commands. So let's start by deploying some of our unikernels.

## The DNS stack

Email relies on another widely used protocol which is the DNS protocol. Beyond
being able to exchange emails, the first objective in the deployment of an
infrastructure (for an association or a company) is to "present" itself to the
Internet and to inform where is located what will become one of the central
parts of your infrastructure: your primary DNS server.

On the "other side", you also need to have access to the Internet and be able to
resolve domain names and know where they are located (as you do, to know where
you are located).

We are talking about 2 distinct services that use the same protocol:
- a server that tells you where its infrastructure is located (its IP address)
- a server that is able to tell where the infrastructures/authorities are
  located according to their domain names

The second service is often **already** offered. The best known resolver (but
perhaps the one you should be most wary of) is Google with its DNS resolver
[8.8.8.8][google-dns]. In our case, we prefer to use DNS resolvers like
[uncensoreddns][uncensoreddns]. Better than that, it is more interesting to
deploy your own DNS resolver to avoid censorship and you can do it with a
unikernel!

### The DNS resolver

The idea of the DNS resolver is to be used internally. From an external point of
view, it is not necessary. On the other hand, for our future unikernels for
emails, some will use this DNS resolver to resolve the MX field and to know
where the email server where we have to send our emails is located.

Fortunately, the [Robur][robur] association builds and distributes unikernels
for you. We could look at how to build a unikernel here but we'll concentrate on
deployment. So you can download the image (`bin/resolver.hvt`) here:

[https://builds.osau.re/job/dns-resolver/build/latest/][dns-resolver]

Secondly, it is about:
1) allowing the DNS resolver to communicate with the outside world (with
   `iptables`)
2) use `albatross` to launch the unikernel `resolver.hvt`

```sh
$ echo "1" > /proc/sys/net/ipv4/ip_forward
$ iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -j MASQUERADE
$ wget https://builds.osau.re/job/dns-resolver/build/latest/f/bin/resolver.hvt
$ cat resolver.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=64 \
  --net=service:service resolver resolver.hvt \
  --restart-on-fail \
  --arg="--ipv4=10.0.0.2" \
  --arg="--ipv4-gateway=10.0.0.1"
EOF
$ chmod +x resolver.sh
$ ./resolver.sh
host [vm: :resolver]: success: created VM
$ apt install dnsutils
$ dig +short google.com @10.0.0.2
142.251.40.110
```

That's it! The last line with the `dig` utility confirms that our unikernel
works and can resolve domain names.

You have probably noticed the "restart-on-fail" option. This option will restart
the unikernel if it goes down. About this option, it comes from the fact that we
have been observing (for quite some time [now][memory-leak]) memory leaks in our
unikernels. However, we have to admit that the boot time of the unikernel is
very fast. In this respect, the interrupt should be almost transparent.

### The primary DNS server with Git

A fairly common design with unikernels is to use a Git repository to store
information that the unikernel will then synchronise to. The advantage here is:
1) the unikernel does not need a file system
2) it keeps track (with the Git history) of all changes
3) we can easily (with the Git tool) go back to a data state in which our
   unikernel is working

To do this, we use the [`git-kv`][git-kv] project which does exactly that. But
this requires a "Git server". In truth, Git doesn't really implement a server,
it implements tools that can wrap themselves in streams managed by servers (an
SSH server or an HTTP server). The basic deployment (explained by the [Git
manual][git-manual]) is to create a Git user, add _bare_ repositories and use
SSH to `fetch`/`push`.

```sh
$ apt install git
$ ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519 -N ""
$ adduser git
$ su git
git$ cd
git$ mkdir .ssh && chmod 700 .ssh
git$ touch .ssh/authorized_keys && chmod 600 .ssh/authorized_keys
git$ exit
$ ssh-copy-id $HOME/.ssh/id_ed25519 git@localhost
$ ssh git@localhost
git$ mkdir zone.git
git$ cd zone.git
git$ git init --bare
git$ exit
$ git clone git@localhost:zone.git
$ cd zone
$ git commit --allow-empty -m "First commit"
```

Here, we create what will become our Git repository<sup>[1](#fn1)</sup>
`zone.git` which will contain our [zone file][zone-file] for our domain name.

<hr />

<tag id="fn1">**1**</tag>: A common problem is the branch name, it seems to me
that the Debian 11 version of Git still uses the name "master" (instead of
"main"). In our case, we'll specify the branch in the arguments expected by our
unikernels - but keep in mind the branch you're using.

#### Git, SSH & unikernels

We now need to explain another aspect related to Git, unikernels and SSH
communication. When it comes to deployment and security, it is important not to
put carrots and potatoes in the same basket. Thus, providing an **exclusive**
communication channel between our unikernels and Git via SSH remains a
preferable solution.

The exclusivity in question here is **not to use** our SSH key (which we have
just generated) to ensure communication between our unikernels and Git but
rather to generate a new key which will only be used by our unikernels.

To do this, we have thought of everything, including a tool that can generate
keys _on the fly_ and give you a representation that you can then give to the
unikernel as an argument on the command line.

```sh
$ apt install opam
$ opam init
$ opam switch create 4.14.0
$ opam install awa
$ eval $(opam env)
$ awa_gen_key --keytype ed25519
ED25519 private key AqKcLX40SblHbAeZ63FCDXJD3xOiRUmCRxzxQFThEf4=
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3PyCx3KPc84KGXpel9uMwwKailyUWnoLICjSZo37Y7 awa@awa.local
```

The first line is our private key and the second line is the public key. The
latter will have to be added to the authorized keys for Git.

```sh
$ awa_gen_key --keytype ed25519 > ssh.key
$ tail -n1 ssh.key > unikernel_ed25519.pub
$ cat unikernel_ed25519.pub | ssh git@localhost "cat >> .ssh/authorized_keys"
```

#### Glue record and domain-name providers 

We need to understand one last point more specific to DNS. When we are in
possession of a domain name, the provider also offers the possibility to manage
the primary DNS server itself. This is the "basic" use of buying and using a
domain name.

However, in our revolutionary plan to re-appropriate the means of production,
we would like to manage our own domain name. To do this, we need to inform our
provider of the location of our primary DNS server. This involves adding a
"Glue record" informing the public IP address of our `ns1.<your-domain>` server.
Finally, we need to notify the provider that our primary DNS server is external
and corresponds to `ns1.<you-domain>`.

In my case, I must notify gandi.net that:
- my domain name is managed by `ns1.x25519.net` (and `ns6.gandi.net` is a
  secondary DNS server that Gandi offers<sup>[2](#fn2)</sup>)
- `ns1.x25519.net` points to `76.8.60.93` (my VPS) as "Glue record"

<hr />

<tag id="fn2">**2**</tag>: At the moment I have some issues with Gandi and it
seems that the transfer between the primary and secondary server requires some
undocumented mechanism. However, it is mandatory to have a second DNS server for
your domain name. We won't talk about the latter since it requires a second
public IP address... However, if you are in the situation where the primary
server cannot do the transfer, [Robur][robur] has a few secondary servers at its
disposal. Just contact us!

### Deploy your DNS primary Git

Our first objective is to create our "zone file". The latter must contain some
information, notably the SOA (Start Of Authority) field and say that it is the
authority managing our domain name.

This authority, we have informed with our provider (with Gandi) and we must
reaffirm it from our own primary server. Here, we inform that our authority is:
`ns1.x25519.net`.

Then, we affirm where `ns1.x25519.net` is located and, at the same time,
`x25519.net`.

```sh
$ cd zone
$ cat >x25519.net <<EOF
$ORIGIN	x25519.net.
$TTL	3600
@		IN	SOA	ns1	hostmaster	1	86400	7200	1048576	3600
@		IN	NS	ns1
@		IN	NS	ns6.gandi.net.
@		IN	A	76.8.60.93
ns1		IN	A	76.8.60.93
ns6.gandi.net.	IN	A	217.70.177.40
EOF
```

An update mechanism also exists with DNS and this can be password protected.
Indeed, our primary DNS server will make a "clone" of our Git repository. The
problem is if we modify this Git repository, do we have to restart our server?
The objective of such a service is to keep it alive as long as possible.

So, we will add such a password to be able to modify the Git repository and
notify our DNS server of such a change so that it can "fetch"/"pull" the
repository and update the zone file.

```sh
$ dd if=/dev/urandom bsd=32 count=1|base64 -
s1/eSOziiA+rvScunET9G9sEB6bDcIrHb/HdE2wexhE=
$ cat >x25519.net._keys <<EOF
personal._update.x25519.net. DNSKEY 0 3 163 PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M=
EOF
$ git add .
$ git commit -m "Insert x25519.net"
$ git push
$ cd $HOME
```

At last we can really deploy our server. In our series of articles, we will have
to modify the zone file a little bit but, thanks to the update mechanism, we
will not need to restart our server.

Note that the script to run the unikernel uses the `ssh.key` file. This is the
file in which we have saved our "in the fly" SSH key.

```sh
$ wget https://builds.robur.coop/job/dns-primary-git/build/latest/f/bin/primary-git.hvt
$ cat >primary-git.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service primary-git \
  primary-git.hvt --restart-on-fail \
  --arg="--axfr" \
  --arg="--ipv4=10.0.0.3/24" \
  --arg="--ipv4-gateway=10.0.0.1" \
  --arg="--ssh-key=ed25519:$(head -n1 ssh.key | cut -d' ' -f4)" \
  --arg="--remote=git@10.0.0.1:zone.git"
EOF
$ chmod +x primary-git.sh
$ dig +short x25519.net @10.0.0.3
76.8.60.93
```

All that remains is to allow the outside to communicate with our primary DNS
server. To do this, we will use `iptables`. Note that our last rule only allowed
unikernels to communicate with the outside. Now we need to redirect some packets
to our unikernels: in particular those arriving on port `76.8.60.93:53`.

```sh
$ iptables -t nat -N PRIMARY-GIT
$ iptables -t nat -A PRIMARY-GIT ! -s 10.0.0.3/32 -p tcp -m tcp --dport 53 \
  -j DNAT --to-destination 10.0.0.3:53
$ iptables -t nat -A PRIMARY-GIT ! -s 10.0.0.3/32 -p udp -m udp --dport 53 \
  -j DNAT --to-destination 10.0.0.3:53
$ iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j PRIMARY-GIT
```

On another machine, we can test the transfer mechanism that Gandi will use:

```sh
$ dig +short -t axfr x25519.net @76.8.60.93
ns1.x25519.net. hostmaster.x25519.net. 1 86400 7200 1048576 3600
ns6.gandi.net.
ns1.x25519.net.
76.8.60.93
76.8.60.93
ns1.x25519.net. hostmaster.x25519.net. 1 86400 7200 1048576 3600
```
**Warning**: The transfer operation (and the change of authority from your
provider to our primary DNS server) may take some time. Don't expect a simple
`dig +short x25519.net` to work immediately.

#### How to update my `primary-git`?

The DNS stack offered by [mirage][dns-mirage] provides tools including one to
notify the unikernel that it needs to resynchronise with the Git repository:
`onotify`.

```sh
$ opam install dns-cli
$ cat >update.sh <<EOF
#!/bin/bash

eval $(opam env)
onotify 10.0.0.3 x25519.net \
  --key=personal._update.x25519.net:SHA256:PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M=
EOF
$ chmod +x update.sh
$ ./update.sh
notifying to 10.0.0.3:53 zone x25519.net serial 1
successful TSIG signed notify!
```

And that's it! An **important note** when editing your zone file is the serial
number (here `1`). For each modification/addition, you must increment this
number otherwise these modifications will not be taken into account by the other
DNS servers. But we will see that in time.

### Conclusion

We finally deployed what will be essential for our unikernels and emails, our
domain name. For feedback, this is perhaps the oldest unikernel I'm actively
using!

This is perhaps the most important element in the deployment of any service.
Indeed, when it comes to websites, services like Bob, OpenVPN, etc. the domain
name remains your central identity on Internet.

Indeed, behind this identity, all your services will be articulated (as it is
the case for `osau.re`). The design is very pleasant: a very small unikernel
(11Mb) to manage a domain name as a full operating system with a Git history of
all changes made to the zone file, this ensures traceability and trust but above
all a reappropriation of such a basic but essential service for a small fee
(again, the VPS costs only ~ 8$... and other services will follow).

In the second part, we will focus on sending emails! This part will allow us to
solve two problems:
1) how to send an email to a Gmail and not get spammed (we will realize that,
   once again, the DNS service becomes central)
2) how to manipulate TLS certificates from services like Let's encrypt and send
   emails securely

I would like to mention that Hannes also made [an article][hannes-article]
explaining the deployment of a primary DNS server here. The big difference is
the slightly more practical case here, especially on details like "Glue
records". Anyway, as far as my services but also Robur's are concerned, again,
this is perhaps the oldest unikernel used. Reason enough to go ahead and use
MirageOS!

[launchvps]: https://cp.launchvps.com/index.php
[gandi.net]: https://gandi.net/
[uncensoreddns]: https://blog.uncensoreddns.org/
[dns-resolver]: https://builds.osau.re/job/dns-resolver/build/latest/
[git-kv]: https://github.com/roburio/git-kv
[git-manual]: https://git-scm.com/book/en/v2/Git-on-the-Server-Setting-Up-the-Server
[zone-file]: https://en.wikipedia.org/wiki/Zone_file
[hannes-article]: https://hannes.nqsb.io/Posts/DnsServer
[bob]: https://bob.osau.re/
[mirage-smtp]: https://mirage.io/blog/2022-04-01-Mr-MIME
[albatross]: https://github.com/roburio/albatross
[bridge]: https://en.wikipedia.org/wiki/Network_bridge
[solo5]: https://github.com/Solo5/solo5
[google-dns]: https://developers.google.com/speed/public-dns
[dns-mirage]: https://github.com/mirage/ocaml-dns/
[robur]: https://robur.coop/
[memory-leak]: https://github.com/mirage/mirage-tcpip/issues/499
[robur]: https://robur.coop/
