#!/bin/sh

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

OPENSSL_VERSION="0.9.8j"
OPENSSL_SOURCE_DIR="openssl-$OPENSSL_VERSION"
OPENSSL_ARCHIVE="$OPENSSL_SOURCE_DIR.tar.gz"
OPENSSL_URL="http://www.openssl.org/source/$OPENSSL_ARCHIVE"
OPENSSL_MD5="a5cb5f6c3d11affb387ecf7a997cac0c"  # for openssl-0.9.8j.tar.gz"

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

fetch_archive "$OPENSSL_URL" "$OPENSSL_ARCHIVE" "$OPENSSL_MD5"
extract "$OPENSSL_ARCHIVE"

top="$(pwd)"
cd "$OPENSSL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
			load_vsvars

            # disable idea cypher per Phoenix's patent concerns (DEV-22827)
            perl Configure no-idea "VC-WIN32"

            ./ms/do_masm.bat

            patch ms/ntdll.mak < ../openssl-disable-manifest.patch

            # *TODO figure out why this step fails when I use cygwin perl instead of
            # ActiveState perl for the above configure
            nmake -f ms/ntdll.mak 

            mkdir -p stage/lib/debug
            mkdir -p stage/lib/release

            cp "out32dll/libeay32.lib" "stage/lib/debug"
            cp "out32dll/ssleay32.lib" "stage/lib/debug"
            cp "out32dll/libeay32.lib" "stage/lib/release"
            cp "out32dll/ssleay32.lib" "stage/lib/release"

            cp out32dll/{libeay32,ssleay32}.dll "stage/lib/debug"
            cp out32dll/{libeay32,ssleay32}.dll "stage/lib/release"

            mkdir -p stage/include/openssl
            # *NOTE: the -L is important because they're symlinks in the openssl dist.
            cp -r -L "include/openssl" "stage/include/"
        ;;
        "darwin")
            #./config no-idea --prefix="$(pwd)/stage" -fno-stack-protector
            ./Configure no-idea 'darwin-i386-cc:gcc-4.0:-iwithsysroot /Developer/SDKs/MacOSX10.4u.sdk' --prefix="$(pwd)/stage"
            make depend
            make
            make install
        ;;
        "linux")
			./Configure no-idea linux-generic32 -fno-stack-protector -m32 --prefix="$(pwd)/stage"
            make
            make install
        ;;
    esac
    mkdir -p stage/LICENSES
    cp LICENSE stage/LICENSES/openssl.txt
cd "$top"

pass

