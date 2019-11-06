#!/usr/bin/env bash

# The logic to find out base compare commit is borrowed from
# https://github.com/iynere/compare-url/blob/master/src/commands/reconstruct.yml

# Required environment variables that are not set by CircleCI:
# - CIRCLE_TOKEN: CircleCI API token
# - CIRCLE_COMPARE_URL_DEBUG: Additional debugging output about CIRCLE_COMPARE_URL

# Output files (could persist to workspace so all following steps can use them):
# - BASE_COMPARE_COMMIT.txt
# - CIRCLE_COMPARE_URL.txt

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

## VARS

# absolute path of this script
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

## SETUP

VCS_TYPE=github
MASTER_BRANCH=master

## EXECUTION

if [[ "${CIRCLE_BRANCH}" != "${MASTER_BRANCH}" ]]; then
    # We are building a non-master branch.
    # Always compare to origin/${MASTER_BRANCH} branch to find out what changed.
    GIT_DIFF_OUT=$(git diff "origin/${MASTER_BRANCH}" --name-status)
else
    # We are building master branch.
    # Find the most recent job that:
    # - had different commit SHA
    # - also ran on master branch

    FOUND_BASE_COMPARE_COMMIT=false

    # start iteration from the job before $CIRCLE_BUILD_NUM
    JOB_NUM=$(( $CIRCLE_BUILD_NUM - 1 ))

    # manually iterate through previous jobs
    until [[ $FOUND_BASE_COMPARE_COMMIT == true ]]
    do
        # save circle api output to a temp file for reuse
        curl --silent --user ${CIRCLE_TOKEN}: \
            https://circleci.com/api/v1.1/project/$VCS_TYPE/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$JOB_NUM \
            > JOB_OUTPUT

        if [[ $(grep "\"vcs_revision\" : \"$CIRCLE_SHA1\"" JOB_OUTPUT) ]]; then
            JOB_NUM=$(( $JOB_NUM - 1 ))
            continue
        fi

        if [[ ! $(grep "\"branch\" : \"${MASTER_BRANCH}\"" JOB_OUTPUT) ]]; then
            JOB_NUM=$(( $JOB_NUM - 1 ))
            continue
        fi

        FOUND_BASE_COMPARE_COMMIT=true

        BASE_COMPARE_COMMIT=$(cat JOB_OUTPUT | grep '"vcs_revision" : ' | sed -E 's/"vcs_revision" ://' | sed -E 's/[[:punct:]]//g' | sed -E 's/ //g')
        GIT_DIFF_OUT=$(git diff "${BASE_COMPARE_COMMIT:0:12}...${CIRCLE_SHA1:0:12}" --name-status)

        # clean up
        rm -f JOB_OUTPUT
    done
fi

echo "${GIT_DIFF_OUT}" > GIT_DIFF_OUT.txt
