---
date: 2021-04-18
article_title: Implementing a minimalist mathematical statement prover with Java
article_description:
  The world of Proof Assistants is quite related to complicated
  functional programming languages. But it is possible, quite
  simply, to write a minimalist proof assistant in Java.
tags:
  - Java
  - Gödel
  - Proof
---

> Proving things, like mathematical expressions, is serious
> business. But in general, the theory behind attempted _automatic
> proving_ is often barbarically complex. To demystify the exercise, I
> decided that my first article would be about writing an automatic
> demonstrator of mathematical expressions, in Java, because Java
> Champions (which I dream of becoming) write programs in Java.

To prove a mathematical statement, it is first important to be able to
describe in which **system of axioms** the statement is to be
validated. Next, it is necessary to describe the **model** used. And
yes, even if one would like each axiomatized theory to lead to only
one model... this is unfortunately not the case. Typically, there are
several models that validate [Peano's
arithmetic](https://it.wikipedia.org/wiki/Assiomi_di_Peano).

Thus, to provide a _flexible automatic prover_, the class describing
the _validation engine_ will need to be **parametrised** by several
other classes. Either, cleverly use **parametric polymorphism** (the
_intellectual_ name of _Generics_, probably what a Java Champion would
say). Well, we can broadly sketch the outline of our prover! For this,
we will describe them in an **interface**!

```java
package io.github.xhtmlboi;

import java.util.Optional;

public interface Prover<Axioms, Model, Statement>  {

    Axioms getAxioms();
    Model getModel();

    /**
     * A statement that must be verified in the given axioms,
     * for the given model
     * @param st the statement
     * @return Returns an optional containing the result of
     *         the statement validation. (true for valid, false
     *         for invalid), if the optional is empty, the
     *          statement could not be validated or refuted.
     */
    Optional<Boolean> run(Statement st);
}
```

Well this is strange! Why return an optional boolean
(`Optional<Boolean>`)? A statement is valid or not, what a shame! Here
is a very **detailed** diagram of what _we would like_:

![a pretty ambitious goal](/images/proof-aut.png)

But in **1936**, on the basis of the incomprehensible (for the
_not-Java-Champion_ that I am) paper "**_Über formal unentscheidbare
Sätze der Principia Mathematica und verwandter Systeme_**" written by
[Kurt Gödel](https://de.wikipedia.org/wiki/Kurt_G%C3%B6del) in 1931,
[Alonzo Church](https://en.wikipedia.org/wiki/Alonzo_Church) and [Alan
Turing](https://en.wikipedia.org/wiki/Alan_Turing) tackled the famous
**_Entscheidungsproblem_** ([Gottfried Wilhelm
Leibniz](https://de.wikipedia.org/wiki/Gottfried_Wilhelm_Leibniz),
yeah, the guy behind the monads, nah not those from the category
theory, others, about _soul stuff_). This leads to some rather
annoying problems, _or at least sets in stone_ that some dreams (of
[Hildebert](https://de.wikipedia.org/wiki/David_Hilbert)'s for
example) will remain dreams **forever**. Transforming our perspectives
in this way:

![What a mess](/images/proof.png)

Now you should understand (unless you were a Java Champion and you
would have already understood) why use an option?

- `result.get() == true` the statement is **valid**;
- `result.get() == false` the statement is **invalid**;
- `result.isEmpty()` the prover **cannot** validate the statement.

But what about the **nonterminaison**? Just think about it... if we
**can't prove that a program terminates**... how could we ask our
statement checker to tell us that the statement does not terminate?
But don't panic, the concrete implementation I will give you can
**never** nonterminate! Without further ado, here is a class that
implements our interface, let me introduce "**Ein Super Automatischer
Prüfer Der Immer Fertig Wird**" (Some will notice how I want to avoid
controversy by deliberately choosing a name that has no ambiguous
connotations in another language. A little tip, if you want to find a
name for a project and you absolutely want to avoid offending someone,
or a whole community... nothing could be easier, translate a sentence
into German):

```java
package io.github.xhtmlboi;

import java.util.Optional;

public class EinSuperAutomatischerPrüferDerImmerFertigWird<Axioms, Model, Statement>
        implements Prover<Axioms, Model, Statement> {

    protected Axioms axioms;
    protected Model model;

    public EinSuperAutomatischerPrüferDerImmerFertigWird(Axioms axioms, Model model) {
        this.axioms = axioms;
        this.model = model;
    }

    @Override
    public Axioms getAxioms() {
        return this.axioms;
    }

    @Override
    public Model getModel() {
        return this.model;
    }

    @Override
    public Optional<Boolean> run(Statement st) {
        return Optional.empty();
    }
}
```

To avoid the risk of evaluating a statement that may not
finish... just don't evaluate it and always return an acceptable
answer: "**I don't know**". According to Gödel, Church and
Turing... this answer is **quite acceptable** (sometimes... but all the
time is "_a kind of sometimes_").

It's great, by respecting all the principles of **Clean Code**, using
a hint of design pattern and showing an uncommon intelligence, we
have, in few lines (which, in Java is a feat), succeeded in building a
very formal software that always returns the **right answer**. The
least I can say is that **Java excels at this kind of exercise**! You
should use it often. Another positive point is that this software can
probably run on any machine (provided it has a JVM installation
compatible with the byte code of the distributed software). And, even
more _deep_, because the verification algorithm is so clear, it is
possible **to run it without a JVM**... and even without a computer. For
example... close your eyes, think very hard about a mathematical
statement, **then simply say to yourself that you have no idea of the
validity of that statement**. _So far so good_.

To conclude... is this software useful? Probably not for
_intelligently_ checking mathematical statements or programs. But it
has the merit to demonstrate my quality as a Java programmer and my
**eligibility to become a Champion**. Although the lack of explicit
sums (as opposed to products) forces me to use an optional, rather
than an explcite sum: `Valid | Invalid | Dont_know`, but hey, that's
just functional programmer's flair (and yes, I am aware of the
existence of enums, but I find that even if it would have been
possible to represent the form I am proposing, it would have, firstly,
spoiled the substance of my article and apart from this aspect, they
propose a rather limited version of sums).

I hope you enjoyed reading this, and see you soon for new articles!
