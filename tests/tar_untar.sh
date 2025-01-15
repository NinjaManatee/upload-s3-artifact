#!/bin/bash
#
# Sets up environment variables and does a dry run execution of main.sh to test taring the file. Creates files to be 
# tarred for testing.
#
# Usage: tar_untar.sh

#region set up environment variables
echo "Initializing variables"
export INPUT_NAME="tempArchiveName"
export INPUT_PATH="./tmp"
export INPUT_IF_NO_FILES_FOUND="warn"
export INPUT_RETENTION_DAYS="7"
export INPUT_COMPRESSION_LEVEL="6"
export INPUT_OVERWRITE="false"
export INPUT_INCLUDE_HIDDEN_FILES="false"
export RUNNER_OS="Windows"
export GITHUB_REPOSITORY="foo/bar"
export GITHUB_RUN_ID="1"
export ENV_S3_ARTIFACTS_BUCKET="this-is-an-s3-bucket-name"
export ENV_AWS_ACCESS_KEY_ID=""
export ENV_AWS_SECRET_ACCESS_KEY=""
export DRY_RUN=true

# variables needed, but are usually defined by the GitHub runner
export RUNNER_TEMP="$TEMP"
export RUNNER_DEBUG=true
#endregion

#region generate test files
echo "Generating test files"
mkdir -p "$INPUT_PATH"
mkdir -p "$INPUT_PATH/folder1"
mkdir -p "$INPUT_PATH/folder2"

touch "$INPUT_PATH/file1.txt"
touch "$INPUT_PATH/folder1/file2.txt"
touch "$INPUT_PATH/folder2/file3.txt"
#endregion

#region run main script
echo "Running main.sh"
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
ARTIFACT_PATH=$(source "$DIR/../scripts/main.sh")
echo "artifact path: $ARTIFACT_PATH"
#endregion

#region untar archive to a different directory
echo "Testing untar"
OUTPUT_PATH="./newTemp"
tar -xzvf "$ARTIFACT_PATH" -C "$OUTPUT_PATH"
#endregion

#region verify that the untar happened correctly
echo "Comparing folders"
diff -r $INPUT_PATH $OUTPUT_PATH
#endregion

#region clean up
echo "Cleaning up"
rm -rf ./tmp
rm -rf ./newTmp
echo "Done"
#endregion