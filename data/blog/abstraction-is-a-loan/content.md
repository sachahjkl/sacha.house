An abstraction is a loan.

It gives you something now: you stop thinking about the machine and start thinking about the problem. The price comes later, with interest, in cycles, in memory and in the hours you spend finding out what the layer was doing for you. The better the abstraction hides the price, the more you will borrow.

![Five painted matryoshka dolls of different sizes standing in a row, with two tiny ones in front](/media/blog/abstraction-is-a-loan/assets/matryoshka.jpg)

*Each layer hides the next one. The price is in the smallest doll.*[^photos]

## The layer that leaks

Joel Spolsky named the problem in 2002: "All non-trivial abstractions, to some degree, are leaky. Abstractions fail. Sometimes a little, sometimes a lot."[^spolsky]

His example is the one I like best, because it is so small. Iterating over a large two-dimensional array "can have radically different performance if you do it horizontally rather than vertically", depending on the grain of the wood: one direction causes many more page faults than the other. The array looks like a grid. It is a strip of memory, laid out in rows, read through a cache and paged in by an operating system. The grid is an abstraction. The page faults are the machine, coming through.

You do not need to know the machine all the time. You need to know it on the day the program is slow.

## The price of a rule

A rule is an abstraction for behavior. Casey Muratori took the first rule of "clean code", which says to prefer polymorphism to a `switch`, and timed it. On a small example with shapes, removing the polymorphism gave "an immediate 1.5x performance increase", from 35 cycles per shape to 24. A table of values, with no branching at all, was nearly 15 times faster than the clean version.[^muratori]

It is one benchmark, on one problem. But look at what it shows. The code was clean in the sense that every shape knew how to compute its own area. That is a very comfortable way to think. The machine does not think that way. It wants an array of numbers and one loop.

When the abstraction is the unit of thinking, the machine is somewhere below the unit, and nobody looks.

## The objection

Dijkstra has the best answer against everything I have said so far. In 1972 he wrote that "the purpose of abstracting is not to be vague, but to create a new semantic level in which one can be absolutely precise."[^dijkstra]

He is right. A file, a stack, a sorted list: each one says exactly what you can do with it and what you cannot, and you can build a program on it without ever opening it. That is a tool, and it pays for itself.

So the question is not abstraction or no abstraction. It is which kind. An abstraction that is narrow and exact is Dijkstra's. It answers a precise question, and you can say what it costs. An abstraction that is wide and hides its cost is a loan, and it is the kind that Spolsky's law is about. The Go proverbs put it in one line: "The bigger the interface, the weaker the abstraction."[^proverbs]

The danger grows with the width. A wide abstraction covers many things, so it can say little about any one of them. And it is exactly the wide ones that are used as the unit of thought: the "resource", the "object", the "service". I wrote about the wrong ones in [another post](/blog/wrong-abstraction-fork-files-resources). Sandi Metz put the cost in a sentence: "duplication is far cheaper than the wrong abstraction".[^metz]

## Composition

The other way to build is to compose.

![Loose LEGO bricks of several colors and sizes lying on a table, with a coin for scale](/media/blog/abstraction-is-a-loan/assets/bricks.jpg)

*Nothing underneath. Every piece shows what it is and how it connects.*

Composition is putting structures next to each other and inside each other, with nothing underneath that holds them together. An array of records. A record that holds another record. A pipe that connects a program that reads to a program that writes. You can see the whole thing, because it is only the parts and the way they touch.

The pipe is the oldest example. The 1974 Unix paper describes a "filter", a program that copies its input to its output with some processing, and a line of them chained with `|`.[^unix] Each filter is small. The structure of the whole is the order in which they are written. There is no framework above them that knows what they mean.

The file of this site that describes each of my projects is a smaller one. It is a list of `key=value` lines, and the program that reads it returns a flat map of strings. No schema, no parser library, no base class. The data is what it looks like, and the reader is twenty lines.

Compare that with an abstraction. An abstraction makes a promise about something it does not show you. A composition shows you everything, and promises nothing more than the parts. That is why it does not become a well of complexity: there is nothing to put the complexity in.

The Go proverbs have a line for the discipline: "Make the zero value useful." A structure that works when it is empty, and that grows by holding more of itself, needs no hidden machinery.

## A rule of thumb

Here is how I choose.

*   Use the abstraction when you can say, in a sentence, what it guarantees and what it costs.
*   If you cannot, compose. Put the data in a plain structure and write the loop.
*   When the program is slow or wrong, look at the machine first, and the layer second.

The first rule keeps Dijkstra's tool. The second keeps the loan from growing. The third is the day when the layer leaks.

## Sources

[^spolsky]: Joel Spolsky, [The Law of Leaky Abstractions](https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/), 2002.
[^muratori]: Casey Muratori, ["Clean" Code, Horrible Performance](https://www.computerenhance.com/p/clean-code-horrible-performance), 2023. The figures are 35 and 24 cycles per shape, and the lookup table at nearly 15x.
[^dijkstra]: Edsger W. Dijkstra, [The Humble Programmer](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html), EWD340, 1972.
[^proverbs]: Rob Pike, [Go Proverbs](https://go-proverbs.github.io/).
[^metz]: Sandi Metz, [The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction), 2016.
[^unix]: Dennis M. Ritchie and Ken Thompson, [The UNIX Time-Sharing System](https://people.eecs.berkeley.edu/~brewer/cs262/unix.pdf), 1974, section 6.2.
[^photos]: Photographs from Wikimedia Commons, resized: [matryoshka dolls](https://commons.wikimedia.org/wiki/File:Matryoshka_from_Hungary.jpg) by Wilfredor (CC0), and [LEGO bricks](https://commons.wikimedia.org/wiki/File:LEGO-01.jpg) by Priwo (public domain).
