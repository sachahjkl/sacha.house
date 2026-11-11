In [the first post](/blog/unix-philosophy-bark-like-a-dog), I looked at where the Unix text stream comes from. In [the second](/blog/wrong-abstraction-fork-files-resources), I looked at the same shortcut in `fork`, in files and in the idea of a "resource". They all make a duck, a mouse and an elephant bark like a dog.

This post is about the same mistake in a modern coat. YAML, JSON and XML are generic formats: they bark every kind of data in one shape. We pay for it in code, in bugs, and in attack surface.

![Two small dogs wearing knitted sweaters, standing on grass](/media/blog/generic-formats-same-dog-nicer-coat/assets/dogs-in-sweaters.jpg)

*Still a dog.*[^photos]

## The same dog, with a nicer coat

This week I counted that cost in my own projects.

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

*   In YAML 1.1, the unquoted value `no` is a boolean. The country code of Norway becomes `false`.[^yaml11] YAML 1.2 fixed it, and libraries still differ on which version they follow.[^yaml12]
*   _Parsing JSON is a Minefield_ is an article with a test suite that compares JSON parsers on valid, invalid and ambiguous inputs. The parsers do not give the same answer.[^jsonmine]

A generic format promised that we would agree on one thing. We now have to agree on which parser, which version and which options. We did not remove the problem. We built a new one next to it, and it is bigger than the one we started with.

Now take the other road: a format that is yours.

You know its shape before you read the file. So you do not need a tree, and you do not need to check the format first and understand it second. You read the file once, and the data comes out in the form your program wants. The check and the extraction are the same loop. The parser for `info.txt` is that loop: it walks the lines, a `key=` line opens a key, any other line continues it, and what comes out is a flat map of strings, which is exactly what the program uses. There is no generic tree in between.

You also get something that no library can sell you: you are in charge of how the file is read.

*   You decide what an invalid file is, and what the error says.
*   You decide the limits, and you know where they are.
*   You do not wait for an upstream fix, you do not read a changelog, and you do not pin a version.
*   You carry no code that you do not use.

The generic format was supposed to save work. It gave you two passes, a dependency and a bug surface that other people own. The custom format gives you one pass and no one else to wait for.

## Less code, fewer bugs, a smaller target

There is one more reason, and it is not about convenience. It is about safety.

Code that does not exist has no bugs. A reader that needs twenty lines has fewer places to fail than a reader that needs a library. The library I removed from my site, `yaml.v3`, is about 11,000 lines of Go without its tests, and that includes a writer for YAML that I never used. The parser of `info.txt` is 23 lines, comments included. I can read all of it. I cannot say that of the 11,000.[^linecount]

![A large pile of books on the floor of a library](/media/blog/generic-formats-same-dog-nicer-coat/assets/stack-of-books.jpg)

*yaml.v3: about 11,000 lines of Go, without the tests.*

And every feature of a format is something an attacker can use, even a feature you never needed:

*   **YAML can build objects.** Before version 2.0, SnakeYAML, a widely used Java library, let a YAML document instantiate any class on the classpath. Whoever controlled the document could run code. It is CVE-2022-1471.[^cve1]
*   **A format inside a format.** In 2013, Ruby on Rails accepted XML parameters. An XML parameter could declare itself as YAML, and Rails decoded it as YAML. That could expose the application to remote code execution or SQL injection. It is CVE-2013-0156.[^cve2]
*   **XML can read files.** An XML document can declare an external entity. A parser that resolves it can be made to disclose local files, call internal servers, or hang. OWASP has a whole name for it, XXE, and a cheat sheet to disable the feature.[^xxe]

None of these is a story about a careless programmer. Each one is a feature of a generic format that the reader did not need and that someone else found a use for.

A `key=value` file has none of this. A line is text. A value is text. Nothing is built, resolved, included or executed, because the format has no word for it. You cannot add power to a format that has none.

This is also what makes the format cheap to share. Even when someone else has to read your file, a format that fits in twenty lines is the lightest thing you can ask of them: they write their reader in an afternoon, with no dependency and no attack surface that they did not choose.

A simple, custom format is not only more convenient. It makes the programs that read it smaller, easier to check, and harder to attack.

## Do not be afraid of the custom thing

This is the real point: stop shaping everything the same way.

*   If the data is a list of records, give it a format and an API for records.
*   If the data is a number, return a number.
*   If the data is a post, a project or a process, let the format and the functions follow the data.

A custom format is worth it when its rule fits in one paragraph. If it needs a manual, you shaped it badly. The rule of `info.txt` fits in one sentence.

## Who is the reader?

There is one question that decides everything: who reads this?

*   **If the reader is you**, your own programs reading your own data, shape the format to the data. Nobody else needs to agree with you, so you do not need a format that everybody agrees on.
*   **If the readers are strangers**, the convention wins. HTTP, SMTP, a JSON API that other teams call: these exist so that people who never met can talk. It is not for us to impose our own protocol on everyone.

And a protocol is not something you declare. A protocol is a protocol because it was built to be shared: it has a specification, several independent implementations, and people who agreed on it before the first byte was sent. A file does not become one because you gave it a format.

That is exactly where the generic format went wrong for me. `.project/project.yaml` was a private file. I invented the `.project` folder, and nobody else had ever been asked to read it. Yet I had dressed it as a protocol, with the parser, the schema and the dependency that go with it. The mistake was not YAML itself. It was paying the price of sharing for a file that was never shared.

The Unix text stream makes the same mistake at a bigger scale, as I wrote in the first post. It treats every conversation between two programs as if it were public, even when only two programs of mine are talking.

## Sources

[^photos]: Photographs from Wikimedia Commons, resized: [dog sweater](https://commons.wikimedia.org/wiki/File:Dog_sweater_1.jpg) by Sciencia58 (CC0), and [books in a stack](https://commons.wikimedia.org/wiki/File:Books_in_a_stack_%28a_stack_of_books%29_-_Flickr_-_austinevan.jpg) by Evan Bench ([CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)).
[^yaml11]: YAML 1.1, [Boolean Language-Independent Type](https://yaml.org/type/bool.html): the values `y`, `yes`, `n`, `no`, `on` and `off`, in three spellings each, are booleans.
[^yaml12]: YAML 1.2.2, [section 10.3.2, Core Schema, Tag Resolution](https://yaml.org/spec/1.2.2/): only `true` and `false`, in three spellings, resolve to booleans.
[^jsonmine]: Nicolas Seriot, _Parsing JSON is a Minefield_, and its test suite, [JSONTestSuite](https://github.com/nst/JSONTestSuite), which runs many parsers on files that must be accepted, rejected, or are left open by the standard.
[^linecount]: Measured by me: the non-test Go files of `gopkg.in/yaml.v3` v3.0.1 total 11,285 lines. The parser of `info.txt` in `internal/projects/projects.go`, from its regular expression to the end of `parseInfo`, is 23 lines.
[^cve1]: [CVE-2022-1471](https://nvd.nist.gov/vuln/detail/cve-2022-1471), SnakeYAML unsafe deserialization, with the [Veracode analysis](https://www.veracode.com/blog/resolving-cve-2022-1471-snakeyaml-20-release-0/).
[^cve2]: [CVE-2013-0156](https://nvd.nist.gov/vuln/detail/cve-2013-0156), Ruby on Rails, with the [Rapid7 explanation](https://www.rapid7.com/blog/post/2013/01/09/serialization-mischief-in-ruby-land-cve-2013-0156/).
[^xxe]: OWASP, [XML External Entity (XXE) Processing](https://community.owasp.org/vulnerabilities/XML_External_Entity_(XXE)_Processing) and the [XXE Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/XML_External_Entity_Prevention_Cheat_Sheet.html).
