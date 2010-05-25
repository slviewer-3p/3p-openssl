#!/bin/sh

# turn on verbose debugging output for parabuild logs.
set -x

if [ -z "$AUTOBUILD" ] ; then 
    AUTOBUILD="$(which autobuild)"
fi

OPENSSL_VERSION="0.9.8j"

# *NOTE: temporary workaround until autobuild is installed on the build farm
autobuild_installed ()
{
    local hardcoded_rev="parabuild-bootstrap"
    local bootstrap_url="http://pdp47.lindenlab.com/cgi-bin/hgwebdir.cgi/brad/autobuild/archive/$hardcoded_rev.tar.bz2"

    # hg.lindenlab.com is kind of hosed right now.
    #local hardcoded_rev="c8062b08a710"
    #local boostrap_url="http://hg.lindenlab.com/brad/autobuild-trunk/get/$hardcoded_rev.bz2"

    if [ -z "$AUTOBUILD" ] || [ ! -x "$AUTOBUILD" ] ; then
        echo "failed to find executable autobuild $AUTOBUILD" >&2

        echo "fetching autobuild rev $hardcoded_rev from $bootstrap_url"
        curl "$bootstrap_url" | tar -xj
        AUTOBUILD="$(pwd)/autobuild-$hardcoded_rev/bin/autobuild"
        if [ ! -x "$AUTOBUILD" ] ; then
            echo "failed to bootstrap autobuild!"
            return 1
        fi
    fi
    echo "located autobuild tool: '$AUTOBUILD'"
}

# at this point we should know where everything is, so make errors fatal
set -e

# this fail function will either be provided by the parabuild buildscripts or
# not exist.  either way it's a fatal error
autobuild_installed || fail

# *HACK - bash doesn't know how to pass real pathnames to native windows python
if [ "$OSTYPE" == 'cygwin' ] ; then
	AUTOBUILD="$(cygpath -u $AUTOBUILD.cmd)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

"$AUTOBUILD" build

"$AUTOBUILD" package

OPENSSL_INSTALLABLE_PACKAGE_FILENAME="$(ls -1 openssl-$OPENSSL_VERSION-$AUTOBUILD_PLATFORM-$(date +%Y%m%d)*.tar.bz2)"
"$AUTOBUILD" upload "$OPENSSL_INSTALLABLE_PACKAGE_FILENAME"

OPENSSL_INSTALLABLE_PACKAGE_MD5="$(calc_md5 "$OPENSSL_INSTALLABLE_PACKAGE_FILENAME")"
echo "{'md5':'$OPENSSL_INSTALLABLE_PACKAGE_MD5', 'url':'http://s3.amazonaws.com/viewer-source-downloads/install_pkgs/$OPENSSL_INSTALLABLE_PACKAGE_FILENAME'}" > "output.js"

upload_item installer "output.js" text/plain

pass

