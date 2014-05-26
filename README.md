p
=

This is a [pump.io](http://pump.io) version of the command line utility [t](https://github.com/sferik/t).

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
$ p set account <webfinger>
```

Removing account
----------------

To remove an account you can do:
```
$ p unauthorize <webfinger>
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

Licence
=======

p is under the GPLv3 (or at your option later).

