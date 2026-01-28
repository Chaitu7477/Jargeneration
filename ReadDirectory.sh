#!/bin/sh -e 

bash --version
echo "${BASH_VERSION}"

BRANCHNAME=$1

echo "${BRANCHNAME}"

TIREPOS=("localservices")
cloneURL="https://gitlab.com/muchbetter-group/groups/maveric-systems-temenos/digital_banking_fabric_source"

CURRENT_PATH=$(pwd)
gitIgnoreList=()
echo "current path is $CURRENT_PATH"
TIPROJECTKEY="ti"	

for repo in "${TIREPOS[@]}"; do
  echo "Cloning $repo..."
  echo "$cloneURL/$TIPROJECTKEY/$repo.git"
  git clone --branch "$BRANCHNAME" --depth 1 "$cloneURL/$TIPROJECTKEY/$repo.git" $repo
  cd $repo
  git rev-parse --short HEAD
  cd ..
done

ls
echo "current path is $CURRENT_PATH"