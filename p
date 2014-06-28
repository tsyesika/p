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

from six.moves.html_parser import HTMLParser

import pytz
import click
import html2text

from pypump import WebPump, Client, JSONStore
from pypump.models.note import Note
from pypump.models.image import Image

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
    """P - Pump.io command line utility. """

    def __init__(self, settings, output):
        self.settings = settings
        self.output = output
        self.html_cleaner = re.compile(r'<[^>]+>')


        # If there is an account set - setup PyPump
        if settings["active"]:
            self._client = self._get_client(settings["active"])
            # I know this isn't a website but the way WebPump works
            # is sligthly more what I want.
            try:
                self._pump = WebPump(
                    client=self.client,
                    verify_requests=self.settings["verify_ssl_certs"]
                )
            except:
                self.output.error("Could not load account: {0}".format(settings["active"]))

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

    def _get_client(self, webfinger):
        """ Gets pump.io client instance for webfinger """
        return Client(
            webfinger=webfinger,
            name="p",
            type="native"
        )

    def _verification_callback(self, url):
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

    def _display_object(self, obj, indent=0):

        def indenter(msg, cnt=4):
            msg = msg.split("\n")
            newmsg = [u"{0}{1}".format(" "*cnt, i) for i in msg]
            return "\n".join(newmsg)

        html2text.INLINE_LINKS = False
        md = html2text.html2text
        body_width = click.get_terminal_size()[0] - (indent*2)

        meta = u"{name} - {date}".format(
            name=click.style(u"{0}".format(obj.author), fg="yellow"),
            date=click.style(self.__relative_date(obj.published), fg="red")
        )
        self.output.log(indenter(meta, indent))

        if obj.display_name:
            title = click.style(u"{0}\n".format(obj.display_name), fg="blue")
            self.output.log(indenter(title, indent))

        content = u""
        # add image to top of content if image object
        if isinstance(obj, Image):
            content = u"<p><img src='{0}' alt='Image {1}x{2}'/></p>".format(
                obj.original.url,
                obj.original.width,
                obj.original.height
            )
        if obj.content:
            content = content + obj.content
        #convert to markdown
        content = md(content, bodywidth=body_width).rstrip()
        self.output.log(indenter(content, indent))

    def prepare_recipients(self, data):
        """ Prepare recipients.

        Prepare a list of webfingers and collection names
        before being used as recipients.
        """
        prepped = []
        for item in data:
            if "@" in item:
                prepped.append(self.pump.Person(item))
            elif item.lower() == "followers":
                prepped.append(self.pump.me.followers)
            elif item.lower() == "public":
                prepped.append(self.pump.Public)
            else:
                #try to find a user list
                for i in self.pump.me.lists:
                    if i.display_name == item:
                        prepped.append(i)

        return prepped


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


pass_p = click.make_pass_decorator(P)

@click.group()
@click.pass_context
def cli(ctx):
    """P - Pump.io command line utility. """
    ctx.obj = P(settings, Output())

@cli.command('activate')
@pass_p
@click.argument('webfinger', required=True)
def p_activate(p, webfinger):
    """ Change account p uses. """
    p.settings["active"] = webfinger

@cli.command('set')
@pass_p
@click.argument('setting', required=False)
@click.argument('value', required=False)
def p_set(p, setting=None, value=None):
    """Set or retrive a setting.

    If no setting or value is given all settings and values
    will be listed. If just a setting is given just a value will
    be returned.
    
    \b
    Examples:
        $ p set
        active = someone@somewhere.com
        verify_ssl_cert = true
        \b
        $ p set active
        someone@somewhere.com

        $ p set active hai@bai.org
    """
    if setting is None and value is None:
        # List all settings
        for setting, value in p.settings.items():
            p.output.log("{0} = {1}".format(setting, value))
        return

    if setting is not None and value is None:
        # Just get value of specific setting
        if setting not in p.settings.keys():
            p.output.log("Unknown setting {0!r}".format(setting))
            return

        p.output.log(p.settings[setting])
        return

    # Set setting
    p.settings[setting] = value

@cli.command('accounts')
@pass_p
def p_accounts(p):
    """ List all accounts authorized. """
    store_data = p.pump.store.export()
    accounts = set([key.split("-")[0] for key in store_data.keys()])
    max_length = max([len(a) for a in accounts]) + 1
    p.output.log(click.style("Authorized", underline=True), nl=False)
    p.output.log("    ", nl=False)
    p.output.log(click.style("Webfinger"), underline=True)
    for account in accounts:
        output = u""
        if "{0}-oauth-access-token".format(account) in store_data.keys():
            output = click.style("     ✓        ", fg="green")
        else:
            output = click.style("     ✗        ", fg="red")

        if account == p.settings["active"]:
            account = click.style(account + " (active)", bold=True)

        p.output.log(output + account.encode("utf-8"))

@cli.command('authorize')
@pass_p
@click.argument('webfinger', required=True)
def p_authorize(p, webfinger):
    """ Authorize a new account.

    \b
    Example:
        p authorize username@microca.st
    """
    if p._pump is None or p.pump.client.webfinger != webfinger:
        p._client = p._get_client(webfinger)
        p._pump = WebPump(
            client=p.client,
            verify_requests=p.settings["verify_ssl_certs"]
        )

    if p.pump.logged_in:
        p.output.fatal("You have already authorized this account.")

    verifier = p._verification_callback(p.pump.url)
    p.pump.verifier(verifier)

    # That should be everything
    if p.pump.logged_in:
        p.output.log("Success!")
    else:
        p.output.fatal("Something has gone wrong :(")

    if p.settings["active"] != p.pump.client.webfinger:
        if click.confirm("Make {0!r} the active account?".format(webfinger)):
            p.settings["active"] = p.pump.client.webfinger
        else:
            p.output.log("Okay, if you change your mind you can use the 'set' command.")

    p.output.log("All done.")

@cli.group('post', short_help='Post item to pump.io feed')
def p_post():
    """ Post item to pump.io feed. """
    pass

@p_post.command('image', short_help='Post image to pump.io feed.')
@pass_p
@click.argument('path', required=True)
@click.option('--title', help="Image title.")
@click.option('--to', multiple=True, help="Image to.")
@click.option('--cc', multiple=True, help="Image cc.")
def p_post_image(p, path, title, to, cc):
    """ Post image to pump.io feed.

    This will post an image to your pump.io feed.

    \b
    Syntax:
        $ p post image PATH

    \b
    Examples:
        $ p post image /home/jessica/Pictures/awesome.png
        $ p post image --title "My kitteh" --to followers ~/kitteh9001.png
    """

    if len(path) <= 0:
        p.output.fatal("Need to specify image path.")

    if not os.path.isfile(path):
        p.output.fatal("File at path cannot be found {0!r}.".format(path))

    image = p.pump.Image(display_name=title)
    image.to = p.prepare_recipients(to)
    image.cc = p.prepare_recipients(cc)
    image.from_file(path)
    return

@p_post.command('note', short_help='Post note to pump.io feed.')
@pass_p
@click.argument('message', required=False)
@click.option('--editor', '-e', is_flag=True, help='Open message in external editor.')
@click.option('--title', help="Note title.")
@click.option('--to', multiple=True, help="Note to.")
@click.option('--cc', multiple=True, help="Note cc.")
def p_post_note(p, message, editor, title, to, cc):
    """ Post note to pump.io feed.

    This will post a note to your pump.io feed. If no
    data is given it will assume the data will come from
    stdio.

    --to, --cc takes one argument but can be used multiple times. Accepts a webfinger,
    a list (p lists) or the special values "followers" and "public".

    \b
    Syntax:
        $ p post note [MESSAGE]

    \b
    Examples:
        $ p post note "Hai I'm posting this from the command line ^_^"
        $ cat something.txt | p post note
        $ p post note --title "Notes beginning.." "..in titles are annoying"
        $ p post note --to Tsyesika@microca.st --cc "followers" "Hey there"
    """
    if editor:
        message = click.edit(message)
    else:
        if message:
            pass
        else:
            message = sys.stdin.read()

    if not message:
        p.output.fatal("No message provided.")

    note = p.pump.Note(message, display_name=title)

    note.to = p.prepare_recipients(to)
    note.cc = p.prepare_recipients(cc)

    note.send()

@cli.command('follow')
@pass_p
@click.argument('webfingers', nargs=-1)
def p_follow(p, webfingers):
    """ Follow a user.

    This will follow a user that you previously
    didn't follow.

    \b
    Syntax:
        $ p follow WEBFINGER [WEBFINGER] ...

    \b
    Example:
        $ p follow Tsyesika@microca.st
    """
    if not webfingers:
        p.output.fatal("Need to specify webfinger(s).")

    for webfinger in webfingers:
        person = p.pump.Person(webfinger)
        person.follow()

@cli.command('unfollow')
@pass_p
@click.argument('webfingers', nargs=-1)
def p_unfollow(p, webfingers):
    """ Unfollow a user.

    This will stop following a user that you currently
    follow.

    \b
    Syntax:
        $ p unfollow WEBFINGER [WEBFINGER] ...

    \b
    Example:
        $ p unfollow Tsyesika@microca.st
    """
    if not webfingers:
        p.output.fatal("Need to specify webfinger(s).")

    for webfinger in webfingers:
        person = p.pump.Person(webfinger)
        person.unfollow()

@cli.command('followers')
@pass_p
@click.argument('webfinger', required=False)
def p_followers(p, webfinger):
    """ Display all users following you.
    If webfinger is given it will display users following that user.
    """
    if webfinger:
        user = p.pump.Person(webfinger)
    else:
        user = p.pump.me

    for person in user.followers:
        p.output.log(person.webfinger)

@cli.command('following')
@pass_p
@click.argument('webfinger', required=False)
def p_following(p, webfinger):
    """ Display all users you follow.
    If webfinger is given it will display users followed by that user.
    """
    if webfinger:
        user = p.pump.Person(webfinger)
    else:
        user = p.pump.me

    for person in user.following:
        p.output.log(person.webfinger)

@cli.command('groupies')
@pass_p
def p_groupies(p):
    """ Display all users who follow you that you don't follow back. """
    following = [u.webfinger for u in p.pump.me.following]
    followers = [u.webfinger for u in p.pump.me.followers]

    # Find out who is in following that isn't in followers
    for person in followers:
        if person not in following:
            p.output.log(person)

@cli.command('friends')
@pass_p
def p_friends(p):
    """ Display all users who follow you that you follow back. """
    followers = [u.webfinger for u in p.pump.me.followers]
    following = [u.webfinger for u in p.pump.me.following]

    for person in followers:
        if person in following:
            p.output.log(person)

@cli.command('leaders')
@pass_p
def p_leaders(p):
    """ Display all the users you follow that don't follow you back. """
    following = [u.webfinger for u in p.pump.me.following]
    followers = [u.webfinger for u in p.pump.me.followers]

    # Find out who is in followers that isn't in following
    for person in following:
        if person not in followers:
            p.output.log(person)

@cli.command('intersection')
@pass_p
@click.argument('users', nargs=-1)
def p_intersection(p, users):
    """ Displays the intersection of users followed by the specified users.

    If only one user is specified, intersection is found between the user
    and yourself. If two or more users are specified the intersection is
    found between all those people. If no mutual users are found will exit
    with a non-zero exit status.

    \b
    Syntax:
        $ p intersection WEBFINGER [WEBFINGER ...]

    \b
    Example:
        $ p intersection evan@e14n.com
        $ p intersection moggers87@microca.st cwebber@identi.ca
    """
    if len(users) <= 0:
        p.output.fatal("Must specify user(s) to find intersection with.")

    if len(users) == 1:
        users = [users[0], p.pump.me.webfinger]

    # Find all the followers of each user.
    following = []
    for user in users:
        user = p.pump.Person(user)
        following.append([person.webfinger for person in user.following])

    def in_lists(key, lists):
        """ Returns true if key in all lists """
        for l in lists:
            if key not in l:
                return False

        return True

    for user in following[0]:
        if in_lists(user, following[1:]):
            p.output.log(user)

@cli.command('inbox')
@pass_p
@click.option('--number', '-n', default=20, help='Number of items to show.')
@click.option('--unread', is_flag=True, help='Only show unread items.')
def p_inbox(p, number, unread):
    """ Lists latest 20 notes in inbox. """
    limit = number
    last_read = None
    if unread:
        last_setting = "{wf}-inbox-lastread".format(wf=p.pump.me.webfinger)
        #get last read from settings or inbox[number]
        last_read = p.settings.get(last_setting) or p.pump.me.inbox.major[number].id
    for activity in p.pump.me.inbox.major.items(limit=None, since=last_read):
        if activity.obj.deleted:
            #skip deleted objects
            continue

        p.output.log(click.style(u"{0}".format(activity), fg="green"))

        item = activity.obj
        p._display_object(item, indent=2)

        # TODO: deal with nested comments
        if hasattr(item, 'comments'):
            comments = list(item.comments)
            for comment in comments[::-1]:
                p._display_object(comment, indent=4)

        p.output.log("")
        if unread:
            p.settings[last_setting] = activity.id

        limit -= 1

        if number > 0 and limit <= 0:
            return

@cli.command('outbox')
@pass_p
@click.argument('webfinger', required=False)
@click.option('--number', '-n', default=20, help='Number of items to show.')
def p_outbox(p, webfinger, number):
    """ Lists latest 20 notes in outbox.

    If no webfinger is specified it will list the latest notes for the
    currently active account.
    If webfinger is specified it will list the latest public notes for
    that webfinger.

    \b
    Syntax:
        $ p outbox [WEBFINGER]

    \b
    Example:
        $ p outbox
        $ p outbox Tsyesika@microca.st
    """
    limit = number

    if webfinger:
        user = p.pump.Person(webfinger)
    else:
        user = p.pump.me

    for activity in user.outbox:
        if activity.verb != "post":
            continue

        item = activity.obj
        if not isinstance(item, Note) or getattr(item, "deleted", True):
            continue

        p._display_object(item)
        comments = list(item.comments)
        for comment in comments[::-1]:
            p._display_object(comment, indent=4)

        p.output.log("")

        limit -= 1

        if limit <= 0:
            return

@cli.command('favorites')
@pass_p
@click.argument('webfinger', required=False)
@click.option('--number', '-n', default=20, help='Number of items to show.')
def p_favorites(p, webfinger, number):
    """ Display items favorited by you.
    If webfinger is given, display items favorited by user.
    """
    limit = number

    if webfinger:
        user = p.pump.Person(webfinger)
    else:
        user = p.pump.me

    for item in user.favorites:

        p._display_object(item)

        p.output.log("")

        limit -= 1

        if limit <= 0:
            return

    
@cli.command('lists')
@pass_p
def p_lists(p):
    """ List all lists for the active user. """
    for l in p.pump.me.lists:
        p.output.log(l.display_name)
    return

@cli.group('list')
def p_list():
    """ Manage a list. """
    pass

@p_list.command('create')
@pass_p
@click.argument('name')
def p_list_create(p, name):
    """ Create a list.

    \b
    Syntax:
        p list create NAME

    \b
    Example:
        p list create pypumpers
    """
    l = [l for l in p.pump.me.lists if l.display_name.lower() == name.lower()]
    if l:
        p.output.fatal("List with name {0!r} already exists.".format(name))

    p.pump.me.lists.create(name)

@p_list.command('delete')
@pass_p
@click.argument('name', required=True)
def p_list_delete(p, name):
    """ Delete a list.

    \b
    Syntax:
        p list delete NAME

    \b
    Example:
        p list delete pypumpers
    """
    l = [l for l in p.pump.me.lists if l.display_name.lower() == name.lower()]
    if not l:
        p.output.fatal("No list can be found with name {0!r}.".format(name))
    #TODO confirmation?
    l[0].delete()

@p_list.command('add')
@pass_p
@click.argument('name', required=True)
@click.argument('webfingers', nargs=-1)
def p_list_add(p, name, webfingers):
    """ Add members to a list.

    \b
    Syntax:
        p list add NAME WEBFINGER [WEBFINGER] ...

    \b
    Example:
        p list add pypumpers moggers87@microca.st Tsyesika@microca.st
    """
    l = [l for l in p.pump.me.lists if l.display_name.lower() == name.lower()]
    if not l:
        p.output.fatal("No list can be found with name {0!r}.".format(name))
    for w in webfingers:
        u = p.pump.Person(w)
        l[0].add(u)

@p_list.command('remove')
@pass_p
@click.argument('name', required=True)
@click.argument('webfingers', nargs=-1)
def p_list_add(p, name, webfingers):
    """ Remove members from a list.

    \b
    Syntax:
        p list remove NAME WEBFINGER [WEBFINGER] ...

    \b
    Example:
        p list remove pypumpers moggers87@microca.st Tsyesika@microca.st
    """
    l = [l for l in p.pump.me.lists if l.display_name.lower() == name.lower()]
    if not l:
        p.output.fatal("No list can be found with name {0!r}.".format(name))
    for w in webfingers:
        u = p.pump.Person(w)
        l[0].remove(u)

@p_list.command('members')
@pass_p
@click.argument('name', required=True)
def p_list_members(p, name):
    """ Display all members of a list.
    
    \b
    Syntax:
        p list members NAME

    \b
    Example:
        p list members pypumpers
    """
    l = [l for l in p.pump.me.lists if l.display_name.lower() == name.lower()]
    if not l:
        p.output.fatal("No list can be found with name {0!r}.".format(name))

    for person in l[0].members:
        p.output.log(person.webfinger)

@cli.command('whoami')
@click.pass_context
def p_whoami(ctx):
    """ Display information on active user. """
    ctx.invoke(p_whois, ctx.obj.pump.client.webfinger)

@cli.command('whois')
@pass_p
@click.argument('webfinger', required=True)
def p_whois(p, webfinger):
    """ Display information on user. """
    person = p.pump.Person(webfinger)
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
        if information["location"].display_name is not None:
            information["location"] = information["location"].display_name
        else:
            del information["location"]

    # Now display each value with the padding
    for name, value in information.items():
        padding = max_length - len(name) + 2
        item = name + (" "*padding) + str(value)
        p.output.log(item)


if __name__ == "__main__":
    settings = Settings.load(None, None)

    # Certain keys settings should have
    if "active" not in settings:
        settings["active"] = None

    if "verify_ssl_certs" not in settings:
        settings["verify_ssl_certs"] = True

    cli()
