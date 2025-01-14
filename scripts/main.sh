#!/bin/bash
# Zips files/directories into a tarball and uploads it to AWS S3.
#
# based on open-turo/actions-s3-artifact
# see: https://github.com/open-turo/actions-s3-artifact/blob/main/upload/action.yaml

#region import scripts
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/encoding.sh"
#endregion

#region validate input variables
# validate script input variables
if [[ "$INPUT_NAME" == "" ]]; then
    echo "::error::The values of 'NAME' input is not specified"
fi

if [[ "$INPUT_PATH" == "" ]]; then
    echo "::error::The values of 'PATH' input is not specified"
fi

if [[ "$INPUT_IF_NO_FILES_FOUND" == "" ]]; then
    echo "::error::The values of 'IF_NO_FILES_FOUND' input is not specified"
fi

if [[ "$INPUT_RETENTION_DAYS" == "" ]]; then
    echo "::error::The values of 'RETENTION_DAYS' input is not specified"
fi

if [[ "$INPUT_COMPRESSION_LEVEL" == "" ]]; then
    echo "::error::The values of 'COMPRESSION_LEVEL' input is not specified"
fi

if [[ "$INPUT_OVERWRITE" == "" ]]; then
    echo "::error::The values of 'overwrite' input is not specified"
fi

if [[ "$INPUT_INCLUDE_HIDDEN_FILES" == "" ]]; then
    echo "::error::The values of 'INCLUDE_HIDDEN_FILES' input is not specified"
fi

# validate github actions variables
if [[ "$RUNNER_OS" == "" ]]; then
    echo "::error::The values of 'RUNNER_OS' GitHub variable is not specified"
fi

if [[ "$GITHUB_REPOSITORY" == "" ]]; then
    echo "::error::The values of 'GITHUB_REPOSITORY' GitHub variable is not specified"
fi

if [[ "$GITHUB_RUN_ID" == "" ]]; then
    echo "::error::The values of 'GITHUB_RUN_ID' GitHub variable is not specified"
fi

# check whether AWS credentials are specified and warn if they aren't
if [[ "$ENV_AWS_ACCESS_KEY_ID" == "" || "$ENV_AWS_SECRET_ACCESS_KEY" == "" ]]; then
    echo "::warn::AWS_ACCESS_KEY_ID and/or AWS_SECRET_ACCESS_KEY is missing from environment variables."
fi

# check whether S3_ARTIFACTS_BUCKET is defined
if [[ "$ENV_S3_ARTIFACTS_BUCKET" == "" ]]; then
    echo "::error::S3_ARTIFACTS_BUCKET is missing from environment variables."
    exit 1
fi
#endregion

#region create temp directories
# Create our temporary directory parent for our artifacts
TMP_ARTIFACT="$RUNNER_TEMP/upload-s3-artifact"
if [[ "$RUNNER_OS" == "Windows" ]]; then
    # On some windows runners, the path for TMP_ARTIFACT is a mix of windows and unix path (both / and \), which
    # caused errors when un-taring. Converting to unix path resolves this.
    TMP_ARTIFACT=$(cygpath -u "$TMP_ARTIFACT")
fi
mkdir -p "$TMP_ARTIFACT"

# Create a unique directory for this particular action run
TMPDIR="$(mktemp -d -p "$TMP_ARTIFACT" "upload.XXXXXXXX")"
echo "::debug::Created temporary directory $TMPDIR"

# Assign the tarball file name for future use
TMPTAR="$TMPDIR/artifacts.tgz"

# Create a path within our temporary directory to collect all the artifacts
TMPARTIFACT="$TMPDIR/artifacts"
mkdir -p "$TMPARTIFACT"
echo "::debug::Created artifact directory $TMPARTIFACT"
#endregion

#region populate artifact directory
# Read the path string into a bash array for easy looping
read -a ARTIFACT_PATHS <<<"$INPUT_PATH"
echo "::debug::Inputs read: $ARTIFACT_PATHS"

# iterate through each artifact path and copy it to the temporary path
for name in ${ARTIFACT_PATHS[@]}; do
    if [[ -z "$name" ]]; then
        echo "::debug::Skipping empty"
        continue
    fi

    if [[ -n "$RUNNER_DEBUG" ]]; then
        echo "::debug::Contents of path"
        echo "$(tree -a "$name" 2>&1)"
    fi

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
        echo "Adding '$name'"

        echo "::debug::Check if $name exists"
        if [[ -f "$name" ]]; then
            echo "::debug::$name exists"
            mkdir -p "$TMPARTIFACT/$(dirname "$name")"
            cp -r "$name" "$TMPARTIFACT/$(dirname "$name")"
        else
            case "$INPUT_IF_NO_FILES_FOUND" in
            "warn")
                echo "::warn::$name does not exist"
                ;;
            "ignore")
                echo "::debug::$name does not exist"
                ;;
            "error")
                echo "::error::$name does not exist"
                exit 1
                ;;
            esac
        fi
    fi
done

# List out everything in the temporary path
if [[ -n "$RUNNER_DEBUG" ]]; then
    echo "::debug::Contents of our temporary artifact build"
    if [[ "$RUNNER_OS" = "Windows" ]]; then
        cmd //c tree "$TMPDIR" /f
    else
        echo "$(tree -a '$TMPDIR' 2>&1)"
    fi
fi
#endregion

#region tarball the temporary path into a single object
# exclude hidden files, if necessary
if ! [[ "$INPUT_INCLUDE_HIDDEN_FILES" ]]; then
    echo "::debug::Excluding hidden files."
    exclude=-"-exclude='.*'"
fi

# create tar
echo "::debug::GZIP=-$INPUT_COMPRESSION_LEVEL tar $exclude -zcvf '$TMPTAR' -C '$TMPARTIFACT' ."
GZIP=-$INPUT_COMPRESSION_LEVEL tar $exclude -zcvf "$TMPTAR" -C "$TMPARTIFACT" .

# TODO: Delete this when it is no longer necessary
# original tar command from other repo. Am I missing something important? What does --transform and
# --show-transformed do?
# tar -czvf "$TMPTAR" -C "$TMPARTIFACT" --transform='s/^\.\///' --show-transformed .

# List the actual contents of the archive
if [[ -n "$RUNNER_DEBUG" ]]; then
    echo "::debug::Artifact contents"
    echo "$(tar -ztvf '$TMPTAR' 2>&1)"
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

echo "Uploading '$TMPTAR' to S3 '$S3URI'"
echo "::debug::aws s3 cp '$TMPTAR' '$S3URI'"
aws s3 cp "$TMPTAR" "$S3URI"
echo "::debug::File uploaded to AWS S3"
#endregion

#region generate outputs
# create presigned URL to download the artifact. AWS CLI expects expiration to be in seconds
EXPIRES_IN=$((INPUT_RETENTION_DAYS * 24 * 60 * 60))
echo "::debug::PRESIGNED_URL=\$\(aws s3 presign '$S3URI' --expires-in $EXPIRES_IN\)"
# TODO: Presigned URL doesn't appear to be working correctly
PRESIGNED_URL=$(aws s3 presign "$S3URI" --expires-in $EXPIRES_IN)
echo "::debug::Presigned URL created: '$PRESIGNED_URL'"

# create outputs and summary
echo "artifact-url=$PRESIGNED_URL" >>$GITHUB_OUTPUT
echo "artifact-urlartifact-digest=$(echo -n $TMPARTIFACT | sha256sum)" >>$GITHUB_OUTPUT
NUM_BYTES=$(stat --printf="%s" "$TMPARTIFACT")
echo "$NUM_BYTES"
FORMATTED_BYTES=$(numfmt --to=iec $NUM_BYTES)
echo "$FORMATTED_BYTES"
echo "[$INPUT_NAME]($PRESIGNED_URL)&nbsp;&nbsp;&nbsp;&nbsp;'$FORMATTED_BYTES'B" >>$GITHUB_STEP_SUMMARY
#endregion

#region clean up temp dir
rm -rf $TMP_ARTIFACT
#endregion
