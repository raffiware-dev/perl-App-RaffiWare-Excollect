#!/bin/bash


set -euo pipefail

# Load ID variable
# . /etc/os-release
# 
# 
# case "$ID" in
#   centos*)  OS_FAMILY="redhat" ;;
#   debian*)  OS_FAMILY="debian" ;;
#   ubuntu*)  OS_FAMILY="ubuntu" ;;
#   *)
#      echo "Unknown OS family"
#      exit 1;;
# esac 
# 
# case "$OS_FAMILY" in
#   redhat*) 
#     VERSION=0;
#   debian*)  
#     VERSION=$(cat /etc/debian_version);
#
#      for 12 apt install build-essential libssl-dev zlib1g-dev
#   ubuntu*)  
#     VERSION=$(cat /etc/debian_version);  
#  
#     libz-dev ubuntu
#   *)
# esac 


SCRIPT_DIR=$( dirname -- "${BASH_SOURCE[0]}" );

$SCRIPT_DIR/cpanm --from "$PWD/vendor/cache" --local-lib=~/.exc/perl5 local::lib

eval $(perl -I ~/.exc/perl5/lib/perl5/ -Mlocal::lib)

$SCRIPT_DIR/cpanm --from "$PWD/vendor/cache"  --local-lib=~/.exc/perl5 --installdeps --notest --quiet .

# Needed by AnyEvent but not detected as dependency
$SCRIPT_DIR/cpanm --from "$PWD/vendor/cache" --local-lib=~/.exc/perl5 common::sense

perl -p -i -e "s|## installed-lib ##|use lib '$HOME/.exc/perl5/lib/perl5';|g" bin/exc

$SCRIPT_DIR/cpanm install --local-lib=~/.exc/perl5  --notest --quiet .

printf "\n## ADDED BY EXC INSTALLER ##\nexport PATH=\$PATH:~/.exc/perl5/bin\n##\n" >> ~/.bashrc 
