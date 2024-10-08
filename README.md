# blog.osau.re

The source code of the generator and the content of my blog, naively using
[YOCaml](https://github.com/xhtmlboi/yocaml). The blog is available on:
- https://dinosaure.github.io/blogger/
- https://blog.osau.re/

The first website uses the GitHub pages mechanism (see the `gh-pages` branch),
the second is an unikernel with [`unipi`](https://github.com/robur-coop/unipi) on
my machine (plus [`contruno`](https://github.com/dinosaure/contruno) for TLS).

You can have a local version of my blog with:
```sh
$ opam pin add -y https://github.com/dinosaure/blogger
$ dune exec bin/watch.exe ---
$ wget http://localhost:8000/
```

The executable is able to push (like `git push`) the website to a Git repository 
on a specific branch (like `repository.git#gh-pages`). By default, the tool can
use `ssh` (with recorded private SSH key with `ssh-agent`) to push into a Git
repository. It can notify an `unipi` unikernel with the `--hook` option (and
let it to resynchronize values with the new commit).
```sh
$ dune exec bin/push.exe -- -r git@localhost:blog.git --hook http://10.0.0.1/hook \
  [--name "Romain Calascibetta"] \
  [--email romain.calascibetta@gmail.com]
```

For more details, you can see my article:
[Again, re-update of my blog after 2 years.][article]

[article]: https://dinosaure.github.io/blogger/articles/blog_requiem.html
