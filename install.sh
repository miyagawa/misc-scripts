#!/bin/sh
pwd=`pwd`

for i in `ls`
do
    if [ "$i" != "install.sh" ]
    then
        ln -s $pwd/$i $HOME/local/bin/$i
    fi
done
