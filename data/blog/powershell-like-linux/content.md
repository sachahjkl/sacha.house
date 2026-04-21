A lot of us here _programmers_ reeeeaallllyy love the dev experience on **Linux**.

Unfortunately, our job at `$CURRENT_JOB` does not always allow us to use the tools that we would _like_ to use. (Am I right or am I right...)

More often than not, you'll have to use _Windows._

_**I know right ?**_

*   Forget about using the _oh so amazing_ [Fish shell](https://fishshell.com/ "https://fishshell.com/")...
    
*   Want to use the marvelous [starship.rs](https://starship.rs/ "https://starship.rs/") prompt for your favorite shell and take advantage of _automatic environnement shell adjustments_ ? Foggetaboutit.
    
*   You've grown the habit of using the ubiquitous pipes, GNU coreutils, and shell goodness you find on (mostly) POSIX-compatible OSes ?
    

All things good seem close on your _Enterprise-Ready, VPN-secured_ and _McAfee-protected_ computer. But somehow, they're always _unattainable._

> _You can thank your local_ [_GPO_](https://en.wikipedia.org/wiki/Group_Policy "https://en.wikipedia.org/wiki/Group_Policy") _and_ [_WAF_](https://en.wikipedia.org/wiki/Web_application_firewall "https://en.wikipedia.org/wiki/Web_application_firewall") _for that._

## The solution

Guess what ! I found **a solution.** And no, it's not [WSL2](https://learn.microsoft.com/fr-fr/windows/wsl/install "https://learn.microsoft.com/fr-fr/windows/wsl/install").

You know, that thing ? Yeah that one, **Powershell**.

> I know you don't want to use it, I know it feels foreign to the tools you're used to. But you don't really have a choice, do you ?

It's actually pretty nice once you get used to it (and tweak it a lot). It's not gonna give you that warm, fuzzy feeling that using FOSS (stands for Free and Open Source Software) gives you but it's will allow you to work without that little voice going in your head :

> You could be doing this a better way....wayy ...waaayyy....

That solution comes in multiple steps:

*   Update your **Powershell** command line so that it uses [**PSReadLine**](https://learn.microsoft.com/fr-fr/powershell/module/psreadline/about/about_psreadline?view=powershell-7.3 "https://learn.microsoft.com/fr-fr/powershell/module/psreadline/about/about_psreadline?view=powershell-7.3") (a _GNU readline-inspired_ command line)
    
*   Install [starship.rs](https://starship.rs/ "https://starship.rs/") and setup Powershell to use it (_yay it's actually cross-platform thanks to Rust !_)
    
*   Install a truckload of [Rust](https://www.rust-lang.org/ "https://www.rust-lang.org/") alternative to [GNU coreutils](https://www.gnu.org/software/coreutils/ "https://www.gnu.org/software/coreutils/")
    
*   Install a ;good; package manager : [scoop](https://scoop.sh/ "https://scoop.sh/")
    

## Installing scoop (this is the best and most useful part)

```
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser # Optional: Needed to run a remote script the first time
irm get.scoop.sh | iex
# you'll probably need to close and reopen your terminal here
scoop install git
scoop bucket add extras
```

## Installing PSReadline

As easy as _A-B-C :_

```
Install-Module -Name PSReadLine -AllowClobber -Force
```

That's it !

## Setting up Starship

This is all pretty simple :

```
scoop install starship
echo "Invoke-Expression (&starship init powershell)" >> $PROFILE
```

## Rusting it up

There isn't a specific recommended list of Rust CLI tools that you should install but I have my personal favorite :

**ripgrep :** [https://github.com/BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep "https://github.com/BurntSushi/ripgrep")

A modern alternative to grep. It's generally much faster and more intuitive to use.

**fd** : [https://github.com/sharkdp/fd](https://github.com/sharkdp/fd "https://github.com/sharkdp/fd")

As the description on their Github page says :

> A simple, fast and user-friendly alternative to 'find'

What else could **I** add ?

**fzf :** [https://github.com/junegunn/fzf](https://github.com/junegunn/fzf "https://github.com/junegunn/fzf") (this one is not Rust, it's Go)

> 🌸 A command-line fuzzy finder

Great way to find your file through heaps of directories _quickly._

> If you're interested in getting more _Rust-based_ coreutils alternatives, see [https://github.com/matu3ba/awesome-cli-rust](https://github.com/matu3ba/awesome-cli-rust "https://github.com/matu3ba/awesome-cli-rust")
