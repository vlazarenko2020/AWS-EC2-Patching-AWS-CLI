#!/bin/bash
#
# https://docs.aws.amazon.com/cli/latest/reference/backup/start-backup-job.html


# --
# -- Instance to Patch is a line in the info file 
# -- ${MENU_SCRIPT} selects line (resource) to backup
# --
# -- OpenSystemAccount or MainAccount info is a part of the line in the info file
# --



# Input parameters:
#  -f <FILE-WITH-LINES.TXT>
#  -f EC2_to_patch.txt


MENU_SCRIPT='../_COMMON/menu.sh'
DIR_LOCAL_TEMP_OUTPUT='output'
red_color='\033[0;31m'
yellow_color='\033[0;33m'
clear_color='\033[0m'


# my_idempotency_token=$(date "+%Y%d%m-%H%M%S")


# ----------------------------------------------------------------------------------------------------
f_process_script_arguments()
{
    # echo -e "\n Arguments: $@\n"

    # -- getopts doesn't detect no argument
    # -- need to check it separatly
    if [[ $# -ne 2 ]]; then
        echo -e "\nERROR: Need a parameter with value: -f <file-with-lines>\n" >&2
        exit 1
    fi

    optspec="f:"    # -- getopts will process errors by itself because no colon at the beginning
    while getopts "$optspec" optchar; do
        case "${optchar}" in
            f) 
                FILE_WITH_LINES_TO_SELECT=${OPTARG}
                FILE_WITH_CUR_SELECTED_LINE=${FILE_WITH_LINES_TO_SELECT}.current_selected_line.tmp
                ;; 
            \?)
                # -- getopts will print its error message like 
                #    './menu.sh: illegal option -- k'
                #    So my echo is just an addition to the bash error message
                echo -e "Exiting.\n" >&2
                exit 1
                ;; 
        esac
    done
}
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
f_action_run_patch_scan()
{
    echo -e "\n..Scanning for new patches on EC2: ${selected_instance_id} (${selected_instance_name})\n"
    # aws ssm send-command --document-name "AWS-RunPatchBaseline" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["i-0123456789abcdef8"]}]' --parameters '{"Operation":["Scan"],"SnapshotId":[""],"InstallOverrideList":[""],"BaselineOverride":[""],"RebootOption":["NoReboot"]}' --tim    eout-seconds 600 --max-concurrency "50" --max-errors "0" --output-s3-bucket-name "your-bucket-name" --output-s3-key-prefix "system-manager-patching/" --re    gion us-east-1
    # aws ssm send-command --document-name "AWS-RunPatchBaseline" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["i-0123456789abcdef3"]}]' --parameters '{"Operation":["Install"],"SnapshotId":[""],"InstallOverrideList":[""],"RebootOption":["RebootIfNeeded"]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --output-s3-bucket-name "your-bucket-name" --output-s3-key-prefix "system-manager-patching/" --region us-east-1

    # - ORIGINAL
    # --targets '[{"Key":"InstanceIds","Values":["i-0123456789abcdef8"]}]'

    # - MADE SUITED FOR BASH SCRIPT
    # --targets '[{"Key":"InstanceIds","Values":["'"${selected_instance_id}"'"]}]' \
    #                                             ^                ^
    #                                             ^                ^
    #                                             ^                ^
    #                                             ^                ^
    COMMAND_ID=$(aws ssm send-command --document-name "AWS-RunPatchBaseline" \
                        --document-version "1" \
                        --targets '[{"Key":"InstanceIds","Values":["'"${selected_instance_id}"'"]}]' \
                        --parameters '{"Operation":["'"${SCAN_INSTALL}"'"],"SnapshotId":[""],"InstallOverrideList":[""],"BaselineOverride":[""],"RebootOption":["NoReboot"]}' \
                        --timeout-seconds 600 \
                        --max-concurrency "50" \
                        --max-errors "0" \
                        --output-s3-bucket-name "${BUCKET_NAME}" \
                        --output-s3-key-prefix "${BUCKET_PATH}" \
                        --region "${REGION_MY}" \
                        --query "Command.CommandId" \
                        --output text \
                        --profile ${MY_PROFILE})
    echo -e "\n..COMMAND_ID: ${COMMAND_ID}"
}
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
f_action_run_patch_install()
{
    if [[ ${reboot} = 'yes' ]]; then
        echo -e "\n..Installing patches (with reboot) to EC2: ${selected_instance_id} (${selected_instance_name})\n"
        COMMAND_ID=$(aws ssm send-command --document-name "AWS-RunPatchBaseline" \
                            --document-version "1" \
                            --targets '[{"Key":"InstanceIds","Values":["'"${selected_instance_id}"'"]}]' \
                            --parameters '{"Operation":["'"${SCAN_INSTALL}"'"],"SnapshotId":[""],"InstallOverrideList":[""],"RebootOption":["RebootIfNeeded"]}' \
                            --timeout-seconds 600 \
                            --max-concurrency "50" \
                            --max-errors "0" \
                            --output-s3-bucket-name "${BUCKET_NAME}" \
                            --output-s3-key-prefix "${BUCKET_PATH}" \
                            --region "${REGION_MY}" \
                            --query "Command.CommandId" \
                            --output text \
                            --profile ${MY_PROFILE})
        echo -e "\n..COMMAND_ID: ${COMMAND_ID}"
    elif [[ ${reboot} = 'no' ]]; then
        echo -e "\n..Installing patches (without reboot) to EC2: ${selected_instance_id} (${selected_instance_name})\n"
        COMMAND_ID=$(aws ssm send-command --document-name "AWS-RunPatchBaseline" \
                            --document-version "1" \
                            --targets '[{"Key":"InstanceIds","Values":["'"${selected_instance_id}"'"]}]' \
                            --parameters '{"Operation":["'"${SCAN_INSTALL}"'"],"SnapshotId":[""],"InstallOverrideList":[""],"RebootOption":["NoReboot"]}' \
                            --timeout-seconds 600 \
                            --max-concurrency "50" \
                            --max-errors "0" \
                            --output-s3-bucket-name "${BUCKET_NAME}" \
                            --output-s3-key-prefix "${BUCKET_PATH}" \
                            --region "${REGION_MY}" \
                            --query "Command.CommandId" \
                            --output text \
                            --profile ${MY_PROFILE})
        echo -e "\n..COMMAND_ID: ${COMMAND_ID}"
    else
        echo -e "\nERROR: Need parameter rebooy=yes or reboot=no. Patches were not installed."
        exit 1
    fi
}
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
f_sleepWithIndicator() {
    # $1 - seconds I want to sleep
    secondsBetweenPrint=2

    # -- If $1 (amount of seconds to sleep) is not passed -- use 300 seconds as default
    if [[ $1 ]]; then
        HowManyTimes=$(( $1 / secondsBetweenPrint ))
        # echo "Sleeping for $1 seconds"
    else
        HowManyTimes=$(( 300 / secondsBetweenPrint ))
        # echo "Sleeping for 300 seconds"
    fi

    declare -i second_passed=0
    while [[ ${1} -ge ${second_passed} ]]; do
        echo -n "."
        /usr/bin/sleep ${secondsBetweenPrint}
        (( second_passed = ${second_passed} + ${secondsBetweenPrint} ))
    done
}
# ----------------------------------------------------------------------------------------------------

f_download_patch_err_and_out_files()
{
    bucket_beginning="$1"
    # -- checking for stderr file in S3 Bucket
    echo -e "\naws s3 ls ${bucket_beginning}/stderr --profile ${MY_PROFILE}"
                aws s3 ls ${bucket_beginning}/stderr --profile ${MY_PROFILE}
    command_exit_status=$?
    if [[ ${command_exit_status} -eq 0 ]]; then 

            echo -e "\naws s3 cp ${bucket_beginning}/stderr ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stderr --profile ${MY_PROFILE}"
                        aws s3 cp ${bucket_beginning}/stderr ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stderr --profile ${MY_PROFILE}
    fi

    # -- checking for stdout file in S3 Bucket
    echo -e "\naws s3 ls ${bucket_beginning}/stdout --profile ${MY_PROFILE}"
                aws s3 ls ${bucket_beginning}/stdout --profile ${MY_PROFILE}
    command_exit_status=$?
    if [[ ${command_exit_status} -eq 0 ]]; then 

            echo -e "\naws s3 cp ${bucket_beginning}/stdout ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout --profile ${MY_PROFILE}"
                        aws s3 cp ${bucket_beginning}/stdout ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout --profile ${MY_PROFILE}
    fi
}








# --COMMON FOR ALL SCRIPTS PART - START ---------------------------------------------------------------
# ------------------------------------------------------------
f_process_script_arguments "${@}"   # -- passing scripts arguments to function as the same set of arguments
                                    # -- argument is a FILE WITH LINES TO SELECT
# ------------------------------------------------------------

echo -e "\n--- from $0"
echo -e " Input file with many lines:    ${FILE_WITH_LINES_TO_SELECT}"
echo -e " Temp file with selected lines: ${FILE_WITH_CUR_SELECTED_LINE}\n"

if [ ! -e "${MENU_SCRIPT}" ]; then
    echo -e "\nERROR: Menu script (${MENU_SCRIPT}) is missing. Exiting.\n"
    exit 2
fi

# -- Exit this parent script if ${MENU_SCRIPT} failed.
./${MENU_SCRIPT} "${@}" || exit 1


user_selected_line=$(head -n 1 ${FILE_WITH_CUR_SELECTED_LINE})
selected_instance_id=$( echo ${user_selected_line} | cut -d'|' -f1)
selected_instance_name=$( echo ${user_selected_line} | cut -d'|' -f4)
selected_win_or_linux=$( echo ${user_selected_line} | cut -d'|' -f3)
selected_aws_account=$( echo ${user_selected_line} | cut -d'|' -f2)
# --COMMON FOR ALL SCRIPTS PART - END ------------------------------------------------------------------











case ${selected_aws_account} in
'DS')
    MY_PROFILE='ARDSAdmin'
    BUCKET_NAME="S3-BACKET-FOR-LOGS-OUTPUTS"
    BUCKET_PATH="system-manager-patching-DS/"
    REGION_MY='us-east-1'
    ;;
'OF')
    MY_PROFILE='AROFAdmin'
    BUCKET_NAME="S3-BACKET-FOR-LOGS-OUTPUTS"
    BUCKET_PATH="system-manager-patching-OF/"
    REGION_MY='us-east-1'
    ;;
'SD')
    MY_PROFILE='ARDevAccountAdmin'
    BUCKET_NAME="S3-BACKET-FOR-LOGS-OUTPUTS"
    BUCKET_PATH="system-manager-patching-SD/"
    REGION_MY='us-east-1'
    ;;
*)
    echo "ERROR"
    ;;
esac







echo -e "\nSelected Instance_ID: ${selected_instance_id}"
echo      "Instance Name:        ${selected_instance_name}"
echo      "Operating System:     ${selected_win_or_linux}"
echo -e   "AWS Account:          ${selected_aws_account}\n"




echo '------------------------------------------------'
echo -e "-- Do you want to\n     - Scan (s)\n     - Install with reboot (i)\n     - Install without reboot (w)"
echo '------------------------------------------------'
read -p '-- Enter (s) or (i) or (w): ' user_selection

case ${user_selection} in
's')
    SCAN_INSTALL="Scan"
    f_action_run_patch_scan
    ;;
'i')
    SCAN_INSTALL="Install"
    reboot='yes'
    f_action_run_patch_install
    ;;
'w')
    SCAN_INSTALL="Install"
    reboot='no'
    f_action_run_patch_install
    ;;
*)
    echo "ERROR: You must enter: (s) or (i) or (w). Exiting." >&2
    exit 1
    ;;
esac    






# --------------------------------------------------------------------------
# -- Not using this command to check status in loop
command_list_status=$(aws ssm list-command-invocations --command-id "${COMMAND_ID}" \
                                                       --instance-id "${selected_instance_id}" \
                                                       --region "${REGION_MY}" \
                                                       --query "CommandInvocations[0].StatusDetails" \
                                                       --output text \
                                                       --profile ${MY_PROFILE})
echo -e "\nSTATUSDETAILS_LIST = $command_list_status"
# --------------------------------------------------------------------------



# --------------------------------------------------------------------------
# -- Using this command to check status in loop
command_get_status='Lipa'
while [ "$command_get_status" != 'Success' ]
do
    command_get_status=$(aws ssm get-command-invocation --command-id "${COMMAND_ID}" \
                                                        --instance-id "${selected_instance_id}" \
                                                        --region "${REGION_MY}" \
                                                        --query "StatusDetails" \
                                                        --output text \
                                                        --profile ${MY_PROFILE})                                                
    echo -e "\n${SCAN_INSTALL} command status: $command_get_status"
    # -- because while can have 'InProgress' but 'aws ssm' command returned 'Success'
    # -- need to f_sleepWithIndicator only when 1= 'Success'
    if [ "$command_get_status" != 'Success' ]; then
        # ---------------------------------------------------
        f_sleepWithIndicator 15
        # ---------------------------------------------------
    fi
done
# --------------------------------------------------------------------------


LOG_PREFIX="$(date '+%Y%m%d%H%M')--${selected_instance_id}--${COMMAND_ID}"


case ${selected_win_or_linux} in
    'W')
        # bucket_beginning="s3://your-bucket-name/system-manager-patching/${COMMAND_ID}/${selected_instance_id}/awsrunPowerShellScript/PatchWindows"
        bucket_beginning="s3://${BUCKET_NAME}/${BUCKET_PATH}${COMMAND_ID}/${selected_instance_id}/awsrunPowerShellScript/PatchWindows"
        # ------------------------------------------------------
        f_download_patch_err_and_out_files ${bucket_beginning}
        # ------------------------------------------------------
        case ${SCAN_INSTALL} in
            'Scan') 
                echo ""
                prom=$(cat ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout | grep -A2 'Scan found the following updates missing:' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${red_color}Scan found the following updates missing:${clear_color}"
                echo -e "${prom}"

                prom=$(cat ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout | grep 'Scan found no missing updates.' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${yellow_color}Scan found no missing updates.${clear_color}"
                echo -e "${prom}"
                echo ""
                ;;
            'Install')
                echo ""
                prom=$(cat ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout | grep -A7 'Installation Results' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${yellow_color}Installation Results${clear_color}"
                echo -e "${prom}"
                echo ""
                ;;
        esac
        ;;
    'L')
        # bucket_beginning="s3://your-bucket-name/system-manager-patching/${COMMAND_ID}/${selected_instance_id}/awsrunShellScript/PatchLinux"
        bucket_beginning="s3://${BUCKET_NAME}/${BUCKET_PATH}${COMMAND_ID}/${selected_instance_id}/awsrunShellScript/PatchLinux"
        # ------------------------------------------------------
        f_download_patch_err_and_out_files ${bucket_beginning}
        # ------------------------------------------------------
        case ${SCAN_INSTALL} in
            'Scan') 
                echo -e "\n\n"
                prom=$(cat ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout | grep 'Instance is Compliant' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${red_color}Instance is Compliant${clear_color}"
                echo -e "${prom}"
                echo ""
                prom=$(cat ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout | grep -A3 'Instance is Non-Compliant' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${red_color}Instance is Non-Compliant${clear_color}"
                echo -e "${prom}"
                echo -e "\n\n"
                ;;
            'Install')
                echo -e "\n\n"
                prom=$(cat ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout | grep 'Instance is Compliant' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${yellow_color}Instance is Compliant${clear_color}"
                echo -e "${prom}"
                echo -e "\n\n"
                ;;
        esac
        ;;
    *)
        echo -e "\nERROR: OS has to be W or L.\n" >&2
        exit 2
        ;;
esac    

