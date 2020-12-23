#!/bin/sh

RELEASE_PKG_NAME="dpcpp-compiler.tar.gz"
UNZIP_PATH=$1

# Command line parameters:
export http_proxy=http://proxy-dmz.intel.com:911
export https_proxy=http://proxy-dmz.intel.com:912

lastest_tag=`proxychains curl \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/intel/llvm/releases \
  | grep tag_name | head -1 \
  | cut -d '"' -f 4`

REGEX='sycl-nightly/[0-9]{4}[0-9]{2}[0-9]{2}$'
if [[ $lastest_tag =~ $REGEX ]]; then
    echo "get latest release tag: ${lastest_tag}"
    proxychains curl \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/intel/llvm/releases/tags/sycl-nightly/20201222 \
    | grep browser_download_url \
    | cut -d '"' -f 4 \
    | wget -qi -

    if [ -f ${RELEASE_PKG_NAME} ]; then
        tar -xzf ${RELEASE_PKG_NAME}
    fi
else
    echo "cannot find latest release tag"
    exit 1
fi

exit 0