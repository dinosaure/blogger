---
date: 2023-01-03
article.title: Deploy an SMTP service (3/3)
article.description:
  How to deploy a SMTP service to receive emails
tags:
  - OCaml
  - MirageOS
  - SMTP
  - Deployement
---

Finally, the last part, we find ourselves with a fairly substantial
infrastructure now. Not only have we deployed our DNS service (with our primary
server and DNS resolver) but also an email submission service that allows us to
send emails under our authority.

The sending goes through different unikernels allowing to sign the content and
let the receivers check the integrity of the emails. We have added some
information to our file zone, notably the SPF field so that recipients can also
verify the source of our emails.

In short, at this stage, all that is missing is the reception of emails under
our authority in order to redirect them to their real destinations. We will take
the opportunity to analyse these emails in order to note them as spam or not and
to check the SPF data. These unikernels **don't** actually do any filtering,
they just add information that our IMAP server can manipulate and really filter.

## Spam filter

Perhaps it's in the old pots that good soup is made. The issue of spam
recognition can be complex. An email can be considered spam (like yours :p)
without being real spam in our opinion. The analysis is then based on
"heuristics" allowing to filter the bulk of the spam.

It turns out that our OCaml king has made an old project,
[spamoracle][spamoracle], which allows to filter emails. Carine then updated
this software under my supervision to make it a unikernel!

The project is called Spamtacus (my supervision extended to the name of the
library...) and is available [here][spamtacus].

Let's test this unikernel to see:

```sh
$ https://builds.osau.re/job/spamfilter-hvt/build/latest/f/bin/spamfilter.hvt
$ cat >spamfilter.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service spamfilter spamfilter.hvt \
	--arg="--domain x25519.net" \
	--arg="--destination=10.0.0.1" \
	--arg="--ipv4=10.0.0.8/24" \
	--arg="--ipv4-gateway=10.0.0.1" \
	--arg="--postmaster=hostmaster@x25519.net"
EOF
$ chmod +x spamfilter.sh
$ ./spamfilter.sh
$ blaze.srv -o new.eml &
$ cat >send.sh <<EOF
#!/bin/bash

blaze.make \
    --to $1 \
    --from dinosaure@x25519.net \
    -f "Subject:Lorem Ipsum" <<EOF \
  | blaze.send \
    --sender dinosaure@x25519.net -r $1 \
    - 10.0.0.8
Hello World!
EOF
$ ./send foo@bar
$ cat new.eml
Received: from x25519
 by x25519.net
 via tcp with esmtp id <00000000@x25519.net> for <foo@bar>;
 Wed, 4 Jan 2023 13:45:44 GMT
X-Spamtacus: unknown
Date: Wed, 4 Jan 2023 08:45:44 -0500
To: foo@bar
Sender: dinosaure@x25519.net
From: dinosaure@x25519.net
Content-Transfer-Encoding: 7bit
Content-Type: text/plain; charset=utf-8
Subject: Lorem Ipsum

Hello World!
```

As you can see, we have a new X-Spamtacus field that tells us it can't file the
email (there is too little information) and has returned the email to
`blaze.srv` (10.0.0.1). We'll remodify the `spamfilter.sh` file to put the IP of
our relay as the destination (10.0.0.5).

```sh
$ sed -i -e 's/destination=10.0.0.1/destination=10.0.0.5/' spamfilter.sh
$ albatross-client-local destroy spamfilter
$ ./spamfilter.sh
host [vm: :spamfilter]: success: created VM
```

### The database

The spam filter works on the basis of an already calculated database. It is
therefore fixed within the unikernel. If you want to change it, you have to
recalculate the db and recompile the unikernel with it.

The filter is a simple Bayesian filter from a word dictionary. The unikernel
adds the field `X-Spamtacus` with 3 possible labels:
- yes (it is a spam)
- no (it is not a spam)
- unknown (impossible to determine if it is a spam or not)

Then it returns the email like all our other unikernels.

### [`mrmime`][mrmime]

This one also uses the `mrmime` project for the first time, which allows you to
parse an email. This is crucial in what can go wrong when receiving emails.
`mrmime` tries to parse incoming emails but they can be malformed (for a
variety of reasons). In this case, it simply fails before the transfer and the
email will never reach you. However, I'm actively working on this problem so
that I can have a more resilient system.

I would like to highlight this project as it took me a long time to implement it
and get an interesting result. It is difficult to parse emails and `mrmime` can
be considered as the exception in its design since I really tried to respect the
RFCs.

This work allowed us to produce something even more interesting: checking a form
of _isomorphism_ between the decoder and the email encoder. Add to that a fuzzer
like [afl-fuzz][afl-fuzz] and you have the almost automatic production of
RFC-compliant emails that any email reading software should handle:
[hamlet][hamlet]!

## The SPF verifier and the MX record!

We will finally finish with our last unikernel, the one that will deal with the
famous port 25, the gates of hell! Indeed, this is where all emails to
`x25519.net` will arrive and there may even be emails to other destinations
(remember the routes in the email addresses...).

The special thing about this one is that it knows the public IP address of the
sender and so it is through this one that we can check the SPF data of the
domain if it matches the sender's IP. Here again, and I think you have just
understood the principle, the unikernel only adds a new field which will be the
result of the SPF verification.

This unikernel will do its SPF check from DNS requests, so it will use our DNS
resolver (10.0.0.2). It also needs a TLS certificate on our domain x25519.net
(not smtp.x25519.net) to give the senders the possibility to use
`STARTTLS`<sup>[1](#fn1)</sup>.

```sh
$ wget https://builds.osau.re/job/verifier-hvt/build/latest/f/bin/verifier.hvt
$ dd if=/dev/urandom bs=32 count=1|base64 -
rnM63JSKxhfo1L5WedIPlRD57bnfjg7SOJ47DhAlaAg=
$ cat >verifier.sh <<EOF
#!/bin/bash

albatross-client-local create --mem=256 --net=service:service verifier verifier.hvt \
	--arg="--destination=10.0.0.8" \
	--arg="--domain x25519.net" \
	--arg="--dns-key=personal._update.x25519.net:SHA256:PAPPkecDvEBnhqTzG5Xsbrbi7W0QY7TpVaEMxndMv2M=" \
	--arg="--dns-server=10.0.0.3" \
	--arg="--key-seed=rnM63JSKxhfo1L5WedIPlRD57bnfjg7SOJ47DhAlaAg=" \
	--arg="--nameserver=tcp:10.0.0.2" \
	--arg="--postmaster=hostmaster@x25519.net" \
	--arg="--ipv4=10.0.0.9/24" \
	--arg="--ipv4-gateway=10.0.0.1"
EOF
$ chmod +x verifier.sh
$ ./verifier.sh
host [vm: :verifier]: success: created VM
```

And that's it, now we just have to allow communication between the Internet and
our unikernel via iptables. The rules are similar to those for our submission
unikernel but it will be on port 25.

```sh
$ iptables -t nat -N SMTP
$ iptables -t nat -A SMTP ! -s 10.0.0.9/32 -p tcp -m tcp --dport 25 \
  -j DNAT --to-destination 10.0.0.9:25
$ iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j SMTP
```

Finally, we need to fill in the MX field<sup>[2](#fn2)</sup> to point to our
server so that the other services can send us an email. Before you change it,
make sure you **resynchronise**! `letsencrypt` has since added quite a bit of
information to the zone file.

```sh
$ cd zone
$ git pull
$ echo "@	3600	MX	0	x25519.net." >> x25519.net
$ ... modify the serial number on the SOA record ...
$ git add x25519.net
$ git commit -m "Add the MX record"
$ git push
$ cd
$ ./update.sh
```

<hr />

<tag id="fn1">**1**</tag>: This is because the first state in which an email is
sent is **unencrypted**! The server (our unikernel) is expected to implement
`STARTTLS` to wrap the communication in TLS. We will therefore obtain this
certificate with `letsencrypt` as with our submission unikernel.

<tag id="fn2">**2**</tag>: A notion of "priority" exists in the MX field.
Indeed, if the first service is not available, one can always communicate with
the next. What could be interesting is to put our unikernel as the first
available service and then put a more conventional service ([postfix][postfix])
as the second.

## `PTR` record

There is one final element missing from our SMTP stack, which is, once again,
DNS. Services such as Gmail expect certain information from you. We have already
seen that they necessarily expect a DKIM signature and SPF data. However, to
prevent spam, they expect one last piece of information which is the
"reverse DNS lookup".

The idea is that whoever allocated you your public IP address (76.8.60.93)
should add a `PTR` field to their zone file `60.8.76.in-addr.arpa` such as:

```
93	IN	PTR	x25519.net.
```

In my case, it is [launchvps][launchvps] where you can manage your DNS and add
the `PTR` field as required. It depends on your hosting company which should
let you add such a field.

Finally, the site [intodns.com][intodns] allows you to check that almost all the
requirements for the NS, MX and SOA fields are correct for the rest of the
Internet. More simply, you can check the reverse lookup with this command:

```sh
$ dig +short -x $(dig +short x25519.net)
x25519.net.
```

## The final test with Gmail!

The most effective test is to associate your Gmail account with your new
address. In your account "settings", you can add a new identity to "Send mail
as". The latter will ask you for several parameters such as the SMTP server
(`smtp.x25519.net`), the port (`465`), the security (`SSL`), your login and your
password.

In this case, Gmail will try a simple connection to our submission server and
see that it works (with the right credentials).

Then, to confirm your identity, it will send an email to `<login>@x25519.net`.
In our case, Gmail will then talk to our unikernel on port 25. The latter will
map `<login>@x25519.net` to your Gmail address that you specified in the Git
database.

This being said, the relay will then send the Gmail email back to your... Gmail
account! The loop is complete! In this email, a code has been sent to you that
you will need to use to confirm your identity with Gmail.

Let's recap:
1) you set up your Gmail <login>@gmail.com to have a new identity
2) it asks you for the submission server information
3) Gmail will then try your credentials to see if everything is correct
4) Gmail will then email <login>@x25519.net, so this time it will talk to our
   last deployed unikernel (the verifier)
5) The email will go through our spam filter and land on the relay
6) The relay will look at what <login>@x25519.net is associated with, say
   <login>@gmail.com
7) The relay will then send the email back to <login>@gmail.com
8) You should receive it in your mailbox

We can confirm these passages by looking at the sources of our email received by
Gmail. It contains 2 fields<sup>[3](#fn3)</sup>:

```bash
Received: from x25519.net by x25519.net via tcp with esmtp id
  <00000000@x25519.net> for <dinosaure@x25519.net>;
  Fri, 6 Jan 2023 14:56:34 GMT
X-Spamtacus: yes
```

We can now have fun sending an email under our new identity from our Gmail! For
the example, I decided to send an email to another of my addresses (Outlook) and
here is the result:

![ptt](../images/ptt.png)

In this email, 2 pieces of information are of interest:

```bash
Authentication-Results: spf=pass (sender IP is 76.8.60.93)
 smtp.mailfrom=x25519.net; dkim=pass (signature was verified)
 header.d=x25519.net;dmarc=bestguesspass action=none
 header.from=x25519.net;compauth=pass reason=109
Received-SPF: Pass (protection.outlook.com: domain of x25519.net designates
 76.8.60.93 as permitted sender) receiver=protection.outlook.com;
 client-ip=76.8.60.93; helo=x25519.net; pr=C
```

Here we have a confirmation that our SPF data is correct and that our DKIM
signature (available later in the mail) is the correct one. Since this email was
sent from my Gmail, other information has been added by Gmail which reinforces
the validity of the email so that it doesn't get spammed!

In short, we have done a complete tour of all our unikernels and everything
seems to work perfectly!

<hr />

<tag id="fn3">**3**</tag>: We can see that our spam filter considers the Gmail
email as spam!

## Conclusion

The SMTP stack is finally deployed! I hope that this series of articles has
shown you a little bit how unikernels are conceived in a "macro" way,
considering them as units more or less independent from each other and which
allow to propose a whole, an email service!

I also hope that the question of the deployability of a unikernel with Solo5 is
a bit clearer (with [albatross][albatross], [Solo5][solo5] and our [infra of
reproducibility][reproducibility]).

I also hope that this suite of articles shows the possibilities with MirageOS
and unikernels. I would like to point out that the last services offered by
`osau.re` and `x25519.net` are almost all unikernels! The SMTP stack catapults
us to another level where we can deploy **8 unikernels** together which is a
first in the history of MirageOS.

Now it's a matter of knowing how long all this will work and improve the
lifetime of the unikernels (especially on memory leaks) and thus really offer
resilient services.

Finally, I would like to inform the reader that this work is above all a
community work and it is indeed the aggregation of the work of several people
without any particular interest other than taking back control of the means of
communication. As such, and I think you are used to this, you can support us
[here][robur-donate]. I'd also like to inform the reader that this work, while
the practical goal is unikernels, also contributes to the health of the OCaml
community by offering a whole bunch of libraries that many users use on a daily
basis.

Again, we really want our projects ([mrmime][mrmime], [sendmail][sendmail],
[spamtacus][spamtacus] or [blaze][blaze]) to be not only for the purpose of
unikernels but also for the use that the community can expect without it being
"in the chapel".

Anyway, that being said, you can ask me for an email address in x25519.net if
you wish. All I need is your password hashed to BLAKE2B and the actual address
you wish to use. I also hope that some people will have fun with our different
services available. The most important thing for us is to offer something
resilient and stable - and that's the biggest thing to do! And above all,
happy new year and hack well!

[mrmime]: https://github.com/mirage/mrmime
[sendmail]: https://github.com/mirage/colombe
[blaze]: https://github.com/dinosaure/blaze
[hamlet]: https://github.com/mirage/hamlet
[spamoracle]: https://github.com/xavierleroy/spamoracle
[spamtacus]: https://github.com/mirage/spamtacus
[afl-fuzz]: https://lcamtuf.coredump.cx/afl/
[postfix]: http://www.postfix.org/
[launchvps]: https://cp.launchvps.com/index.php
[intodns.com]: https://intodns.com/
[robur-donate]: https://robur.coop/Donate
