#! /bin/bash

set -eux 

echo -e "Deploy updates to GitHub...\n"

# Build the project. 
hugo -d docs

# git submodule
# push docs to `joyrap.github.io`
cp CNAME docs/
cp -rf images docs/

git add -A
git commit -m "Publish"
git push 



