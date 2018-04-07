#!/usr/bin/env bash

# @copyright Copyright (c) 2017, Daniel Calviño Sánchez (danxuliu@gmail.com)
#
# @license GNU AGPL version 3 or any later version
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Helper script to run the acceptance tests, which test a running Nextcloud
# instance from the point of view of a real user, configured to start the
# Nextcloud server themselves and from their grandparent directory.
#
# The acceptance tests are written in Behat so, besides running the tests, this
# script installs Behat, its dependencies, and some related packages in the
# "vendor" subdirectory of the acceptance tests. The acceptance tests expect
# that the last commit in the Git repository provides the default state of the
# Nextcloud server, so the script installs the Nextcloud server and saves a
# snapshot of the whole grandparent directory (no .gitignore file is used) in
# the Git repository. Finally, the acceptance tests also use the Selenium server
# to control a web browser, so this script waits for the Selenium server
# (which should have been started before executing this script) to be ready
# before running the tests.
#
# By default the acceptance tests run are those for the Nextcloud server;
# acceptance tests for apps can be run by providing the
# "--acceptance-tests-dir XXX" option. When this option is used the Behat
# configuration and the Nextcloud installation script used by the acceptance
# tests for the Nextcloud server are ignored; they must be provided in the given
# acceptance tests directory. Note, however, that the context classes for the
# Nextcloud server and the core acceptance test framework classes are
# automatically loaded; there is no need to explicitly set them in the Behat
# configuration. Also, even when that option is used, the packages installed by
# this script end in the "vendor" subdirectory of the acceptance tests for the
# Nextcloud server, not in the one given in the option.

# Exit immediately on errors.
set -o errexit

# Ensure working directory is script directory, as some actions (like installing
# Behat through Composer or running Behat) expect that.
cd "$(dirname $0)"

# "--acceptance-tests-dir XXX" option can be provided to set the directory
# (relative to the root directory of the Nextcloud server) used to look for the
# Behat configuration and the Nextcloud installation script.
# By default it is "tests/acceptance", that is, the acceptance tests for the
# Nextcloud server itself.
ACCEPTANCE_TESTS_DIR="tests/acceptance"
if [ "$1" = "--acceptance-tests-dir" ]; then
	ACCEPTANCE_TESTS_DIR=$2

	shift 2
fi

# "--timeout-multiplier N" option can be provided to set the timeout multiplier
# to be used in ActorContext.
TIMEOUT_MULTIPLIER=""
if [ "$1" = "--timeout-multiplier" ]; then
	if [[ ! "$2" =~ ^[0-9]+$ ]]; then
		echo "--timeout-multiplier must be followed by a positive integer"

		exit 1
	fi

	TIMEOUT_MULTIPLIER=$2

	shift 2
fi

# "--nextcloud-server-domain XXX" option can be provided to set the domain used
# by the Selenium server to access the Nextcloud server.
DEFAULT_NEXTCLOUD_SERVER_DOMAIN="127.0.0.1"
NEXTCLOUD_SERVER_DOMAIN="$DEFAULT_NEXTCLOUD_SERVER_DOMAIN"
if [ "$1" = "--nextcloud-server-domain" ]; then
	NEXTCLOUD_SERVER_DOMAIN=$2

	shift 2
fi

# "--selenium-server XXX" option can be provided to set the domain and port used
# by the acceptance tests to access the Selenium server.
DEFAULT_SELENIUM_SERVER="127.0.0.1:4444"
SELENIUM_SERVER="$DEFAULT_SELENIUM_SERVER"
if [ "$1" = "--selenium-server" ]; then
	SELENIUM_SERVER=$2

	shift 2
fi

# Safety parameter to prevent executing this script by mistake and messing with
# the Git repository.
if [ "$1" != "allow-git-repository-modifications" ]; then
	echo "To run the acceptance tests use \"run.sh\" instead"

	exit 1
fi

SCENARIO_TO_RUN=$2
if [ "$ACCEPTANCE_TESTS_DIR" != "tests/acceptance" ]; then
	if [ "$SCENARIO_TO_RUN" == "" ]; then
		echo "When an acceptance tests directory is given the scenario to run" \
			 "should be provided too (paths are relative to the acceptance" \
			 "tests directory; use the features directory to run all tests)"
		echo "No scenario was given, so \"features/\" was automatically used"

		SCENARIO_TO_RUN="features/"
	fi

	SCENARIO_TO_RUN=../../$ACCEPTANCE_TESTS_DIR/$SCENARIO_TO_RUN
fi

if [ "$TIMEOUT_MULTIPLIER" != "" ]; then
	# Although Behat documentation states that using the BEHAT_PARAMS
	# environment variable "You can set any value for any option that is
	# available in a behat.yml file" this is currently not true for the
	# constructor parameters of contexts (see
	# https://github.com/Behat/Behat/issues/983). Thus, the default "behat.yml"
	# configuration file has to be adjusted to provide the appropriate
	# parameters for ActorContext.
	ORIGINAL="\
        - ActorContext"
	REPLACEMENT="\
        - ActorContext:\n\
            actorTimeoutMultiplier: $TIMEOUT_MULTIPLIER"
	sed --in-place "s/$ORIGINAL/$REPLACEMENT/" ../../$ACCEPTANCE_TESTS_DIR/config/behat.yml
fi

# TODO
if [ "$NEXTCLOUD_SERVER_DOMAIN" != "$DEFAULT_NEXTCLOUD_SERVER_DOMAIN" ]; then
	# Although Behat documentation states that using the BEHAT_PARAMS
	# environment variable "You can set any value for any option that is
	# available in a behat.yml file" this is currently not true for the
	# constructor parameters of contexts (see
	# https://github.com/Behat/Behat/issues/983). Thus, the default "behat.yml"
	# configuration file has to be adjusted to provide the appropriate
	# parameters for NextcloudTestServerContext.
	# TODO valid only if no parameters are set in behat.yml
	ORIGINAL="\
        - NextcloudTestServerContext:\?"
	REPLACEMENT="\
        - NextcloudTestServerContext:\n\
            nextcloudTestServerHelperParameters:\n\
              - $NEXTCLOUD_SERVER_DOMAIN"
	sed --in-place "s/$ORIGINAL/$REPLACEMENT/" ../../$ACCEPTANCE_TESTS_DIR/config/behat.yml
fi

if [ "$SELENIUM_SERVER" != "$DEFAULT_SELENIUM_SERVER" ]; then
	# Set the Selenium server to be used by Mink; this extends the default
	# configuration from "config/behat.yml".
	export BEHAT_PARAMS='
{
    "extensions": {
        "Behat\\MinkExtension": {
            "sessions": {
                "default": {
                    "selenium2": {
                        "wd_host": "http://'"$SELENIUM_SERVER"'/wd/hub"
                    }
                },
                "John": {
                    "selenium2": {
                        "wd_host": "http://'"$SELENIUM_SERVER"'/wd/hub"
                    }
                },
                "Jane": {
                    "selenium2": {
                        "wd_host": "http://'"$SELENIUM_SERVER"'/wd/hub"
                    }
                }
            }
        }
    }
}'
fi

composer install

cd ../../

INSTALL_AND_CONFIGURE_SERVER_PARAMETERS=""
if [ "$NEXTCLOUD_SERVER_DOMAIN" != "$DEFAULT_NEXTCLOUD_SERVER_DOMAIN" ]; then
	INSTALL_AND_CONFIGURE_SERVER_PARAMETERS+="--nextcloud-server-domain $NEXTCLOUD_SERVER_DOMAIN"
fi

echo "Installing and configuring Nextcloud server"
mkdir data
chown -R www-data:www-data apps config data
# TODO not a login shell, probably receive the user as a parameter so with the built-in server root is used anyway
su --shell /bin/bash www-data --command "$ACCEPTANCE_TESTS_DIR/installAndConfigureServer.sh $INSTALL_AND_CONFIGURE_SERVER_PARAMETERS"

echo "Saving the default state so acceptance tests can reset to it"
find . -name ".gitignore" -exec rm --force {} \;
git add --all && echo 'Default state' | git -c user.name='John Doe' -c user.email='john@doe.org' commit --quiet --file=-

cd tests/acceptance

# Ensure that the Selenium server is ready before running the tests.
echo "Waiting for Selenium"
timeout 60s bash -c "while ! curl $SELENIUM_SERVER >/dev/null 2>&1; do sleep 1; done"

vendor/bin/behat --config=../../$ACCEPTANCE_TESTS_DIR/config/behat.yml $SCENARIO_TO_RUN
