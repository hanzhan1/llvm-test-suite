#!/bin/sh

RELEASE_PKG_NAME="dpcpp-compiler.tar.gz"
UNZIP_PATH=$1
CURL_PREFIX="proxychains curl -H 'Accept: application/vnd.github.v3+json' "
RELEASE_URL="https://api.github.com/repos/intel/llvm/releases"
# Command line parameters:
export http_proxy=http://proxy-dmz.intel.com:911
export https_proxy=http://proxy-dmz.intel.com:912

lastest_tag=`${CURL_PREFIX} ${RELEASE_URL} | grep tag_name | head -1 | cut -d '"' -f 4`

REGEX='sycl-nightly/[0-9]{4}[0-9]{2}[0-9]{2}$'
if [[ $lastest_tag =~ $REGEX ]]; then
    echo "get latest release tag: ${lastest_tag}"
    ${CURL_PREFIX} ${RELEASE_URL}/tags/${lastest_tag} | grep browser_download_url | cut -d '"' -f 4 | wget -qi -

    if [ -f ${RELEASE_PKG_NAME} ]; then
        tar -xzf ${RELEASE_PKG_NAME} -C ${UNZIP_PATH}
        mv dpcpp_compiler llvm.obj
    else
        echo "error wget latest release package"
        exit 2
    fi
else
    echo "cannot find latest release tag"
    exit 1
fi

exit 0