Every few years, a good idea gets loose.

It is a real idea. It solved a real problem, for real people, in a real place. Then it grows. Within a couple of years it is no longer a tool, it is a worldview. It explains everything and it must be applied everywhere, and the developers who hold it start to build programs for the idea, not for the problem.

Fred Brooks saw it in 1986: "There is no single development, in either technology or management technique, which by itself promises even one order-of-magnitude improvement within a decade in productivity, in reliability, in simplicity."[^brooks] He wrote it as a warning. It is still the best summary of the cycle, and the cycle has not slowed down.

## The cycle

It goes in five steps. You have seen it, probably more than once.

1.  **A good idea.** Someone solves a hard problem in a hard place, and writes it down.
2.  **A principle.** The solution is turned into a rule. A rule is easier to carry than a context.
3.  **An identity.** You are no longer someone who uses the idea. You are one of the people who _do it right_.
4.  **A detachment.** The measures stop. A program is judged by how closely it follows the idea, not by what it costs or what it does. The vocabulary replaces the evidence.
5.  **A return of reality.** A bill arrives. Some people walk back. The idea survives as a word, usually with a meaning that its author would not recognize.

Look at four cases. Each one is an idea that was good.

## REST: the word outlived the idea

Roy Fielding described REST in his dissertation. In 2008, he wrote a blog post that starts with a complaint: "I am getting frustrated by the number of people calling any HTTP-based interface a REST API."[^rest1]

His rule is short. If the engine of application state is not driven by hypertext, then it is not a REST API. A client that has to know the URLs of an API in advance is not following the idea. In the comments under his post, a reader asked why so many people who think they do REST get it wrong. Fielding answered that he had left out detail on media types, and then he said what he thought the real reason was: "REST is software design on the scale of decades: every detail is intended to promote software longevity and independent evolution. Many of the constraints are directly opposed to short-term efficiency. Unfortunately, people are fairly good at short-term design, and usually awful at long-term design." He added: "lately there has been a lot of 'me too' activity around REST, as is the nature of any software buzzword."[^rest2]

The idea was about decades. The word was used for next week's JSON endpoint.

## Objects: the idea that left the building

Alan Kay made up the term "object-oriented". In 1997, at OOPSLA, he said what people had done with it: "I've been shown some very, very strange-looking pieces of code over the years by various people, including people in universities, that they have said is OOP code, and written in an OOP language—and actually, I made up the term object-oriented, and I can tell you I did not have C++ in mind." He also said he had apologized "profusely over the last twenty years" for the name, because he should have used "a much more process-oriented term for it."[^kay]

Then the measures. Casey Muratori took the first rule of "clean code", the one that says to prefer polymorphism to a `switch`, and timed it on a small example with shapes. Removing the polymorphism gave "an immediate 1.5x performance increase": from 35 cycles per shape to 24. A lookup table version was "nearly 15x faster".[^muratori] That is one microbenchmark. The point is not the 15x. The point is that the rule was taught for years as a law, and nobody had put it to the test.

## Microservices: the idea needs a bill

Microservices were the answer to teams stepping on each other in a big program. For a while they were the answer to everything.

In 2023 a team at Amazon Prime Video published a case study of a monitoring service that checks the quality of every stream. Their first design used distributed components and AWS Step Functions. It "quickly reached account limits", and it charged for every state transition. So they packed the components into one process. Their conclusion: "Moving our service to a monolith reduced our infrastructure cost by over 90%." They were careful. "Microservices and serverless components are tools that do work at high scale, but whether to use them over monolith has to be made on a case-by-case basis."[^prime]

David Heinemeier Hansson was less careful. He wrote that the case "really sums up so much of the microservices craze", and that "in practice, microservices pose perhaps the biggest siren song for needlessly complicating your system."[^dhh]

Note the difference. The team's sentence is about one service. The idea had been sold as a rule for all of them.

## Agile: the word was subverted

In 2014, Dave Thomas, one of the seventeen people who signed the Agile Manifesto, wrote an article with a title that says it: _Agile is Dead (Long Live Agility)_. "The word 'agile' has been subverted to the point where it is effectively meaningless, and what passes for an agile community seems to be largely an arena for consultants and vendors to hawk services and products."[^thomas]

When a word becomes an identity, it becomes a market.

## None of these ideas is wrong

Fielding's hypertext constraint is a serious answer to how an interface can last for decades. Objects are a useful way to hold some state. Splitting a system can fix a real coordination problem. A team that inspects its own work and adapts is better than one that does not.

The idea is not the problem. The capture is. A good idea has a home: the context it was made in. The cycle takes it out of its home and applies it to the street. The signs of it are always the same. People defend the idea instead of describing the program. The costs are named by the critics, not by the believers. And the idea comes with a vocabulary that makes the question "what does this cost here?" feel rude.

## The current one

The idea of the moment is AI, and it is the biggest one so far. It is also a real one. I use it every day.

It has already gone through the first four steps. There is a principle: the agent writes the code. There is an identity. And there are people for whom a program that an agent wrote is good because an agent wrote it, and who have stopped looking at what it does.

The numbers are not an argument against the idea. They are a description of what it does to what it meets. The DORA report of 2025 says that AI's primary role in software development "is that of an amplifier. It magnifies the strengths of high-performing organizations and the dysfunctions of struggling ones."[^dora] An amplifier does not choose. If the program was bad, it makes it bad faster. If the team measured nothing, it now measures nothing at ten times the volume.

That is the case for the constraints of [the last article](/blog/free-man-is-constrained). A big idea without a harness runs away with its believers.

## How to tell

There is one test that I use. I take the idea, and I ask someone who believes in it to name what it costs in this program. Not in general, in this program.

If the answer is a number, a time or a failure they have seen, the idea is a tool. If the answer is that it does not cost anything, or that the cost is not the point, the idea has a developer.

A cost is a fact that fits in a sentence. Keep the ideas that can name theirs, and use them where their home is.

Beware.

## Sources

[^brooks]: Frederick P. Brooks Jr., _No Silver Bullet: Essence and Accident in Software Engineering_, 1986. The sentence is quoted on [Embedded Artistry](https://embeddedartistry.com/fieldatlas/paper-no-silver-bullet/).
[^rest1]: Roy T. Fielding, [REST APIs must be hypertext-driven](https://roy.gbiv.com/untangled/2008/rest-apis-must-be-hypertext-driven), 2008.
[^rest2]: Roy T. Fielding, answer to a reader in the comments of the same post, 20 October 2008.
[^kay]: Alan Kay, _The Computer Revolution has not Happened Yet_, OOPSLA 1997, [transcript](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet).
[^muratori]: Casey Muratori, ["Clean" Code, Horrible Performance](https://www.computerenhance.com/p/clean-code-horrible-performance), 2023. The figures are 35 and 24 cycles per shape, and the lookup table at nearly 15x.
[^prime]: Marcin Kolny, [Scaling up the Prime Video audio/video monitoring service and reducing costs by 90%](https://www.primevideotech.com/video-streaming/scaling-up-the-prime-video-audio-video-monitoring-service-and-reducing-costs-by-90), Prime Video Tech, 2023, as quoted in the [report of DevClass](https://www.devclass.com/ci-cd/2023/05/05/reduce-costs-by-90-by-moving-from-microservices-to-monolith-amazon-internal-case-study-raises-eyebrows/1621790).
[^dhh]: David Heinemeier Hansson, [Even Amazon can't make sense of serverless or microservices](https://world.hey.com/dhh/even-amazon-can-t-make-sense-of-serverless-or-microservices-59625580), 2023, as quoted in the same DevClass report.
[^thomas]: Dave Thomas, [Agile is Dead (Long Live Agility)](https://pragdave.me/thoughts/active/2014-03-04-time-to-kill-agile.html), 2014.
[^dora]: DORA, [State of AI-assisted Software Development 2025](https://dora.dev/research/2025/dora-report/).
