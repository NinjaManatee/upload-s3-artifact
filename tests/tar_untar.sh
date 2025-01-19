#!/bin/bash
#
# Sets up environment variables and does a dry run execution of main.sh to test taring the file. Creates files to be 
# tarred for testing.
#
# Usage: tar_untar.sh

#region initialize common environment variables
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
export GITHUB_OUTPUT=/dev/null
export GITHUB_STEP_SUMMARY=/dev/null
#endregion

#region upload folder with sub-folders
#region set up environment variables
echo "Initializing variables"
export INPUT_NAME="tempArchiveName"
export INPUT_PATH="./tmp"
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
# shellcheck disable=SC1091
source "$DIR/../scripts/main.sh"
# shellcheck disable=SC1091
source "./tmp.txt"
echo "artifact path: $ARTIFACT_PATH"
#endregion

#region untar archive to a different directory
echo "Testing untar"
OUTPUT_PATH="./newTemp1"
mkdir -p "$OUTPUT_PATH"
tar -xzvf "$ARTIFACT_PATH" -C "$OUTPUT_PATH"
#endregion

#region verify that the untar happened correctly
echo "Comparing folders"
diff -r "$INPUT_PATH" "$OUTPUT_PATH"
#endregion
#endregion

#region upload single file
#region set up environment variables
echo "Initializing variables"
export INPUT_NAME="tempArchiveName"
export INPUT_PATH="testFile.txt"
#endregion

#region generate test file
touch "$INPUT_PATH"
#endregion

#region run main script
echo "Running main.sh"
# shellcheck disable=SC1091
source "$DIR/../scripts/main.sh"
# shellcheck disable=SC1091
source "./tmp.txt"
echo "artifact path: $ARTIFACT_PATH"
#endregion

#region untar archive to a different directory
echo "Testing untar"
OUTPUT_PATH="./newTemp2"
mkdir -p "$OUTPUT_PATH"
tar -xzvf "$ARTIFACT_PATH" -C "$OUTPUT_PATH"
#endregion

#region verify that the untar happened correctly
echo "Comparing folders"
diff -r "$INPUT_PATH" "$OUTPUT_PATH"
#endregion
#endregion

#region upload single file from subdirectory
#region set up environment variables
echo "Initializing variables"
export INPUT_NAME="tempArchiveName"
export INPUT_PATH="tmp/folder1"
#endregion

#region run main script
echo "Running main.sh"
# shellcheck disable=SC1091
source "$DIR/../scripts/main.sh"
# shellcheck disable=SC1091
source "./tmp.txt"
echo "artifact path: $ARTIFACT_PATH"
#endregion

#region untar archive to a different directory
echo "Testing untar"
OUTPUT_PATH="./newTemp3"
mkdir -p "$OUTPUT_PATH"
tar -xzvf "$ARTIFACT_PATH" -C "$OUTPUT_PATH"
#endregion

#region verify that the untar happened correctly
echo "Comparing folders"
diff -r "$INPUT_PATH" "$OUTPUT_PATH"
#endregion
#endregion