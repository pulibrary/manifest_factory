#!/bin/bash

#
# IIIF Manifests from PUL METS
# Usage: $ ./build.sh <path_to_src_mets>
#

if [ "x$1" != "x" ]; then
  INPUT_METS=$(readlink -f $1)
  echo "HERE"
fi

# Get the directory of the script 
# cf. http://stackoverflow.com/a/246128/714478
get_script_dir() {
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  echo "$( cd -P "$( dirname "$SOURCE" )" && pwd )"
}

BIN=$(get_script_dir)
LIB=$(readlink -f $BIN/../lib)
SAXON="$LIB/saxon9he.jar"
MANIFEST_XQ="$LIB/to_manifest.xql"

# Run the XQ
cmd="java -cp $SAXON net.sf.saxon.Query -q:$MANIFEST_XQ"
if [ "x$INPUT_METS" != "x" ]; then
  cmd="$cmd doc-path=$INPUT_METS"
fi
big_json_string=$($cmd)

# If it worked, make it pretty and dump it.
if [ $? == 0 ]; then
  echo $big_json_string | python -m json.tool
fi
