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
#   - S3_ARTIFACTS_BUCKET - the name of the AWS S3 bucket to use
#   - AWS_ACCESS_KEY_ID - the AWS access key ID (optional if uploading to a public S3 bucket)
#   - AWS_SECRET_ACCESS_KEY - the AWS secret access key (optional if uploading to a public S3 bucket)
#   - DRY_RUN - whether to run without uploading to AWS (optional, set to true to enable dry run)
#
# based on open-turo/actions-s3-artifact
# see: https://github.com/open-turo/actions-s3-artifact/blob/main/upload/action.yaml

# exit immediately if an error occurs
set -e

#region import scripts
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
# shellcheck disable=SC1091
source "$DIR/encoding.sh"
#endregion

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
echo "::debug::    S3_ARTIFACTS_BUCKET:       $S3_ARTIFACTS_BUCKET"
echo "::debug::    AWS_ACCESS_KEY_ID:         $AWS_ACCESS_KEY_ID"
echo "::debug::    AWS_SECRET_ACCESS_KEY:     $AWS_SECRET_ACCESS_KEY"
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
    if [[ "$AWS_ACCESS_KEY_ID" == "" || "$AWS_SECRET_ACCESS_KEY" == "" ]]; then
        echo "::warn::AWS_ACCESS_KEY_ID and/or AWS_SECRET_ACCESS_KEY is missing from environment variables."
    fi

    # check whether S3_ARTIFACTS_BUCKET is defined
    if [[ "$S3_ARTIFACTS_BUCKET" == "" ]]; then
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
TMP_DIRECTORY="$(mktemp -d -p "$TMP_ARTIFACT" "upload.XXXXXXXX")"
mkdir -p "$TMP_DIRECTORY"
echo "::debug::Created temporary directory $TMP_DIRECTORY"

# assign the tarball file name for future use
TMP_TAR="$TMP_DIRECTORY/artifacts.tgz"
echo "::debug::Tarball path is $TMP_TAR"

# create a path within our temporary directory to collect all the artifacts
TMP_ARTIFACT="$TMP_DIRECTORY/artifacts"
mkdir -p "$TMP_ARTIFACT"
echo "::debug::Created artifact directory $TMP_ARTIFACT"
#endregion

#region populate artifact directory
echo "::debug::Reading the path string ($INPUT_PATH) into an array"
read -r ARTIFACT_PATHS <<< "$INPUT_PATH"

# exclude hidden files, if necessary
if [[ "$INPUT_INCLUDE_HIDDEN_FILES" ]]; then
    echo "::debug::including hidden files"
    shopt -s globstar dotglob
else
    echo "::debug::excluding hidden files"
    shopt -s globstar
fi

# iterate through each artifact path and copy it to the temporary path
for name in "${ARTIFACT_PATHS[@]}"; do
    # check whether the path is an exclude and delete files in exclude from TMP_ARTIFACT
    if [[ "$name" == ^!.* ]]; then
        echo "::debug::Deleting $name"
        # remove first character
        name="${name:1}"

        # delete file
        # TODO: Is this working correctly? Do I want to be using "." here?
        relativePath=$(realpath --relative-to="." "$name")
        if [[ "${relativePath#".."}" != "${relativePath}" ]]; then
            echo "::error::Path $name isn't a subdirectory of the current directory! Not deleting."
        else
            rm -rf "$name"
        fi
    else
        if [[ -e "$name" || -z "$name" ]]; then
            echo "::debug::$name exists and has files"
            echo "::debug::Adding contents of $name"
            echo "::debug::$(ls "$name" 2>&1)"

            # check whether it is a file or a folder to copy
            if [[ -f "$name" ]]; then
                # file to copy
                # get file name
                FILENAME=$(basename "$name")
                # append file name to TMP_ARTIFACT
                NEW_FILE_PATH="$TMP_ARTIFACT/$FILENAME"
                echo "::debug::cp \"$name\" \"$NEW_FILE_PATH\""
                cp "$name" "$NEW_FILE_PATH"
                echo "::debug::$name copied to $NEW_FILE_PATH"
            else
                # folder to copy
                echo "::debug::cp -aT \"$name\" \"$TMP_ARTIFACT\""
                cp -aT "$name" "$TMP_ARTIFACT"
                echo "::debug::$name copied to $TMP_ARTIFACT"
            fi
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

# unset globbing
shopt -u globstar dotglob

# list out everything in the temporary path
echo "::debug::Contents of our temporary directory"
if [[ "$RUNNER_OS" = "Windows" ]]; then
    echo "::debug::$(cmd //c tree //f "$TMP_DIRECTORY")"
else
    echo "::debug::$(tree -a "$TMP_DIRECTORY" 2>&1)"
fi
#endregion

#region tarball the temporary path into a single object
# create tar
echo "::debug::GZIP=-$INPUT_COMPRESSION_LEVEL tar -zcvf '$TMP_TAR' -C '$TMP_ARTIFACT' ."
GZIP=-$INPUT_COMPRESSION_LEVEL tar -zcvf "$TMP_TAR" -C "$TMP_ARTIFACT" .

# List the actual contents of the archive
if [[ -n "$RUNNER_DEBUG" ]]; then
    echo "::debug::Artifact contents"
    echo "::debug::$(tar -ztvf "$TMP_TAR" 2>&1)"
fi
#endregion

#region upload artifact tarball to S3 bucket
# Get AWS S3 bucket URI and ensure it starts with "s3://"
S3URI="$S3_ARTIFACTS_BUCKET"
if [[ "$S3URI" != s3://* ]]; then
    echo "::debug::Adding s3:// to bucket URI"
    S3URI="s3://$S3URI"
fi

# Build key to object in S3 bucket
REPO="$GITHUB_REPOSITORY"
RUN_ID="$GITHUB_RUN_ID"
ENCODED_FILENAME="$(urlencode "$INPUT_NAME").tgz"
KEY="$REPO/$RUN_ID/$ENCODED_FILENAME"
S3URI="${S3URI%/}/$KEY"

echo "::debug::Uploading \"$TMP_TAR\" to S3 \"$S3URI\""
echo "::debug::aws s3 cp \"$TMP_TAR\" \"$S3URI\""
if [[ "$DRY_RUN" != "true" ]]; then
    aws s3 cp "$TMP_TAR" "$S3URI"
fi
echo "::debug::File uploaded to AWS S3"
#endregion

#region generate outputs
# create presigned URL to download the artifact. AWS CLI expects expiration to be in seconds
EXPIRES_IN=$((INPUT_RETENTION_DAYS * 24 * 60 * 60))
echo "::debug::aws s3 presign \"$S3URI\" --expires-in $EXPIRES_IN"
if [[ "$DRY_RUN" != "true" ]]; then
    # Presigned URL doesn't work correctly if ENV_AWS_ACCESS_KEY_ID is a secret in GitHub. If it in the generated URL, 
    # so if it is a secret, GitHub replaces it with '***', which causes the URL to fail
    PRESIGNED_URL=$(aws s3 presign "$S3URI" --expires-in $EXPIRES_IN)
    echo "::debug::Presigned URL created: '$PRESIGNED_URL'"
fi

# get the SHA256 checksum of the uploaded tarball
ARTIFACT_HASH=$(echo -n "$TMP_TAR" | sha256sum)

# create outputs and summary
echo "artifact-url=$PRESIGNED_URL" >> "$GITHUB_OUTPUT"
echo "artifact-digest=$ARTIFACT_HASH" >> "$GITHUB_OUTPUT"
echo "::debug::The presigned URL is $PRESIGNED_URL"
echo "::debug::The artifact sha256 is $ARTIFACT_HASH"

NUM_BYTES=$(stat --printf="%s" "$TMP_TAR")
FORMATTED_BYTES=$(numfmt --to=iec "$NUM_BYTES")
echo "[$INPUT_NAME]($PRESIGNED_URL)&nbsp;&nbsp;&nbsp;&nbsp;$S3URI&nbsp;&nbsp;&nbsp;&nbsp;${FORMATTED_BYTES}B" >> "$GITHUB_STEP_SUMMARY"
#endregion

#region clean up temp dir
# TODO: move to clean up step?
if [[ "$DRY_RUN" != "true" ]]; then
    rm -rf "$TMP_ARTIFACT"
else
    echo "ARTIFACT_PATH=$TMP_TAR" > tmp.txt
fi
#endregion