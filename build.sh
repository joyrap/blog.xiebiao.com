#! /bin/bash

set -eux 

echo -e "Publish to blog.xiebiao.com!\n"

# git submodule add git@github.com:joyrap/joyrap.github.io.git publish
# Build the project. 
rm -rf publish
#git submodule add git@joyrap.github.com:joyrap/joyrap.github.io.git publish
hugo -d publish

# push docs to `joyrap.github.io`
cp CNAME publish/
cp -rf images publish/
git add -A
git commit -m "Update"
git  push -f publish




