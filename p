#!/usr/bin/python

import collections
import sys
import os
import re

from HTMLParser import HTMLParser

from pypump import WebPump, Client, JSONStore
from pypump.models.note import Note
from termcolor import colored

class Output(object):
    """ Handle output of for program to provide uniform messages. """    

    def __init__(self):
        self.stdout = sys.stdout
        self.stderr = sys.stderr

    def fatal(self, message):
        """ Fatal message - will produce an error and exit with none 0 error code """
        self.error(message)
        sys.exit(1)

    def error(self, message):
        """ Produce an error message """
        self.stderr.write("{0} {1}".format(colored("[Error]", "red"), message))
        self.stderr.write("\n")

    def log(self, message, color=None):
        """ Produce normal message """
        if color is not None:
            message = colored(message, color)

        self.stdout.write(message)
        self.stdout.write("\n")

class P(object):
    """P - Pump.io command line utility.

    Commands:
        p authorize WEBFINGER
        p accounts
        p post NOTE
        p follow WEBFINGER
        p unfollow WEBFINGER
        p followers
        p following
        p whoami
        p whois WEBFINGER
    """

    def __init__(self, settings, output):
        self.settings = settings
        self.output = output

        # If there is an account set - setup PyPump
        if settings["active"]:   
            self.client = self.__get_client(settings["active"])
            # I know this isn't a website but the way WebPump works
            # is sligthly more what I want.
            self.pump = WebPump(
                client=self.client,
                verify_requests=self.settings["verify_ssl_certs"]
            )
        else:
            self.client = None
            self.pump = None

    def __get_client(self, webfinger):
        """ Gets pump.io client instance for webfinger """
        return Client(
            webfinger=webfinger,
            name="p",
            type="native"
        )

    def __verification_callback(self, url):
        """ Ask user for verifier code for OOB authorization """
        print "To add an account you need to authorize p to use your"
        print "account and paste the verifier:"
        print url
        verifier = raw_input("Verifier Code: ").strip(" ")
        return verifier

    def __ask_y_or_n(self, question, default=True):
        """ Asks a yes or no question """
        if default:
            question = "{question} [Y/n]: ".format(question=question)
        else:
            question = "{question} [y/N]: ".format(question=question)

        answer = raw_input(question).strip()
        choices = {
            "y": True,
            "yes": True,
            "n": False,
            "no": False,
            # And for all yall na'vi speakers ;)
            "sran": True,
            "srane": True,
            "kehe": False,
        }

        while answer.lower() not in choices.keys():
            print "Unknown answer {0!r}. Please answer yes or no."
            answer = raw_input(question).strip()

        return choices[answer]

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
        for account in accounts:
            self.output.log(account)

    def authorize(self, webfinger):
        """ Authorize a new account """
        if self.pump is None or self.pump.client.webfinger != webfinger:
            self.client = self.__get_client(webfinger)
            self.pump = WebPump(
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
            if self.__ask_y_or_n("Would you like to make {0!r} the active account".format(webfinger)):
                self.settings["active"] = self.pump.client.webfinger
            else:
                self.output.log("Okay, if you change your mind you can use the 'set' command.")

        self.output.log("All done.")

    def post(self, *message):
        """ Post a new note to pump.io """
        message = " ".join(message)
        if not message:
            self.output.fatal("You need to specify a message.")

        note = self.pump.Note(message)
        note.send()

    def follow(self, webfinger):
        """ Follow a user """
        person = self.pump.Person(webfinger)
        person.follow()

    def unfollow(self, webfinger):
        """ Unfollow a user """
        person = self.pump.Person(webfinger)
        person.unfollow()

    def followers(self):
        """ Display all users you follow """
        for person in self.pump.me.followers:
            self.output.log(person.webfinger)

    def following(self):
        """ Display all users following you """
        for person in self.pump.me.following:
            self.output.log(person.webfinger)

    def inbox(self):
        """ Lists latest 20 notes in inbox """
        limit = 20
        html_cleaner = re.compile(r'<[^>]+>')
        for activity in self.pump.me.inbox:
            if activity.verb != "post":
                continue # skip these too

            item = activity.obj

            if not isinstance(item, Note):
                continue

            
            content = item.content
            content = HTMLParser().unescape(html_cleaner.sub("", content)).strip()

            self.output.log(item.author.display_name, color="yellow")
            self.output.log(content)
            self.output.log("")

            if limit <= 0:
                return

            limit -= 1

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
            ("Followers", len(person.followers)),
            ("Following", len(person.following)),
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
        path = os.path.expanduser("~/.config/p/")
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
