#!/usr/bin/env bash
#

# MY_PROFILE='default'
MY_PROFILE='ARDSAdmin'
#BUCKET_NAME="bucket_name_passed_as_parameter"
BUCKET_PATH="system-manager-patching/"
REGION_MY='us-east-1'

DIR_LOCAL_TEMP_OUTPUT='output'


f_process_script_arguments()
{
    if [[ $# -lt 8 ]]; then
        echo -e "\nERROR: Need a parameter: -i <instanceID> -a <action-type(S/I)> -o <OperationSystem(L/W)> -b <S3BucketName>\n" >&2
        exit 1
    fi

    optspec="i:a:o:b:"
    while getopts "$optspec" optchar; do
        case "${optchar}" in
            i)
                selected_instance_id=${OPTARG}
                ;;
            a)
                selected_action_type=${OPTARG}
                ;;
            o)
                selected_win_or_linux=${OPTARG}
                ;;
            b)
                BUCKET_NAME=${OPTARG}
                ;;
            \?)
                #    './$0: illegal option -- i'
                echo -e "Exiting.\n" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "${BUCKET_NAME}" ]]; then
        echo -e "\nERROR: -b <S3BucketName> is required\n" >&2
        exit 1
    fi
}


f_action_run_patch_scan()
{
    echo -e "\n..Scanning for new patches on EC2: ${selected_instance_id} (${selected_instance_name})\n"
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


f_action_run_patch_install()
{
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
}


f_sleepWithIndicator() {
    secondsBetweenPrint=2
    if [[ $1 ]]; then
        HowManyTimes=$(( $1 / secondsBetweenPrint ))
    else
        HowManyTimes=$(( 300 / secondsBetweenPrint ))
    fi

    declare -i second_passed=0
    while [[ ${1} -ge ${second_passed} ]]; do
        echo -n "."
        /usr/bin/sleep ${secondsBetweenPrint}
        (( second_passed = ${second_passed} + ${secondsBetweenPrint} ))
    done
}


f_download_patch_err_and_out_files()
{
    bucket_beginning="$1"
    echo -e "\naws s3 ls ${bucket_beginning}/stderr --profile ${MY_PROFILE}"
                aws s3 ls "${bucket_beginning}"/stderr --profile ${MY_PROFILE}
    command_exit_status=$?
    if [[ ${command_exit_status} -eq 0 ]]; then

            echo -e "\naws s3 cp ${bucket_beginning}/stderr ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stderr --profile ${MY_PROFILE}"
                        aws s3 cp "${bucket_beginning}"/stderr "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stderr --profile ${MY_PROFILE}
    fi

    echo -e "\naws s3 ls ${bucket_beginning}/stdout --profile ${MY_PROFILE}"
                aws s3 ls "${bucket_beginning}"/stdout --profile ${MY_PROFILE}
    command_exit_status=$?
    if [[ ${command_exit_status} -eq 0 ]]; then

            echo -e "\naws s3 cp ${bucket_beginning}/stdout ${DIR_LOCAL_TEMP_OUTPUT}/${LOG_PREFIX}-stdout --profile ${MY_PROFILE}"
                        aws s3 cp "${bucket_beginning}"/stdout "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout --profile ${MY_PROFILE}
    fi
}


f_process_script_arguments "${@}"

# echo -e "\n--- from $0"
# echo -e " Instance_ID: ${selected_instance_id}"
# echo -e " Action Type: ${selected_action_type}\n"
# echo -e " OS Type:     ${selected_action_type}\n"

SCAN_INSTALL=${selected_action_type}
f_action_run_patch_scan

command_list_status=$(aws ssm list-command-invocations --command-id "${COMMAND_ID}" \
                                                       --instance-id "${selected_instance_id}" \
                                                       --region "${REGION_MY}" \
                                                       --query "CommandInvocations[0].StatusDetails" \
                                                       --output text \
                                                       --profile ${MY_PROFILE})
echo -e "\nSTATUSDETAILS_LIST = $command_list_status"

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
    if [ "$command_get_status" != 'Success' ]; then
        f_sleepWithIndicator 15
    fi
done

LOG_PREFIX="$(date '+%Y%m%d%H%M')--${selected_instance_id}--${COMMAND_ID}"

red_color='\033[0;31m'
yellow_color='\033[0;33m'
clear_color='\033[0m'

case ${selected_win_or_linux} in
    'W')
        bucket_beginning="s3://${BUCKET_NAME}/${BUCKET_PATH}${COMMAND_ID}/${selected_instance_id}/awsrunPowerShellScript/PatchWindows"
        # ------------------------------------------------------
        f_download_patch_err_and_out_files "${bucket_beginning}"
        # ------------------------------------------------------
        case ${SCAN_INSTALL} in
            'Scan')
                echo ""
                prom=$(cat "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout | grep -A2 'Scan found the following updates missing:' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${red_color}Scan found the following updates missing:${clear_color}"
                echo -e "${prom}"

                prom=$(cat "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout | grep 'Scan found no missing updates.' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${yellow_color}Scan found no missing updates.${clear_color}"
                echo -e "${prom}"
                echo ""
                ;;
            'Install')
                echo ""
                prom=$(cat "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout | grep -A7 'Installation Results' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${yellow_color}Installation Results${clear_color}"
                echo -e "${prom}"
                echo ""
                ;;
        esac
        ;;
    'L')
        bucket_beginning="s3://${BUCKET_NAME}/${BUCKET_PATH}${COMMAND_ID}/${selected_instance_id}/awsrunShellScript/PatchLinux"
        # ------------------------------------------------------
        f_download_patch_err_and_out_files "${bucket_beginning}"
        # ------------------------------------------------------
        case ${SCAN_INSTALL} in
            'Scan')
                echo -e "\n\n"
                prom=$(cat "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout | grep 'Instance is Compliant' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${red_color}Instance is Compliant${clear_color}"
                echo -e "${prom}"
                echo ""
                prom=$(cat "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout | grep -A3 'Instance is Non-Compliant' | grep -v grep)
                [[ $? -eq 0 ]] && echo -e "${red_color}Instance is Non-Compliant${clear_color}"
                echo -e "${prom}"
                echo -e "\n\n"
                ;;
            'Install')
                echo -e "\n\n"
                prom=$(cat "${DIR_LOCAL_TEMP_OUTPUT}"/"${LOG_PREFIX}"-stdout | grep 'Instance is Compliant' | grep -v grep)
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
