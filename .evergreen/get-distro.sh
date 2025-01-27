#!/usr/bin/env bash

get_distro ()
{
   if [ -f /etc/os-release ]; then
      . /etc/os-release
      DISTRO="${ID}-${VERSION_ID}"
   elif [ -f /etc/centos-release ]; then
      version=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d '.' -f1)
      DISTRO="centos-${version}"
   elif command -v lsb_release >/dev/null 2>&1; then
      name=$(lsb_release -s -i)
      if [ "$name" = "RedHatEnterpriseServer" ]; then # RHEL 6.2 at least
         name="rhel"
      fi
      version=$(lsb_release -s -r)
      DISTRO="${name}-${version}"
   elif [ -f /etc/redhat-release ]; then
      release=$(cat /etc/redhat-release)
      case $release in
         *Red\ Hat*)
            name="rhel"
         ;;
         Fedora*)
            name="fedora"
         ;;
      esac
      version=$(echo $release | sed 's/.*\([[:digit:]]\).*/\1/g')
      DISTRO="${name}-${version}"
   elif [ -f /etc/lsb-release ]; then
      . /etc/lsb-release
      DISTRO="${DISTRIB_ID}-${DISTRIB_RELEASE}"
   elif grep -R "Amazon Linux" "/etc/system-release" >/dev/null 2>&1; then
      DISTRO="amzn64"
   fi

   OS_NAME=$(uname -s)
   MARCH=$(uname -m)
   DISTRO=$(echo "$OS_NAME-$DISTRO-$MARCH" | tr '[:upper:]' '[:lower:]')

   echo $DISTRO
}

get_distro
