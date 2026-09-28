# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Bash script that patches EC2 instances via AWS Systems Manager (SSM), using the
`AWS-RunPatchBaseline` SSM document. It triggers a scan or install, polls the command status
until it succeeds, then downloads the resulting stdout/stderr logs from S3 and greps them for
human-readable results (compliance status on Linux, missing/installed updates on Windows).

There is no build tooling — this is an operational script, not an application. Linting is done
with shellcheck via `./lint.sh` (see below).

## Linting

```bash
./lint.sh
```

Runs `shellcheck` over every `*.sh` file in the repo. Requires `shellcheck` to be installed
(`apt-get install shellcheck` on Debian/Ubuntu). There is no automated test suite.

## Running the script

```bash
cd patching_simple
./patch_run_passing_instanceid_as_argument.sh -i <instance-id> -a <Scan|Install> -o <L|W> -b <bucket-name>
```

- `-i` : EC2 instance ID
- `-a` : action type passed straight through as the SSM `Operation` parameter — must be `Scan` or `Install`
- `-o` : target OS — `L` for Linux, `W` for Windows (controls which S3 log path and grep patterns are used)
- `-b` : S3 bucket name used for SSM command output (mandatory)

All four flags are required (the arg parser hard-requires at least 8 tokens on the command line
and validates `-b` is non-empty).
See `patching_simple/__HOW_TO_RUN.txt` for real example invocations and expected output.

Requires AWS CLI configured with a profile named `ARDSAdmin` (hardcoded as `MY_PROFILE`) that has
`ssm:SendCommand`, `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`, and S3 read access to
the output bucket.

## Architecture

Everything lives in `patching_simple/patch_run_passing_instanceid_as_argument.sh`, structured as:

1. **Config constants** at the top: AWS profile, S3 bucket/prefix for command output, region, and
   local output dir (`output/`, created relative to wherever the script is run from).
2. **`f_process_script_arguments`** — parses `-i/-a/-o` via `getopts`.
3. **`f_action_run_patch_scan` / `f_action_run_patch_install`** — both call
   `aws ssm send-command` with `AWS-RunPatchBaseline`, differing only in the `RebootOption`
   (`NoReboot` for scan, `RebootIfNeeded` for install) and both use `${SCAN_INSTALL}` (set from the
   `-a` value) as the SSM `Operation` parameter. Only `f_action_run_patch_scan` is actually called
   in the main flow further down — `Scan` vs `Install` behavior is driven by the `Operation`
   parameter value passed to SSM, not by branching between these two functions.
4. **Polling loop** — repeatedly calls `aws ssm get-command-invocation` until `StatusDetails` is
   `Success`, printing a `.` every 2 seconds via `f_sleepWithIndicator` while waiting.
5. **`f_download_patch_err_and_out_files`** — downloads `stderr`/`stdout` for the command from the
   command's S3 output path into `output/<timestamp>--<instance-id>--<command-id>-{stdout,stderr}`.
6. **OS-specific result parsing** — a `case` on `-o` (`W`/`L`) picks the correct SSM plugin path
   within the S3 output (`awsrunPowerShellScript/PatchWindows` vs `awsrunShellScript/PatchLinux`),
   then a nested `case` on the action type greps the downloaded stdout for known result phrases
   (e.g. "Instance is Compliant", "Scan found the following updates missing:") and prints them
   color-highlighted (red/yellow ANSI codes).

Log/output file naming convention: `output/YYYYMMDDHHMM--<instance-id>--<command-id>-stdout`.
