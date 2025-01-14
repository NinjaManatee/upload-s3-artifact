#!/bin/bash
# Reads inputs for GitHub action into variables used by main.sh

# read inputs into variables
INPUT_NAME="${{ inputs.name }}"
INPUT_PATH="${{ inputs.path }}"
INPUT_IF_NO_FILES_FOUND="${{ inputs.if-no-files-found }}"
INPUT_RETENTION_DAYS="${{ inputs.retention-days }}"
INPUT_COMPRESSION_LEVEL="${{ inputs.compression-level }}"
INPUT_OVERWRITE="${{ inputs.overwrite }}"
INPUT_INCLUDE_HIDDEN_FILES="${{ inputs.include-hidden-files }}"

# read github actions variables
RUNNER_OS="${{ runner.os }}"
GITHUB_REPOSITORY="${{ github.repository }}"
GITHUB_RUN_ID="${{ github.run_id }}"

# read environment variables
# TODO: Are these necessary since they are already environment variables?
ENV_S3_ARTIFACTS_BUCKET="${{ env.S3_ARTIFACTS_BUCKET }}"
ENV_AWS_ACCESS_KEY_ID="${{ env.AWS_ACCESS_KEY_ID }}"
ENV_AWS_SECRET_ACCESS_KEY="${{ env.AWS_SECRET_ACCESS_KEY }}"

# print inputs for debugging
echo "::debug::Inputs:"
echo "::debug::\tname:$INPUT_NAME"
echo "::debug::\tpath:$INPUT_PATH"
echo "::debug::\tif-no-files-found:$INPUT_IF_NO_FILES_FOUND"
echo "::debug::\tretention-days:$INPUT_RETENTION_DAYS"
echo "::debug::\tcompression-level:$INPUT_COMPRESSION_LEVEL"
echo "::debug::\toverwrite:$INPUT_OVERWRITE"
echo "::debug::\tinclude-hidden-files:$INPUT_INCLUDE_HIDDEN_FILES"