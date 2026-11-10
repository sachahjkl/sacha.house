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

## The universal interface is a loan

An interface is universal when it carries no meaning. The meaning does not disappear. It moves to the reader, and every reader pays for it, again and again.

You know the symptoms:

*   `ls | grep` breaks on a file name with a space. It breaks worse on a file name with a newline.
*   `ps aux | awk '{print $2}'` works until a column is empty or a command contains a space.
*   `find -print0 | xargs -0` exists because the dog could not bark a file name. We patched the dog with a null byte.
*   A program that prints a friendlier message breaks every script that read the old message. The output was never an API, but it became one.
*   Each tool brings its own half-parser for the text: `cut`, `awk`, `sed`, `tr`, and a regular expression that nobody wants to read again.

PowerShell made a different bet: pass objects, not text. You can dislike its syntax and still see the point. A file is a file object, with a size that is a number.

## The same dog, with a nicer coat

This week I did the same thing to my own projects, and I got to count the cost.

Each of my repositories had a `.project/project.yaml` file, with metadata for my website. It held five fields: `name`, `description`, `topics`, `homepage` and a nested `source` map with a provider, a namespace and a path. The site read two of them. The other three were never read by anything, and `source` only repeated the address of the repository.

Still, the site embedded a full YAML parser to read them. It decoded in strict mode, so that an unknown field was an error. Then it decoded a second time, to refuse a file with two documents. Only after that did it copy two strings. That code was mine, and it was all checks.

Then I decided to leave YAML. More than a hundred repositories on GitHub had to change, so I wrote a migration script. Here is what the "universal format" gave me:

*   **A dependency I did not have.** The Python on my machine has no YAML module. To read a "standard" file I had two choices: install a package, or write a partial parser. I wrote a few regular expressions for the two fields I needed.
*   **A value that looked right and was wrong.** The dry run printed the plan for every repository before changing anything. One of them, `backoffice-demo`, showed the description `>-`. That is not a description. It is the YAML marker for a folded block, and the real text was on the next lines. My regular expression read the marker as the value. Nothing had crashed. The file was valid YAML, and my second pass just did not know the block syntax.
*   **Hidden line endings.** Some descriptions held Windows line endings (`\r\n`), written as escape sequences inside quoted strings. They would have gone into the new files as they were. The script now turns them into plain newlines.

I fixed the script to handle block scalars, and to stop with an error on any value it does not understand. Then I ran it. Without the dry run, it would have written `>-` as the description of a project.

Then the site. I removed the YAML dependency. That one change altered the hash of the Go modules in the Nix build, so I had to recompute it and rebuild before the change could ship. A dependency is not only code. It is also a line in every lock file and every build.

The new file is `.project/info.txt`:

```
name=sacha.house
description=Personal website.
It can have several lines.
```

One rule: a line that starts with `key=` opens a key, and any other line continues the previous value. The parser has about twenty lines, and a shell script can read the file with `grep`.

It is not less structured than the YAML file. It is structured to fit what it carries. And it is not perfect: a description that has a line starting with `word=` would be cut at that line. I chose to live with this limit, because it fits in one sentence and I know exactly where it is. I cannot say the same about the limits of a YAML parser.

## Two passes where one would do

Look at what a program does with a generic format like YAML, JSON or XML. It reads the file twice.

1.  **The generic pass.** The parser checks that the text is valid YAML, or JSON, or XML, and builds a tree. It knows nothing about your problem.
2.  **The specific pass.** Your code walks the tree, looks for the keys it needs, checks that they have the right shape, and rejects the rest.

The second pass is the real work. It is the only one that knows what your file means. The first pass only proves that the dog barked correctly.

My old code shows it. It decoded the YAML with strict field names. It decoded a second time to refuse a file with two documents. Then it copied two fields. All the checks were mine, written on top of the parser. And in my migration script, the `>-` mistake came from the second pass, not from the first: the file was valid, and my code did not understand what it meant.

The usual answer is the tooling: syntax colors, validators, formatters, support in every editor. It is real. But look at what it costs. Each of those tools must implement the whole generic format, and a generic format is big. So there is a lot of code, in a lot of independent implementations, and every one of them has its own bugs.

The implementations do not agree with each other:

*   In YAML 1.1, the unquoted value `no` is a boolean. The country code of Norway becomes `false`. YAML 1.2 fixed it, and libraries still differ on which version they follow.
*   _Parsing JSON is a Minefield_ is an article with a test suite that compares JSON parsers on valid, invalid and ambiguous inputs. The parsers do not give the same answer.

A generic format promised that we would agree on one thing. We now have to agree on which parser, which version and which options. We did not remove the problem. We built a new one next to it, and it is bigger than the one we started with.

Now take the other road: a format that is yours.

You know its shape before you read the file. So you do not need a tree, and you do not need to check the format first and understand it second. You read the file once, and the data comes out in the form your program wants. The check and the extraction are the same loop. The parser for `info.txt` is that loop: it walks the lines, a `key=` line opens a key, any other line continues it, and what comes out is a flat map of strings, which is exactly what the program uses. There is no generic tree in between.

You also get something that no library can sell you: you are in charge of how the file is read.

*   You decide what an invalid file is, and what the error says.
*   You decide the limits, and you know where they are.
*   You do not wait for an upstream fix, you do not read a changelog, and you do not pin a version.
*   You carry no code that you do not use.

The generic format was supposed to save work. It gave you two passes, a dependency and a bug surface that other people own. The custom format gives you one pass and no one else to wait for.

## Do not be afraid of the custom thing

This is the real point. The Unix philosophy is right about small programs that do one thing. It is wrong about one shape for everything.

*   If the data is a list of records, give it a format and an API for records.
*   If the data is a number, return a number.
*   If the data is a post, a project or a process, let the format and the functions follow the data.

A custom format is worth it when its rule fits in one paragraph. If it needs a manual, you shaped it badly. The rule of `info.txt` fits in one sentence.

The duck can quack. The mouse can squeak. The program that reads them only has to know which one it is talking to.
