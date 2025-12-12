#!/bin/bash

# ENV variables
#
#    EXC_DEBUG_BUILD=1 : Leave build directory .
#    EXC_NO_BIN=1      : Force cpan dist install.
#    EXC_BRANCH
#    EXC_RELEASE

set -euo pipefail
 
EXC_PERL_ROOT="$HOME/.exc/perl5"
EXC_PERL_LIB="$EXC_PERL_ROOT/lib/perl5/"
EXC_PERL_BIN="$EXC_PERL_ROOT/bin"
BUILD_DIR="$HOME/exccollect"
WEB='https://dev.raffiware.io'
LOG="$BUILD_DIR/log"
EXC_RC_FILE="$HOME/.exc/bashrc" 

check_deps () { 
  check_deps=("$@")
  missing_deps=0;

  for dep in ${check_deps[@]}; do

    dep_found='';

    case "$OS_FAMILY" in
      redhat*) dep_found=$( rpm -qa | grep $dep )   && true ;;
      debian*) dep_found=$( dpkg -l | grep $dep  )  && true ;;
      arch*)   dep_found=$( pacman -Q | grep $dep ) && true ;;
    esac

    if [[ -z "$dep_found" ]]; then 
      echo "$dep not installed"
      missing_deps=1
    fi 

  done

  if [ "$missing_deps" == 1 ]; then 
     echo "Install cannot complete" 
     exit 1;
  fi 
}

check_group_deps () { 
  check_deps=("$@")
  missing_deps=0;

  for ((i = 0; i < ${#check_deps[@]}; i++)); do

    dep="${check_deps[$i]}"

    dep_found='';

    case "$ID" in
      fedora*) dep_found=$( dnf group info $dep 2>/dev/null |  grep -E 'Installed.*yes' ) && true ;;
      centos*) dep_found=$( yum group list --installed  | grep -E "^\s*$dep" ) && true ;;
    esac

    if [[ -z "$dep_found" ]]; then 
      echo "$dep not installed"
      missing_deps=1
    fi 

  done

  if [ "$missing_deps" == 1 ]; then 
     echo "Install cannot complete" 
     exit 1;
  fi 
}

# Check for packages needed to run installer and exc even as a stand-alone binary.
check_installer_deps () {
   echo "Checking installer dependencies..."
   check_deps "${INSTALLER_DEPS[@]}";
}

# Check for packages needed to run exc even as a stand-alone binary.
check_run_deps () {
   echo "Checking exc dependencies..."
   check_deps "${RUN_DEPS[@]}";
}

# Check for packages needed to build and run exc.
check_build_deps () {
   echo "Checking build dependencies..."
   check_deps "${BUILD_DEPS[@]}";
   check_group_deps "${BUILD_GROUP_DEPS[@]}";
}
 

debug () {
  out=$1

  if [[ ! -z ${EXC_DEBUG+x} ]]; then 
    echo "debug - $out"
  fi
}
 
fetch_install_file () {
  url=$1

  debug "Fetching $url";

  if which wget 1>/dev/null  2>&1; then
      wget $url  1>>$LOG   2>&1
      return $?
  elif which curl 1>/dev/null  2>&1; then
      HTTP_CODE=$(curl  -O --write-out "%{http_code}" "$url"   2>>$LOG )

      debug "$HTTP_CODE"

      if [[ ${HTTP_CODE} -lt 200 || ${HTTP_CODE} -gt 299 ]]; then
        debug "Error!";
        return 404
      fi
      return $?
  else
      echo "Neither wget nor curl is available."
      exit 1;
  fi
}

. /etc/os-release 

case "$ID" in
  centos*)
      OS_FAMILY="redhat" 
      VERSION=$VERSION_ID;
      INSTALLER_DEPS=( perl );
      BUILD_DEPS=( 
        openssl-devel 
        zlib-devel 
        perl-Safe 
        perl-Dumpvalue 
        perl-Digest-SHA 
        perl-Test-Simple 
        perl-Sys-Hostname 
        perl-English 
        perl-Hash-Util-FieldHash 
      );
      BUILD_GROUP_DEPS=('Development Tools');
      RUN_DEPS=();  

      ;;
  debian*)
      OS_FAMILY="debian"
      VERSION=$VERSION_ID;
      INSTALLER_DEPS=(); 
      RUN_DEPS=();
      BUILD_DEPS=( build-essential libssl-dev zlib1g-dev );
      BUILD_GROUP_DEPS=(); 
      ;;
  ubuntu*)
      OS_FAMILY="debian" 
      VERSION=$VERSION_ID;
      INSTALLER_DEPS=();
      RUN_DEPS=();
      BUILD_DEPS=( build-essential libssl-dev zlib1g-dev );
      BUILD_GROUP_DEPS=(); 
      ;;
  arch*)
      OS_FAMILY="arch" 
      RUN_DEPS=(  tzdata );
      INSTALLER_DEPS=();
      BUILD_DEPS=( base-devel openssl );
      BUILD_GROUP_DEPS=(); 
      ;; 
  almalinux*) 
      OS_FAMILY="redhat" 
      VERSION=$VERSION_ID;
      INSTALLER_DEPS=( perl which tar ); 
      BUILD_DEPS=( openssl-devel zlib-devel ); 
      BUILD_GROUP_DEPS=();
      RUN_DEPS=();
      ;;
  fedora*)
      OS_FAMILY="redhat" 
      VERSION=$VERSION_ID;
      INSTALLER_DEPS=( perl );
      BUILD_DEPS=( 
        openssl-devel 
        zlib-ng-compat-devel 
        perl-Safe 
        perl-Dumpvalue 
        perl-Digest-SHA 
        perl-Test-More-UTF8 
        perl-Sys-Hostname 
        perl-English 
        perl-Hash-Util-FieldHash 
      );
      BUILD_GROUP_DEPS=('development-tools' ); 
      RUN_DEPS=();
      ;; 
  *)
     echo "Unknown OS"
     exit 1;;
esac

check_installer_deps
check_run_deps


SYSPERL=$( which perl );

if [[ -z "$SYSPERL" ]]; then 
  echo "perl not found" 1>&2
  exit 1
fi 


rm -rf $BUILD_DIR
mkdir $BUILD_DIR
pushd $BUILD_DIR 1>>$LOG 2>&1 

fetch_install_file "$WEB/downloads/install_files/local_lib.pl" 

eval $( $SYSPERL $BUILD_DIR/local_lib.pl $EXC_PERL_ROOT  )

fetch_install_file "$WEB/downloads/install_files/bin_name.pl"

BIN_NAME=$( $SYSPERL $BUILD_DIR/bin_name.pl )

BRANCH=${EXC_BRANCH:-main};


fetch_install_file  "$WEB/downloads/$BRANCH/binaries/$BIN_NAME" && true; # Don't trigger set -e on fail
BIN_FOUND=$?


if [[ $BIN_FOUND == 0 && -z ${EXC_NO_BIN+x} ]]; then 
   echo "Installing binary version $BIN_NAME from $BRANCH"
   mkdir -p $EXC_PERL_LIB
   mkdir -p $EXC_PERL_BIN

   cp -f $BIN_NAME $EXC_PERL_BIN/exc
   cp -f $BIN_NAME $EXC_PERL_BIN/anyevent-fork

   chmod 0755 $EXC_PERL_BIN/exc 
   chmod 0755 $EXC_PERL_BIN/anyevent-fork
else
  echo "No binary version found, attempting to build from source"

  check_build_deps

  SYS_TAR=$( which tar );

  if [[ -z "$SYS_TAR" ]]; then 
    echo "tar not found" 1>&2
    exit 1
  fi 

  RELEASE=${EXC_RELEASE:-'UNSET'};

  if [[ "$RELEASE" == 'UNSET' ]]; then 
     REL_URL="$WEB/downloads/$BRANCH/App-RaffiWare-ExCollect-release" 
     debug "checking release $REL_URL";
     fetch_install_file  "$WEB/downloads/$BRANCH/App-RaffiWare-ExCollect-release"
     RELEASE=$( cat App-RaffiWare-ExCollect-release )
  fi 

  echo "Building $RELEASE from $BRANCH"; 

  fetch_install_file "$WEB/downloads/install_files/cpanm"
  fetch_install_file "$WEB/downloads/$BRANCH/vendor-cache-$RELEASE.tar.gz"
  tar -xzvf  vendor-cache-$RELEASE.tar.gz 1>>$LOG 2>&1

  CACHE="$BUILD_DIR/vendor/cache"

  DIST="App-RaffiWare-ExCollect-$RELEASE.tar.gz"
  fetch_install_file "$WEB/downloads/$BRANCH/$DIST"
  tar -xzvf  $DIST 1>>$LOG 2>&1 

  #DIST_DIR=$( find . -maxdepth 1 -type d  -name 'App-RaffiWare-ExCollect-*' );
  DIST_DIR="App-RaffiWare-ExCollect-$RELEASE";

  pushd $DIST_DIR 1>>$LOG 2>&1 

  echo "Building dependencies, this will take a few minutes";

  $SYSPERL $BUILD_DIR/cpanm --from $CACHE --local-lib=$EXC_PERL_ROOT --installdeps --notest --quiet . 1>>$LOG 2>&1

  $SYSPERL -p -i -e "s|## installed-lib ##|use lib '$EXC_PERL_LIB';|g" bin/exc
  $SYSPERL -p -i -e "s|## installed-lib ##|use lib '$EXC_PERL_LIB';|g" bin/anyevent-fork

  $SYSPERL $BUILD_DIR/cpanm install --local-lib=$EXC_PERL_ROOT --notest --quiet . 1>>$LOG 2>&1

  popd 1>>$LOG 2>&1 
fi

popd 1>>$LOG 2>&1 


printf "\n## AUTO-GENERATED BY EXC INSTALLER ##\nexport PATH=\$PATH:$EXC_PERL_ROOT/bin\n" >> $EXC_RC_FILE 

printf "\nRun the following to add the exc command to your path:\n\nsource $EXC_RC_FILE \n\nYou can also add this line to your .bashrc file to make the command automatically available\n\n";

if [[ -z ${EXC_DEBUG_BUILD+x} ]]; then
  rm -rf $BUILD_DIR
fi

echo "Install complete"; 
