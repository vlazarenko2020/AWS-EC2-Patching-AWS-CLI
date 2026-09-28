#!/bin/bash
#

# FILE_WITH_LINES_TO_SELECT='info/InstanceIDs_to_patch.txt'
# FILE_WITH_CUR_SELECTED_LINE='info/current_selected_line.txt'

# ----------------------------------------------------------------------------------------------------
f_process_script_arguments()
{
    # -- getopts doesn't detect no argument
    # -- need to check it separatly
    if [[ $# -ne 2 ]]; then
        echo -e "\nERROR: Need an agrument -f <file-with-lines>\n" >&2
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
f_process_input_from_file() {

    local reg='^[0-9]*$'
    local total_lines_displayed
    local user_selection

    while (( user_selection != 99 ))
    do
        echo "------------------------------------------------"
        (( n=0 ))
        # -- read file line-by-line
        while read -r cur_line;
        do
            (( n=n+1 ))
            printf "%2s - %s\n" "$n" "$cur_line"
        done < "${FILE_WITH_LINES_TO_SELECT}"

        total_lines_displayed=$n
        echo "99 - Exit"
        echo "------------------------------------------------"
        read -p '-- What is your selection: ' user_selection

        echo -e "\n${user_selection} was selected."

        if [[ $user_selection =~ $reg ]]
        then
            if (( $user_selection <= $total_lines_displayed || $user_selection == 99 )); then
                # ---------------------------------------
                f_action_based_on_selected_digit "$1"
                # ---------------------------------------
                break
            else
                clear
                echo -e "\nWrong Input. Try again\n."
                continue
            fi
        else
            clear
            echo -e '\nYou must enter only digits. Try again.\n'
            user_selection=1 # keep it integer
            continue
        fi
    done
}
# ----------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------
f_action_based_on_selected_digit() {

    prom_line_with_comment=$(sed -n "${user_selection}p" "${FILE_WITH_LINES_TO_SELECT}")
    sed -n "${user_selection}p" "${FILE_WITH_LINES_TO_SELECT}" > ${FILE_WITH_CUR_SELECTED_LINE}
}
# ----------------------------------------------------------------------------------------------------


# ------------------------------------------------------------
f_process_script_arguments "${@}"    # -- passing scripts arguments to function as the same set of arguments
# ------------------------------------------------------------



echo -e "\n--- from $0"
echo -e " Input file with many lines:    ${FILE_WITH_LINES_TO_SELECT}"
echo -e " Temp file with selected lines: ${FILE_WITH_CUR_SELECTED_LINE}\n"



if [[ ! -e "${FILE_WITH_LINES_TO_SELECT}" ]]; then
  echo -e "\n ERROR: File with list of InstanceIDs to select (${FILE_WITH_LINES_TO_SELECT}) doesn't exist. Exiting.\n" >&2
  exit 1
fi

if [[ -e "${FILE_WITH_CUR_SELECTED_LINE}" ]]; then
  echo -e "\n..Deleting old file with selected line (${FILE_WITH_CUR_SELECTED_LINE}).\n"
  rm "${FILE_WITH_CUR_SELECTED_LINE}"
fi



# ------------------------------------------------------------
f_process_input_from_file "${FILE_WITH_LINES_TO_SELECT}"
# ------------------------------------------------------------

echo -e "\n\n..You selected line is\n $(cat ${FILE_WITH_CUR_SELECTED_LINE})\n\n"

