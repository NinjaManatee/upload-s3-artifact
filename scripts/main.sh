#!/bin/bash
# Zips files/directories into a tarball and uploads it to AWS S3.
#
# Usage: main.sh
#
# The following environment variables must be defined:
#   - INPUT_NAME - The name of the artifact
#   - INPUT_PATH - The path to be archived
#   - INPUT_IF_NO_FILES_FOUND - what should be done when no files are found (warn, ignore, error)
#   - INPUT_RETENTION_DAYS - the number of days the presigned URL should be valid for (number greater than 1)
#   - INPUT_COMPRESSION_LEVEL - the compression level to use for tar (1-9)
#   - INPUT_OVERWRITE - whether to overwrite existing archive (true/false)
#   - INPUT_INCLUDE_HIDDEN_FILES - whether to include hidden files in the artifact (true/false)
#   - RUNNER_OS - the OS of the runner
#   - GITHUB_REPOSITORY - the repository the artifact is associated with
#   - GITHUB_RUN_ID - the run ID the artifact is associated with
#   - ENV_S3_ARTIFACTS_BUCKET - the name of the AWS S3 bucket to use
#   - ENV_AWS_ACCESS_KEY_ID - the AWS access key ID (optional if uploading to a public S3 bucket)
#   - ENV_AWS_SECRET_ACCESS_KEY - the AWS secret access key (optional if uploading to a public S3 bucket)
#   - DRY_RUN - whether to run without uploading to AWS (optional, set to true to enable dry run)
#
# based on open-turo/actions-s3-artifact
# see: https://github.com/open-turo/actions-s3-artifact/blob/main/upload/action.yaml

# exit immediately if an error occurs
set -e

#region import scripts
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
source "$DIR/encoding.sh"
#endregion

#region read input arguments
# INPUT_NAME="$1"
# INPUT_PATH="$2"
# INPUT_IF_NO_FILES_FOUND="$3"
# INPUT_RETENTION_DAYS="$4"
# INPUT_COMPRESSION_LEVEL="$5"
# INPUT_OVERWRITE="$6"
# INPUT_INCLUDE_HIDDEN_FILES="$7"
# RUNNER_OS="$8"
# GITHUB_REPOSITORY="$9"
# GITHUB_RUN_ID="${10}"
# ENV_S3_ARTIFACTS_BUCKET="${11}"
# ENV_AWS_ACCESS_KEY_ID="${12}"
# ENV_AWS_SECRET_ACCESS_KEY="${13}"

echo "::debug::Inputs:"
echo "::debug::    name:                      $INPUT_NAME"
echo "::debug::    path:                      $INPUT_PATH"
echo "::debug::    if-no-files-found:         $INPUT_IF_NO_FILES_FOUND"
echo "::debug::    retention-days:            $INPUT_RETENTION_DAYS"
echo "::debug::    compression-level:         $INPUT_COMPRESSION_LEVEL"
echo "::debug::    overwrite:                 $INPUT_OVERWRITE"
echo "::debug::    include-hidden-files:      $INPUT_INCLUDE_HIDDEN_FILES"
echo "::debug::    runner.os:                 $RUNNER_OS"
echo "::debug::    github.repository:         $GITHUB_REPOSITORY"
echo "::debug::    github.run-id:             $GITHUB_RUN_ID"
echo "::debug::    S3_ARTIFACTS_BUCKET:       $ENV_S3_ARTIFACTS_BUCKET"
echo "::debug::    AWS_ACCESS_KEY_ID:         $ENV_AWS_ACCESS_KEY_ID"
echo "::debug::    AWS_SECRET_ACCESS_KEY:     $ENV_AWS_SECRET_ACCESS_KEY"
#endregion

#region validate input variables
# validate script input variables
ERROR=false
if [[ "$INPUT_NAME" == "" ]]; then
    echo "::error::The values of 'INPUT_NAME' input is not specified"
    ERROR=true
fi

if [[ "$INPUT_PATH" == "" ]]; then
    echo "::error::The values of 'INPUT_PATH' input is not specified"
    ERROR=true
fi

if [[ "$INPUT_IF_NO_FILES_FOUND" == "" ]]; then
    echo "::error::The values of 'INPUT_IF_NO_FILES_FOUND' input is not specified"
    ERROR=true
fi

if [[ "$INPUT_RETENTION_DAYS" == "" ]]; then
    echo "::error::The values of 'INPUT_RETENTION_DAYS' input is not specified"
    ERROR=true
fi

if [[ "$INPUT_COMPRESSION_LEVEL" == "" ]]; then
    echo "::error::The values of 'INPUT_COMPRESSION_LEVEL' input is not specified"
    ERROR=true
fi

if [[ "$INPUT_OVERWRITE" == "" ]]; then
    echo "::error::The values of 'INPUT_OVERWRITE' input is not specified"
    ERROR=true
fi

if [[ "$INPUT_INCLUDE_HIDDEN_FILES" == "" ]]; then
    echo "::error::The values of 'INPUT_INCLUDE_HIDDEN_FILES' input is not specified"
    ERROR=true
fi

# validate github actions variables
if [[ "$RUNNER_OS" == "" ]]; then
    echo "::error::The values of 'RUNNER_OS' GitHub variable is not specified"
    ERROR=true
fi

if [[ "$GITHUB_REPOSITORY" == "" ]]; then
    echo "::error::The values of 'GITHUB_REPOSITORY' GitHub variable is not specified"
    ERROR=true
fi

if [[ "$GITHUB_RUN_ID" == "" ]]; then
    echo "::error::The values of 'GITHUB_RUN_ID' GitHub variable is not specified"
    ERROR=true
fi

if [[ "$DRY_RUN" != "true" ]]; then
    # check whether AWS credentials are specified and warn if they aren't
    if [[ "$ENV_AWS_ACCESS_KEY_ID" == "" || "$ENV_AWS_SECRET_ACCESS_KEY" == "" ]]; then
        echo "::warn::AWS_ACCESS_KEY_ID and/or AWS_SECRET_ACCESS_KEY is missing from environment variables."
    fi

    # check whether S3_ARTIFACTS_BUCKET is defined
    if [[ "$ENV_S3_ARTIFACTS_BUCKET" == "" ]]; then
        echo "::error::S3_ARTIFACTS_BUCKET is missing from environment variables."
        ERROR=true
    fi
fi

if [[ "$ERROR" == "true" ]]; then
    echo "::error::Input error(s) - exiting"
    exit 1
else
    echo "::debug::Validation complete"
fi
#endregion

#region create temp directories
echo "::debug::Creating temp directories"
# create our temporary directory parent for our artifacts
TMP_ARTIFACT="$RUNNER_TEMP/upload-s3-artifact"
if [[ "$RUNNER_OS" == "Windows" ]]; then
    # On some windows runners, the path for TMP_ARTIFACT is a mix of windows and unix path (both / and \), which
    # caused errors when un-taring. Converting to unix path resolves this.
    TMP_ARTIFACT=$(cygpath -u "$TMP_ARTIFACT")
fi
mkdir -p "$TMP_ARTIFACT"
echo "::debug::The artifact directory is $TMP_ARTIFACT"

# create a unique directory for this particular action run
TMPDIR="$(mktemp -d -p "$TMP_ARTIFACT" "upload.XXXXXXXX")"
mkdir -p "$TMPDIR"
echo "::debug::Created temporary directory $TMPDIR"

# assign the tarball file name for future use
TMPTAR="$TMPDIR/artifacts.tgz"
echo "::debug::Tarball path is $TMPTAR"

# create a path within our temporary directory to collect all the artifacts
TMPARTIFACT="$TMPDIR/artifacts"
mkdir -p "$TMPARTIFACT"
echo "::debug::Created artifact directory $TMPARTIFACT"
#endregion

#region populate artifact directory
echo "::debug::Reading the path string into an array"
read -a ARTIFACT_PATHS <<< "$INPUT_PATH"
echo "::debug::Inputs read: $ARTIFACT_PATHS"

# iterate through each artifact path and copy it to the temporary path
for name in ${ARTIFACT_PATHS[@]}; do
    # check whether the path is an exclude and delete files in exclude from TMPARTIFACT
    if [[ "$name" == ^!.* ]]; then
        echo "::debug::Deleting $name"
        # remove first character
        name="${name:1}"

        # delete file
        # TODO: Is this working correctly? Do I want to be using "." here?
        relativePath=$(realpath --relative-to="." "$name")
        upperDir=".."
        if [[ "${relativePath#upperDir}" != "${relativePath}" ]]; then
            echo "::error::Path $name isn't a subdirectory of the current directory! Not deleting."
        else
            rm -rf "$name"
        fi
    else
        if [[ -e "$name" || -z "$name" ]]; then
            echo "::debug::$name exists and has files"
            echo "::debug::Adding contents of $name"
            if [[ "$RUNNER_OS" == "Windows" ]]; then
                cmd //c tree //f "$name"
            else
                echo "::debug::$(tree -a 'tmp' 2>&1)"
            fi
    
            COPY_DIR="$TMPARTIFACT/$(dirname "$name")"
            mkdir -p $COPY_DIR
            cp -r "$name" "$COPY_DIR"
            echo "::debug::$name copied to $COPY_DIR"
        else
            case "$INPUT_IF_NO_FILES_FOUND" in
            "warn")
                echo "::warn::$name does not exist or is empty"
                ;;
            "ignore")
                echo "::debug::$name does not exist or is empty"
                ;;
            "error")
                echo "::error::$name does not exist or is empty"
                exit 1
                ;;
            esac
        fi
    fi
done

# List out everything in the temporary path
if [[ -n "$RUNNER_DEBUG" ]]; then
    echo "::debug::Contents of our temporary directory"
    if [[ "$RUNNER_OS" = "Windows" ]]; then
        # TODO: Can I make this debug somehow?
        cmd //c tree //f "$TMPDIR"
    else
        echo "::debug::$(tree -a '$TMPDIR' 2>&1)"
    fi
fi
#endregion

#region tarball the temporary path into a single object
# exclude hidden files, if necessary
if ! [[ "$INPUT_INCLUDE_HIDDEN_FILES" ]]; then
    echo "::debug::Excluding hidden files"
    exclude=-"-exclude='.*'"
fi

# create tar
echo "::debug::GZIP=-$INPUT_COMPRESSION_LEVEL tar $exclude -zcvfx '$TMPTAR' -C '$TMPARTIFACT' ."
GZIP=-$INPUT_COMPRESSION_LEVEL tar $exclude -zcvf "$TMPTAR" -C "$TMPARTIFACT" .

# TODO: Delete this when it is no longer necessary
# original tar command from other repo. Am I missing something important? What does --transform and
# --show-transformed do?
# tar -czvf "$TMPTAR" -C "$TMPARTIFACT" --transform='s/^\.\///' --show-transformed .

# List the actual contents of the archive
if [[ -n "$RUNNER_DEBUG" ]]; then
    echo "::debug::Artifact contents"
    echo "$(tar -ztvf "$TMPTAR" 2>&1)"
fi
#endregion

#region upload artifact tarball to S3 bucket
# Get AWS S3 bucket URI and ensure it starts with "s3://"
S3URI="$ENV_S3_ARTIFACTS_BUCKET"
if [[ "$S3URI" != s3://* ]]; then
    echo "::debug::Adding s3:// to bucket URI"
    S3URI="s3://$S3URI"
fi

# Build key to object in S3 bucket
REPO="$GITHUB_REPOSITORY"
RUN_ID="$GITHUB_RUN_ID"
ENCODED_FILENAME="$(urlencode $INPUT_NAME).tgz"
KEY="$REPO/$RUN_ID/$ENCODED_FILENAME"
S3URI="${S3URI%/}/$KEY"

echo "::debug::Uploading \"$TMPTAR\" to S3 \"$S3URI\""
echo "::debug::aws s3 cp \"$TMPTAR\" \"$S3URI\""
if [[ "$DRY_RUN" != "true" ]]; then
    aws s3 cp "$TMPTAR" "$S3URI"
fi
echo "::debug::File uploaded to AWS S3"
#endregion

#region generate outputs
# create presigned URL to download the artifact. AWS CLI expects expiration to be in seconds
EXPIRES_IN=$((INPUT_RETENTION_DAYS * 24 * 60 * 60))
echo "::debug::PRESIGNED_URL=$\(aws s3 presign \"$S3URI\" --expires-in $EXPIRES_IN\)"

if [[ "$DRY_RUN" != "true" ]]; then
    # TODO: Presigned URL doesn't appear to be working correctly
    PRESIGNED_URL=$(aws s3 presign "$S3URI" --expires-in $EXPIRES_IN)
    echo "::debug::Presigned URL created: '$PRESIGNED_URL'"
fi

# create outputs and summary
echo "artifact-url=$PRESIGNED_URL" >> $GITHUB_OUTPUT
ARTIFACT_HASH=$(echo -n $TMPARTIFACT | sha256sum)
echo "artifact-urlartifact-digest=$(echo -n $TMPARTIFACT | sha256sum)" >> $GITHUB_OUTPUT
echo "::debug::The presigned URL is $PRESIGNED_URL"
echo "::debug::The artifact sha256 is $ARTIFACT_HASH"

NUM_BYTES=$(stat --printf="%s" "$TMPARTIFACT")
FORMATTED_BYTES=$(numfmt --to=iec $NUM_BYTES)
echo "[$INPUT_NAME]($PRESIGNED_URL)&nbsp;&nbsp;&nbsp;&nbsp;'$FORMATTED_BYTES'B" >> $GITHUB_STEP_SUMMARY
#endregion

#region clean up temp dir
# TODO: move to clean up step?
if [[ "$DRY_RUN" != "true" ]]; then
    rm -rf "$TMP_ARTIFACT"
else
    printf "ARTIFACT_PATH=$TMPTAR" > tmp.txt
fi
#endregion