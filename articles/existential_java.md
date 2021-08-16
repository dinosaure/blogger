---
date: 2021-08-16
article_title: Understanding "Existential Types" with Java
article_description:
  An existential type (or "existentially quantified type") is a
  complicated type system fanatic thing. But to become a Java
  Champion, it's a must. Let's learn how to use it, in Java, of course.
tags:
  - Java
  - Types
  - Existential
  - Interface
---

> Java is becoming, from version to version, more and more comfortable for
> functional programming (which can be very useful **if you want to program with
> Greek** words like `αλφα`, `βήτα`, `γάμα`, `φέτα` and `λάμδα`) it becomes
> convenient to understand the buzzwords used in languages that nobody uses to
> import their techniques and make 23rd century _enterprise_ code. In this
> article, let's discover together a type system enthusiast's trick:
> **existential types**.

> By "existential types", I don't mean "types that exist", well yes, otherwise
> it would be super easy to describe, right? "A type that exists" is a type that
> exists, for example... `int`. **No**, by _existential_ one could essentially
> draw a parallel with [Kant](https://de.wikipedia.org/wiki/Immanuel_Kant)'s
> "**existentialism**". _Pfrtt just kidding_, like almost everything else that
> seems to have a connection with philosophy, in functional programming, **it
> actually has nothing to do with it**, [Haskell's
> monads](<https://en.wikipedia.org/wiki/Monad_(functional_programming)>)
> probably have nothing to do with [Leibniz's
> monads](<https://de.wikipedia.org/wiki/Monade_(Philosophie)>), and
> [Arrows](<https://en.wikipedia.org/wiki/Arrow_(computer_science)>) share
> nothing with [Robin Hood](https://en.wikipedia.org/wiki/Robin_Hood) or [Shad
> Gregory Moss](<https://en.wikipedia.org/wiki/Bow_Wow_(rapper)>). Ahah life is
> hard.

Before fighting with Java to describe existential types (just kidding, it's
actually _very easy_), I propose a small diversions to a very popular language in
French research, [OCaml](https://ocaml.org), which allows to describe
existentials **quite easily**.

### OCaml diversions

OCaml is a very nice language with lots of tools for working with functions,
algebraic types, modules and objects (even if I am far from being an expert in
OCaml, I decided to use this language to write the [generator for my
site](https://github.com/xhtmlboi/yocaml)). Before the introduction of
generalized algebraic types
([GADTs](https://web.cecs.pdx.edu/~sheard/papers/silly.pdf)), the introduction
of existential types could be expressed through [several
encodings](http://okmij.org/ftp/Computation/Existentials.html). However, it was
common to use only two relatively straigthforward methods. The first is to use
[Skolemization](https://en.wikipedia.org/wiki/Skolem_normal_form), which is a
trick to **turn an existential quantification** (_in its logical sense_) **into
a universal quantification**, because yes, the term "existential" is closely
related to its logical counterpart. The second was to use a [first-class
module](https://ocaml.org/manual/firstclassmodules.html). I'm not going to
present the first method because it's pretty far from what you would do in Java
(and I want to become **Java Champion**, not OCaml Champion) and I'm not going
to present the second one because it would be a _horrible spoiler_ of this whole
article!

But since the introduction of **GADTs** (_a kind of sum type whose constructors
can be non-surjective and which introduce **local type equalities**_) it has
become very easy to declare existential types because they are local types (we
will see later why) and once we have local type equality, local type integration
becomes trivial.

Now that we have introduced a lot of jargon that is unnecessary for the
understanding of this article, let's have a look at a real use case without
further ado. **Let's imagine that we have some types and we would like to
_pretty-print_ them in XML** (a quality format). For example :

```ocaml
module Individual : sig
  type t = {
    name: string
  ; age: int
  }
end
```

Which would be printed this way in XML:

```xml
<individual age="38" name="The XHTMLBoy"/>
```

And a contact book that would have a list of individuals:

```ocaml
module Contacts : sig
  type t = Individual.t list
end
```

Which would be printed this way in XML:

```xml
<contacts>
  <individual age="38" name="The XHTMLBoy"/>
  <individual age="39" name="Charlotte de Belfroid"/>
</contacts>
```

#### A first approach, a direct encoding

There are many ways to write the serialization strategy. The first, and most
obvious, would be to use direct encoding, i.e. to describe each serialization
function individually. For example :

```ocaml
let concat_with f list =
  List.fold_left
      (fun buff x -> " " ^ buff ^ (f x))
      "" list

let individual_to_xml individual =
   Format.asprintf
     "<individual age=\"%d\" name=\"%s\"/>"
     individual.age
     individual.name

let contacts_to_xml contacts =
  Format.asprintf
  "<contacts>%s</contacts>"
  (concat_with individual_to_xml)
```

In our very simple example, it works quite well. The problem is that this method
... doesn't _scale_ much. Indeed, we have to keep in mind how to describe XML
for each new element. **What we want are generic combinators to build,
generically, fragments of XML**.

#### A widely better approach, an indirect encoding

Another approach would be to **split** the
description of the structure of the XML and the structure of the entities being
manipulated. For example, let's start by describing generically what an XML
document is (in this example, for the sake of brevity, I am obviously assuming
less than what an XML document actually is):

```ocaml
type attr =
  | Int of int
  | String of string

type node = {
  tag: string
; attr:(string * attr) list
; content: node list
}

let int key value = (key, Int value)
let string key value = (key, String value)
let node tag ~attr content = {tag; attr; content}
```

Now we can write a generic function that traverses a `node` (which is a
recursive type) and turns it into XML. (To simplify the function I haven't dealt
with the case of leaves, but don't worry, the XML produced is still valid).
Don't rely too much on the code, it is written as an example only.

```ocaml
let rec to_xml {tag; attr; content} =
  let attr_s = List.fold_left
    (fun r (key, v) ->
      let value = match v with
      | Int x -> string_of_int x
      | String x -> x
      in Format.asprintf "%s %s=\"%s\"" r key value
     ) "" attr
   in Format.asprintf "<%s%s>%s</%s>"
     tag attr_s (concat_with to_xml content) tag
```

Now I can use my structure within my modules, it is much easier to write than
having to interpolate data everywhere, as was previously the case:

```ocaml
let individual_to_xml individual =
   node
      "individual"
      ~attr:[ int "age" individual.age
            ; string "name" individual.name ]
      []

let contacts_to_xml contacts =
  node "contacts" ~attr:[] (List.map individual_to_xml contacts)
```

This approach looks good in every way, however, **there is one aspect in which
it is really bad**... This method **does not take advantage of existential
types** at all and therefore makes this article completely useless. I suggest
that we **add artificial constraints** to our serialization routine to make
sense of the use of existentials and that these examples be transposed to Java.
One of these constraints could be, for example, to say that **it is strictly
forbidden to use an intermediate format** because ... _lol_, I do what I want.

#### A cheaper approach, but one that takes advantage of existential types

If we want to avoid having an intermediate description (for no other reason than
the pleasure of discovering existentials), one solution would be to compose, not
constructors, but _pretty-printer functions_. So far so good, let's try to write
an symetric function that compose _printers_:

```ocaml
let attr key f x = (key, f, x)
let string key x = attr key Fun.id x
let int key x = attr key string_of_int x
let content f x = (f, x)


let attr_to_string (k, f, x) =
  Format.asprintf "%s=\"%s\"" k (f x)

let content_to_string (f, x) = f x

let node tag ~attr content =
  Format.asprintf "<%s%s>%s</%s>"
    tag
    (concat_with attr_to_string attr)
    (concat_with content_to_string content)
    tag
```

The type of our `node` function is :

```ocaml
val node :
  string ->
  attr:(string * ('a -> string) * 'a) list ->
  (('b -> string) * 'b) list -> string = <fun>
```

Yeah, it seems to work! Let's try a simple node : `node "foo" ~attr:[string "name" "Antoine"] []`, it returns `"<foo name=\"Antoine\"></foo>"`, Great, it
works, **we are brilliant**! Let's try to write the function to transform an
individual! An attentive reader may ask this very justified question: "_why
storint the elements and not directly applying the `attr_to_string` and
`content_to_string` functions_?" This is an excellent question. Essentially
because **once our transformation is applied, we can no longer act on it at
all**. So if I had, for example, optional fields, I'd have to build a combiner
**for each type and each optional type** that I want to manipulate, which
doesn't scale much.

```ocaml
let individual_to_xml individual =
  node
    "individual"
    ~attr:[ string "name" individual.name
          ; int "age" individual.age ]
    []
```

And this... **does not work**. Because the `'a` of the `node` signature is set
to `string` the first time `string` is used in the attribute list by
[monomorphization](https://en.wikipedia.org/wiki/Monomorphization). The problem
would have been the same for `content` if I had wanted to fill it with
heterogeneous fields. **What a mess**!

So at this point we are faced with an alternative:

- Apply the function directly and impose a potentially exponential growth of combinators.
- Not being able to describe the nodes one would like.

It seems that we are faced with a Cornelian choice! What to take, the plague or
cholera? Well, I suggest you choose **neither**! We will simply describe **a
type that hides** the fact that we work on different types!

```ocaml
type attr =
   | A : (string * 'a * ('a -> string) ) -> attr

type content =
   | C : ('a * ('a -> string)) -> content
```

As you can see, the variable of type `'a` only appears in the right-hand side of
the type equation, **this variable is an existential type** (and this is only
possible if you use the GADT syntax, for the reasons I mentioned at the
beginning of the article). To understand the difference between a type variable
that is **existentially quantified** and a _normal_ type variable, I invite you to
compare these two statements:

```ocaml
type 'a normal =
   | Normal : 'a -> 'a normal

 type exists =
   | Exist : 'a -> exist
```

In the first declaration, the type is **parametrized** by `'a`, so the variable
appears on the left and right of the equation. In the second declaration, the
variable does not escape from the signature, so **it denotes an existential
type**. For example, `Normal 10` will have the type `int normal` and `Exists 10`
aura le type `exists` (Yeah, no more _leaking_).

In general, types that involve existentials imply having two additional
functions, `pack`, which will **bury** our data in our type (which defines one
or more existential types) and `unpack` whose role will be to **extract** our
values buried in the type. In fact our `pack` function is very similar to the
`attr` and `content` functions we defined earlier, and `unpack` has
`attr_to_string` and `content_to_string`. Let's modify our code to make it work:

```ocaml
let attr key f x = A (key, x, f)
let string key x = attr key Fun.id x
let int key x = attr key string_of_int x
let content f x = C (x, f)


let attr_to_string = function
  | A (k, x, f) -> Format.asprintf "%s=\"%s\"" k (f x)

let content_to_string = function
  | C (x, f) -> f x
```

And the `node` function does not change at all, except that now it will have the
type: `val node : string -> attr:attr list -> content list -> string`. Our types
`attr` and `content` hide **the implementation details**. And slightly more
formally the `pack` function, generally, associates a value with a strategy for
normalising that value, in this case, a string projection function. So we could
say that the `pack` function guarantees that a type **exists** such that it can be
consumed in a certain way. That's why we talk about "existential types".

Now that we have seen what existentials are in a very artificial example, we can
go back to a real language, Java.

### Existential types in Java

Even though Java is becoming more modern every day (which explains my obsession
to becoming a Java **champion**), the language does not allow to describe
complicated stuff like GADTs. **So how can we describe existentials?** (_What a
clue!_)

You may not believe me, but in the world of _enterprise_ code, it is even easier
to describe existentials and here is an example partially similar to the one we
described in OCaml:

```java
// I could have named it AbstractBeanXmlAttribute
interface XMLAttr {
  String toXMLAttr()
}

// I could have named it AbstractBeanXmlAttribute
interface XMLContent {
  String toXMLContent()
}
```

And our previous `node` function, (assuming that functions to transform a list
of attributes into a string and a list of contents into a string are available,
of course):

```java
class XMLNode implements XMLContent {
   private String tag;
   private List<XMLAttr> attr;
   private List<XMLContent> content;
   public XMLNode(String tag, List<XMLAttr> attr, List<XMLContent> content) {
     this.tag = tag;
     this.attr = attr;
     this.content = content;
   }

   String toXMLContent() {
    return
      "<" + this.tag + createXMLAttributesStr(this.attr) + ">"
    + createXMLContentStr(this.content)
    + "</"+ this.tag + ">";
   }
}
```

And so... existentials in Java would be **nothing more than instantiated objects
of classes that implement interfaces**? Not really, it's even more pervasive
than that! Interfaces (but not only, any form of _polymorphisms related to
overtyping_) **make it possible to produce abstract representations of
behaviour**. Moreover, **encapsulation** is at the heart of the fundamental
idioms of object-oriented programming.

As we have seen in OCaml, an existential type hides implementation details (like
encapsulation in OOP where the internal state of the object is generally hidden,
hence the famous _Blackbox analogy_) and provides a proof of the existence of a
consumption strategy. This is exactly the "contract" part of an interface. As a
result, it is possible to treat uniformly instances of different classes
implementing the same interface (or several). This analogy between objects (and
more generically, **abstract types**) has long been known (1988), indeed
[Abstract types have existential
type](https://homepages.inf.ed.ac.uk/gdp/publications/Abstract_existential.pdf).

So, what can we learn from this article? Well... **that you already know the
existential types**, it's just that you call them, _probably differently_.

I hope you enjoyed reading this, and see you soon for new articles!
