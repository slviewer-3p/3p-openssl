#!/bin/sh

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

OPENSSL_VERSION="1.0.0g"
OPENSSL_SOURCE_DIR="openssl-$OPENSSL_VERSION"

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

top="$(pwd)"
stage="$top/stage"
cd "$OPENSSL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            load_vsvars

            # disable idea cypher per Phoenix's patent concerns (DEV-22827)
            perl Configure VC-WIN32 no-asm no-idea

            # Not using NASM
            ./ms/do_ms.bat

            nmake -f ms/ntdll.mak

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            cp "out32dll/libeay32.lib" "$stage/lib/debug"
            cp "out32dll/ssleay32.lib" "$stage/lib/debug"
            cp "out32dll/libeay32.lib" "$stage/lib/release"
            cp "out32dll/ssleay32.lib" "$stage/lib/release"

            cp out32dll/{libeay32,ssleay32}.dll "$stage/lib/debug"
            cp out32dll/{libeay32,ssleay32}.dll "$stage/lib/release"

            mkdir -p "$stage/include/openssl"

            # These files are symlinks in the SSL dist but just show up as text files
            # on windows that contain a string to their source.  So run some perl to
            # copy the right files over.
            perl ../copy-windows-links.pl "include/openssl" "$stage/include/openssl"
        ;;
        "darwin")
            opts='-arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.5.sdk -mmacosx-version-min=10.5'
            export CFLAGS="$opts"
            export CXXFLAGS="$opts"
            export LDFLAGS="$opts"
            ./Configure no-idea no-shared no-gost 'debug-darwin-i386-cc' --prefix="$stage"
            make depend
            make
            make install
        ;;
        "linux")
            # "shared" means build shared and static, instead of just static.
            ./Configure shared no-idea linux-generic32 -fno-stack-protector -m32 --prefix="$stage"
            make

            make install
            mkdir -p "$stage/lib/release"
            mv "$stage/lib/"*.a "$stage/lib/release"
            mv "$stage/lib/"*so* "$stage/lib/release"
             
            # By default, 'make install' leaves even the user write bit off.
            # This causes trouble for us down the road, along about the time
            # the consuming build tries to strip libraries.
            chmod u+w "$stage/lib/release"/libcrypto.so.* "$stage/lib/release"/libssl.so.*
            
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/openssl.txt"
cd "$top"

pass

