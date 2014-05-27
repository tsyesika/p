p
=

This is a [pump.io](http://pump.io) version of the command line utility [t](https://github.com/sferik/t).

Troubleshooting
===============

This is still a very new program so there are probably many bugs however
if you get any of the following try the solutions first as they're known
about:

Modules missing
---------------
If you get something which looks like:
```
Traceback (most recent call last):
  File "./p", line 27, in <module>
    from pypump import WebPump, Client, JSONStore
ImportError: No module named pypump
```

That's because you don't have the modules you need to, please run:
```
$ virtualenv . && . bin/activate
$ pip install -r requirements.txt
```

(everytime you wish to use p you will have to do `. bin/activate` this is until you have
the dependecies installed on your system).

You will also *need* to use `python p <command>` until you install the dependences in your
real enviroment (not in a virtual one).


Configure
=========

Add new account
---------------

To add a new pump.io account to p you need to authorize it:
```
$ p authorize <webfinger>
```

List accounts
-------------

To list all the authorized accounts:
```
$ p accounts
```

Switching between accounts
--------------------------

To switch between multiple accounts you can use
```
$ p set active <webfinger>
```

Usage
======

Type `p help` to list the available commands. To get more information you can do:
```
$ p help <subcommand>
```

Post a new note
---------------

Post a note by using:
```
$ p post "I'm posting a note via the command line ^_^"
```

(For compatability with t `p update` is aliased to `p new`).

Lookup a user
-------------

To get detailed information about a user you can use:
```
$ p whois <webfinger>
```

If the user you want is on the same server you can just put their username.

Follow user
-----------

To follow a user
```
$ p follow <webfinger>
```

Unfollow
--------

To unfollow a user
```
$ p unfollow <webfinger>
```

Post an object
--------------

You can post notes and images via p, there are several ways this is how:
```
$ p post note "Hai this is a message from p ^_^."
$ p post image /home/jessica/Pictures/awesome.png
$ cat something.txt | p post note
```

Read your inbox
---------------

You can see items in your inbox by doing, this by default will show the last 20 items:
```
$ p inbox
```

Licence
=======

p is under the GPLv3 (or at your option later).

Screenshots
===========

Inbox
-----

![Inbox screenshot](https://theperplexingpariah.co.uk/media/p-inbox.png)

Whoami
-------

![Whoami screenshot](https://theperplexingpariah.co.uk/media/p-whoami.png)
