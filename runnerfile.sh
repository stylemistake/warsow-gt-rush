#!/bin/bash
cd `dirname ${0}`
source vendor/runner/runner.sh

if ! hash zip; then
    runner_error "Missing dependencies. Aborting..."
    exit 1
fi

task_make_pk3() {
    mkdir -p dist
    zip -r dist/gt_rush.pk3 progs
}

task_clean() {
    rm -rf dist
}

task_default() {
    runner_sequence clean make_pk3
}
