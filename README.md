git-fastclone
=============

[![Twitter: @longboardcat13](https://img.shields.io/badge/contact-@longboardcat13-blue.svg?style=flat)](https://twitter.com/longboardcat13)
[![License](https://img.shields.io/badge/license-Apache-green.svg?style=flat)](https://github.com/square/git-fastclone/blob/master/LICENSE)
[![Build Status](https://travis-ci.org/square/git-fastclone.svg?branch=master)](https://travis-ci.org/square/git-fastclone)
[![Gem Version](https://badge.fury.io/rb/git-fastclone.svg)](http://badge.fury.io/rb/git-fastclone)

git-fastclone is git clone --recursive on steroids.


Why fastclone?
--------------
Doing lots of repeated checkouts on a specific machine?

| Repository | 1st Fastclone | 2nd Fastclone | git clone | cp -R |
| -----------|---------------|---------------|-----------|-------|
| angular.js |    8s         |     3s        | 6s        | 0.5s  |
| bootstrap  |    26s        |     3s        | 11s       | 0.2s  |
| gradle     |    25s        |     9s        | 19s       | 6.2s  |
| linux      |    4m 53s     |     1m 6s     | 3m 51s    | 29s   |
| react.js   |    18s        |     3s        | 8s        | 0.5s  |
| tensorflow |    19s        |     4s        | 8s        | 1.5s  |

Above times captured using `time` without verbose mode.


What does it do?
----------------
It creates a reference repo with `git clone --mirror` in `/var/tmp/git-fastclone/reference` for each
repository and git submodule linked in the main repo. You can control where it puts these by
changing the `REFERENCE_REPO_DIR` environment variable.

It aggressively updates these mirrors from origin and then clones from the mirrors into the
directory of your choosing. It always works recursively and multithreaded to get your checkout up as
fast as possible.

Detailed explanation [here][1].


Usage
-----
    gem install git-fastclone
    git fastclone [options] <git-repo-url>

    -b, --branch <branch>   Clone a specific branch
    -v, --verbose           Verbose mode
    -c, --color             Display colored output
        --config CONFIG     Git config applied to the cloned repo
        --lock-timeout N    Timeout in seconds to acquire a lock on any reference repo.

Change the default `REFERENCE_REPO_DIR` environment variable if necessary.

Cygwin users need to add `~/bin` to PATH.


How to test?
------------
Manual testing:

    ruby -Ilib bin/git-fastclone <git url>

Compatible with Travis and Kochiku.


Contributing
------------
If you would like to contribute to git-fastclone, you can fork the repository and send us pull
requests.

When submitting code, please make every effort to follow existing conventions and style in order to
keep the code as readable as possible.

Before accepting any pull requests, we need you to sign an [Individual Contributor Agreement][2]
(Google form).

Once landed, please reach out to any owner listed in https://rubygems.org/gems/git-fastclone and ask them to help publish the new version.


Acknowledgements
----------------
[thoughtbot/terrapin][3] - jyurek and collaborators

[robolson][4]

[ianchesal][5]

[mtauraso][6]

[chriseckhardt][7]


License
-------
    Copyright 2015 Square Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

[1]: https://corner.squareup.com/2015/11/fastclone.html
[2]: https://docs.google.com/a/squareup.com/forms/d/13WR8m5uZ2nAkJH41k7GdVBXAAbzDk00vxtEYjd6Imzg/viewform?formkey=dDViT2xzUHAwRkI3X3k5Z0lQM091OGc6MQ&ndplr=1
[3]: https://github.com/thoughtbot/terrapin
[4]: https://github.com/robolson
[5]: https://github.com/ianchesal
[6]: https://github.com/mtauraso
[7]: https://github.com/chriseckhardt
