#!/usr/bin/python
# -*- coding: utf-8 -*-
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


import collections
import sys
import os
import re
import datetime
import textwrap

from HTMLParser import HTMLParser

import pytz
import click

from pypump import WebPump, Client, JSONStore
from pypump.models.note import Note

class Output(object):
    """ Handle output of for program to provide uniform messages. """

    def __init__(self):
        self.stdout = click.get_text_stream('stdout')
        self.stderr = click.get_text_stream('stderr')

    def fatal(self, message):
        """ Fatal message - will produce an error and exit with none 0 error code """
        self.error(message)
        sys.exit(1)

    def error(self, message):
        """ Produce an error message """
        error = "{0} {1}".format(click.style("[Error]", fg="red"), message)
        click.echo(error, file=self.stderr)

    def log(self, message, nl=True, **kwargs):
        """ Produce normal message """
        message = click.style(message, **kwargs)
        click.echo(message, file=self.stdout, nl=nl)

class P(object):
    """P - Pump.io command line utility.

    Commands:
        p authorize WEBFINGER
        p accounts
        p post note CONTENT
        p post image PATH
        p follow WEBFINGER
        p unfollow WEBFINGER
        p followers
        p following
        p friends
        p leaders
        p groupies
        p intersection WEBFINGER [WEBFINGER ...]
        p whoami
        p whois WEBFINGER
        p inbox
        p outbox [WEBFINGER]
        p list [NAME]
    """

    def __init__(self, settings, output):
        self.settings = settings
        self.output = output
        self.html_cleaner = re.compile(r'<[^>]+>')


        # If there is an account set - setup PyPump
        if settings["active"]:
            self._client = self.__get_client(settings["active"])
            # I know this isn't a website but the way WebPump works
            # is sligthly more what I want.
            self._pump = WebPump(
                client=self.client,
                verify_requests=self.settings["verify_ssl_certs"]
            )
        else:
            self._client = None
            self._pump = None

    @property
    def pump(self):
        """ Return PyPump instance """
        pump = getattr(self, "_pump")
        if pump is None:
            self.output.fatal("No active account. Use `p set active WEBFINGER` or `p authorize`")

        return pump

    @property
    def client(self):
        """ Returns PyPump client instance """
        client = getattr(self, "_client")
        if client is None:
            self.output.fatal("No active account. Use `p set active WEBFINGER` or `p authorize`")

        return client

    def __get_client(self, webfinger):
        """ Gets pump.io client instance for webfinger """
        return Client(
            webfinger=webfinger,
            name="p",
            type="native"
        )

    def __verification_callback(self, url):
        """ Ask user for verifier code for OOB authorization """
        self.output.log("To add an account you need to authorize p to use your")
        self.output.log("account and paste the verifier:")
        self.output.log(click.style(url, fg="blue"))
        verifier = click.prompt("Verifier Code", type=unicode).strip(" ")
        return verifier

    def __relative_date(self, d, now=None, reversed=False):
        """ Returns fuzzy timestamp for date relative to now """
        # This was taken from django 1.6 which is under the BSD licence
        # commit: b625e861e5d2709a16588ecb82f46e1fb86004c7
        # URL: https://github.com/django/django/

        # Subin ungettext_lazy until I can implement proper localisation
        def ungettext_lazy(singular, plural):
            return lambda x: singular % x if x == 1 else plural % x

        chunks = (
            (60 * 60 * 24 * 365, ungettext_lazy("%d year", "%d years")),
            (60 * 60 * 24 * 30, ungettext_lazy("%d month", "%d months")),
            (60 * 60 * 24 * 7, ungettext_lazy("%d week", "%d weeks")),
            (60 * 60 * 24, ungettext_lazy("%d day", "%d days")),
            (60 * 60, ungettext_lazy("%d hour", "%d hours")),
            (60, ungettext_lazy("%d minute", "%d minutes"))
        )

        # Convert datetime.date to datetime.datetime for comparison.
        if not isinstance(d, datetime.datetime):
            d = datetime.datetime(d.year, d.month, d.day)
        if now and not isinstance(now, datetime.datetime):
            now = datetime.datetime(now.year, now.month, now.day)

        if not now:
            now = datetime.datetime.now(pytz.UTC)

        delta = (d - now) if reversed else (now - d)
        # ignore microseconds
        since = delta.days * 24 * 60 * 60 + delta.seconds
        if since <= 0:
            # d is in the future compared to now, stop processing.
            return u"Just now"

        for i, (seconds, name) in enumerate(chunks):
            count = since // seconds
            if count != 0:
                break

        result = name(count)
        if i + 1 < len(chunks):
            # Now get the second item
            seconds2, name2 = chunks[i + 1]
            count2 = (since - (seconds * count)) // seconds2
            if count2 != 0:
                result += ", " + name2(count2)

        return u"{0} ago".format(result)

    def __display_object(self, obj, indent=0):
        """ Displays an object """
        content = obj.content
        if obj.content is None:
            return # this happens apparently?

        content = HTMLParser().unescape(content).strip()

        meta = u"{name} - {date}".format(
            name=click.style(obj.author.display_name, fg="yellow"),
            date=click.style(self.__relative_date(obj.published), fg="red")
        )

        self.output.log(" "*indent + meta)

        wrapper = textwrap.TextWrapper(
            initial_indent=" "*indent,
            break_on_hyphens=False,
        )

        content = self.html_cleaner.sub("", content)
        content = content.split("\n")

        while content:
            line = content.pop(0)
            fragments = wrapper.wrap(line)
            content = fragments[1:] + content

            if fragments:
                self.output.log(fragments[0])
            else:
                self.output.log("")

    def help(self, subcommand=None):
        if subcommand is None:
            # Display generic help
            return self.output.log(self.__doc__)

        method = getattr(self, subcommand)
        if method is None:
            self.output.fatal("Unknown command '{0}'.".format(subcommand))

        self.output.log(method.__name__ + ":" + method.__doc__)

    def activate(self, webfinger):
        """ Change account p uses """
        self.settings["active"] = webfinger

    def set(self, setting=None, value=None):
        """Set or retrive a setting.

        If no setting or value is given all settings and values
        will be listed. If just a setting is given just a value will
        be returned.

        Examples:
            $ p set
            active = someone@somewhere.com
            verify_ssl_cert = true

            $ p set active
            someone@somewhere.com

            $ p set active hai@bai.org
        """
        if setting is None and value is None:
            # List all settings
            for setting, value in self.settings.items():
                self.output.log("{0} = {1}".format(setting, value))
            return

        if setting is None and value is not None:
            # Just get value of specific setting
            if setting not in self.settings:
                self.output.log("Unknown setting {0!r}".format(setting))

            self.output.log(self.settings[setting])
            return

        # Set setting
        self.settings[setting] = value

    def accounts(self):
        """ List all accounts authorized """
        store_data = self.pump.store.export()
        accounts = set([key.split("-")[0] for key in store_data.keys()])
        max_length = max([len(a) for a in accounts]) + 1
        self.output.log(click.style("Authorized", underline=True), nl=False)
        self.output.log("    ", nl=False)
        self.output.log(click.style("Webfinger"), underline=True)
        for account in accounts:
            output = u""
            if "{0}-oauth-access-token".format(account) in store_data.keys():
                output = click.style("     ✓        ", fg="green")
            else:
                output = click.style("     ✗        ", fg="red")

            if account == self.settings["active"]:
                account = click.style(account + " (active)", bold=True)

            self.output.log(output + account.encode("utf-8"))

    def authorize(self, webfinger):
        """ Authorize a new account """
        if self._pump is None or self.pump.client.webfinger != webfinger:
            self._client = self.__get_client(webfinger)
            self._pump = WebPump(
                client=self.client,
                verify_requests=self.settings["verify_ssl_certs"]
            )

        if self.pump.logged_in:
            self.output.fatal("You have already authorized this account.")

        verifier = self.__verification_callback(self.pump.url)
        self.pump.verifier(verifier)

        # That should be everything
        if self.pump.logged_in:
            self.output.log("Success!")
        else:
            self.output.fatal("Something has gone wrong :(")

        if self.settings["active"] != self.pump.client.webfinger:
            if click.confirm("Make {0!r} the active account?".format(webfinger)):
                self.settings["active"] = self.pump.client.webfinger
            else:
                self.output.log("Okay, if you change your mind you can use the 'set' command.")

        self.output.log("All done.")

    def post(self, object_type, *message):
        """ Post item to pump.io feed

        This will post an object to your pump.io feed. If no
        data is given it will assume the data will come from
        stdio.

        Syntax:
            $ p post note [MESSAGE]
            $ p post image [PATH]

        TYPE: note image

        Examples:
            $ p post note "Hai I'm posting this from the command line ^_^"
            $ p post image /home/jessica/Pictures/awesome.png
            $ cat something.txt | p post note
        """
        if object_type not in ["image", "note"]:
            self.output.fatal("Unknown object type {0!r}.".format(object_type))

        if object_type == "image":
            if len(message) <= 0:
                self.output.fatal("Need to specify image path.")

            path = message[0]
            if not os.path.isfile(path):
                self.output.fatal("File at path cannot be found {0!r}.".format(path))

            image = self.pump.Image()
            image.from_file(path)
            return

        if object_type == "note":
            if message:
                # Message has been given as an argument
                message = " ".join(message)
            else:
                message = sys.stdin.read()

            if not message:
                self.output.fatal("No message provided.")

            note = self.pump.Note(message)
            note.send()

    def follow(self, *webfingers):
        """ Follow a user

        This will follow a user that you previously
        didn't follow.

        Syntax:
            $ p follow WEBFINGER

        Example:
            $ p follow Tsyesika@microca.st
        """
        if not webfingers:
            self.output.fatal("Need to specify webfinger(s).")

        for webfinger in webfingers:
            person = self.pump.Person(webfinger)
            person.follow()

    def unfollow(self, *webfingers):
        """ Unfollow a user

        This will stop following a user that you currently
        follow.

        Syntax:
            $ p unfollow WEBFINGER

        Example:
            $ p unfollow Tsyesika@microca.st
        """
        if not webfingers:
            self.output.fatal("Need to specify webfinger(s).")

        for webfinger in webfingers:
            person = self.pump.Person(webfinger)
            person.unfollow()

    def followers(self):
        """ Display all users following you """
        for person in self.pump.me.followers:
            self.output.log(person.webfinger)

    def following(self):
        """ Display all users you follow """
        for person in self.pump.me.following:
            self.output.log(person.webfinger)

    def groupies(self):
        """ Display all users who follow you that you don't follow back """
        following = [p.webfinger for p in self.pump.me.following]
        followers = [p.webfinger for p in self.pump.me.followers]

        # Find out who is in following that isn't in followers
        for person in followers:
            if person not in following:
                self.output.log(person)

    def friends(self):
        """ Display all users who follow you that you follow back """
        followers = [p.webfinger for p in self.pump.me.followers]
        following = [p.webfinger for p in self.pump.me.following]

        for person in followers:
            if person in following:
                self.output.log(person)

    def leaders(self):
        """ Display all the users you follow that don't follow you back """
        following = [p.webfinger for p in self.pump.me.following]
        followers = [p.webfinger for p in self.pump.me.followers]

        # Find out who is in followers that isn't in following
        for person in following:
            if person not in followers:
                self.output.log(person)

    def intersection(self, *users):
        """ Displays the intersection of users followed by the specified users

        If only one user is specified, intersection is found between the user
        and yourself. If two or more users are specified the intersection is
        found between all those people. If no mutual users are found will exit
        with a non-zero exit status.

        Syntax:
            $ p intersection WEBFINGER [WEBFINGER ...]

        Example:
            $ p intersection evan@e14n.com
            $ p intersection moggers87@microca.st cwebber@identi.ca
        """
        if len(users) <= 0:
            self.output.fatal("Must specify user(s) to find intersection with.")

        if len(users) == 1:
            users = [users[0], self.pump.me.webfinger]

        # Find all the followers of each user.
        following = []
        for user in users:
            user = self.pump.Person(user)
            following.append([person.webfinger for person in user.following])

        def in_lists(key, lists):
            """ Returns true if key in all lists """
            for l in lists:
                if key not in l:
                    return False

            return True

        for user in following[0]:
            if in_lists(user, following[1:]):
                self.output.log(user)

    def inbox(self):
        """ Lists latest 20 notes in inbox """
        limit = 20
        for activity in self.pump.me.inbox:
            if activity.verb != "post":
                continue # skip these too

            item = activity.obj
            if not isinstance(item, Note) or getattr(item, "deleted", True):
                continue

            # TODO: deal with nested comments
            self.__display_object(item)
            comments = list(item.comments)
            for comment in comments[::-1]:
                self.__display_object(comment, indent=4)

            self.output.log("")

            if limit <= 0:
                return

            limit -= 1

    def outbox(self, webfinger=None):
        """ Lists latest 20 notes in outbox

        If no webfinger is specified it will list the latest notes for the
        currently active account.
        If webfinger is specified it will list the latest public notes for
        that webfinger.

        Syntax:
            $ p outbox [WEBFINGER]

        Example:
            $ p outbox
            $ p outbox Tsyesika@microca.st
        """
        limit = 20

        if webfinger:
            user = self.pump.Person(webfinger)
        else:
            user = self.pump.me

        for activity in user.outbox:
            if activity.verb != "post":
                continue

            item = activity.obj
            if not isinstance(item, Note) or getattr(item, "deleted", True):
                continue

            self.__display_object(item)
            comments = list(item.comments)
            for comment in comments[::-1]:
                self.__display_object(comment, indent=4)

            self.output.log("")

            if limit <= 0:
                return

            limit -= 1
        

    def list(self, name=None):
        """ List lists or people in lists

        This will list everyone in a given list or if no list has been given
        it will list all the lists which exist.

        Syntax:
            $ p list [NAME]

        Example:
            $ p list
            $ p list Family
        """
        if name is None:
            for l in self.pump.me.lists:
                self.output.log(l.display_name)
            return

        l = [l for l in self.pump.me.lists if l.display_name.lower() == name.lower()]
        if not l:
            self.output.fatal("No list can be found with name {0!r}.".format(name))

        for person in l[0].members:
            self.output.log(person.webfinger)

    def whoami(self):
        """ Display information on active user """
        return self.whois(self.pump.client.webfinger)

    def whois(self, webfinger):
        """ Display information on user. """
        person = self.pump.Person(webfinger)
        information = collections.OrderedDict((
            ("Webfinger", person.webfinger),
            ("Username", person.username),
            ("Name", person.display_name),
            ("URL", person.url),
            ("location", person.location),
            ("Bio", person.summary),
            ("Followers", person.followers.total_items),
            ("Following", person.following.total_items),
        ))

        # Remove any information which doesn't actually have a value
        information = collections.OrderedDict(((key, value) for key, value in information.items() if value is not None))

        # We want to line up all the values so find the max length of the keys
        max_length = max(len(key) for key in information.keys())

        if "location" in information:
            if information["location"].name is not None:
                information["location"] = information["location"].name
            else:
                del information["location"]

        # Now display each value with the padding
        for name, value in information.items():
            padding = max_length - len(name) + 2
            item = name + (" "*padding) + str(value)
            self.output.log(item)

class Settings(JSONStore):

    @classmethod
    def get_filename(cls):
        XDG_CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME", "~/.config")
        XDG_CONFIG_HOME = os.path.expanduser(XDG_CONFIG_HOME)
        if not os.path.isdir(XDG_CONFIG_HOME):
            os.mkdir(XDG_CONFIG_HOME)

        path = os.path.join(os.path.expanduser(XDG_CONFIG_HOME), "p")
        if not os.path.isdir(path):
            os.mkdir(path)

        return os.path.join(path, "settings.json")

if __name__ == "__main__":
    settings = Settings.load(None, None)

    # Certain keys settings should have
    if "active" not in settings:
        settings["active"] = None

    if "verify_ssl_certs" not in settings:
        settings["verify_ssl_certs"] = True

    p = P(settings, Output())

    # Parse the command line arguments
    if len(sys.argv) <= 1:
        # display the help message
        p.help()
    else:
        command = getattr(p, sys.argv[1])
        if command is None:
            p.output.fatal("Unknown command '{0}'.".format(command))

        command(*sys.argv[2:])
