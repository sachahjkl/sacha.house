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

## The same story with fork

Starting a program on Unix takes two steps. The process clones itself with `fork`. Then the clone replaces itself with the new program with `exec`. You copy a whole process, and you throw the copy away a moment later.

It looks like a design. It was a shortcut. Ritchie wrote that the first `fork` took 27 lines of assembly on the PDP-7, and that it exists in Unix "mainly because of the ease with which fork could be implemented without changing much else". He also noted that a single call to create a process and run a program "would have been considerably more complicated, if only because exec as such did not exist": the shell did that job with explicit I/O.

In 2019, four researchers from Microsoft Research, Boston University and ETH Zurich wrote a paper with a clear title: _A fork() in the road_. Their conclusion is that `fork` "was a clever hack for machines and programs of the 1970s that has long outlived its usefulness and is now a liability". Here is some of what they list:

*   The POSIX specification now lists 25 special cases for what the child inherits from the parent.
*   In a program with several threads, the child gets only one of them. A lock held by another thread stays locked forever in the child.
*   The child inherits everything by default, which goes against the principle of least privilege.
*   On their test machine, `posix_spawn` took about 0.5 ms whatever the size of the parent, while `fork` followed by `exec` took longer as the parent grew. Chrome has measured delays of up to 100 ms in `fork`.

They also looked at how the culture talks about it. Every operating system textbook they reviewed presents `fork` in positive or uncritical terms. One of them says: "the Unix designers simply got it right". Fifty years later, they counted 1,304 Ubuntu packages that call `fork`, and 41 that call `posix_spawn`.

Windows made the opposite choice: a function built for the job, `CreateProcess`. It creates a process and its primary thread. It takes ten parameters: the program, the command line, the security attributes of the process and of its thread, whether to inherit handles, creation flags, the environment, the current directory, the startup information, and a structure that receives the result. That is long. But it is written down: each aspect of the new process has a parameter, and the documentation describes each one. Apache, Chrome and PostgreSQL all run on Windows without `fork`.

One mechanism for everything is simple to implement on a small machine. It is not simple to live with.

## The universal interface is a loan

An interface is universal when it carries no meaning. The meaning does not disappear. It moves to the reader, and every reader pays for it, again and again.

You know the symptoms:

*   `ls | grep` breaks on a file name with a space. It breaks worse on a file name with a newline.
*   `ps aux | awk '{print $2}'` works until a column is empty or a command contains a space.
*   `find -print0 | xargs -0` exists because the dog could not bark a file name. We patched the dog with a null byte.
*   A program that prints a friendlier message breaks every script that read the old message. The output was never an API, but it became one.
*   Each tool brings its own half-parser for the text: `cut`, `awk`, `sed`, `tr`, and a regular expression that nobody wants to read again.

## The other bet: structure

PowerShell made a different bet: pass objects, not text.

Take one job, twice. List the text files bigger than 10,000 bytes, sorted by size.

```
ls -l *.txt | awk '$5 > 10000' | sort -k5 -n
```

```
Get-ChildItem -Path *.txt | Where-Object {$_.Length -gt 10000} | Sort-Object -Property Length
```

In the first line, `5` is a column number. I must know that the fifth column of `ls -l` is the size. The text does not say it. The position is the only information.

In the second line, `Length` is the name of a property of a file object. Nothing is guessed. And I can ask. Piping a command to `Get-Member` lists the type of the objects it returns, with their properties and methods. `Get-Help Start-Service -Parameter *` says which parameters accept pipeline input, and of which type. With text, the only way to learn the shape of the data is to run the command and look at it.

The more structure the data carries, the less the next program has to guess about its context. It is also where the ambiguity comes back when the structure is missing. `CreateProcess` takes the command line as one string. Its own documentation says that `c:\program files\sub dir\program name` can be read in four ways, and that the system tries them in order: `c:\program.exe`, then `c:\program files\sub.exe`, and so on. It also warns that this can run a `Program.exe` planted by an attacker instead of the program you meant. Unix passes the arguments of `exec` as separate strings, and it has done so since 1974: `execute(file, arg1, arg2, ..., argn)`. That ambiguity does not exist there.

This matters more in the era of AI, because the reader of the output is now often a language model. A model that reads the text of `ls -l` has to guess what each column means from the context, and it can guess wrong. The tools that coding agents call are built the other way. In the Model Context Protocol, each tool declares a name, a description, and an `inputSchema` that defines its parameters. It can also declare an `outputSchema` for its result. The specification gives the reason: it helps "clients and LLMs to properly parse and utilize the returned data". A reader that has only the text to go on needs the data to say what it is.

Look at what happened there. Nobody built one universal tool interface where every tool takes a string. Each tool declares its own shape.

Structure removes the guess. A flat string brings it back, even inside a specialized API.

## The same mistake in C++: the resource

Unix made the first resource: the file. The 1974 paper says that file and device I/O are "as similar as possible", so that a program written for a file works on a device. The same paper already shows the leak. For some devices, "seek calls are ignored". A read from a typewriter never returns more than one line. A read may return less than you asked for, "without error". The abstraction held until it met something that was not a file.

C++ built the same thing into the language, and gave it a name. RAII ties the lifetime of an object to a "resource", and cppreference defines the word: allocated heap memory, a thread, an open socket, an open file, a locked mutex, disk space, a database connection, "anything that exists in limited supply".

Anything. Look at what the word puts together:

*   **A file.** Closing it can fail, and the failure matters. The `close(2)` manual says that errors on an earlier write may be reported only at the final `close`, and that not checking it "may lead to silent loss of data". The RAII rule says that "the destructor releases the resource and never throws exceptions". So the one error that matters has nowhere to go. To see it, you must close the file yourself before the destructor runs. The abstraction does nothing, and it is still there.
*   **A texture.** In Vulkan, destroying an image (a `VkImage`, the texture on the GPU) is valid only when all submitted commands that refer to it "have completed execution". The release must wait for another device. The end of a scope is not the moment to decide that.
*   **Heap memory.** `free` returns nothing. It has no error to report and nobody to wait for.

That is three releases: one that can lose your data, one that must wait for the GPU, and one that cannot fail. They share a word. They do not share a mechanism.

Scope-bound cleanup is not the problem. Hiding it inside the type is. The word "resource" says that these things are one kind of thing, so that one mechanism can release them all. It makes them bark like a dog: acquire, release.

Several languages do the cleanup in the open, with `defer`. The release is a line of code, written next to the acquisition.

*   **Go** runs a deferred call "immediately before the surrounding function returns". The specification adds that a deferred function "may access and modify the result parameters before they are returned". So the error of the file has somewhere to go:

```go
func write(name string, data []byte) (err error) {
	f, err := os.Create(name)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, f.Close()) }()
	_, err = f.Write(data)
	return err
}
```

*   **Zig** has `defer`, which executes an expression "unconditionally at scope exit". It also has `errdefer`, which runs only if the function returns an error. A destructor runs on both paths. `errdefer` is written for one of them.
*   **Odin** shows `defer os.close(f)` right after `os.open`, and its documentation says that it "acts akin to an explicit C++ destructor however, the error handling is basic control flow".

Nothing is hidden. The reader sees what is released, when it is released, and what happens to the error. Each thing has its own release, written for it, and no type decides for all of them.

Sandi Metz wrote a sentence that sounds exaggerated and is not: "duplication is far cheaper than the wrong abstraction". Her advice for when you are stuck in one is: "the fastest way forward is back". A wrong abstraction is worse than none, because every user must work around it, and its presence argues that it is correct. Without it, each thing would have a release that says what it does: a file closes with a function that returns an error, a texture is destroyed through a queue that waits for the GPU. It would be a few more lines. They would be true.

## Let the interface fit the thing

The answer is not a better universal format. It is to stop looking for one.

A call to create a process, with a parameter for each thing that matters. Objects with named properties that you can list. A release for each thing, written next to its acquisition, with its own result and its own timing. A file format for a project, with the two keys that the project needs. Each of them says what it carries. Each can be documented, discovered and checked. And the program that uses them has less to guess.

Unix is right about small programs that do one thing. It is wrong about one shape for everything. The text stream treats every conversation between two programs as if it were public, even when only two programs of mine are talking.

The mistake did not stay in the shell. It followed us into our files, with a nicer coat: YAML, JSON and XML are the same dog, dressed for the modern web. I paid for it this week, in my own repositories. That is the subject of [the next post](/blog/generic-formats-same-dog-nicer-coat).

The duck can quack. The mouse can squeak. The program that reads them only has to know which one it is talking to.

## Sources

*   Dennis M. Ritchie and Ken Thompson, [The UNIX Time-Sharing System](https://people.eecs.berkeley.edu/~brewer/cs262/unix.pdf), _Communications of the ACM_ 17(7), July 1974. Sections 2, 3.1, 6.2 and 8 (the memory, the files without structure, the filters, the three design considerations).
*   M. D. McIlroy, E. N. Pinson and B. A. Tague, [Unix Time-Sharing System: Foreword](https://archive.org/details/bstj57-6-1899), _The Bell System Technical Journal_ 57(6), 1978, pages 1902 to 1903.
*   Douglas McIlroy, [the 1964 memo on connecting programs like a garden hose](https://doc.cat-v.org/unix/pipes/), and Doug McIlroy's account of the pipe added by Ken Thompson in 1973 in [A Research Unix Reader](https://www.cs.dartmouth.edu/~doug/reader.pdf).
*   Peter H. Salus, _A Quarter Century of UNIX_, Addison-Wesley, 1994, pages 52 to 53.
*   Mike Gancarz, _The UNIX Philosophy_, 1994. Eric S. Raymond, _The Art of Unix Programming_, Addison-Wesley, 2003.
*   Andrew Baumann, Jonathan Appavoo, Orran Krieger and Timothy Roscoe, [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), HotOS '19, 2019. The source of the quotes about Ritchie, the list of problems, the measures, the textbooks and the package counts.
*   Dennis M. Ritchie, [The Evolution of the Unix Time-sharing System](https://www.read.seas.harvard.edu/~kohler/class/aosref/ritchie84evolution.pdf), on the 27 lines of assembly of the first `fork`.
*   Microsoft, [CreateProcess function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa), on the parameters, and on the four readings of the command line.
*   Microsoft, [about_Pipelines](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pipelines), on objects in the pipeline, `Get-Member` and `Get-Help`.
*   Model Context Protocol, [Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools), specification of 2025-06-18, on `inputSchema` and `outputSchema`.
*   cppreference, [RAII](https://en.cppreference.com/w/cpp/language/raii), for the definition of a resource and the rule that a destructor never throws.
*   Linux man-pages, [close(2)](https://man7.org/linux/man-pages/man2/close.2.html), on the errors reported at `close` and the silent loss of data.
*   Khronos, [vkDestroyImage](https://docs.vulkan.org/refpages/latest/refpages/source/vkDestroyImage.html), on the commands that must have completed before an image is destroyed.
*   Sandi Metz, [The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction), 2016.
*   The Go Programming Language Specification, [Defer statements](https://go.dev/ref/spec#Defer_statements).
*   Zig Language Reference, [defer](https://ziglang.org/documentation/master/#defer) and [errdefer](https://ziglang.org/documentation/master/#errdefer).
*   Odin Programming Language, Overview, [defer statement](https://odin-lang.org/docs/overview/#defer-statement).
