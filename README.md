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
the dependencies installed on your system).


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

Files
-----
Configuration files are stored in `XDG_CONFIG_HOME/p` or `~/.config/p`

Usage
======

Type `p --help` to list the available commands. To get more information you can do:
```
$ p <subcommand> --help
```

Posting content
---------------

Post a note by using:
```
$ p post note "I'm posting a note via the command line ^_^"
```

Post an image:
```
$ p post image /home/jessica/Pictures/awesome.png
```

Titles of notes and images can be set with the option `--title <string>`.
```
$ p post image /path/to/my_cool_image.png --title "My cool image.."
```

Recipients can be set with the options `--to` and `--cc` and can be:
 * a webfinger (user@server.tld)
 * the name of a user created list (see `$ p lists`)
 * `followers` or `public`

(if no recipients are set cc=followers is used by default)
```
$ p post note "It's too early" --title "Yaawn" --to kabniel@microca.st --cc followers
```

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

Unfollow user
-------------

To unfollow a user
```
$ p unfollow <webfinger>
```

Read your inbox
---------------

You can see items in your inbox, this by default will show the last 20 items:
```
$ p inbox
```

Working with lists
------------------
Lists can be used as recipients when posting things.

Display your lists:
```
$ p lists
```

Create and delete a list:
```
$ p list create <list>
$ p list delete <list>
```

Display members of a list:
```
$ p list members <list>
```

Add and remove a list member:
```
$ p list add <list> <webfinger>
$ p list remove <list> <webfinger>
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
