#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e
# complain about unreferenced environment variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$autobuild" source_environment)"
set -x

# pull in LL_BUILD appropriate for platform and Release
set_build_variables convenience Release

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/{debug,release}/*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}


# Restore all .dylibs
restore_dylibs ()
{
    for dylib in "$stage/packages/lib"/{debug,release}/*.dylib.disable; do
        if [ -f "$dylib" ]; then
            mv "$dylib" "${dylib%.disable}"
        fi
    done
}

top="$(pwd)"
stage="$top/stage"

[ -f "$stage"/packages/include/zlib/zlib.h ] || fail "You haven't yet run 'autobuild install'."

OPENSSL_SOURCE_DIR="openssl"
# Look in crypto/opensslv.h instead of the more obvious
# include/openssl/opensslv.h because the latter is (supposed to be) a symlink
# to the former. That works on Mac and Linux but not Windows: on Windows we
# get a plain text file containing the relative path to crypto/opensslv.h, and
# a very strange "version number" because perl can't find
# OPENSSL_VERSION_NUMBER. (Sigh.)
raw_version=$(perl -ne 's/#\s*define\s+OPENSSL_VERSION_NUMBER\s+([\d]+)/$1/ && print' "${OPENSSL_SOURCE_DIR}/crypto/opensslv.h")

major_version=$(echo ${raw_version:2:1})
minor_version=$((10#$(echo ${raw_version:3:2})))
build_version=$((10#$(echo ${raw_version:5:2})))

patch_level_hex=$(echo $raw_version | cut -c 8-9)
patch_level_dec=$((16#$patch_level_hex))
str="abcdefghijklmnopqrstuvwxyz"
patch_level_version=$(echo ${str:patch_level_dec-1:1})

version_str=${major_version}.${minor_version}.${build_version}${patch_level_version}

build=${AUTOBUILD_BUILD_ID:=0}
echo "${version_str}.${build}" > "${stage}/VERSION.txt"

pushd "$OPENSSL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            mkdir -p "$stage/lib/release"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                targetname=VC-WIN32
                batname=do_ms
            else
                targetname=VC-WIN64A
                batname=do_win64a
            fi

            # disable idea cypher per Phoenix's patent concerns (DEV-22827)
            # The syntax ${LL_BUILD////-} is ${var//a/b} ("expand var,
            # substituting every 'a' with 'b'") in which a is '/' and b is
            # '-'. In other words, we're changing /GR to -GR, etc., because
            # Configure states that -switches will be passed through to the
            # compiler. It doesn't mention /switches.
            perl Configure "$targetname" no-asm no-idea zlib threads -DNO_WINDOWS_BRAINDEATH \
                --with-zlib-include="$(cygpath -w "$stage/packages/include/zlib")" \
                --with-zlib-lib="$(cygpath -w "$stage/packages/lib/release/zlib.lib")" \
                ${LL_BUILD////-}

            # Not using NASM
            ./ms/"$batname.bat"

            nmake -f ms/ntdll.mak

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd out32dll
                    # linden_test.bat is a clone of test.bat with unavailable
                    # tests removed and the return status changed to fail if a problem occurs.
                    ../ms/linden_test.bat
                popd
            fi

            cp -a out32dll/{libeay32,ssleay32}.{lib,dll} "$stage/lib/release"

            # Clean
            nmake -f ms/ntdll.mak vclean

            # Publish headers
            mkdir -p "$stage/include/openssl"

            # These files are symlinks in the SSL dist but just show up as text files
            # on windows that contain a string to their source.  So run some perl to
            # copy the right files over.
            perl ../copy-windows-links.pl "include/openssl" "$stage/include/openssl"
        ;;

        darwin*)
            # workaround for finding makedepend on OS X
            export PATH="$PATH":/usr/X11/bin/

            # Install name for dylibs based on major version number
            crypto_target_name="libcrypto.1.0.0.dylib"
            crypto_install_name="@executable_path/../Resources/${crypto_target_name}"
            ssl_target_name="libssl.1.0.0.dylib"
            ssl_install_name="@executable_path/../Resources/${ssl_target_name}"

            # Force static linkage by moving .dylibs out of the way
            trap restore_dylibs EXIT
            for dylib in "$stage/packages/lib"/{debug,release}/*.dylib; do
                if [ -f "$dylib" ]; then
                    mv "$dylib" "$dylib".disable
                fi
            done

            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD}"
            export CFLAGS="$opts"
            export CXXFLAGS="$opts"
            export LDFLAGS="-Wl,-headerpad_max_install_names"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                targetname='darwin-i386-cc 386'
            else
                targetname='darwin64-x86_64-cc'
            fi

            # Release
            ./Configure zlib threads no-idea shared no-gost $targetname \
                --prefix="$stage" --libdir="lib/release" --openssldir="share" \
                --with-zlib-include="$stage/packages/include/zlib" \
                --with-zlib-lib="$stage/packages/lib/release"
            make depend
            make
            # Avoid plain 'make install' because, at least on Yosemite,
            # installing the man pages into the staging area creates problems
            # due to the number of symlinks. Thanks to Cinder for suggesting
            # this make target.
            make install_sw

            # Modify .dylib path information.  Do this after install
            # to the copies rather than built or the dylib's will be
            # linked again wiping out the install_name.
            crypto_stage_name="${stage}/lib/release/${crypto_target_name}"
            ssl_stage_name="${stage}/lib/release/${ssl_target_name}"
            chmod u+w "${crypto_stage_name}" "${ssl_stage_name}"
            install_name_tool -id "${ssl_install_name}" "${ssl_stage_name}"
            install_name_tool -id "${crypto_install_name}" "${crypto_stage_name}"
            install_name_tool -change "${crypto_stage_name}" "${crypto_install_name}" "${ssl_stage_name}"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            make clean
        ;;

        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target per AUTOBUILD_ADDRSIZE
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="${TARGET_CPPFLAGS:-}"
            fi

            # Force static linkage to libz by moving .sos out of the way
            trap restore_sos EXIT
            for solib in "${stage}"/packages/lib/debug/*.so* "${stage}"/packages/lib/release/*.so*; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "$solib".disable
                fi
            done

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                targetname='linux-generic32'
            else
                targetname='linux-x86_64'
            fi

            # '--libdir' functions a bit different than usual.  Here it names
            # a part of a directory path, not the entire thing.  Same with
            # '--openssldir' as well.
            # "shared" means build shared and static, instead of just static.

            ./Configure zlib threads shared no-idea "$targetname" -fno-stack-protector "$opts" \
                --prefix="$stage" --libdir="lib/release" --openssldir="share" \
                --with-zlib-include="$stage/packages/include/zlib" \
                --with-zlib-lib="$stage"/packages/lib/release/
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
            # the consuming build tries to strip libraries.  It's easier to
            # make writable here than fix the viewer packaging.
            chmod u+w "$stage"/lib/{release,debug}/lib{crypto,ssl}.so*
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp -a LICENSE "$stage/LICENSES/openssl.txt"
popd

mkdir -p "$stage"/docs/openssl/
cp -a README.Linden "$stage"/docs/openssl/

pass

