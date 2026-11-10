> Write programs to handle text streams, because that is a universal interface.
>
> Doug McIlroy

It sounds wise. It is also how you end up making a duck, a mouse and an elephant bark like a dog.

## The dog

In the Unix philosophy, the dog is the text stream: lines of bytes, with no type and no shape. Every program reads it. Every program writes it. That is why they all fit together with a `|`.

Now look at what has to bark:

*   **The duck** is a list of files, each with a name, a size, an owner and a date.
*   **The mouse** is a single number: an exit code, a size, a port.
*   **The elephant** is a nested structure: a process tree, an API response, a configuration.

None of them is text. All of them are flattened into lines so they can go through the pipe. Then the next program has to guess what the lines meant.

## The dog was not a wise choice

The text stream was not chosen because it was the best way to connect programs. The authors of Unix say so themselves.

In 1974, Dennis Ritchie and Ken Thompson wrote down why Unix looks the way it does. They name three considerations. The second one is size:

> there have always been fairly severe size constraints on the system and its software. [...] the size constraint has encouraged not only economy but a certain elegance of design. This may be a thinly disguised version of the "salvation through suffering" philosophy, but in our case it worked.

The machine in that paper is a PDP-11/45 with 144K bytes of memory. Unix itself takes 42K of it.

On that machine, a uniform stream of bytes was the cheap answer. The paper says that all programs must work with any file or device, so the device-specific code goes into the operating system: the alternatives are "expensive in space", or "expensive either in overhead or in hardware". Pipes had the same reason. About commands like `ls`, they write that it would be "unwise for efficiency reasons" to ask each one to provide many output options.

Look at what they did not say. The system expects no structure at all: "No particular structuring is expected by the system [...] the structure of files is controlled by the programs which use them, not by the system." In 1974, the authors left the shape of the data to the programs. That is the opposite of the slogan.

They did not claim to be wise, either: "the success of UNIX is largely due to the fact that it was not designed to meet any predefined objectives."

The idea of the pipe was good, and it was deliberate. Doug McIlroy wrote a memo in 1964 about connecting programs "like garden hose", and Ken Thompson built the pipe in 1973. But the sentence that made the dog a principle came later. In 1978, McIlroy and two colleagues wrote the foreword of a Unix issue of the Bell System Technical Journal. It says to expect that the output of every program will become the input of another, and to "avoid stringently columnar or binary input formats". That is advice. The sentence "write programs to handle text streams, because that is a universal interface" was written down in 1994 by Peter Salus, who credits it to McIlroy. That is twenty-one years after the first pipe. The same year, Mike Gancarz listed "store data in flat text files" among the tenets of the Unix philosophy. In 2003, Eric Raymond made a whole book of it.

So the order is: a machine with 144K of memory forced a simple stream, then the stream was explained as a design, then it was taught as a principle.

The constraint is gone. A machine today has gigabytes of memory, and a pipe between two programs is cheap. The habit stayed, and in my experience it became a badge: knowing `awk` and `sed` by heart is treated as a sign of intelligence. A way to survive a small machine became a way to prove you belong. This is my opinion, not a finding. But I think that is how a limit turns into a culture.

## The universal interface is a loan

An interface is universal when it carries no meaning. The meaning does not disappear. It moves to the reader, and every reader pays for it, again and again.

You know the symptoms:

*   `ls | grep` breaks on a file name with a space. It breaks worse on a file name with a newline.
*   `ps aux | awk '{print $2}'` works until a column is empty or a command contains a space.
*   `find -print0 | xargs -0` exists because the dog could not bark a file name. We patched the dog with a null byte.
*   A program that prints a friendlier message breaks every script that read the old message. The output was never an API, but it became one.
*   Each tool brings its own half-parser for the text: `cut`, `awk`, `sed`, `tr`, and a regular expression that nobody wants to read again.

PowerShell made a different bet: pass objects, not text. You can dislike its syntax and still see the point. A file is a file object, with a size that is a number.

## One shape for everything

Unix is right about small programs that do one thing. It is wrong about one shape for everything.

The text stream treats every conversation between two programs as if it were public, even when only two programs of mine are talking. And the mistake did not stay in the shell. It followed us into our files, with a nicer coat: YAML, JSON and XML are the same dog, dressed for the modern web.

I paid for it this week, in my own repositories. That is the subject of [the next post](/blog/generic-formats-same-dog-nicer-coat).

The duck can quack. The mouse can squeak. The program that reads them only has to know which one it is talking to.

## Sources

*   Dennis M. Ritchie and Ken Thompson, [The UNIX Time-Sharing System](https://people.eecs.berkeley.edu/~brewer/cs262/unix.pdf), _Communications of the ACM_ 17(7), July 1974. Sections 2, 3.1, 6.2 and 8 (the memory, the files without structure, the filters, the three design considerations).
*   M. D. McIlroy, E. N. Pinson and B. A. Tague, [Unix Time-Sharing System: Foreword](https://archive.org/details/bstj57-6-1899), _The Bell System Technical Journal_ 57(6), 1978, pages 1902 to 1903.
*   Douglas McIlroy, [the 1964 memo on connecting programs like a garden hose](https://doc.cat-v.org/unix/pipes/), and Doug McIlroy's account of the pipe added by Ken Thompson in 1973 in [A Research Unix Reader](https://www.cs.dartmouth.edu/~doug/reader.pdf).
*   Peter H. Salus, _A Quarter Century of UNIX_, Addison-Wesley, 1994, pages 52 to 53.
*   Mike Gancarz, _The UNIX Philosophy_, 1994. Eric S. Raymond, _The Art of Unix Programming_, Addison-Wesley, 2003.
