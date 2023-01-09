---
date: 2022-12-15
article.title: Deploy an SMTP service (2/3)
article.description:
  How to deploy a SMTP service to send emails
tags:
  - OCaml
  - MirageOS
  - SMTP
  - Deployement
---

In our [previous][previous-article] article, we saw how to deploy 2 essential
services for emails:
the DNS stack. This basically means that:
1) you have a domain name (this will be your identity on the Internet)
2) this domain name is managed by your unikernel (you don't have any
   intermediary regarding the propagation and changes of your domain name)
3) you have a DNS resolver which allows you to control the end-to-end
   communication of your services with those of the Internet via the DNS
   protocol

It is important to understand that this is a question of reappropriating the
means of communication. We are now going to try to deploy a service allowing us
to send an email under our domain name.

This service consists of 4 unikernels and a "meta" information on the DNS stack:
1) a unikernel that manages authentication and allows only certain people to
   send an email
2) a unikernel signing emails with a DKIM key
3) a unikernel that can communicate with the outside world and our DNS resolver
   in order to send our email to inboxes
4) a unikernel that manages the obtaining of TLS certificates (one of which will
   be used by our first unikernel - we would like to send our emails from home
   to our unikernel via an encrypted channel)
5) Finally a DNS information informing services like Gmail where our emails
   should be sent from - this is the SPF framework.

For the example, we use a server whose public address is **76.8.60.93** and
whose domain name is **x25519.net**.

## SMTP protocol

The SMTP protocol is a very basic protocol that consists in transmitting an
email to a server. The key point to understand is that the transmission may not
be only between the sender and the recipient. The email may well go through
"stages".

There is also a mechanism specific to SMTP (deprecated) where it is necessary to
specify an explicit route in the transmission of an email such as:
`<@gmail.com:dinosaure@x25519.net>` where the email will first pass through the
Gmail service and then be sent back to x25519.net.

In this respect, an email can (and quite commonly does) pass through several
SMTP servers. Each of them makes choices about the retransmission and often adds
information. The most common piece of information added is the `Received` field,
which "marks" the email as having been forwarded to a particular service. You
can even have fun (well... [I had fun][received]) drawing the path that an
email has taken!

This being said, our email service is essentially a composition of several SMTP
servers in a private network. Each server has a specific purpose and strictly
retransmits the email received, adding the information required.

That's why I developed [ptt][ptt], a very small framework that allows to manage
the reception and the sending of emails. This framework allows you to implement
the real purpose of the SMTP server (sign the email, resend it, notify it as
spam, etc.). Thus, all unikernels derive from this little project.

## SPF & DKIM

Services like Gmail, when they receive an email to one of their users (like
`romain.calascibetta@gmail.com`), try to verify 2 key pieces of information:
1) the DKIM signature. This is to prove that the content received has not been
   altered. The email contains a signature and the receiver can recalculate this
   signature via a key it obtains via a DNS request and the content of the email
   as it receives it. If this signature matches the one announced in the email,
   it means that there has been no tampering.
2) the IP of the sender. The service will then make another DNS request to the
   sender's domain name and the sender must allow the same IP address as seen by
   the receiver. Pragmatically, 76.8.60.93 will be our address allowed to send
   emails.

These two security features allow to prove 2 things: the integrity of the
content of the email and the identity of the sender. If these two pieces of
information are correct, services like Gmail will consider that the email
received was sent by a **legitimate identity**.

In any case, at the time of writing, it is impossible for an email sent without
this information to be accepted by Gmail... It is also important to understand
that the identification as spam comes later.

These mechanisms are therefore essential elements in the deployement of an email
service.

### The DKIM signer

This is perhaps the simplest unikernel! Its purpose is to sign a received email
with a private key and forward it to a fixed destination.

```
                     [ DNS primary ]
                            |
             [ nsupdate with our public key ]
                            |
-[ email via SMTP]-> [ DKIM signer ] -[ signed email via SMTP ]-> 10.0.0.5:25
                       10.0.0.4:25
```

The idea is that any incoming email will be signed and sent back to 10.0.0.5
which will be another unikernel. When our unikernel is booted, a command
(`nsupdate`) will be made to inform our primary DNS server of the public key and
register it so that it is available to all external services such as Gmail.

Again, these services need the public key in order to verify the signature
announced by the received email. We can already have fun, as long as we are our
primary DNS server, deploying this service and using it! We'll also use a tool
I'm developing in my spare time, [blaze][blaze]. It's a Swiss army knife for
handling, sending and receiving emails.

```sh
$ apt install libcurl4-gnutls-dev
$ opam pin add -y https://github.com/dinosaure/blaze.git
$ dd if=/dev/urandom bsd=32 count=1|base64 -
iI9jJBB/XLd6r0C1cNobumjKRyMfnGKKb6nYFJ5dD48=
$ cat >dkim.key <<EOF
iI9jJBB/XLd6r0C1cNobumjKRyMfnGKKb6nYFJ5dD48=
EOF
$ wget https://builds.osau.re/job/signer/build/latest/f/bin/signer.hvt
$ cat >signer.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service signer signer.hvt \
	--arg="--domain=x25519.net" \
	--arg="--dns-key=personal._update.x25519.net:SHA256:PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M=" \
	--arg="--destination=10.0.0.1" \
	--arg="--dns-server=10.0.0.3" \
	--arg="--ipv4=10.0.0.4/24" \
	--arg="--ipv4-gateway=10.0.0.1" \
	--arg="--postmaster=hostmaster@x25519.net" \
	--arg="--private-key=$(cat dkim.key)" \
	--arg="--selector=s1"
EOF
$ chmod +x signer.sh
$ ./signer.sh
host [vm: :signer]: success: created VM
```

Here we have to explain several things. Firstly, we will set up what is needed
to get `blaze`. Then, we generate a _seed_ that will generate an RSA key to sign
our emails. We save this key in the file `dkim.key`. Finally, we download the
unikernel `sign.hvt` from [our reproducibility infrastructure][reproducible] and
run our startup script.

Finally we launch our unikernel and, as we mentioned, the unikernel will try to
modify the zone file of our domain **x25519.net**. This is why it needs the
`--dns-key` argument (see our [previous article][update-my-primary-git] on how
to update our primary DNS server) and the `--dns-server` argument (the private
IP address of our primary DNS server).

The `--destination` option is also important. For our test, we use 10.0.0.1
since we will be running an SMTP server locally **for testing**. But later on,
we will specify the IP address of our next unikernel.

There are two pieces of information about DKIM: `--private-key` and
`--selector`. The first one is waiting for the _seed_ we just generated
(available into our `dkim.key`). The second defines _the selector_.

It is indeed possible to have several DKIM keys for the same domain. The
"selector" allows you to choose a specific one. The methodology behind the
selector may differ between email services. Some consider a selector by group,
others by date (with key expiration mechanisms) and still others by user (one
key per user...). In short, here we will define one `s1` selector which will be
used all the time.

After launching the unikernel, we can have fun seeing the new version of our
zone file:

```sh
$ cd zone
$ git pull
$ git log --oneline | head -n1
c1fdc87 10.0.0.4 changed x25519.net
$ dig +short TXT s1._domainkey.x25519.net @10.0.0.3
"h=sha256; v=DKIM1; p=...; k=rsa;"
```

Finally, we can have fun, using `blaze`, to launch a small SMTP server and send
an email directly to our signer:

```sh
$ blaze.srv -o new.eml &
$ cat >send.sh <<EOF
#!/bin/bash

blaze.make <<EOF \
  | blaze.send --sender foo@bar -r romain.calascibetta@gmail.com - 10.0.0.4
Hello World!
EOF
$ chmod +x send.sh
$ ./send.sh
$ cat new.eml
Received: from x25519
 by x25519.net
 via tcp with esmtp id <00000000@x25519.net> 
  for <romain.calascibetta@gmail.com>;
 Tue, 20 Dec 2022 14:03:56 GMT
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=x25519.net; s=s1; 
  q=dns/txt; bh=z85OKVJZHnmg3qFlSpLbpPCZ00irfBdrzQUtabiSl3A=; h=from; b=gkgejf
  MJH0CBcJ1HyhV2xRIn98DM5KMfK+8noZhKkvdg+JgHCitG8r48+pNKH7C2QsdIjaRSrn1vfSDKS0
 yADaYzfiN6sDm3H13ZGFBt/2dDZEh0j4PbM0ZixDP7ZdTAvETRfVcPKEuEAtzIKT7SlvWaig0TyXi
 Tx53Z3HdagKtzGk8VICCnGHIcjXmn9af9u4nv+ocp5GQ0EmY8WvRNkQxQ9fSs1b3XfLtdsXh/5b2p
 JewMX8BDnNxeV/O+4058nbUvZ6Tedfit58nNqd9PDqMbTpcbQtmVChCTxGWMor6YXvapvf5ioPcdQ
 56XMKvHbAp9fwc9dIhTvPEGhM4E/w==; 
Date: Tue, 20 Dec 2022 09:03:56 -0500
Content-Transfer-Encoding: 7bit
Content-Type: text/plain; charset=utf-8

Hello World!
```

Our email, originally made using `blaze.make` only contained the date,
`Content-Type` and `Content-Transfer-Encoding` (you can change these
informations, e.g. `blaze.make --help`). We add a simple "Hello World" and send
it to our signer. The signer will then sign the email and add the
`DKIM-Signature` field with the famous `bh` signature. It specifies several
information like the selector `s1` or the domain. Several options exist for our
signer like signing specific fields (like `From` or `To`, see `--fields`
option).

We can also note a new field, `Received`. As explained above, it allows to trace
the path of our email and we notify that it has passed through our signer via
TCP/IP with a specific ID.

What's more, if the DNS propagation has gone well (and our new `s1._domainkey`
field is available via `dig`), we can even have fun checking our own email!

```sh
$ apt install dos2unix
$ dos2unix new.eml
$ blaze.dkim verify new.eml
[OK]: x25519.net
```

That's it! We have our little unikernel for signing emails. On top of that, it
automates the necessary changes to our primary DNS server. After the information
has been propagated, the first level of security required to send emails is
deployed! Don't forget to change the `--destination` argument of our unikernel
by the IP address of our second unikernel: the sender.

### The Sender

This unikernel plays perhaps the most critical role in sending an email. It
attempts to send emails inbound to the Internet. In truth, this unikernel will
be the only one able to communicate with the Internet (but the Internet will not
be able to communicate with it). It will also have a use for our DNS resolver.
Indeed, sending an email is simply a matter of looking at the domain of the
recipients and forwarding the email to the SMTP service of those domains - it
then needs to be able to "resolve" the domains (and more specifically the `MX`
field of those domains).

```sh
$ dig +short MX gmail.com
5 gmail-smtp-in.l.google.com.
20 alt2.gmail-smtp-in.l.google.com.
30 alt3.gmail-smtp-in.l.google.com.
10 alt1.gmail-smtp-in.l.google.com.
40 alt4.gmail-smtp-in.l.google.com.
```

But this unikernel does something else too. It is the unikernel to act as a
relay. It won't receive all the emails going to `x25519.net` directly (we'd like
to do some upstream checking but we'll see that in part 3), but it will take
care of translating the `x25519.net` recipients to their real email addresses.
After this translation (from `romain@x25519.net` to
`romain.calascibetta@gmail.com` for instance), it will forward the emails to
their real destinations (Gmail, Outlook, etc.).

Of course, in order for the unikernel to know the real destinations, we will
use... a Git repository!

#### The Git repository for users

So we'll create a local Git repository that contains our users. To these, we
will associate a password (for our next unikernel) and the real email.

```sh
$ su git
$ cd
$ mkdir users.git
$ cd users.git
$ git init --bare
$ exit
```

Fortunately, the ptt project has several utilities that allow us to interact
with the Git repository and add our users to it without "directly" manipulating
the Git repository. Indeed, the files will have to have a very standard format
expected by our unikernel, it is only JSON but to avoid typing errors, it is
better to use these tools<sup>[1](#fn1)</sup>.

```sh
$ opam pin add https://github.com/mirage/ptt.git
$ opam install ptt-bin
$ eval $(opam env)
$ ptt.adduser -r git@localhost:users.git#master dinosaure \
  <password> -t romain.calascibetta@gmail.com
```

We have just added a new `dinosaure` user. This means that we can send an email
as `dinosaure@x25519.net` now. Finally, all emails to this address will go to
`romain.calascibetta@gmail.com` (you can put in more than one address if you
like). The password is not used yet, but it will be used in our last unikernel,
the one that handles authentication.

<tag id="fn1">**1**</tag>: Our `ptt.adduser` will use our personal SSH key and
more factually directly use `ssh` to do the git push (`ssh-agent` can then
intervene too). More complex usage (such as specifying a precise SSH key for the
transfer) is not yet implemented and so the tool may not work for some obscure
reason - unless you have been following the articles!

#### The SMTP relay

As with the signer, we will download our unikernel from our infrastructure and
create a shell script to properly launch our unikernel with `albatross`.

```sh
$ wget https://builds.osau.re/job/relay/build/latest/f/bin/relay.hvt
$ cat >relay.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service relay relay.hvt \
	--arg="--domain=x25519.net" \
	--arg="--nameserver=tcp:10.0.0.2" \
	--arg="--postmaster=hostmaster@x25519.net" \
	--arg="-r git@10.0.0.1:users.git#master" \
	--arg="--ssh-key=ed25519:$(head -n1 ssh.key | cut -d' ' -f4)" \
	--arg="--ipv4=10.0.0.5/24" \
	--arg="--ipv4-gateway=10.0.0.1"
EOF
$ chmod +x relay.sh
$ ./relay.sh
host [vm: :relay]: success: created VM
```

As you can see, in addition to the relative information for the Git repository,
we have the `--nameserver` option where we specify the DNS resolver we want to
use (and, here, we are going to use ours).

We also need to relaunch our signer with the correct destination, that of our
relay:

```sh
$ sed -i "s/destination=10.0.0.1/destination=10.0.0.5/" signer.sh
$ albatross-client-local destroy signer
$ ./signer.sh
host [vm: :signer]: success: created VM
```

#### SPF metadata

Before trying to send an email, we will add one last piece of information to our
DNS stack: the IP address that is allowed to send our emails. This way, services
like Gmail, when they receive an email from one of our users, will be able to
verify that the IP address trying to send an email matches the one notified in
our zone file.

Again, SPF rules can be complex. Indeed, we may have some policy very intrinsic
to the way we deploy our email service (having multiple submission servers from
which our emails can be sent - users would then choose one of them based on its
geographical location for example... in which case, you need to specify a set of
IP addresses rather than just one). But in our case, let's keep it simple and
specify our single public IP address as the one that is allowed to send our
emails.

```sh
$ ptt.spf 10.0.0.3 \
  personal._update.x25519.net:SHA256:PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M= \
  x25519.net "v=spf1 +ip4:76.8.60.93 -all"
$ cd zone
$ git pull
$ git log --oneline | head -n1
5cffdb9 10.0.0.1 changed x25519.net
$ cat x25519.net | grep spf1
@	TXT	"v=spf1 +ip4:76.8.69.93/32 -all"
```

#### Send an email locally to Internet

While waiting for information about SPF to spread, we can still try sending an
email with the [yopmail][yopmail] service. We will therefore create a new
address with this service, say: `foo@yopmail.com`. And we'll use `blaze` to send
an email locally directly to our DKIM signer. The latter will forward it to our
relay and finally the relay will send it to yopmail!

```sh
$ cat >send.sh <<EOF
blaze.make \
    --to $1 \
    --from dinosaure@x25519.net \
    -f "Subject:Hello World" <<EOF \
  | blaze.send \
    --sender dinosaure@x25519.net -r $1 \
    - 10.0.0.4
Hello World!
EOF
$ chmod +x send.sh
$ ./send.sh foo@yopmail.com
```

That's it! You should receive an email on your yopmail account. If the DNS
propagation was done on the SPF data, you can try to send it to a Gmail address.
You can test the propagation with the website:
[https://dnschecker.org/][dnschecker]

### Let's encrypt and DNS

We only have 2 unikernels left! The first one will be used to make the
Let's encrypt challenge in order to obtain a TLS certificate and launch our
submission unikernel with it.

In detail, a Let's encrypt challenge can be done in 2 ways: by DNS or by HTTP.
You can see an example of the latter with [`contruno`][contruno]. In our case,
to avoid an explosion of protocols involved in our infrastructure, we will use
the first one.

The idea is to launch a unikernel that receives certificate requests and
communicates with our primary DNS server (**locally**) to complete the
challenges. In this way, it will:
1) keep locally the certificates already obtained
2) manage the challenges
3) transmit the certificates to our other unikernels (in this case, our
   submission unikernel) _via_ the primary DNS server

```sh
$ wget https://builds.robur.coop/job/dns-letsencrypt/build/latest/f/bin/letsencrypt.hvt
$ dd if=/dev/urandom bs=32 count=1|base64 -
/m/in8tIYG2hgX8AAG+cnVB6zzFlxUdJEb3q9GkrLOE=
$ cat >letsencrypt.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service letsencrypt letsencrypt.hvt \
	--arg="--email=<your-email>" \
	--arg="--account-key-seed=/m/in8tIYG2hgX8AAG+cnVB6zzFlxUdJEb3q9GkrLOE=" \
	--arg="--dns-key=personal._update.x25519.net:SHA256:PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M=" \
	--arg="--production" \
	--arg="--dns-server=10.0.0.3" \
	--arg="--ipv4=10.0.0.6/24" \
	--arg="--ipv4-gateway=10.0.0.1"
EOF
$ chmod +x letsencrypt.sh
$ ./letsencrypt.sh
host [vm: :letsencrypt]: success: created VM
```

This unikernel will observe our zone file. When our submitting unikernel
attempts to obtain a certificate, it will make its request to our primary DNS
server. The primary DNS server will notify our `letsencrypt` unikernel which
will actually make the expected challenge and modify the zone file accordingly
to complete the challenge.

Once the challenge is complete, the certificate is saved in the zone file and
can be retrieved by our submitting unikernel.

This unikernel takes care of reapplying for certificates that will expire in 14
days. In short, it is a [`certbot`][certbot] with a harissa^Wmirage sauce!

### Submission unikernel

Finally, we have just about everything we need to finally launch our submission
unikernel. Once again, we'll download it from our infrastructure. However, we'll
pay close attention to one parameter: the domain name. In our email service,
we have to separate the receiving domain name from the sending domain name, and
the two are usually different.

In our case, we will use the domain `smtp.x25519.net` here. And it is on this
domain that we can send our emails! We need to add it to our zone file and
update our primary DNS server.

```sh
$ cd zone
$ git pull
$ echo "smtp A 76.8.60.93" >> x25519.net
$ ... modify the serial number on the SOA record ...
$ git add x25519.net
$ git commit -m "Add smtp.x25519.net"
$ git push
$ cd
$ ./update.sh
notifying to 10.0.0.3:53 zone x25519.net serial 1
successful TSIG signed notify!
```

We can now launch our unikernel correctly.

```sh
$ wget https://builds.osau.re/job/submission/build/latest/f/bin/submission.hvt
$ dd if=/dev/urandom bs=32 count=1|base64 -
DNEyBXLa7959WAL53oxwi54EIaN+2jN7whKNXMfRJHw=
$ cat >submission.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service submission submission.hvt \
	--restart-on-fail \
	--arg="--destination=10.0.0.4" \
	--arg="--dns-key=personal._update.x25519.net:SHA256:PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M=" \
	--arg="--dns-server=10.0.0.3" \
	--arg="--domain x25519.net" \
	--arg="--postmaster=hostmaster@x25519.net" \
	--arg="-r git@10.0.0.1:users.git#master" \
	--arg="--ssh-key=ed25519:$(head -n1 ssh.key | cut -d' ' -f4)" \
	--arg="--submission-domain=smtp.x25519.net" \
	--arg="--key-seed=DNEyBXLa7959WAL53oxwi54EIaN+2jN7whKNXMfRJHw=" \
	--arg="--ipv4=10.0.0.7/24" \
	--arg="--ipv4-gateway=10.0.0.1"
EOF
$ chmod +x submission.sh
$ ./submission.sh
host [vm: :submission]: success: created VM
```

You can notify the occurrence of a `key-seed` argument. Indeed, our submission
server can turn itself off (and on again with `--restart-on-fail`) but to avoid
that it asks for a new certificate every time it turns on, we have to specify a
specific key.

The information about our primary server is also expected to obtain the TLS
certificate (via our `letsencrypt` unikernel). There is also the use of the Git
repository to get the users and their passwords and finally the
`--submission-domain` corresponding to the domain we want to use to send emails.
Note also that the destination refers to our signer!

We can then, once again, have fun but this time, the communication between us
and the submission server will be secure (thanks to TLS) and we will have to
authenticate ourselves:

```sh
$ cat >submit.sh <<EOF
#!/bin/bash

eval $(opam env)
blaze.make \
	--to $1 \
	--from dinosaure@x25519.net \
	-f "Subject:Hello" <<EOF \
  | blaze.submit -p "$2" -r $1 -s dinosaure@x25519.net \
        - 10.0.0.7
Hello World!
EOF
$ chmod +x submit.sh
$ ./submit.sh foo@yopmail.com <password>
```

Our last goal is to redirect TCP/IP connections from port 465 (the submission
port) to our unikernel:

```sh
$ iptables -t nat -N SUBMISSION
$ iptables -t nat -A SUBMISSION ! -s 10.0.0.7/32 -p tcp -m tcp --dport 465 \
  -j DNAT --to-destination 10.0.0.7:465
$ iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j SUBMISSION
```

### Thunderbird and "outgoing" SMTP server

You can now use software like Thunderbird to send emails under the identity
**x25519.net**! As for Thunderbird, creating an account requires IMAP access
which we do not have. However, from an existing account, you can add a new
identity. By entering `smtp.x25519.net:465`, your name and your password, you
can choose this new identity when sending a new email.

## Troubleshouting

It can happen that an email you have sent is not actually sent. There are a
number of errors in this case:
- the SMTP server has received the email but does not register it (at least, it
  does not report any errors)
- the DNS resolution (for the MX field) did not work
- the SMTP server has invalidated the reception

For the last case, you can see in the logs the reasons why the mail was
invalidated. For the second case, we can complete the relay with another
nameserver (more stable like `--nameserver tcp:8.8.8.8` instead of our
resolver). Finally, the first case is possible and there are no real
solutions...

### Return-Path

Currently, `ptt` does not yet implement the "Return-Path". Remember, each server
adds a trace to the email, there may also be a "Return-Path" which informs the
SMTP server that if an error occurs, it should resend an email to that
destination (specifying the trace).

The difficulty with this mechanism is that you can have an "infinite loop of
emails". An error to the `Return-Path` can have its own `Return-Path` and result
in an error... For example, x25519.net can send an error email to gmail.com (and
which has foo.com as its destination for example) with the `Return-Path` to
x25519.net. Gmail may then have an error and want to send the error back to
x25519.net which may retry sending to foo.com...

This is why the RFC about emails makes a point of saying that you should keep
the last ~ 100 emails sent and if you get one back with the same `Message-ID`
(also informed in the `Received`), you stop the loop.

For the smart ones, this way of "breaking" the loop is not really effective, an
email with a certain domain route could pass this test without difficulty (if
100 emails are passed before this email by the server having recognized the
error)... And it does! As I speak, there is an infinite loop of emails (mostly
spam) that is continuously lying around the Internet...

This case however concerns the unikernel that we will deploy in our next
article. We can consider that opening port 25 is opening the doors to email
hell!

## Conclusion

We've actually done most of this series, the rest will be simple as our Git
repositories are all deployed. Only 2 unikernels are missing:
- The one that will take care of the gateway to hell
- The second one that will identify emails as spam or not

The latter will directly reuse our relay to send emails back to the Internet.
This relay will be careful to translate our x25519.net addresses to our real
addresses.

The first unikernel is important because it will check the SPF data (and to do
so, it must be on "the front end" to recognize the public IP address of the
senders).

Anyway, you can send emails under your authority now, they will probably get
spammed for some but that problem is outside the scope of this series of
articles. The next article is available [here][next-article]!

[blaze]: https://github.com/dinosaure/blaze
[received]: https://twitter.com/Dinoosaure/status/1372903235778908163
[ptt]: https://github.com/mirage/ptt
[reproducible]: https://blog.osau.re/articles/reproducible.html
[update-my-primary-git]: smtp_1.html#how-to-update-my-primary-git
[yopmail]: https://yopmail.com/
[contruno]: https://github.com/dinosaure/contruno
[certbot]: https://certbot.eff.org/
[dnschecker]: https://dnschecker.org/
[next-article]: smtp_3.html
[previous-article]: smtp_1.html
