> Write programs to handle text streams, because that is a universal interface.
>
> Doug McIlroy

It sounds wise. It is also how you end up making a duck, a mouse and an elephant bark like a dog.


![A mallard duck, a house mouse and an African elephant, followed by a German shepherd that is really barking](/media/blog/unix-philosophy-bark-like-a-dog/assets/duck-mouse-elephant-dog.jpg)

*4 dogs*

## The dog

In the Unix philosophy, the dog is the text stream: lines of bytes, with no type and no shape. Every program reads it. Every program writes it. That is why they all fit together with a `|`.

![A Teletype ASR-33 terminal on a table at a computer festival](/media/blog/unix-philosophy-bark-like-a-dog/assets/teletype.jpg)

*A Teletype ASR-33, a typical terminal of the 1970s. It prints text, and nothing else.*

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

![A man in a white coat at a PDP-11 computer and its terminal](/media/blog/unix-philosophy-bark-like-a-dog/assets/pdp11.jpg)

*A PDP-11/34 at a U.S. Army center, 1978. The PDP-11/45 of the 1974 paper had 144K bytes of memory.*

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

## When the text is also the command

Text is fine for people to read: a log, a message, a README. The trouble starts when text is the interface between programs. A program that reads text cannot tell the data from the commands. They travel in the same channel, and whoever writes the data can write a command.

The best example is the language that was meant to be written by anyone. In 1974, Donald Chamberlin and Raymond Boyce called it SEQUEL, for Structured English Query Language. Their abstract says it is "intended as a data base sublanguage for both the professional programmer and the more infrequent data base user". Plain English words, so that you did not need to be a programmer. In my experience, that is not what happened. Today SQL is written by programmers, and the text it is made of is assembled by programs, from strings.

That is where the trouble comes from. OWASP defines a SQL injection like this: "untrusted data (usually strings) becomes part of a query's SQL syntax, modifying the logic of the SQL request". Its first example is a query built by gluing a request parameter into a string. The user types SQL, and the database runs it.

The fix is to stop using one channel. OWASP says: "define the SQL structure separately from its data values, then bind those values through the database API". The query goes one way, the values go the other way. It is structure that fixes the problem. And even then, parameter markers stand for values only, not for table names, column names or `ASC` and `DESC`. Those still travel as text, so OWASP asks for a fixed list of allowed choices. It calls manual escaping "strongly discouraged".

The same thing happened in the shell. In 2014, Shellshock (CVE-2014-6271) showed that Bash processed "trailing strings after function definitions in the values of environment variables". An environment variable is text. A function definition is code. A crafted value was enough to run commands on the server.

And it is happening again with language models. OWASP explains prompt injection like this: the developer's instructions and the user's input "share the same fundamental format: natural-language text strings". The model reads both in one stream. It is the first risk on OWASP's list for LLM applications in 2025.

Look at the pattern. A text interface is easy to write for everyone. That was the idea. It is also easy to write for an attacker, and the good intentions did not change that.

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

The more structure the data carries, the less the next program has to guess about its context. It is also where the ambiguity comes back when the structure is missing. `CreateProcess`, the Windows call that starts a program, takes the command line as one string. Its own documentation says that `c:\program files\sub dir\program name` can be read in four ways, and that the system tries them in order: `c:\program.exe`, then `c:\program files\sub.exe`, and so on. It also warns that this can run a `Program.exe` planted by an attacker instead of the program you meant. Unix passes the arguments of `exec` as separate strings, and it has done so since 1974: `execute(file, arg1, arg2, ..., argn)`. That ambiguity does not exist there.

This matters more in the era of AI, because the reader of the output is now often a language model. A model that reads the text of `ls -l` has to guess what each column means from the context, and it can guess wrong. The tools that coding agents call are built the other way. In the Model Context Protocol, each tool declares a name, a description, and an `inputSchema` that defines its parameters. It can also declare an `outputSchema` for its result. The specification gives the reason: it helps "clients and LLMs to properly parse and utilize the returned data". A reader that has only the text to go on needs the data to say what it is.

Look at what happened there. Nobody built one universal tool interface where every tool takes a string. Each tool declares its own shape.

Structure removes the guess. A flat string brings it back, even inside a specialized API.

## One mechanism for everything

The text stream is not the only place where a shortcut became a principle. It is the first one, and the easiest to see. Data that says what it is, like a property you can list or a parameter with a schema, leaves the reader less to guess. Data that is flattened to text leaves it more.

Starting a program, closing a file, freeing memory: Unix, and C++ after it, did the same thing again and again. They found one mechanism that was cheap to build, and they asked it to serve everything. I look at two more cases in [the next post](/blog/wrong-abstraction-fork-files-resources).

The duck can quack. The mouse can squeak. The program that reads them only has to know which one it is talking to.

## Sources

*   Dennis M. Ritchie and Ken Thompson, [The UNIX Time-Sharing System](https://people.eecs.berkeley.edu/~brewer/cs262/unix.pdf), _Communications of the ACM_ 17(7), July 1974. Sections 2, 3.1, 6.2 and 8 (the memory, the files without structure, the filters, the three design considerations).
*   M. D. McIlroy, E. N. Pinson and B. A. Tague, [Unix Time-Sharing System: Foreword](https://archive.org/details/bstj57-6-1899), _The Bell System Technical Journal_ 57(6), 1978, pages 1902 to 1903.
*   Douglas McIlroy, [the 1964 memo on connecting programs like a garden hose](https://doc.cat-v.org/unix/pipes/), and Doug McIlroy's account of the pipe added by Ken Thompson in 1973 in [A Research Unix Reader](https://www.cs.dartmouth.edu/~doug/reader.pdf).
*   Peter H. Salus, _A Quarter Century of UNIX_, Addison-Wesley, 1994, pages 52 to 53.
*   Mike Gancarz, _The UNIX Philosophy_, 1994. Eric S. Raymond, _The Art of Unix Programming_, Addison-Wesley, 2003.
*   Microsoft, [CreateProcess function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa), on the parameters, and on the four readings of the command line.
*   Microsoft, [about_Pipelines](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pipelines), on objects in the pipeline, `Get-Member` and `Get-Help`.
*   Model Context Protocol, [Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools), specification of 2025-06-18, on `inputSchema` and `outputSchema`.
*   Donald D. Chamberlin and Raymond F. Boyce, [SEQUEL: A structured English query language](https://dl.acm.org/doi/10.1145/800296.811515), 1974.
*   OWASP, [SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html).
*   NVD, [CVE-2014-6271](https://nvd.nist.gov/vuln/detail/cve-2014-6271) (Shellshock).
*   OWASP, [Prompt Injection](https://community.owasp.org/attacks/PromptInjection) and [LLM01:2025 Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/).
*   Illustration: four photographs from Wikimedia Commons: a [mallard duck](https://commons.wikimedia.org/wiki/File:Male_mallard_duck;_2008.jpg) (CC0), a [house mouse](https://commons.wikimedia.org/wiki/File:House_mouse_%28Mus_musculus%29_2808.jpg) (CC0), an [African elephant bull](https://commons.wikimedia.org/wiki/File:African_elephant_bull_%286987533681%29.jpg) (public domain), and a [military dog barking](https://commons.wikimedia.org/wiki/File:Military_dog_barking_%28cropped%29.JPG) (public domain).
*   Photographs from Wikimedia Commons, cropped and resized: a [Teletype ASR-33](https://commons.wikimedia.org/wiki/File:TTY_%2829649845893%29.jpg) by Wolfgang Stief (CC0) and a [PDP-11/34](https://commons.wikimedia.org/wiki/File:PDP_11-34,_by_the_U.S._Army_Natick_Soldier_Systems_Center,_April_18,_1978,_from_the_Digital_Commonwealth_-_commonwealth_4f16d844r.jpg) by the U.S. Army Natick Soldier Systems Center (public domain).
