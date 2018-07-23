#!/bin/sh


# ulimit -S -s  4194304

if [ "$#" -gt 0 ]; then
    fname=$1
else
    exit 1
fi

if [ "$#" -gt 1 ]; then
    thr=$2
else
    thr=4
fi

./make parallel $fname \"\" $thr 

echo Testing ""

apps=$(./make parallel $fname \"\" $thr | awk '/No Applications/{print $3}')

while [ "$apps" -ge 0 ]
do
    echo Testing "[$apps]"
    timeout 2m ./make parallel $fname "\[$apps\]" $thr
    apps=$[$apps-1]
done

# for i in {0..12}
# do
#     echo Testing "[$i]"
#     timeout 2m ./make parallel "\[$i\]"
# done
