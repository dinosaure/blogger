---
date: 2021-08-08
article_title: Type-dependent instances in Java
article_description:
  While studying Java (to become a real Java-Champion) I came across
  a feature I didn't know about, "type-dependent instances".
  Incredible!
tags:
  - Java
  - Types
  - Indexation
---

> Today, I present you with a powerful tip... so strong that I almost didn't
> share it. But when you want to become a champion, in a community other than
> boxing, you have to be able to take on the role of mentor and share the
> knowledge you have acquired over the years without limit. Watch your abs,
> we're going _to build muscle_, and not just the head, let me introduce "_type
> dependent instances_".

When you want to become a 10-engineer you have to master several skills.
Firstly, you need to use a "_business ready_" language (like
[C#](https://docs.microsoft.com/en-us/dotnet/csharp/tour-of-csharp/) or
[Java](https://www.java.com/fr/), usually these kinds of serious languages have
an "_Enterprise_" version), then, you have to be able to write software that
crashes enough to ensure cash-money by doing maintenance, and finally, you have
to be able to abstract enough not to repeat yourself... and yes, it is often
said, software engineers are lazy! In this article, I propose you to discover an
article which will make you save a colossal amount of time! Please note that all
the examples presented here are from a case that actually happened. _I swear on
my mother's life_ (lol).

### A brief background of the problem

This part could have been called "**How I solved, with great intelligence, a very
complex problem**".

> Beware, this first part is full of very complicated code, so don't panic if
> you don't understand everything at first reading.

While awkwardly trying to write software, I kept sadly running into
`NullPointerException`. What a hell! Although Java could be a bit more expansive
on the ability of a value to become `null` (as in
[Kotlin](https://kotlinlang.org/) which is, **to my knowledge**, one of the only
languages that handles explicit treatment of nullable values), the error is
essentially my responsibility! As I am an engineer, I just need to write a
function that can handle **the presence or absence of an integer**! Nice.

First, the parent type is described:

```java
abstract class NullableInt {}
```

And then I can describe the two cases, the first being whether I have a value.
It's quite simple, you just assign a value.

```java
class Int extends NullableInt {
    private int value;
    public Int(int value) {
        this.value = value;
    }

    public String toString() {
        return "" + this.value;
    }
}
```

And the second, if I have no value! Which is even simpler!

```java
// if I don't have any value
class NullInt extends NullableInt {
    public String toString() {
        return "Null";
    }
}
```

On the other hand, for the moment, I am no further ahead... indeed, I can do
nothing with my incredible safety addition... don't panic, to make our class
useful, we just need to be able to apply functions to our value, but ... what is
a function in Java? It seems that there is, since
[Java8](https://www.java.com/en/download/help/java8_fr.html), a feature called
[Lambda](https://docs.oracle.com/javase/tutorial/java/javaOO/lambdaexpressions.html)...
but let's be honest... who in real life wants to program using **obscure Greek
words**? Fortunately, when you want to avoid _greeknessense_ (γεια), you can use
an even more _greeknessense_ encoding presented in [A Theory of
Objects](https://link.springer.com/book/10.1007/978-1-4419-8598-9) by [Martin
Abadi](https://users.soe.ucsc.edu/~abadi/home.html) and [Luca
Cardelli](https://en.wikipedia.org/wiki/Luca_Cardelli).

Indeed, a "lambda" is nothing more than a class that implements a particular
interface:

```java
interface FunctionFromIntToInt {
  int call(int x);
}
```

We can now define, without much verbosity, two functions: `Successor` and
`Predecessor`. The `Successor` function takes an integer and returns, as its
name suggests, its successor.

```java
class Successor implements FunctionFromIntToInt {
    public int call(int x) {
        return x + 1;
    }
}
```

The `Predecessor` function takes an integer and returns, as its name suggests,
its predecessor.

```java
class Predecessor implements FunctionFromIntToInt {
    public int call(int x) {
        return x - 1;
    }
}
```

Another common function is the `identity` function, which in the case of integers
could have been written as the application of successor and predecessor (and
vice versa) can be described even more easily in this way:

```java
class Identity implements FunctionFromIntToInt {
    public int call(int x) {
        return x;
    }
}
```

With a tool to apply functions, we can now modify our API to be able to "surely"
apply functions to our values. Nice. Indeed, we only need to add methods to our
abstract class to be able to ... _deal_... with our null values:

```java
abstract class NullableInt {
    abstract public NullableInt applyFunction(FunctionFromIntToInt f);
    abstract public int fold(FunctionFromIntToInt isNotNull, int isNull);

    public int getValueOrDefault(int defaultValue) {
        return this.fold(new Identity(), defaultValue);
    }
}
```

As you can see, our abstract functions are expressive enough to describe the
`getValueOrDefault` function which is a little masterpiece of mechanics (and
yes, I told you, this blog is for lovers of beautiful mechanics... and muscles).
Now, our two classes must implement the abstract methods... and yes... otherwise
the code will not compile!

Nothing could be simpler, each child class will take care to implement only what
concerns it. So in the case where we have `NullInt`, it is sufficient to return
a `NullInt` instance when applying a function. And in case of `fold` (a kind of
`Visitor` to use the terminology of **The Gang of Four**, not to be confused
with **The Club of Five**, _GO DAGOBERT!_), just return `isNull`.

```java
class NullInt extends NullableInt {
    public NullableInt applyFunction(FunctionFromIntToInt f) {
        return new NullInt();
    }

    public int fold(FunctionFromIntToInt isNotNull, int isNull) {
        return isNull;
    }
    public String toString() {
        return "Null";
    }
}
```

Now that we take into account the case where the value does not exist, it is
sufficient to implement the case for `Int`. Nothing could be simpler, when we
want to apply a function... we just apply a function and for `fold` we execute
`isNotNull` (which is a function):

```java
class Int extends NullableInt {
    private int value;
    public Int(int value) {
        this.value = value;
    }
    public NullableInt applyFunction(FunctionFromIntToInt f) {
        return new Int(f.call(this.value));
    }

    public int fold(FunctionFromIntToInt isNotNull, int isNull) {
        return isNotNull.call(this.value);
    }

    public String toString() {
        return "" + this.value;
    }
}
```

We have all the ingredients to build pipelines of computations on integers that
can be `null` and all... without any `NullPointerException`. This is
extraordinary. Without further ado, I'll give you some exclusive production code
that uses this **clever approach**.

```java
public class ARealWorldService {
    public static void main(String args[]) {
      FunctionFromIntToInt succ = new Successor();
      FunctionFromIntToInt pred = new Predecessor();
      NullableInt myNullableInt = new Int(10);
      NullableInt myOtherNullableInt = new NullInt();
      System.out.println(myOtherNullableInt
            .applyFunction(succ)
            .applyFunction(pred)
            .applyFunction(succ)
            .getValueOrDefault(100)
      );
    }
}
```

Terrific.

### When problems arise

After putting this (micro-)service into production (in a Docker that mounts a
JVM) many of my colleagues came to me for help in refactoring their services...
they had to deal with `nullable strings`, `nullable doubles` etc. When you want
to manipulate a lot of nullable types, you realise that in fact... what you
want... are the templates of C++. Indeed, without methods to generalise
nullability... the growth of **the number of classes required can quickly
explode**.

Fortunately... while immersing myself in existing Java code, I discovered a tool
that allows me to save time. I called it "**type-dependent instances**", because
the only name I could find in the documentation was "Generics" (and I didn't see
a connection with Bernard Minet, _a joke exclusively for French speakers_).

### type-dependent instances

Java has a way of describing type variables in the class definition... which
will allow this type to be fixed (monomorphised) at instance time. For example,
we could redeclare our function `functionFromIntToInt` in this way:

```java
interface Function<In, Out> { Out call(In x); }
interface EndoFunction<T> extends Function<T, T> {}
interface FunctionFromIntToInt extends EndoFunction<Integer> {}
```

Surprisingly, this is a fairly well-known approach in Java (but I didn't know
it) used to, for example... describe lists: `List<A>` where `A` is a (type)
variable, but also to describe... optionality with `Optional<A>`. By the way,
the ultimate form of refactoring my real-world-code would simply be to replace
all my occurrences of `NullableInt` with `Optional<Integer>`. **Wow**.

### Going further with type constraint

Incredible but the magic doesn't stop here. Indeed, it is possible to constrain
the type of a type variable, using the syntax : `Class<T extends S>` which means
the class `Class` is parameterised by a `T` **which is a subtype of** `S`.
It is called a "_Bounded Type Parameter_", but as I find the name unclear, I
suggest using the term: "**type class**", because the type is constrained by a
class (or an interface, but it is the same thing). It is also possible to add
several separate constraints using `&`. Incredible. The documentation talks
about "_Multiple Bounds_" but I also find this name unclear, so I propose to
call it "**type family**" because all the constraints form a family.

### To conclude

Incredibly, we have discovered a rather unknown feature of Java to facilitate
refactoring. To summarise:

- A class can be parameterised by type variables, and I decided to call an
  instance that embodies this kind of class a **type-dependent instances**.
- This kind of class can have constraints on type variables. If there is only
  one constraint, I decided to call it a **type class** and if there are more
  than one constraint, I decided to call it a **type family**.

Some people will tell me that **dependent types**, **type classes** and **type
families** already exist in programming terminology but as mentioned previously
**let's be honest, who in real life wants to program using obscure Greek
words?**

I hope you enjoyed reading this, and see you soon for new articles!
