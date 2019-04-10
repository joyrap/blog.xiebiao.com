#! /bin/bash

set -eux 

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project. 
hugo -d docs

cp CNAME docs/
cp -rf images docs/

git add -A
git commit -m "deploy"
git push 



