#!/bin/bash

##########################################################################
# vmd_install - utility to automatically build a Debian package of VMD for Docker
# Url        : https://github.com/0x1fff/docker-vmd
# Date       : 2014-12-30
# Category   : Utility
##########################################################################

function myfatal {
	if [ "${1}" -ne 0 ] ; then
		echo "${2}" >&2
		exit $1
	fi
}


BUILD_DOCKER="YES"

VMD_ARCHIVE_PATH=$1
VMD_VERSION="0.0"
VMD_BUILD_TARGET="LINUXAMD64"
VMD_CONFIGURE_OPTS="TK OPENGL TCL PTHREADS FLTK PYTHON NETCDF NUMPY"

# Paths to libs:
export TCL_INCLUDE_DIR="/usr/include/tcl8.5/" # location of tcl headers
export TCL_LIBRARY_DIR="/usr/lib/tcl8.5/" # location of tcl library files
export FLTK_LIBRARY='/usr/lib/libfltk.a'
export PYTHON_INCLUDE_DIR="/usr/include/python2.7/"

MYPWD=`pwd`
VMD_PKG_DIR="${MYPWD}/vmd-deb/"


# Get VMD version from archive filename
get_vmd_version() {
	URI=$1
	local VMD_VERSION="${URI}"
	VMD_VERSION=${VMD_VERSION##*-}
	echo ${VMD_VERSION/.src.tar.gz/}
}

##########################################################################
######## MAIN
##########################################################################

if [ $# -ne 1 -a $# -ne 2 ] ; then 
    myfatal 255 "usage: "$0" <vmd_file.tar.gz>" 
fi 

if [ ! -f "${VMD_ARCHIVE_PATH}" -o ! -r "${VMD_ARCHIVE_PATH}" ] ; then
    myfatal 254 "File ${VMD_ARCHIVE_PATH} is not readable file"
fi

echo "##################################################"
echo "# VMD Package build script for Dockerized Debian #"
echo "##################################################"

# Get DISTRIB_DESCRIPTION
DISTRIB_DESCRIPTION=`uname -a`
KERNEL_VERSION=`uname -a`
if [ -e /etc/lsb-release ] ; then
	. /etc/lsb-release
elif [ -e /etc/debian_version ] ; then
	DISTRIB_DESCRIPTION="Debian "`cat /etc/debian_version`
fi

echo ">>>    OS version: ${DISTRIB_DESCRIPTION}"
echo ">>>    Linux Kernel version: ${KERNEL_VERSION}"




# Make it case insensitive
VMD_ARCHIVE_PATH=`readlink -e "${VMD_ARCHIVE_PATH}"`
myfatal $? "Unable to find absolute path to VMD archive!"

echo ">>>    Checking dependencies ..."
VMD_CONFIGURE_OPTS="${VMD_BUILD_TARGET} ${VMD_CONFIGURE_OPTS}"
VMD_CONFIGURE_OPTS="$(echo "${VMD_CONFIGURE_OPTS}" | tr '[:lower:]' '[:upper:]')"

BUILD_DEPS="build-essential"
BIN_DEPS="perl csh libstdc++5 libc6"
for OPT in $VMD_CONFIGURE_OPTS ; do 
        case "$OPT" in
		LINUX*) VMD_BUILD_TARGET=$OPT
                ;;
		OPENGL) BUILD_DEPS="${BUILD_DEPS} libglu1-mesa-dev"
                BIN_DEPS="${BIN_DEPS} libglu1-mesa"
                ;;
        PTHREADS) 
                ;;
        PYTHON) BUILD_DEPS="${BUILD_DEPS} python-dev"
        		BIN_DEPS="${BIN_DEPS} python python-netcdf python"
                ;;
        NUMPY)  BIN_DEPS="${BIN_DEPS} python-numpy"
                ;;
        NETCDF) BUILD_DEPS="${BUILD_DEPS} libnetcdf-dev"
				BIN_DEPS="${BIN_DEPS} python-netcdf libnetcdff5 libnetcdfc7 libnetcdfc++4 libcf0"
                ;;
        MESA)  	BUILD_DEPS="${BUILD_DEPS} x11proto-gl-dev mesa-common-dev libglu1-mesa-dev"
			    BIN_DEPS="${BIN_DEPS} fontconfig libglu1-mesa libgl1-mesa-dri libgl1-mesa-glx"
                ;;
        TCL)	BIN_DEPS="${BIN_DEPS} tcllib"
                ;;
        TK)		BUILD_DEPS="${BUILD_DEPS} tk8.5-dev"
                BIN_DEPS="${BIN_DEPS} tk8.5"
                ;;
        FLTK)	BUILD_DEPS="${BUILD_DEPS} libfltk1.1-dev libxft-dev"
                BIN_DEPS="${BIN_DEPS} libfltk1.1 libxft2"
                ;;
        LIBTACHYON) myfatal 244 "TACHYON option is not currently supported"
                ;;
        *) myfatal 255 "This script won't provide dependency for ... "
                ;;
        esac
done

read -a BUILD_DEPS_ARR <<<"${BUILD_DEPS}"
read -a BIN_DEPS_ARR <<<"${BIN_DEPS}"

echo ">>>    Installing dependencies ..."
apt-get update  -qy
myfatal $? "apt-get update failed"
apt-get upgrade -qy
myfatal $? "apt-get upgrade failed"

apt-get install -qy ${BIN_DEPS_ARR[@]} 
myfatal $? "apt-get bin dependencies failed ${BIN_DEPS}"
apt-get install -qy ${BUILD_DEPS_ARR[@]}
myfatal $? "apt-get compile dependencies failed ${BUILD_DEPS}"



###
### Start compilation:
###
VMD_VERSION=`get_vmd_version ${VMD_ARCHIVE_PATH}`

echo ">>>    Unpacking sources ..."
mkdir -p "${VMD_PKG_DIR}"
myfatal $? "Unable to create directory ${VMD_PKG_DIR}"

cd "${VMD_PKG_DIR}"
myfatal $? "Unable to change directory ${VMD_PKG_DIR}"

tar xzf "${VMD_ARCHIVE_PATH}"
myfatal $? "Unable to unpack VMD sources"

echo ">>>    Cleaning sources ..."
find . -type d -name 'CVS' -prune -exec rm -rf "{}" \;
find . -type f -iname '*.o' -exec rm -rf "{}" \;
find . -type f -iname '.cvsignore' -exec rm -rf "{}" \;
runnables=$(find . -type f -print0 | xargs -0 file | awk '$2 ~ /^ELF/ {print $1}' | sed 's/:$//')
rm -f ${runnables}
myfatal $? "Unable to clean up sources"

mv vmd*/* .
myfatal $? "Unable to move VMD sources"

rmdir vmd*
myfatal $? "Remove empty VMD directory"

## Build plugins
echo ">>>    Starting plugins compilation ..."
cd plugins
INSTALL_ROOT="${VMD_PKG_DIR}/debian/tmp/"
export PLUGINDIR="${INSTALL_ROOT}/usr/local/lib/vmd/plugins/"

make "${VMD_BUILD_TARGET}" TCLINC="-I${TCL_INCLUDE_DIR}" TCLLIB="-L${TCL_LIBRARY_DIR}"
myfatal $? "Problem with plugins compilation" 

echo "Copying plugins to "${PLUGINDIR}
make distrib
myfatal $? "Problem with plugin installation - permissions?" 
cd ..
## End build plugins

### BUILD VMD
echo ">>>    Starting VMD sources configuration ..."
# Name of shell script used to start program; this is the name used by users
export VMDINSTALLNAME="vmd"

# Directory where VMD startup script is installed, should be in users' paths.
INST_DIR="${VMD_PKG_DIR}/debian/tmp/"
VMD_BIN_DIR="/usr/local/bin/"
export VMDINSTALLBINDIR="${INST_DIR}${VMD_BIN_DIR}"

# Directory where VMD files and executables are installed
VMD_LIB_DIR="/usr/local/lib/vmd/"
export VMDINSTALLLIBRARYDIR="${INST_DIR}${VMD_LIB_DIR}"


echo "${VMD_CONFIGURE_OPTS}" > configure.options

./configure
myfatal $? "Problem with ./configure script"

# go to source directory
cd src
echo ">>>    Patching Makefiles ..."
perl -p -i.bak -e 's#(^INCDIRS.*?)$#$1 -I'${PLUGINDIR}/${VMD_BUILD_TARGET}'/molfile/ -I'${TCL_INCLUDE_DIR}' -I'${PYTHON_INCLUDE_DIR}'#g' Makefile
perl -p -i.bak -e 'if (/^LIBS\s+/) { s#-lmolfile_plugin#'${PLUGINDIR}'/'${VMD_BUILD_TARGET}'/molfile/libmolfile_plugin.a#g; }' Makefile
perl -p -i.bak -e 'if (/^LIBS\s+/) { s#-lutil##g; }' Makefile
perl -p -i.bak -e 'if (/^LIBS\s+/) { s#-lnetcdf##g; }' Makefile
perl -p -i.bak -e 's/python2.5/python2.7/mgs' Makefile

echo ">>>    Starting VMD compilation ..."
make
myfatal $? "Compilation problem"

echo ">>>    Starting VMD installation to temporay directory ${INST_DIR}"
make install
myfatal $? "Problem with VMD main program copy"

echo ">>>    Build process of VMD sources completed successfully"


###
echo ">>>    Starting deb package creation ..."
echo ">>>    Patching run script"
perl -p -i -e 's#^(set defaultvmddir=).*#$1"'${VMD_LIB_DIR}'"#g;' "${VMDINSTALLBINDIR}/vmd"

echo ">>>    Creating deb package structure ..."
cd "${VMD_PKG_DIR}"
mkdir -p debian/tmp/DEBIAN
myfatal $? "Unable to create Debian package"

cat <<EOF >debian/changelog
vmd (${VMD_VERSION}-1) UNRELEASED; urgency=low

  * Initial release.

 -- Anonymous <anonymous@anonymous.com>  Thu, 18 Nov 2010 17:25:32 +0000
EOF
cat <<EOF >debian/control
Source: vmd
Standards-Version: ${VMD_VERSION}
Maintainer: Anonymous<anonymous@anonymous.com>
Section: non-free/science
Priority: optional
Build-Depends: debhelper (>= 9)
Homepage: http://www.ks.uiuc.edu/Research/vmd/

Package: vmd
Architecture: $(dpkg-architecture -qDEB_BUILD_ARCH)
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: VMD - Visual Molecular Dynamics
EOF

echo ">>>    Checking shared libraries ..."
elfs=$(find debian/tmp/ -type f -print0 | xargs -0 file | awk '/ELF.*dynamically linked/ {print $1}' | sed 's/:$//')
dpkg-shlibdeps ${elfs}
myfatal $? "Generating dpkg-shlibdeps failed"

echo "misc:Depends=python (>= 2.2), python-support (>= 0.90.0), csh (>=20110502)" >> debian/substvars

echo ">>>    Generating deb package ..."
dpkg-gencontrol
myfatal $? "Generating dpkg-gencontrol failed"

VMD_DEB_NAME="vmd-${VMD_VERSION}.deb"
fakeroot dpkg-deb -b debian/tmp "${MYPWD}/${VMD_DEB_NAME}"
myfatal $? "Creating *.deb failed"

echo ">>>    Installing package ..."
dpkg -i "${MYPWD}/${VMD_DEB_NAME}"
myfatal $? "VMD installation failed"


### 
###### Clean up
if [ "${BUILD_DOCKER}" == "YES" ] ; then
    echo ">>>    Removing downloaded packages and build dependencies"
    cd "${MYPWD}"
    myfatal $? "Error changing direcotry to ${MYPWD}"

    rm -rf "${VMD_ARCHIVE_PATH}" "${VMD_PKG_DIR}"
    myfatal $? "Removing vmd failed"

    apt-get remove -y -auto-remove --purge ${BUILD_DEPS_ARR[@]}
    myfatal $? "Removing build time dependencies failed"
    apt-get autoremove -y
    myfatal $? "Auto-Removing build time dependencies failed"
    rm -rf /var/lib/apt/lists/*
    myfatal $? "Removing /var/lib/apt/lists/ failed"
    rm -rf /var/cache/apt/archives/*
    myfatal $? "Removing /var/cache/apt/archives/ failed"
fi

echo "####################################"
echo "# Installation completed            "
echo "####################################"


