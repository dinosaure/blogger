---
date: 2022-05-05
article.title: Esperanto, when OCaml meets Cosmopolitan
article.description:
  Build-once Run-anywhere
tags:
  - OCaml
  - Build
  - Portability
---

An open question in the Caml community is how to produce a native binary that
will work everywhere. Indeed, OCaml has the advantage of producing bytecode
like Java where the minimal requirement to run the program is to have the OCaml
distribution on your machine.

However, it is often desired to distribute a native program instead of bytecode
— especially for performance reasons. Portability versus speed.

The issue of distribution (and portability) of a native executable is partially
resolved. Indeed, the first barrier to distribution is the static link that
must operate when the executable is created. MirageOS has a long experience of
this goal because the very principle of creating an operating system requires
that there is systematically a static link resolution (and yes, an OS - without
a file system - certainly can't "load" third party `*.so` libraries at boot
time, everything must be statically linked).

### The MirageOS shism

There are different views on how to solve this problem:
- produce an `*.o` of all the `*.cmx`/`*.cmxa` with `-output-obj` needed for
  our program
- vendor the dependencies of our program in a folder and, provided everyone
  uses the same build system, let the build system produce a statically linked
  binary

This is the big difference between MirageOS 3 and MirageOS 4. The former has
the advantage of taking an ecosystem as it is and only dealing with the link.
The issue of compiling artefacts is left to the maintainers of the libraries
(so they can use [b0][b0] for example without there being any
incompatibilities). The disadvantage is that cross-compilation becomes
difficult or impossible. Indeed, leaving the problem of compilation to third
parties (maintainers) makes it difficult to cross-compile their artefacts.
Especially when a library imports object files that are not OCaml (where only
`*.o` is available without its `*.cmo` equivalent).

This is why some libraries (like [digestif][digestif]) distribute a
"cross-compiled"[<sup>1</sup>](#fn1) version of these objects along with a
default version. MirageOS 3, using a hack with `ocamlfind` and `META` files can
then statically link these object files with the operating system correctly.

---
<tag id="fn1">**1**</tag>: When I talk about cross-compiling here, it is not
necessarily producing a different assembler than the host (even if this is part
of the objectives). The definition is indeed somewhat broader, it is sometimes
about producing the same assembler as the host but under different constraints
(with different options) than the usual compilation. For example, we would not
want to include the standard C library in the object needed for our operating
system BUT we would still want to include it in the object that would be used
in the production of a normal native executable.

This is particularly the case with Solo5 where the objective is not to compile
to another assembler but to compile with other options (like `-nostdlib`).

---

The second solution has the advantage of leaving us in control of the
compilation. Indeed, vendoring the dependencies (and thus getting the source
directly) and then controlling how we should compile the source files gives us
the freedom to produce what we want and in what *context* we want to produce
the final artifact. The biggest disadvantage is that all dependencies must use
the same build system in order to orchestrate the compilation of what may be
~11000 artefacts (like [pasteur][pasteur]) with the same tool.

With this solution, it becomes "easy" to ask to statically link all the
artefacts or more generally, to use another more specific and appropriate
*compilation toolchain* to produce our operating system. Of course, it
underlies a constraint to homogenise an ecosystem that belongs to no one to a
central tool, in this case: `dune`. A monopoly situation which, according to my
political views, is problematic.

However, experience speaks for itself and it turns out that MirageOS 4 and
especially [Solo5][solo5] (and [Martin][mato]'s wonderful work) makes way for a
particularly interesting design in terms of producing our programs. Indeed, in
the second solution, it is a question of a *toolchain* which remains to be
defined but finally structures all the compilation of all that is necessary to
the production of our "binary" (a simple executable or an operating system) as
well as the link, final stage but nevertheless very important, especially in
the production of an operating system. To recall, MirageOS 3 was essentially
about linking.

## Cosmopolitan

[Cosmopolitan][cosmopolitan] is a great project that proposes a C library that
would be "portable" on all systems. The difficulty with portability in C is the
ABI. Indeed, a C library proposes a whole bunch of functions which only
communicate with the kernel in order to obtain and manipulate the resources of
your computer. Unfortunately, depending on the kernel (Windows, Linux, Mac,
\*BSD), the ceremony to manipulate resources are not totally the same - even
if they are similar.

But cosmopolitan is not only a simple C library (like [musl][musl]), the
project proposes a linking method to create an artefact able to run on all
machines. Indeed, beyond the question of the ABI proposed by the kernels which
differ, the format of the executable expected by the systems is also different.
Cosmpolitan allows to link the necessary object files in such a way that the
produced program can be launched on any system!

Of course, at this stage, there is some black magic involved, akin to summoning
the god Emacs so that it can change some bits of your program in place to make
it run on your machine...

But in the end, what Cosmopolitan proposes is basically a *toolchain* in the
same way that MirageOS 4 can be expected to create an operating system:
- a C compiler
- a C library (like [nolibc][nolibc] needed by Solo5)
- a link script

The question now remains: how to integrate Cosmopolitan into an OCaml project
to **build-once** executable that can **run-anywhere**?

## [Esperanto][esperanto]

For this, we will mainly use the same design as Solo5 (also applied to
[Gilbraltar][gilbraltar] to make a MirageOS on Raspberry Pi 4) but apply it
with Cosmopolitan. Essentially, we need to propose a new toolchain that will
consist of a new C compiler, a new linker, a `*.a` that will correspond to our
standard C library, some `*.o` that we will have to link well at the end as
well as some `*.h` to give the right definitions to the caml runtime (which
remains only C code after all).

Our real goal in this story is to produce a `libasmrun.a` from the OCaml
compiler source to have a caml runtime compiled with cosmopolitan. Indeed, in
the generation of a native caml program, an important step is to link your
OCaml code (which has become assembly) with `libasmrun.a` so that there is the
implementation of the Garbage Collector as well as the necessary functions
needed for the standard OCaml library (`stdlib.cmxa`).

Unfortunately, one cannot simply take `libasmrun.a` from the OCaml compiler of
your host system since it explicitly uses the standard C library of your host
system (instead of our Cosmopolitan library) - this library is probably `glibc`
for Linux systems. The latter, by the way, expects there to be dynamic loading
of third-party libraries (`*.so`) which is in contradiction with our first
point: getting a program whose link to third-party libraries is **static**.

Of course, the problem is more difficult than simply recompiling `libasmrun.a`
with another standard C library. The OCaml compiler has this ability to compile
C files to object files (`ocamlopt -c strlen.c -o strlen.o`). In truth, it
makes sense to let `ocamlopt` compile the C files needed for your project into
object files to ensure certain `#include` and options - and toolchain
consistency by ultimately using the same C compiler that compiled `libasmrun.a`
to compile our `*.c`.

In other words, we don't just need to compile `libasmrun.a`, we also need to
compile another OCaml compiler...

### Order!

![order](../images/order.gif)

If you are observant, Cosmopolitan only requires a few more options to be given
to our C compiler (like GCC or Clang). We could very well compile the OCaml
distribution with these options and have our `libasmrun.a` (compiled with the
expected options) and our `ocamlopt` (using the expected options) without much
difficulty, but that's without the linkage and order.

If you have ever played with `ld`, you know that the order of the arguments is
very important. It turns out that even though we end up being able to compile
OCaml with Cosmopolitan, our new `ocamlopt` doesn't necessarily emit the
options for the link in the right order... Which makes it unusable...

In this respect, it is a common point with `ld` & `ocamlopt`! Indeed, we still
have to topologically sort the dependencies to make sure that `ld` binds the
objects in the same way that `ocamlopt` binds the `*.cmx{,a}`.

This mostly means that we need to hack the C toolchain used to compile OCaml
and thus create our own C compiler and C linker which will take care of
reordering the arguments so that an invocation by the OCaml distribution's
`Makefile` (to build our `libasmrun.a`) or an invocation by `ocamlopt` (to
compile the C stubs and link objects) works!

Let's not go any further into the arcane mythology of the creation of the OCaml
god by the OCaml titan with incantations to `autotools` and `Makefile`, we
basically just need to make 3 shell scripts that will replace `cc`, `ld` and
`objcopy`:

```sh
prog="$(basename $0)"
I="$(dirname $0)/../include/x86_64-esperanto-none-static"
[ ! -d "${I}" ] && echo "$prog: Could not determine include path" 1>&2 && exit 1
L="$(dirname $0)/../lib/x86_64-esperanto-none-static"
[ ! -d "${L}" ] && echo "$prog: Could not determine library path" 1>&2 && exit 1
[ "$#" -lt 1 ] && \
    echo "$prog: No input files. Compilation terminated." 1>&1 && exit 1
[ "$#" -eq 1 -a "$1" = "-v" ] && exec cc "$@"
M=link
B=0b1111111
Z=
S=
for arg do
    shift
    if [ -n "${Z}" ]; then
        # handle -z linker-arg
        Z=
        case "$arg" in
            cosmopolitan-support-vector=*)
                B="${arg##*=}"
                continue
                ;;
	    caml-startup)
		S=set
		continue
		;;
            *)
                set -- "$@" "-z" "$arg"
                continue
                ;;
        esac
    fi

    case "$arg" in
        -c|-S|-E)
            M=compile
            ;;
        -z)
            if [ -z "${Z}" ]; then
                Z=1
                continue
            fi
    esac
    set -- "$@" "$arg"
done
case ${M} in
    compile)
        [ -n "${B}" ] && B="-DSUPPORT_VECTOR=${B}"
        [ -n "${__V}" ] && set -x
        exec cc \
            -D__ESPERANTO__ -mstack-protector-guard=global \
	    -g -Os -nostdlib -nostdinc \
	    -fno-pie -no-pie -mno-red-zone -fno-omit-frame-pointer -pg -mnop-mcount \
	    -I ${I} \
	    ${B} \
	    "$@" \
        ;;
    link)
        [ -n "${B}" ] && B="-DSUPPORT_VECTOR=${B}"
        [ -n "${S}" ] && S="${L}/startup.o"
        [ -n "${__V}" ] && set -x
        exec cc \
            -D__ESPERANTO__ -mstack-protector-guard=global \
	    -g -Os -static -nostdlib -nostdinc \
	    -fno-pie -no-pie -mno-red-zone -fno-omit-frame-pointer -pg -mnop-mcount \
            -Wl,--build-id=none ${S} ${B} \
            "$@" \
            -fuse-ld=bfd -Wl,-T,${L}/ape.lds \
	    -I ${I} \
	    ${L}/crt.o ${L}/ape.o ${L}/cosmopolitan.a
        ;;
esac
```

This shell script will be our C compiler. As you can see, it introspects the
options the caller gives (again, the OCaml Makefile or `ocamlopt`) and infers
whether the caller is looking to compile or link. In this way, 2 options are
really manipulated:
- `-z cosmopolitan-support-vector=` which allows us to specify which platform
  we want to use.
- `-z caml-startup` which allows to add a `startup.o` file to the link allowing
  to execute the famous `caml_startup`

Of course, we can see, as far as compilation is concerned, the necessary
options such as `-nostdlib` and `-nostdinc` (a small `-D__ESPERANTO__` allowing
third party libraries to know that we are creating an object file for
Cosmopolitan).

And finally, for the linker, we ask to use the `ape.lds` file which describes
how to link our objects with `cosmopolitan.a` (the famous portable C library).

The script will be `x86_64-esperanto-none-static-cc` which follows the
["Target Triplet"][target-triplet] rule (like GCC). The linker offers more or
less the same thing and `objcopy` just ensures consistency in our C toolchain.

## The cosmopolitan distribution in OPAM

Finally, it is a question of proposing an OPAM package allowing, like the Solo5
package, to install and make available this C toolchain. However, before
attacking the big part, i.e. the tuned OCaml compiler, we are going to spend a
little time on the distribution of this toolchain, the genesis of which is
essential in a simple [`cosmopolitan.zip`][cosmopolitan.zip] containing our
archive, our objects and our header (which you can download and use yourself).

As you may know, I like to redo everything in OCaml. So I made a little tool
that extracts from the given `cosmopolitan.zip` the files needed for our
toolchain. The tool goes a bit further than just unzipping a file, of course.
It will also check the contents and ensure the integrity of the files by their
hashes (SHA256).

For such a tool, we essentially need 2 libraries:
- a library to calculate the hash
- a library to unzip a file

For the first one, as you know, one of my oldest libraries is
[digestif][digestif] which allows to calculate several hashes including SHA256.
Let's take it for our tool.

The second is a bit more problematic. I did indeed make a library that
implements the [zlib][zlib] format but `zip`, beyond using zlib (or more
precisely [RFC1951][rfc1951]/`DEFLATE`), also describes a structure (folders &
files). So I mixed what can be found in our good old [camlzip][camlzip] and I
replaced the `Zlib` part by [decompress][decompress]!

Finally, our tool is:
```ocaml
module Digest = Digestif.SHA256

let ( / ) = Filename.concat

let expected =
  [ "dst/cosmopolitan.h",
    (Digest.of_hex "bc5c3d52214eb744d0dbdba95c628b8c53a53efacc558cd36f60c1d585e60e36")
  ; "dst/ape.lds",
    (Digest.of_hex "bcd87c737408ab18a6d4ffce2848a6bbf3cf2e8df904fa3aac475d11a1f938f3")
  ; "dst/crt.o",
    (Digest.of_hex "d4874eaed8fe78ea8745cd3acc66e8eb7ccf2ba2d296aed64f878528b45e2d9b")
  ; "dst/ape.o",
    (Digest.of_hex "7e8d302fd5654235ebebc5a94ab1a22437b90164032d4304ac55729755bc7f5d")
  ; "dst/ape-no-modify-self.o",
    (Digest.of_hex "1ed036a5d9d7d56d473874bcde93901717a71e2f4502f605b1e70913023fadd8")
  ; "dst/cosmopolitan.a",
    (Digest.of_hex "50ae3c76998007ba0a6626dc33f33d387cf12da6261dafb7e05d287bcc656ca4") ]

let digest filename =
  let tmp = Bytes.create 0x1000 in
  let rec digest ic acc = match input ic tmp 0 (Bytes.length tmp) with
    | 0 -> Digest.get acc
    | exception End_of_file -> Digest.get acc
    | len ->
      digest ic (Digest.feed_bytes acc ~off:0 ~len tmp) in
  let ic = open_in filename in
  let hash = digest ic Digest.empty in
  close_in ic ; hash

let extract filename dst =
  let ic = Zip.open_in filename in
  let entries = Zip.entries ic in
  let rec go acc = function
    | [] -> List.rev acc
    | entry :: rest ->
      let filename = dst / entry.Zip.filename in
      Zip.copy_entry_to_file ic entry filename ;
      go (filename :: acc) rest in
  let files = go [] entries in
  Zip.close_in ic ;
  files

let verify bindings =
  let a = List.sort (fun (k0, _) (k1, _) -> String.compare k0 k1) bindings in
  let b = List.sort (fun (k0, _) (k1, _) -> String.compare k0 k1) expected in
  a = b 

let () = match Sys.argv with
  | [| _; "list" |] ->
    List.iter (fun (filename, _) -> Fmt.pr "%s\n%!" filename) expected
  | [| _; zip; dst; |] when Sys.file_exists zip ->
    if Sys.file_exists dst && not (Sys.is_directory dst)
    then Fmt.failwith "%s already exists and it is not a directory" dst ;
    if not (Sys.file_exists dst) then Sys.mkdir dst 0o700 ;
    let files = extract zip dst in
    let hashes = List.map digest files in
    let bindings = List.combine files hashes in
    if verify bindings
    then exit 0 else exit 1
  | _ -> Fmt.epr "%s [cosmopolitan.zip <directory>|list]\n%!" Sys.argv.(0)
```

## The OCaml compiler and `libasmrun.a`

Again, we will mainly follow what [`ocaml-solo5`][ocaml-solo5] already does,
namely, compile the OCaml compiler and `libasmrun.a` with our new C toolchain.
However, even if imitation is the sincerest form of flattery (about
[Lucas][lucas-work]'s work), it is not sufficient for our purpose.

Indeed, OCaml expects basic `#include` such as `stdlib.h` or `string.h`.
However, we only have `cosmopolitan.h`. The trick is to simply create these
expected files and systematically `#include "cosmopolitan.h"` (which contains
everything):

```sh
.
├── cosmopolitan.h
├── ctype.h
├── dirent.h
├── endian.h
├── errno.h
├── esperanto.h
├── fcntl.h
├── float.h
├── limits.h
├── math.h
├── setjmp.h
├── signal.h
├── stdarg.h
├── stddef.h
├── stdint.h
├── stdio.h
├── stdlib.h
├── string.h
├── strings.h
├── sys
│   ├── dir.h
│   ├── ioctl.h
│   ├── resource.h
│   ├── stat.h
│   ├── time.h
│   ├── times.h
│   ├── types.h
│   └── wait.h
└── time.h
```

### `link` and `link`, `write` and `write`...

Unfortunately, as far as OCaml 4.14 is concerned, in some of the C code in the
caml runtime, there is the definition of a `link` structure and a `write`
function. They conflict with the `link(2)` and `write(2)` functions that
Cosmopolitan offers. Fortunately, these declarations remain internal, just
rename them with `sed`[<sup>2</sup>](#fn2) and you're done!

```c
typedef struct link {
  void *data;
  struct link *next;
} link;

Caml_inline void write(int c)
{
  if (extern_ptr >= extern_limit) grow_extern_output(1);
  *extern_ptr++ = c;
}
```

```shell
$ sed -i -e 's/\([^_]\)link/\1link_t/g' ocaml/runtime/roots_nat.c
$ sed -i -e 's/write(/_write(/' ocaml/runtime/extern.c
```

---
<tag id="fn2">**2**</tag>: For this kind of problem, it would have been
interesting to use [coccinelle][coccinelle] which allows to write semantic
patches and to make modifications on C code which is a little more reliable than
`sed`... But let's not use a gas factory for so little.

---

### Constants in C

In the new iteration of compiling the OCaml compiler with my toolchain, I
finally ran into a slightly thornier problem than usual. Indeed, there is a
recurring design in OCaml which consists in "mapping" constants in C with ADT
in OCaml.

```c
static int sys_open_flags[] = {
  O_RDONLY, O_WRONLY, O_APPEND | O_WRONLY, O_CREAT, O_TRUNC, O_EXCL,
  O_BINARY, O_TEXT, O_NONBLOCK
};

CAMLexport int caml_convert_flag_list(value list, int *flags)
{
  int res;
  res = 0;
  while (list != Val_int(0)) {
    res |= flags[Int_val(Field(list, 0))];
    list = Field(list, 1);
  }
  return res;
}

```

```ocaml
type open_flag =
    Open_rdonly | Open_wronly | Open_append
  | Open_creat | Open_trunc | Open_excl
  | Open_binary | Open_text | Open_nonblock
```

The trick here is that when compiling an ADT in OCaml, the first constructor
will have the value `0`, the second will have the value `1`, and so on. Thus,
a list of this ADT can easily turn into a *bitset* expected, in our example, by
`open(2)`. This "mapping" is necessary to be portable since the value of these
constants is not the same for each system.

For example, `O_CREAT` is not the same on Linux as on FreeBSD.

But wait... if these values are not the same according to the system, how does
Cosmopolitan manage these differences? For all values that do not have a
consensus like `O_CREAT`, Cosmopolitan will simply create a global variable
(`static const unsigned O_CREAT;`). Depending on the system from which you want
to run a Cosmopolitan program, `ape.o` will simply modify **itself** these
globals with their expected values (from [`consts.sh`][consts.sh])

However, the error I have now concerns the initialization of this table:
```
error: initializer element is not constant
```

This is due to a known limitation of C which the specification explains:
> All the expressions in an initializer for an object that has static storage
> duration shall be constant expressions or string literals.

You can't really be invasive in the code of the OCaml distribution and change
that part so easily. So we need to find a way to fix the error while keeping
the expected behaviour. One solution that has been [described][issue] to me and
that I've thought about quite a bit is to **lie** once when compiling the OCaml
compiler and then to modify/reset this array at runtime with the real values
that Cosmopolitan gives us only at runtime.

The trick is to define these values as a constant only during the first
compilation of the caml runtime:
```c
#ifdef CAML_NAME_SPACE
#ifndef __OCAML_ESPERANTO__
#define __OCAML_ESPERANTO__

#undef O_CREAT
#define O_CREAT 0

#endif /* __OCAML_ESPERANTO__ */
#endif /* CAML_NAME_SPACE */
```

Luckily, when compiling the runtime, `-DCAML_NAME_SPACE` is passed all the time
which allows us to define a `*.h` (which we will add to `cosmopolitan.h`)
allowing us to lie only when compiling the runtime.

Now we just have to initialise this array before the caml program starts (as
the values are false). The first step is to add a function to modify this
array. The second step is to call this function before calling `caml_startup`.

```sh
$ cat esperanto_sys.c

void _esperanto_init_sys_open_flags(const int cosmopolitan_sys_open_flags[]) {
  memcpy(sys_open_flags, cosmopolitan_sys_open_flags,
         sizeof(sys_open_flags));
}
$ cat esperanto_sys.c >> ocaml/runtime/sys.c
```

For our second step, if you remember, we had a `-z caml-startup` option that
allowed us to add a `startup.o` file during our link. At the begining, it
should look like this (a simple call to `caml_startup`):

```c
int main(int argc, char *argv[]) {
  caml_startup(argv);
  return (0);
}
```

Now it should look like this:

```c
#include "cosmopolitan.h"

extern void _esperanto_init_sys_open_flags(const int[]);

int main(int argc, char *argv[]) {
  int open_flags[] = {
      O_RDONLY, O_WRONLY, O_APPEND | O_WRONLY, O_CREAT, O_TRUNC, O_EXCL,
      0,        0,        O_NONBLOCK}; // Cosmopolitan does not provide O_BINARY
                                       // and O_TEXT

  _esperanto_init_sys_open_flags(open_flags);

  caml_startup(argv);

  return (0);
}
```

The most important thing to note is that our array is initialized **in** the
`main` function (and not outside of it as was the case for `sys_open_flags`).

### Gimme a try!

We finally have our compiler! The big drawback for now is that it doesn't yet
handle `unix.cmxa` which is much harder to integrate but not impossible! 
However, we can already make a small OCaml program and produce a completely
portable binary.

However, do you remember the constraint of the MirageOS projects? **Never
depend on `unix.cmxa`**! And that means especially that `digestif` and
`decompress` do NOT depend on `unix.cmxa`. Even the Zip version of
[camlzip][camlzip] depends very little on `unix.cmxa` (just to get the date).
Let's start having fun!

So let's take our `extract.ml`. The goal here is mainly to 1) get the
dependencies (in this case, digestif, decompress, eqaf, checkseum and optint)
2) create a `dune`'s context using our new OCaml compiler 3) compile our
`extract.ml` with our new OCaml compiler!

```sh
$ cat extract.opam
opam-version: "2.0"
name:         "extract-cosmopolitan"
maintainer:   [ "Romain Calascibetta <romain.calascibetta@gmail.com>" ]
authors:      [ "Romain Calascibetta <romain.calascibetta@gmail.com>" ]
homepage:     "https://github.com/dinosaure/esperanto"
bug-reports:  "https://github.com/dinosaure/esperanto/issues"
dev-repo:     "git+https://github.com/dinosaure/esperanto"
doc:          "https://dinosaure.github.io/esperanto/"
license:      "MIT"
synopsis:     "The extract.com tool used by esperanto"
description:  "The extract.com tool used by esperanto compiled by esperanto..."

build: [
  [ "dune" "build" "-p" name "-j" jobs ]
]
install:  [
  [ "dune" "install" "-p" name ] {with-test}
]

depends: [
  "ocaml"           {>= "4.08.0"}
  "dune"            {>= "2.6.0"}
  "decompress"
  "fmt"
  "digestif"
  "bigstringaf"
]
$ cat >dune-workspace<<EOF
(lang dune 2.0)

(context (default))

(context
 (default
  (name esperanto)
  (toolchain esperanto)
  (merlin)
  (host default)))
EOF
$ cat >dune<<EOF
(executable
 (name extract)
 (link_flags :standard -cclib "-z caml-startup")
 (libraries decompress.de bigstringaf fmt digestif))

(rule
 (target extract.com)
 (deps extract.exe)
 (mode promote)
 (action (run objcopy -S -O binary %{deps} %{target})))
EOF
$ opam monorepo lock
$ opam monorepo pull
$ dune build ./extract.com
$ wget https://justine.lol/cosmopolitan/cosmopolitan.zip
$ bash -c './extract.com cosmopolitan.zip dst'
$ ls dst
ape.lds  ape-no-modify-self.o  ape.o  cosmopolitan.a  cosmopolitan.h  crt.o
```

This now mainly means that the tool to create our Cosmopolitan toolchain was
created from our Cosmopolitan toolchain!

![mind-blown-explosion](../images/mind-blown-explosion.gif)

Of course, and this is the whole point of this article, `extract.com` can run
on Windows, Mac or \*BSD! At this point, one can easily imagine an integration
into MirageOS in the same way as there is Solo5/`ocaml-solo5`. But to be much
more ambitious, it might be more interesting to integrate `unix.cmxa` and thus
have a complete OCaml distribution that generates portable binaries!

## Conclusion

I think this article shows an aspect of the OCaml community that I love: doing
something hacky & dirty! Most of what I have just done is clearly
unconventional but it leads to a very interesting result.

Cosmopolitan is a beautiful, complex but very interesting project. A bit
magical, but:
> Any sufficiently advanced technology is indistinguishable from magic
> Arthur C. Clarke

I really hope to have the time to continue this project and to go a bit further
into the multitudes of tools that I could make in OCaml and that helped me in
my development. The next goal would be to be able to compile [hxd][hxd] which
is certainly small but uses `unix.cmxa`. From there, everything becomes
possible!

Then it will be time for an official release for the happiness of all hackers
like me!

[b0]: https://github.com/b0-system/b0
[digestif]: https://github.com/mirage/digestif
[pasteur]: https://github.com/dinosaure/pasteur
[Solo5]: https://github.com/Solo5/solo5
[mato]: https://github.com/mato
[cosmopolitan]: https://justine.lol/cosmopolitan/index.html
[musl]: https://musl.libc.org/
[nolibc]: https://github.com/mirage/ocaml-solo5/tree/main/nolibc
[esperanto]: https://github.com/dinosaure/esperanto
[gilbraltar]: https://github.com/dinosaure/gilbraltar
[target-triplet]: https://wiki.osdev.org/Target_Triplet
[cosmopolitan.zip]: https://justine.lol/cosmopolitan/download.html
[zlib]: https://zlib.net/
[rfc1951]: https://datatracker.ietf.org/doc/html/rfc1951
[camlzip]: https://github.com/xavierleroy/camlzip
[decompress]: https://github.com/mirage/decompress
[ocaml-solo5]: https://github.com/mirage/ocaml-solo5
[lucas-work]: https://github.com/mirage/ocaml-solo5/pull/104
[coccinelle]: https://coccinelle.gitlabpages.inria.fr/website/
[consts.sh]: https://github.com/jart/cosmopolitan/blob/master/libc/sysv/consts.sh
[issue]: https://github.com/jart/cosmopolitan/issues/401
[hxd]: https://github.com/dinosaure/hxd
