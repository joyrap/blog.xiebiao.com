#! /bin/bash

set -eux 

echo -e "Publish to blog.xiebiao.com!\n"

rm -rf publish
# Build the project. 
hugo -d publish

# git submodule add git@github.com:joyrap/joyrap.github.io.git docs
# push docs to `joyrap.github.io`
cp CNAME publish/
cp -rf images publish/

git add -A
git commit -m "Publish"
git push --recurse-submodules=check



