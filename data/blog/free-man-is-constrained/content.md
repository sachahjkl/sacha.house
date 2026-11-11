"Man is born free; and everywhere he is in chains."

Rousseau wrote it in 1762. It is the most quoted sentence of the _Social Contract_, and it hides the book. A few chapters later, Rousseau says what freedom is, and it is not the absence of chains:

> moral liberty, which alone makes him truly master of himself; for the mere impulse of appetite is slavery, while obedience to a law which we prescribe to ourselves is liberty.

The free man is constrained. By himself.

![Jean-Jacques Rousseau, painted by Maurice Quentin de La Tour, next to the Declaration of the Rights of Man and of the Citizen of 1789](/media/blog/free-man-is-constrained/assets/rousseau-declaration.jpg)

*Man is born free, and everywhere he is in chains. Article 4 sorts it out.*

## The man who rules himself

Over a century, writers who did not agree on much said the same thing in different words.

*   **Locke**, in 1689: "the end of law is not to abolish or restrain, but to preserve and enlarge freedom: for in all the states of created beings capable of laws, where there is no law, there is no freedom". Freedom, he adds, is not "a liberty for every man to do what he lists: (for who could be free, when every other man's humour might domineer over him?)".
*   **Montesquieu**, in 1748: "La liberté politique ne consiste point à faire ce que l'on veut." Political liberty does not consist in doing what one wants. And: "si un citoyen pouvoit faire ce qu'elles défendent, il n'auroit plus de liberté, parce que les autres auroient tout de même ce pouvoir." If a citizen could do what the laws forbid, he would no longer have liberty, because others would have the same power. (My translation.)
*   **Kant**, in 1784: "Enlightenment is man's release from his self-incurred tutelage." Its motto is "Sapere aude! Have courage to use your own reason!"
*   **The French Declaration of 1789**, article 4: liberty consists in being able to do anything that does not harm others, so "the exercise of each man's natural rights has no limits other than those that ensure other members of society the enjoyment of the same rights. These limits can only be determined by law." (My translation.)

Look at what these texts do. They do not give freedom first and add limits later. The limit is in the definition.

## Where this man comes from

I think of the free man as a person who holds his own impulses. No lord holds them for him, and no crowd, and no fear of what the neighbors will say.

Norbert Elias followed this slowly in _The Civilizing Process_ (1939). Over centuries, in the courts of Western Europe, the way people behaved around violence, the body and speech changed. Thresholds of shame and repugnance rose, until the constraint that others imposed became a constraint that each person imposed on himself.

The Church had been working on the same thing since 1215. Canon 21 of the Fourth Lateran Council says that "all the faithful of both sexes shall after they have reached the age of discretion faithfully confess all their sins at least once a year to their own (parish) priest", on pain of excommunication. Every adult Christian was to examine his own conscience, every year.

Anthropologists have a vocabulary for this. Ruth Benedict made popular the distinction between a "shame culture", where behavior is held by the eyes of others, and a "guilt culture", where it is held by an inner voice. I do not claim that the free man feels no shame: the inner constraint that Elias describes is made of it. I claim that the constraint moved inside.

Then there is the place. Quentin Skinner showed how the Italian city republics worked out a theory of liberty as living under no one's arbitrary will, and how it reached seventeenth-century England. England gave Locke. France gave Montesquieu and Rousseau. And in 1776 and 1789, two texts built a political order on the man who rules himself. The American Declaration says that all men "are endowed by their Creator with certain unalienable Rights, that among these are Life, Liberty and the pursuit of Happiness", and that "to secure these rights, Governments are instituted among Men". The French one is article 4, above.

Both rest on a bet: that a man who is given his rights will keep himself inside their limits. My thesis is that this man, as the foundation of the law, could only have appeared in one corner of Europe, made of England, France and northern Italy. Self-mastery as an ideal is much older, and it is not only Western: the Stoics have it, and so does Confucian self-cultivation. What was specific is making it the base of a political order.

## Absolute freedom is not freedom

Absolute freedom is the freedom to do what you want. That includes the freedom to destroy the society you live in, and the freedom to destroy yourself. It is not productive. Nobody builds anything on it, because nobody can count on anything: not on the others, and not on himself tomorrow.

Locke's question is the one to remember: who could be free, when every other man's humour might domineer over him?

Constraints are not the price of freedom. They are the soil. A plant is not less free on a trellis. It is the trellis that lets it grow that high.

![A wisteria growing on a long trellis above a road](/media/blog/free-man-is-constrained/assets/wisteria-trellis.jpg)

*A wisteria, free to grow because it has a trellis.*

## The same thing in software

Programs, processes and languages have the same story.

**Processes.** The 1974 paper on Unix says that its second version "ran on the unprotected PDP-11/20 computer". The system it describes is multi-user. It has user identifiers, protection bits and a super-user, so that a program "may keep an accounting file which should neither be read nor changed except by the program itself". Many people could share one machine because each of them was limited.

**Memory.** C gives the programmer a total freedom over memory. Microsoft reports that "approximately 70% of security vulnerabilities that Microsoft fixes and assigns a CVE" are memory safety issues, "despite mitigations including intense code review, training, static analysis, and more". The freedom was absolute, and it destroyed at scale. Rust answers with a constraint: "incorrect code will refuse to compile and present an error explaining the problem". Its authors nicknamed the result "fearless concurrency". The constraint is why you can stop being afraid.

**Style.** The Go proverbs say: "Gofmt's style is no one's favorite, yet gofmt is everyone's favorite." Nobody chose that style, and everyone uses it. It ends an argument, so you can spend the time elsewhere.

**Interfaces.** The first article of this series was about a constraint that was too weak: a text stream, with no shape. A tool that declares its parameters with a schema is a constraint that frees, because nobody has to guess. And `info.txt` is the smallest constraint I could write: a line that starts with `key=` opens a key.

## The price of constraints

Everyone agreed that these constraints were good. For a long time, many teams still did without them, and ignorance was not the reason. The price was.

When code was written by hand, a constraint had a cost on three sides.

*   **Time.** A test suite, a build that checks types, a pipeline that validates every change: each one is work to set up before it protects anything.
*   **Skills.** The machinery became a craft of its own. The first DevOpsDays conference was held in Ghent in 2009. In my experience, the word named a real job: somebody had to know how the pipeline worked. Jenkins appeared in 2011, Travis CI was founded the same year, and GitHub Actions launched in November 2019. Each step made it cheaper. None made it free.
*   **Friction.** All that machinery has to run, and it has to be maintained. A slow or broken pipeline slows every change. When a deadline came, the pipeline was what had to be justified, and it often lost: skip the tests, merge anyway, add it later.

So constraints were won one at a time, and often given up.

AI changed both sides of the balance.

On the need side: when an agent writes code faster than a person can read it, the check cannot be a person reading. The 2024 DORA report estimated that each 25% increase in AI adoption went with a 1.5% decrease in delivery throughput and a 7.2% reduction in delivery stability. In 2025, the same researchers wrote that "AI's primary role in software development is that of an amplifier. It magnifies the strengths of high-performing organizations and the dysfunctions of struggling ones." An amplifier with no harness amplifies the instability too.

On the cost side: the same agent that writes the code can write the tests and the pipeline around it. What used to need a specialist is now a request.

So the argument turns upside down. Constraints used to be a tax on development, and they had to be justified. Now they are what lets you accept code that nobody wrote line by line. They have become central, and almost impossible to refuse: they are the safety harness of the whole circuit.

I can see it on this very site. Every push runs `nix flake check`, which builds the project and runs its Go tests. A merge to `master` publishes the build and deploys it to staging. Production waits for an approval. When I removed the YAML dependency, the build refused to go on until the hash of the Go modules was updated. And one flaky test failed the pipeline for a post that touched no Go code, so I ran it again. The price is still real. But it is small now: the agent read the log, found the test and told me that it was unrelated.

## The era of AI

This is the strongest case, because an agent is a free man without a childhood. It reads, writes, deletes, pushes and deploys faster than you can look. Its freedom, left absolute, is the freedom to destroy.

Every tool has a switch to turn the questions off. In Claude Code, it is named `--dangerously-skip-permissions`. The name is the argument. The Model Context Protocol says it plainly: "there SHOULD always be a human in the loop with the ability to deny tool invocations".

Here is what happened this week. I asked an AI coding agent to migrate the metadata files of 112 GitHub repositories. Twelve of them refused the push: "Changes must be made through a pull request. Required status check "platform / check" is expected." That rule was mine, set on those repositories, and it stopped my own agent. The agent did not go around it. It asked me. I said yes, for those twelve. It switched one protection off for each repository, pushed, and switched it back on, and I could check afterwards that all of them were in place. The production deploy waits for an approval before it starts. It takes a backup of the data first. And before it changed any repository, the script printed a plan. One description in that plan read `>-`, which is not text but a YAML marker. Without the plan, it would have been written into a repository.

I could hand a hundred repositories to an agent because of that harness. It limited what the agent could break: protected branches, a plan before the action, an approval gate, a backup. The more constraints I have, the more I can delegate. The freedom I give grows with the constraints I keep.

![A single-line kite flying in a blue sky](/media/blog/free-man-is-constrained/assets/kite-on-a-line.jpg)

*No string, no flight.*

## The soil

A man without law is not free. He is exposed. A program without a process boundary or a type system is not free. It is fragile. An agent without a guardrail is not autonomous. It is dangerous.

The free man, the free program and the free agent have the same condition: a frame that they respect, and that they hold first of all themselves. The tradition that built the free man bet that he could do it. I think the bet was right, and that we make the same bet each time we give a program, or a model, the power to act.

The free man is constrained. That is not a bug. It is the specification.

## Sources

*   Jean-Jacques Rousseau, _The Social Contract_, book I, chapters I and VIII, in the [translation by G. D. H. Cole](https://www.gutenberg.org/cache/epub/46333/pg46333.txt).
*   John Locke, _Second Treatise of Government_, [section 57](https://www.gutenberg.org/cache/epub/7370/pg7370.txt), 1689.
*   Montesquieu, _De l'esprit des lois_, book XI, chapter III, 1748, quoted on [Wikiquote](https://fr.wikiquote.org/wiki/Montesquieu).
*   Immanuel Kant, [What is Enlightenment?](https://en.wikisource.org/wiki/What_is_Enlightenment%3F), 1784, translation by Lewis White Beck.
*   [Déclaration des droits de l'homme et du citoyen de 1789](https://www.conseil-constitutionnel.fr/le-bloc-de-constitutionnalite/declaration-des-droits-de-l-homme-et-du-citoyen-de-1789), article 4. The [Declaration of Independence](https://www.archives.gov/founding-docs/declaration-transcript), 1776.
*   Norbert Elias, _The Civilizing Process_, 1939, [summary](https://en.wikipedia.org/wiki/The_Civilizing_Process). Ruth Benedict, _The Chrysanthemum and the Sword_, 1946, on [shame and guilt societies](https://en.wikipedia.org/wiki/Shame_society).
*   [Canons of the Fourth Lateran Council, 1215](https://sourcebooks.fordham.edu/basis/lateran4.asp), canon 21.
*   Quentin Skinner, _Liberty before Liberalism_, Cambridge University Press, 1998.
*   Dennis M. Ritchie and Ken Thompson, [The UNIX Time-Sharing System](https://people.eecs.berkeley.edu/~brewer/cs262/unix.pdf), 1974.
*   Microsoft Security Response Center, [We need a safer systems programming language](https://www.microsoft.com/en-us/msrc/blog/2019/07/we-need-a-safer-systems-programming-language), 2019. The Rust Book, [Fearless Concurrency](https://doc.rust-lang.org/book/ch16-00-concurrency.html). [Go Proverbs](https://go-proverbs.github.io/).
*   Model Context Protocol, [Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools). Claude Code, [CLI reference](https://docs.claude.com/en/docs/claude-code/cli-reference).
*   Photographs and paintings from Wikimedia Commons, cropped and resized, all in the public domain or under CC0: [Rousseau](https://commons.wikimedia.org/wiki/File:Jean-Jacques_Rousseau_%28painted_portrait%29.jpg) by Maurice Quentin de La Tour, the [Declaration of the Rights of Man and of the Citizen](https://commons.wikimedia.org/wiki/File:Declaration_of_the_Rights_of_Man_and_of_the_Citizen_in_1789.jpg), a [single-line kite](https://commons.wikimedia.org/wiki/File:Single_Line_Kite_in_Sky_-_DPLA_-_7a29acc44821c56b3a12cf7b43acc2cd.jpg) (1983), and a [wisteria trellis](https://commons.wikimedia.org/wiki/File:Kurogi%27s_Great_Wisteria_-_A_wisteria_trellis_built_above_National_Route_442.jpg) by 水だらけのプール (CC0).
*   [DevOps](https://en.wikipedia.org/wiki/DevOps), [Jenkins](https://en.wikipedia.org/wiki/Jenkins_%28software%29), [Travis CI](https://en.wikipedia.org/wiki/Travis_CI) and [GitHub](https://en.wikipedia.org/wiki/GitHub) on Wikipedia, for the dates of DevOpsDays (2009), Jenkins (2011), Travis CI (2011) and GitHub Actions (2019).
*   DORA, [Accelerate State of DevOps Report 2024](https://dora.dev/research/2024/dora-report/) and its [announcement](https://cloud.google.com/blog/products/devops-sre/announcing-the-2024-dora-report), and the [2025 State of AI-assisted Software Development](https://dora.dev/research/2025/dora-report/).
