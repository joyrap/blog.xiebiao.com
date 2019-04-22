#! /bin/bash

set -eux 

echo -e "Deploy updates to GitHub...\n"

# Build the project. 
hugo -d docs

# git submodule add git@github.com:joyrap/joyrap.github.io.git docs
# push docs to `joyrap.github.io`
cp CNAME docs/
cp -rf images docs/

git add -A
git commit -m "Publish"
git push 



