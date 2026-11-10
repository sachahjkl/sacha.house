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

I did the same thing to my own projects last week.

Each of my repositories had a `.project/project.yaml` file with the data of my site: a name, a description, and some fields that nothing read. YAML is the modern dog. It can bark anything: lists, maps, anchors, multiline blocks, and several ways to write a string.

My site needed two values. To read them, it embedded a full YAML parser. Every other tool that wanted to read the file had to embed one too. And "YAML" does not mean one thing: block scalars, quoting rules and `---` markers made my own migration script fail on the first run, on one repository.

So I replaced it. The new file is `.project/info.txt`:

```
name=sacha.house
description=Personal website.
It can have several lines.
```

One rule: a line that starts with `key=` opens a key, and any other line continues the previous value. The parser has about twenty lines. A shell script can read it with `grep`.

It is not less structured than the YAML file. It is structured to fit what it carries.

## Two passes, and only one of them is useful

Look at what a program does with a generic format like YAML, JSON or XML. It reads the file twice.

1.  **The generic pass.** The parser checks that the text is valid YAML, or JSON, or XML, and builds a tree. It knows nothing about your problem.
2.  **The specific pass.** Your code walks the tree, looks for the keys it needs, checks that they have the right shape, and rejects the rest.

The second pass is the real work. It is the only one that knows what your file means. The first pass only proves that the dog barked correctly.

My old code shows it. It decoded the YAML with strict field names. It decoded a second time to refuse a file with two documents. Then it copied two fields. All the checks were mine, written on top of the parser. The parser's own job added nothing to them.

To be fair, the generic pass is not worthless. You get editor support, validators, and the ability to read a file from an author you have never met. And a library hides the two passes behind one call. But the second pass is still yours, in every case. So when the first pass is not needed, ask what it is paying for.

## Do not be afraid of the custom thing

This is the real point. The Unix philosophy is right about small programs that do one thing. It is wrong about one shape for everything.

*   If the data is a list of records, give it a format and an API for records.
*   If the data is a number, return a number.
*   If the data is a post, a project or a process, let the format and the functions follow the data.

Custom has a price. You must document it, and you can no longer pipe everything into everything. So keep the rule small enough to explain in one paragraph. If it needs a manual, it is not custom, it is just another elephant.

The duck can quack. The mouse can squeak. The program that reads them only has to know which one it is talking to.
