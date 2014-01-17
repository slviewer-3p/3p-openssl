#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

OPENSSL_VERSION="1.0.1e"
OPENSSL_SOURCE_DIR="openssl"

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
[ -f "$stage"/packages/include/zlib/zlib.h ] || fail "You haven't installed packages yet."

cd "$OPENSSL_SOURCE_DIR"
case "$AUTOBUILD_PLATFORM" in

        "windows")
            load_vsvars

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            # Debug build:
            # disable idea cypher per Phoenix's patent concerns (DEV-22827)
            # crypto/cversion.c attempts to convert the full 'cl' command line into a
            # c-string without escaping characters.  This fails and confuses the compiler
            # so we use the 'NO_WINDOWS_BRAINDEATH' define.  Would be an ideal use case
            # for raw strings.
            perl Configure debug-VC-WIN32 no-asm no-idea zlib threads -DNO_WINDOWS_BRAINDEATH \
                --with-zlib-include="$(cygpath -w "$stage/packages/include/zlib")" \
                --with-zlib-lib="$(cygpath -w "$stage/packages/lib/debug/zlibd.lib")"

            # Not using NASM
            ./ms/do_ms.bat

            nmake -f ms/ntdll.mak

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd out32dll.dbg
                    # linden_test.bat is a clone of test.bat with unavailable
                    # tests removed and the return status changed to fail if a problem occurs.
                    ../ms/linden_test.bat
                popd
            fi

            cp -a out32dll.dbg/{libeay32,ssleay32}.lib "$stage/lib/debug"
            cp -a out32dll.dbg/{libeay32,ssleay32}.dll "$stage/lib/debug"
            cp -a out32dll.dbg/{libeay32,ssleay32}.pdb "$stage/lib/debug"

            # Clean
            nmake -f ms/ntdll.mak vclean

            # Release build:
            # disable idea cypher per Phoenix's patent concerns (DEV-22827)
            perl Configure VC-WIN32 no-asm no-idea zlib threads -DNO_WINDOWS_BRAINDEATH \
                --with-zlib-include="$(cygpath -w "$stage/packages/include/zlib")" \
                --with-zlib-lib="$(cygpath -w "$stage/packages/lib/release/zlib.lib")"

            # Not using NASM
            ./ms/do_ms.bat

            nmake -f ms/ntdll.mak

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd out32dll
                    # linden_test.bat is a clone of test.bat with unavailable
                    # tests removed and the return status changed to fail if a problem occurs.
                    ../ms/linden_test.bat
                popd
            fi

            cp -a out32dll/{libeay32,ssleay32}.lib "$stage/lib/release"
            cp -a out32dll/{libeay32,ssleay32}.dll "$stage/lib/release"
            cp -a out32dll/{libeay32,ssleay32}.pdb "$stage/lib/release"

            # Clean
            nmake -f ms/ntdll.mak vclean

            # Publish headers
            mkdir -p "$stage/include/openssl"

            # These files are symlinks in the SSL dist but just show up as text files
            # on windows that contain a string to their source.  So run some perl to
            # copy the right files over.
            perl ../copy-windows-links.pl "include/openssl" "$stage/include/openssl"
        ;;

        "darwin")
            # Temporary workaround for finding makedepend on mlion machines:
            export PATH="$PATH":/usr/X11/bin/

            # Install name for dylibs based on major version number
            crypto_target_name="libcrypto.1.0.0.dylib"
            crypto_install_name="@executable_path/../Resources/${crypto_target_name}"
            ssl_target_name="libssl.1.0.0.dylib"
            ssl_install_name="@executable_path/../Resources/${ssl_target_name}"

            # Force static linkage by moving .dylibs out of the way
            for dylib in "$stage/packages/lib"/{debug,release}/*.dylib; do
                if [ -f "$dylib" ]; then
                    mv "$dylib" "$dylib".disable
                fi
            done
            
            opts="${TARGET_OPTS}:--arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.7.sdk -mmacosx-version-min=10.6}"
            export CFLAGS="$opts -gdwarf-2"
            export CXXFLAGS="$opts -gdwarf-2"
            export LDFLAGS="-Wl,-headerpad_max_install_names"

            # Debug first
            ./Configure zlib threads no-idea shared no-gost 386 'debug-darwin-i386-cc' \
                --prefix="$stage" --libdir="lib/debug" --openssldir="share" \
                --with-zlib-include="$stage/packages/include/zlib" --with-zlib-lib="$stage/packages/lib/debug"
            make depend
            make
            make install

            # Modify .dylib path information.  Do this after install
            # to the copies rather than built or the dylib's will be
            # linked again wiping out the install_name.
            crypto_stage_name="${stage}/lib/debug/${crypto_target_name}"
            ssl_stage_name="${stage}/lib/debug/${ssl_target_name}"
            chmod +w "${crypto_stage_name}" "${ssl_stage_name}"
            install_name_tool -id "${ssl_install_name}" "${ssl_stage_name}"
            install_name_tool -id "${crypto_install_name}" "${crypto_stage_name}"
            install_name_tool -change "${crypto_stage_name}" "${crypto_install_name}" "${ssl_stage_name}"
            chmod -w "${crypto_stage_name}" "${ssl_stage_name}"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            make clean

            # Release last
            ./Configure zlib threads no-idea shared no-gost 386 'darwin-i386-cc' \
                --prefix="$stage" --libdir="lib/release" --openssldir="share" \
                --with-zlib-include="$stage/packages/include/zlib" --with-zlib-lib="$stage/packages/lib/release"
            make depend
            make
            make install

            # Modify .dylib path information
            crypto_stage_name="${stage}/lib/release/${crypto_target_name}"
            ssl_stage_name="${stage}/lib/release/${ssl_target_name}"
            chmod +w "${crypto_stage_name}" "${ssl_stage_name}"
            install_name_tool -id "${ssl_install_name}" "${ssl_stage_name}"
            install_name_tool -id "${crypto_install_name}" "${crypto_stage_name}"
            install_name_tool -change "${crypto_stage_name}" "${crypto_install_name}" "${ssl_stage_name}"
            chmod -w "${crypto_stage_name}" "${ssl_stage_name}"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            make clean

            # Restore zlib .dylibs
            for dylib in "$stage/packages/lib"/{debug,release}/*.dylib.disable; do
                if [ -f "$dylib" ]; then
                    mv "$dylib" "${dylib%.disable}"
                fi
            done
        ;;

        "linux")
            # Prefer gcc-4.6 if available.
            if [ -x /usr/bin/gcc-4.6 -a -x /usr/bin/g++-4.6 ]; then
                export CC=/usr/bin/gcc-4.6
                export CXX=/usr/bin/g++-4.6
            fi

            # Default target to 32-bit
            opts="${TARGET_OPTS:--m32}"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi
            
            # Force static linkage to libz by moving .sos out of the way
            for solib in "${stage}"/packages/lib/debug/*.so* "${stage}"/packages/lib/release/*.so*; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "$solib".disable
                fi
            done
            
            # '--libdir' functions a bit different than usual.  Here it names
            # a part of a directory path, not the entire thing.  Same with
            # '--openssldir' as well.
            # "shared" means build shared and static, instead of just static.

            # Debug first
            CFLAGS="-g -O0" ./Configure zlib threads shared no-idea debug-linux-generic32 -fno-stack-protector "$opts" \
                --prefix="$stage" --libdir="lib/debug" --openssldir="share" \
                --with-zlib-include="$stage/packages/include/zlib" --with-zlib-lib="$stage"/packages/lib/debug/
            make depend
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            make clean

            # "shared" means build shared and static, instead of just static.
            ./Configure zlib threads shared no-idea linux-generic32 -fno-stack-protector "$opts" \
                --prefix="$stage" --libdir="lib/release" --openssldir="share" \
                --with-zlib-include="$stage/packages/include/zlib" --with-zlib-lib="$stage"/packages/lib/release/
            make depend
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            make clean

            # By default, 'make install' leaves even the user write bit off.
            # This causes trouble for us down the road, along about the time
            # the consuming build tries to strip libraries.
            # chmod u+w "$stage/lib/release"/libcrypto.so.* "$stage/lib/release"/libssl.so.*

            # Restore libz .sos
            for solib in "${stage}"/packages/lib/debug/*.so*.disable "${stage}"/packages/lib/release/*.so*.disable; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "${solib%.disable}"
                fi
            done
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp -a LICENSE "$stage/LICENSES/openssl.txt"
cd "$top"

pass

