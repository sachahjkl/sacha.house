In [the first post](/blog/unix-philosophy-bark-like-a-dog), I looked at the Unix text stream: a small machine, a size constraint, and a slogan written down twenty-one years later. It makes a duck, a mouse and an elephant bark like a dog.

The same pattern appears elsewhere. Someone finds a mechanism that is cheap to build. It gets used for everything. Fifty years later it is taught as a good idea. This post looks at two cases: starting a program, and the idea of a "resource".

![A spool of thread, a plug adapter, a filing cabinet and a pile of gravel](/media/blog/wrong-abstraction-fork-files-resources/assets/four-resources.jpg)

*4 resources*[^photos]

## The same story with fork

Starting a program on Unix takes two steps. The process clones itself with `fork`. Then the clone replaces itself with the new program with `exec`. You copy a whole process, and you throw the copy away a moment later.

![A photocopier next to a paper shredder](/media/blog/wrong-abstraction-fork-files-resources/assets/fork-exec.jpg)

*fork(); exec();*

It looks like a design. It was a shortcut. Ritchie wrote that the first `fork` took 27 lines of assembly on the PDP-7, and that it exists in Unix "mainly because of the ease with which fork could be implemented without changing much else".[^ritchie84] He also noted that a single call to create a process and run a program "would have been considerably more complicated, if only because exec as such did not exist": the shell did that job with explicit I/O.

In 2019, four researchers from Microsoft Research, Boston University and ETH Zurich wrote a paper with a clear title: _A fork() in the road_. Their conclusion is that `fork` "was a clever hack for machines and programs of the 1970s that has long outlived its usefulness and is now a liability".[^baumann] Here is some of what they list:

*   The POSIX specification now lists 25 special cases for what the child inherits from the parent.[^b_simple]
*   In a program with several threads, the child gets only one of them. A lock held by another thread stays locked forever in the child.[^b_thread]
*   The child inherits everything by default, which goes against the principle of least privilege.[^b_secure]
*   On their test machine, `posix_spawn` took about 0.5 ms whatever the size of the parent, while `fork` followed by `exec` took longer as the parent grew. Chrome has measured delays of up to 100 ms in `fork`.[^b_slow]

They also looked at how the culture talks about it. Every operating system textbook they reviewed presents `fork` in positive or uncritical terms. One of them says: "the Unix designers simply got it right". Fifty years later, they counted 1,304 Ubuntu packages that call `fork`, and 41 that call `posix_spawn`.[^b_culture]

Windows made the opposite choice: a function built for the job, `CreateProcess`. It creates a process and its primary thread. It takes ten parameters: the program, the command line, the security attributes of the process and of its thread, whether to inherit handles, creation flags, the environment, the current directory, the startup information, and a structure that receives the result. That is long. But it is written down: each aspect of the new process has a parameter, and the documentation describes each one.[^createprocess] Apache, Chrome and PostgreSQL all run on Windows without `fork`.

One mechanism for everything is simple to implement on a small machine. It is not simple to live with.

## The same mistake in C++: the resource

Unix made the first resource: the file. The 1974 paper says that file and device I/O are "as similar as possible", so that a program written for a file works on a device. The same paper already shows the leak. For some devices, "seek calls are ignored". A read from a typewriter never returns more than one line. A read may return less than you asked for, "without error". The abstraction held until it met something that was not a file.[^r74]

C++ built the same thing into the language, and gave it a name. RAII ties the lifetime of an object to a "resource", and cppreference defines the word: allocated heap memory, a thread, an open socket, an open file, a locked mutex, disk space, a database connection, "anything that exists in limited supply".[^cppref]

Anything. Look at what the word puts together:

*   **A file.** Closing it can fail, and the failure matters. The `close(2)` manual says that errors on an earlier write may be reported only at the final `close`, and that not checking it "may lead to silent loss of data".[^close] The RAII rule says that "the destructor releases the resource and never throws exceptions".[^cppref2] So the one error that matters has nowhere to go. To see it, you must close the file yourself before the destructor runs. The abstraction does nothing, and it is still there.
*   **A texture.** In Vulkan, destroying an image (a `VkImage`, the texture on the GPU) is valid only when all submitted commands that refer to it "have completed execution".[^vulkan] The release must wait for another device. The end of a scope is not the moment to decide that.
*   **Heap memory.** `free` returns nothing. It has no error to report and nobody to wait for.

That is three releases: one that can lose your data, one that must wait for the GPU, and one that cannot fail. They share a word. They do not share a mechanism.

Scope-bound cleanup is not the problem. Hiding it inside the type is. The word "resource" says that these things are one kind of thing, so that one mechanism can release them all. It makes them bark like a dog: acquire, release.

Several languages do the cleanup in the open, with `defer`. The release is a line of code, written next to the acquisition.

*   **Go** runs a deferred call "immediately before the surrounding function returns". The specification adds that a deferred function "may access and modify the result parameters before they are returned".[^go] So the error of the file has somewhere to go:

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

*   **Zig** has `defer`, which executes an expression "unconditionally at scope exit".[^zig] It also has `errdefer`, which runs only if the function returns an error. A destructor runs on both paths. `errdefer` is written for one of them.
*   **Odin** shows `defer os.close(f)` right after `os.open`, and its documentation says that it "acts akin to an explicit C++ destructor however, the error handling is basic control flow".[^odin]

Nothing is hidden. The reader sees what is released, when it is released, and what happens to the error. Each thing has its own release, written for it, and no type decides for all of them.

Sandi Metz wrote a sentence that sounds exaggerated and is not: "duplication is far cheaper than the wrong abstraction". Her advice for when you are stuck in one is: "the fastest way forward is back".[^metz] A wrong abstraction is worse than none, because every user must work around it, and its presence argues that it is correct. Without it, each thing would have a release that says what it does: a file closes with a function that returns an error, a texture is destroyed through a queue that waits for the GPU. It would be a few more lines. They would be true.

## Name the thing

A wrong abstraction is worse than none. It costs every user something, and it hides what each thing really does.

The way out is not a better universal mechanism. It is a call to create a process, with a parameter for each thing that matters. It is a release for each thing, written next to its acquisition, with its own result and its own timing. Each of them says what it carries and what it does. Each can be documented and checked. And the program that uses them has less to guess.

The same mistake lives in our files. YAML, JSON and XML are the same dog, dressed for the modern web. I paid for it this week, in my own repositories. That is the subject of [the next post](/blog/generic-formats-same-dog-nicer-coat).

## Sources

[^photos]: Photographs from Wikimedia Commons, cropped and resized: a [spool of thread](https://commons.wikimedia.org/wiki/File:Spool_of_sewing_thread_made_by_M%C3%B6lnlycke_-_SG1L1735.jpg) by vonSmall (public domain), a [plug adapter](https://commons.wikimedia.org/wiki/File:Mains.plug%2Bsockets.JPG) by Julo (public domain), a [filing cabinet](https://commons.wikimedia.org/wiki/File:Cabinet,_filing_%28AM_2004.52.32-7%29.jpg) from Auckland Museum ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), a [gravel pile](https://commons.wikimedia.org/wiki/File:Gravel_Pile.jpg) by Al-muhaqqiqi (CC0), a [photocopier](https://commons.wikimedia.org/wiki/File:The_Closest_Photocopier_%283594209596%29.jpg) by Dennis Sylvester Hurd (CC0), and a [paper shredder](https://commons.wikimedia.org/wiki/File:Paper_Shredder.jpg) by High Plains Drifter (public domain).
[^ritchie84]: Dennis M. Ritchie, [The Evolution of the Unix Time-sharing System](https://www.read.seas.harvard.edu/~kohler/class/aosref/ritchie84evolution.pdf), on the 27 lines of assembly of the first `fork`. The two quotes of this paragraph are quoted in section 2 of Baumann et al.
[^baumann]: Andrew Baumann, Jonathan Appavoo, Orran Krieger and Timothy Roscoe, [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), HotOS '19, 2019. The source of the quotes about Ritchie, the list of problems, the measures, the textbooks and the package counts.
[^b_simple]: Baumann et al., [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), section 4, "Fork is no longer simple": the POSIX specification lists 25 special cases.
[^b_thread]: Baumann et al., [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), section 4, "Fork isn't thread-safe".
[^b_secure]: Baumann et al., [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), section 4, "Fork is insecure".
[^b_slow]: Baumann et al., [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), section 4, "Fork is slow" and figure 1, measured on Ubuntu 16.04.3 with an Intel i7-6850K.
[^b_culture]: Baumann et al., [A fork() in the road](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/04/fork-hotos19.pdf), section 1: the textbooks they reviewed, the quote, and the count of Ubuntu packages, which they take from Atlidakis et al., EuroSys 2016.
[^createprocess]: Microsoft, [CreateProcess function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa), on the parameters, and on the four readings of the command line. The count of ten parameters is from section 3 of Baumann et al.
[^r74]: Dennis M. Ritchie and Ken Thompson, [The UNIX Time-Sharing System](https://people.eecs.berkeley.edu/~brewer/cs262/unix.pdf), 1974: sections 3.3 ("as similar as possible") and 3.6 (seek ignored on some devices, a typewriter never returns more than one line, a read may return less than asked "without error").
[^cppref]: cppreference, [RAII](https://en.cppreference.com/w/cpp/language/raii), for the definition of a resource and the rule that a destructor never throws.
[^close]: Linux man-pages, [close(2)](https://man7.org/linux/man-pages/man2/close.2.html), on the errors reported at `close` and the silent loss of data.
[^cppref2]: The same page, "RAII can be summarized as follows".
[^vulkan]: Khronos, [vkDestroyImage](https://docs.vulkan.org/refpages/latest/refpages/source/vkDestroyImage.html), on the commands that must have completed before an image is destroyed.
[^go]: The Go Programming Language Specification, [Defer statements](https://go.dev/ref/spec#Defer_statements).
[^zig]: Zig Language Reference, [defer](https://ziglang.org/documentation/master/#defer) and [errdefer](https://ziglang.org/documentation/master/#errdefer).
[^odin]: Odin Programming Language, Overview, [defer statement](https://odin-lang.org/docs/overview/#defer-statement).
[^metz]: Sandi Metz, [The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction), 2016.
