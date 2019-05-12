#! /bin/bash

set -eux 

echo -e "Publish to blog.xiebiao.com!\n"

rm -rf publish
git submodule add git@github.com:joyrap/joyrap.github.io.git publish
# Build the project. 
hugo -d publish

# push docs to `joyrap.github.io`
cp CNAME publish/
cp -rf images publish/

git add -A
git commit -m "Update"
git push 
cd publish
git add -A
git commit -m "Publish"
git push



