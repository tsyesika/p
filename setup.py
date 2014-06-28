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

from sys import version_info
from warnings import warn

try:
    from setuptools import setup
except ImportError:
    from distutils.core import setup

setup(
        name="p",
        version="0.1",
        description="A command-line Pump.io tool",
        long_description=open("README.md").read(),
        author="Jessica Tallon",
        #author_email="",
        scripts=['p'],
        url="https://github.com/xray7224/p",
        license="GPLv3+",
        install_requires=[
                "pypump",
                "click",
                "colorama",
                "pytz",
                "six",
                "html2text"
                ],
        dependency_links=[
                "https://github.com/xray7224/PyPump/tarball/master#egg=pypump-0.6",
                "https://github.com/mitsuhiko/click/tarball/master#egg=click-2.0-dev",
                ],
        classifiers=[
                "Development Status :: 3 - Alpha",
                "Programming Language :: Python",
                "Programming Language :: Python :: 2",
                "Programming Language :: Python :: 2.6",
                "Programming Language :: Python :: 2.7",
                "Programming Language :: Python :: 3",
                "Programming Language :: Python :: 3.3",
                "Programming Language :: Python :: Implementation :: CPython",
                "Operating System :: OS Independent",
                "Operating System :: POSIX",
                "Operating System :: Microsoft :: Windows",
                "Operating System :: MacOS :: MacOS X",
                "Intended Audience :: Developers",
                "License :: OSI Approved",
                "License :: OSI Approved :: GNU General Public License v3 (GPLv3)",
                "License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)",
                ],
     )
