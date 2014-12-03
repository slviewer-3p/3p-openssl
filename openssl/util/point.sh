#!/bin/sh

#OSX filesystem only pretends to be case insensitive.  
os=`echo $OSTYPE | cut -c 1-6`
if [ $os != darwin ] || [ `echo $1 | tr [:upper:] [:lower:]`  !=  `echo $2 | tr [:upper:] [:lower:]` ]; then
	rm -f "$2"
fi

if test "$OSTYPE" = msdosdjgpp || test "x$PLATFORM" = xmingw || [ $os = darwin ] ; then
    cp "$1" "$2"
else
    ln -s "$1" "$2"
fi
echo "$2 => $1"

