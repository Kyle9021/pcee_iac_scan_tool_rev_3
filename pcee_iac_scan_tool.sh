#!/bin/bash
#------------------------------------------------------------------------------------------------------------------#
# Written By Kyle Butler
# Tested on 7.6.2021 on prisma_cloud_enterprise_edition using Ubuntu 20.04
#
# REQUIREMENTS: 
# Requires jq to be installed: 'sudo apt-get install jq'
# Requires cowsay: 'sudo apt install cowsay'
#
# SET-UP:
# Create Access Key and Secret Key in the Prisma Cloud Console
# Access keys and Secret keys are created in the Prisma Cloud Console under: Settings > Access Keys
# Find the Prisma Cloud Enterprise Edition API URL specific to your deployment: https://prisma.pan.dev/api/cloud/api-url
#
# SECURITY RECOMMENDATIONS:
# Don't leave your keys in the script. Use a secret manager or export those variables from a seperate script. Designed so that it will prompt you if the variables aren't assigned. 
# Example of a better way: pcee_console_api_url=$(vault kv get -format=json <secret/path> | jq -r '.<resources>')
#
#
# OPTIONAL: to assign below variables, if you don't assign them you will get prompted to enter them when the script is run;
#
# VARIABLE ASSIGNMENTS:

pcee_console_api_url=''
pcee_accesskey=''
pcee_secretkey=''

#
# END OF USER CONFIGURATION
#-----------------------------------------------------------------------------------------------------------------#



# The script name
readonly SCRIPT_NAME=$(basename $0)
# The script name without the extension
readonly SCRIPT_BASE_NAME=${SCRIPT_NAME%.*}
# Script directory
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Arguments
readonly ARGS="$*"
# Arguments number
readonly ARGNUM="$#"

usage() {
	echo "Script description"
	echo
	echo -e "Usage: \033[34mbash $SCRIPT_NAME -a <path_to_directory_or_file> -t <template_type>  \033[0m[options]..."
	echo
	echo "Options:"
	echo
	echo "  -h, --help"
	echo "      Displays this help text."
	echo
	echo -e "  -a, --asset \033[31m(REQUIRED)\033[0m <path_to_directory_or_file>"
	echo "      Directory or file to be scanned. Recommending directory, to start off with. If \"-\", stdin will be used instead. HINT: Tab complete works"
	echo
	echo -e "  -t, --type \033[31m(REQUIRED)\033[0m tf=terraform, cft=cloud_formation_template, k8=kubernetes_manifest"
	echo "      Template type"
	echo
	echo "  -c, --criteria (OPTIONAL) The number of high medium and low severity policies it'll take to fail. Seperated by commas; default is 1,1,1"
        echo "      Example: -c 1,2,3 = 1 high vulnerability policy will fail the scan, 2 medium vulnerbility policies, 3 low vulnerability policies"
        echo
	echo "  -o, --operator (OPTIONAL) \"AND\" or \"OR\""
	echo "      Relates to the criteria flag; either fail if there's 1 high severity policy alert AND 1 medium AND 1 low.....or OR (I think you get it)"
        echo
        echo "  -i, --additional-info (OPTIONAL) Populate the key:value tags in the Prisma Cloud Console to add additonal context. Seperate values by commas"
        echo -e "      Example: -i developer,kyle,environment,production,department,IT will show up as  \033[33mdeveloper:kyle environment:production department:IT \033[0m"
       	echo "      LIMIT IS THREE TAGS - not because of the platform, but due to my lack of effort"
        echo
       	echo "  -d, --demo-ci (OPTIONAL) Specifiy the CI tool integration you'd like to show off. Acceptable inputs are:"
        echo -e "       \033[33mAzureDevOps AWSCodePipeline BitbucketCloud BitbucketServer CircleCI GitHub GitLab-CICD GitLab-SCM IaC-API IntelliJ Jenkins twistcli or VSCode \033[0m"
        echo "      Defaults to IaC-API if the flag is omitted"
	echo "  --"
	echo "      Do not interpret any more arguments as options."
	echo
}

while [ "$#" -gt 0 ]
do
	case "$1" in
	-h|--help)
		usage
		exit 0
		;;
	-a|--asset)
		pcee_iac_scan_asset="$2"

		# Jump over <file>, in case "-" is a valid input file 
		# (keyword to standard input). Jumping here prevents reaching
		# "-*)" case when parsing <file>
		shift
		;;
	-t|--type)
		pcee_template_type="$2"
		;;
	-i|--additional-info)
		set -f
		IFS=','
		pcee_additional_info=($2)
                ;;
        -c|--criteria)
                set -f
		IFS=','
		pcee_failure_criteria=($2)
                ;;
        -o|--operator)
                pcee_failure_criteria_operator="$2"
                ;;
	-d|--demo-ci)
                pcee_demo_ci_tool="$2"
                ;;
	--)
		break
		;;
	-*)
		echo "Invalid option '$1'. Use --help to see the valid options" >&2
		exit 1
		;;
	# an option argument, continue
	*)	;;
	esac
	shift
done


# FOR DEBUGGING:




# Checks to ensure that JQ and Cowsay are installed.

if ! type "jq" > /dev/null; then
  echo "jq not installed or not in execution path, jq is required for script execution. Install jq: sudo apt-get install jq";
  exit;
fi


# Checks to ensure that the file has been specified and assigned to the variable.

if [ -z "${pcee_iac_scan_asset}" ]; then
        echo;
        echo -e "File/Directory has not been specified; did you know you could use tab complete? Try adding \"-h\" to review documentation" ;
        echo;
        exit;
fi

# Zips the directory if a directory is specified.

if [[ -f $pcee_iac_scan_asset ]]; then 
  pcee_iac_scan_file=${pcee_iac_scan_asset};
elif [[ -d $pcee_iac_scan_asset ]] && [[ ! -f ${pcee_iac_scan_asset}.zip ]]; then
  zip -r ${pcee_iac_scan_asset}.zip ${pcee_iac_scan_asset};
  pcee_iac_scan_file="${pcee_iac_scan_asset}.zip";
elif [[ -d $pcee_iac_scan_asset ]] && [[ -f ${pcee_iac_scan_asset}.zip ]]; then
  pcee_iac_scan_file="${pcee_iac_scan_asset}.zip"
fi


if [[ ! -f $pcee_iac_scan_file ]]; then
  echo "The file/directory wasn't found; Did you use tab complete? Try adding \"-h\" to review documentation" ;
  exit;
fi

# Checks to ensure that the template type has been specified and assigned to the variable.
if [ -z "${pcee_template_type}" ]; then
        echo;
        echo -e "Template type not specified; it should be tf, cft, or k8. Try adding \"-h\" to review documentation" ;
        echo;
        exit;
fi


# Checks to ensure that 3 failure criteria have been specified. 
if ! [ ${#pcee_failure_criteria[@]} -eq 3 ] && ! [ ${#pcee_failure_criteria[@]} -eq 0 ] ; then 
	echo;
	echo "Too many/few values for the --criteria flag, it should look like --criteria 1,1,1 or 1,0,3 as an example; Try adding \"-h\" to review the documentation or leave the flag out of the command" ;
	echo;
	exit;
fi

# This defines the default failure criteria if not input is recieved.
if [ ${#pcee_failure_criteria[@]} -eq 0 ]; then
       pcee_failure_criteria=(1 1 1);
fi

# Checks to ensure that there are no more than 3 tags/keys
if (( ${#pcee_additional_info[@]} % 2 )) && [ ${#pcee_additional_info[@]} != 0 ] || [ ${#pcee_additional_info[@]} -gt 6 ]; then
	echo "You need an equal amount of keys and values, LIMIT is three because I'm lazy; Try adding \"-h\" to review the documentation or leave the flag out of the command" ;
        exit;
fi


pcee_failure_criteria_operator_n=( $(printf %s "${pcee_failure_criteria_operator}" | tr '[:upper:]' '[:lower:]') )

# Sets the default operator to or if no input is recieved
if [ -z "${pcee_failure_criteria_operator_n}" ]; then
        pcee_failure_criteria_operator_n="or"
fi

# Ensures that the operator flag is set properly. 
if [[ "${pcee_failure_criteria_operator_n}" != "or" ]] && [[ "${pcee_failure_criteria_operator_n}" != "and" ]]; then
	echo "You set the flag, for the operator but didn't specify the acceptable options of either 'or' or 'and'; either omit the flag so it runs with the default flag or run again with \"or\" or \"and\" assigned to the \"-o\" flag; Add -h to review the documentation" ;
        exit;
fi


# Assigns the tags if no input is recived. 
if [ ${#pcee_additional_info[@]} -eq 0 ]; then
        pcee_additional_info=('developer' 'kb' 'environment' 'production' 'department' 'IT')

elif [ ${#pcee_additional_info[@]} -lt 6 ] && [ ${#pcee_additional_info[@]} -gt 3 ]; then
	pcee_additional_info+=('tag' 'demo')

elif [ ${#pcee_additional_info[@]} -lt 3 ] && [ ${#pcee_additional_info[@]} -gt 1 ]; then
        pcee_additional_info+=('tag' 'demo' 'tag_two' 'demo')
fi

# Assigns the default value to the pcee_demo_ci_tool variable if no input is recieved. 
if [[ -z "${pcee_demo_ci_tool}" ]]; then
	pcee_demo_ci_tool="IaC-API";
fi

# Checks to ensure that the input pcee_demo_ci_tool variable is assigned to one of the correct variables.
if [[ "${pcee_demo_ci_tool}" != "AzureDevOps" ]] && \
   [[ "${pcee_demo_ci_tool}" != "AWSCodePipeline" ]] && \
   [[ "${pcee_demo_ci_tool}" != "BitbucketCloud" ]] && \
   [[ "${pcee_demo_ci_tool}" != "BitbucketServer" ]] && \
   [[ "${pcee_demo_ci_tool}" != "CircleCI" ]] && \
   [[ "${pcee_demo_ci_tool}" != "GitHub" ]] && \
   [[ "${pcee_demo_ci_tool}" != "GitLab-CICD" ]] && \
   [[ "${pcee_demo_ci_tool}" != "GitLab-SCM" ]] && \
   [[ "${pcee_demo_ci_tool}" != "IaC-API" ]] && \
   [[ "${pcee_demo_ci_tool}" != "IntelliJ" ]] && \
   [[ "${pcee_demo_ci_tool}" != "Jenkins" ]] && \
   [[ "${pcee_demo_ci_tool}" != "twistcli" ]] && \
   [[ "${pcee_demo_ci_tool}" != "VSCode" ]]; then
   echo "Your input for the --demo-ci flag didn't match the accepted values (Input Values are CASE-SENSITIVE); either omit the -d, --demo-ci flag, correct your input value, or review documentation by trying the -h flag with the command" ;
  exit;
fi


# Failure criteria is specifying how many policies will "fail" a check based on the severity
pcee_file_name=$(basename -a ${pcee_iac_scan_file})

pcee_iac_payload="{\"data\": {\"type\": \"async-scan\",\"attributes\": {\"assetName\": \"${pcee_file_name}\",\"assetType\": \"${pcee_demo_ci_tool}\",\"tags\": {\"${pcee_additional_info[0]}\": \"${pcee_additional_info[1]}\",\"${pcee_additional_info[2]}\": \"${pcee_additional_info[3]}\",\"${pcee_additional_info[4]}\": \"${pcee_additional_info[5]}\"},\"scanAttributes\": {\"scantype\":\"vulnerability\",\"dev\":\"kb\"},\"failureCriteria\": {\"high\": \"${pcee_failure_criteria[0]}\",\"medium\": \"${pcee_failure_criteria[1]}\",\"low\": \"${pcee_failure_criteria[2]}\",\"operator\": \"${pcee_failure_criteria_operator_n}\"}}}}"



# Assigns the sensitive variables if they aren't defined in the script. 
if [ ! -n "$pcee_console_api_url" ] || [ ! -n "$pcee_secretkey" ] || [ ! -n "$pcee_accesskey" ]; then
  echo "Enter the api url for Prisma Cloud";
  read -r pcee_console_api_url;
  pcee_console_api_url=${pcee_console_api_url,,}
  echo "Enter the access key";
  read -r -s pcee_accesskey; # read -s so that information isn't written to the bash history
  echo "Enter the secret key";
  read -r -s pcee_secretkey; # read -s so that information isn't writen to the bash history
fi

if [[ ! $pcee_console_api_url =~ ^(\"\')?https\:\/\/api[2-3]?\.prismacloud\.io(\"|\')?$ ]]; then
  echo "pcee_console_api_url variable isn't formatted or assigned correctly; it should look like: https://api.prismacloud.io";
  exit;
fi

if [[ ! $pcee_accesskey =~ ^.{35,40}$ ]]; then
  echo "check the pcee_accesskey variable because it doesn't appear to be the correct length";
  exit;
fi

if [[ ! $pcee_secretkey =~ ^.{27,31}$ ]]; then
  echo "check the pcee_accesskey variable because it doesn't appear to be the correct length";
  exit;
fi



pcee_auth_body_single="
{
 'username':'${pcee_accesskey}', 
 'password':'${pcee_secretkey}'
}"

pcee_auth_body="${pcee_auth_body_single//\'/\"}"

# Saves the auth token needed to access the CSPM side of the Prisma Cloud API to a variable named $pcee_auth_token

pcee_auth_token=$(curl -s --request POST \
                       --url "${pcee_console_api_url}/login" \
                       --header 'Accept: application/json; charset=UTF-8' \
                       --header 'Content-Type: application/json; charset=UTF-8' \
                       --data "${pcee_auth_body}" | jq -r '.token')

if [ -z "${pcee_auth_token}" ]; then
  echo;
  echo -e "\033[32mauth token not recieved, recommending you check your variable assignment; or check to ensure you're able to reach the console by running: curl ${pcee_console_api_url}. For PANW engineers ensure you're off of global protect\033[0m" ;
  echo;
  exit
fi



# This saves the json as a variable so it can be manipulated for downstream processing below.

pcee_scan=$(curl -s \
                 --request POST \
                 --url "$pcee_console_api_url/iac/v2/scans" \
                 -H "x-redlock-auth: ${pcee_auth_token}" \
                 -H 'content-type: application/vnd.api+json' \
                 -d "${pcee_iac_payload}")


# You need this as the scan ID it's part of the json that gets returned from the original curl request
pcee_scan_id=$(printf %s "${pcee_scan}" | jq -r '.[].id')


pcee_scan_id_check=$?
if [ $pcee_scan_id_check != 0 ]; then
  echo "$pcee_scan" | jq -r '. | {error_code: .errors[].status, details: .errors[].detail}';
  exit;
fi

# You need this part to pull out the unique URL that gets sent back to you.
pcee_scan_url=$(printf %s "${pcee_scan}" | jq -r '.[].links.url')

pcee_scan_url_check=$?
if [ $pcee_scan_url_check != 0 ]; then
  echo "$pcee_scan" | jq -r '. | {error_code: .errors[].status, details: .errors[].detail}';
  exit;
fi


# This is where you upload the files to be scanned to Prisma Cloud Enterprise Edition

curl --request PUT \
     --url "${pcee_scan_url}" \
     -T "${pcee_iac_scan_file}"



pcee_temp_json="{\"data\":{ \"id\":\"${pcee_scan_id}\", \"attributes\":{ \"templateType\":\"${pcee_template_type}\", \"templateVersion\":\"${pcee_template_version}\" }}}"


# Starts the scan
curl -s \
     --request POST \
     --header 'content-type: application/vnd.api+json' \
     --header "x-redlock-auth: ${pcee_auth_token}" \
     --url "${pcee_console_api_url}/iac/v2/scans/${pcee_scan_id}" \
     --data-raw "${pcee_temp_json}"



# This part retrieves the scan progress. It should be converted to a "while loop" outside of a demo env. 

pcee_scan_status=$(curl -s \
                        --request GET "${pcee_console_api_url}/iac/v2/scans/${pcee_scan_id}/status" \
                        --header "x-redlock-auth: ${pcee_auth_token}" \
                        --header 'Content-Type: application/vnd.api+json' | jq -r '.[].attributes.status')


# Put a '#' in front of the line directly below this to disable cowsay. Cowsay is required to be installed if you want to run this. 
if [[ $(printf %s "${pcee_scan_status}") != "processing" ]]; then
  echo "Try rerunning the scan on the directory containing the file rather than the individual file." 
  exit;
fi


pcee_iac_processing_wait(){
 sleep 10;
         pcee_scan_status=$(curl -s --request GET "${pcee_console_api_url}/iac/v2/scans/${pcee_scan_id}/status" \
                        --header "x-redlock-auth: ${pcee_auth_token}" \
                        --header 'Content-Type: application/vnd.api+json' | jq -r '.[].attributes.status');
}

if [[ "${pcee_scan_status}" == "processing" ]]; then
	pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi
if [[ "${pcee_scan_status}" == "processing" ]]; then
        pcee_iac_processing_wait
fi


# retrives the results
pcee_iac_results=$(curl -s \
                        --request GET \
                        --url "${pcee_console_api_url}/iac/v2/scans/${pcee_scan_id}/results" \
                        --header "content-type: application/json" \
                        --header "x-redlock-auth: ${pcee_auth_token}")

pcee_scan_date=$(date +%m_%d_%y_%S)

echo "On today's date: $pcee_scan_date"
echo "$(printf %s "${pcee_iac_results}" | jq '.meta.matchedPoliciesSummary.high') high severity issue(s) found"
echo "$(printf %s "${pcee_iac_results}" | jq '.meta.matchedPoliciesSummary.medium') medium severity issue(s) found"
echo "$(printf %s "${pcee_iac_results}" | jq '.meta.matchedPoliciesSummary.low') low severity issue(s) found"


echo
echo 
echo
echo "${pcee_iac_results}" | jq '.data[].attributes' | jq 'sort_by(.severity)'
echo
echo
echo
printf '%s\n' "File,Severity_Level,RQL_Query,Issue,Pan_Link,Description,IaC_Resource_Path,IaC_Code_Line" > "./iac_scan_results_$pcee_scan_date.csv";


printf '\n%s\n' "${pcee_iac_results}" | jq '[.data[] | {issue: .attributes.name, severity: .attributes.severity, rule: .attributes.rule, description: .attributes.desc, pan_link: .attributes.docUrl, file: .attributes.blameList[].file, path: .attributes.blameList[].locations[].path, line: .attributes.blameList[].locations[].line}]' | jq 'group_by(.file)[] | {(.[0].file): [.[] | {file: .file, severity: .severity, rule: .rule, issue: .issue, pan_link: .pan_link, description: .description, tf_resource_path: .path, tf_file_line: .line }]}' | jq '.[]' |jq -r 'map({file,severity,rule,issue,pan_link,description,tf_resource_path,tf_file_line}) | (first | keys_unsorted) as $keys | map([to_entries[] | .value]) as $rows | $rows[] | @csv' >>  "./iac_scan_results_$pcee_scan_date.csv";
echo
echo "Report saved in directory"

if [[ $pcee_iac_scan_file =~ \.zip$ ]]; then
        echo;
        read -r -p "Delete the temp zip IaC Project Directory? yes or no: " pcee_delete_question
        pcee_answer=${pcee_delete_question,,}
  if [[ ${pcee_delete_answer} == "yes" ]]; then
         echo
         echo "deleting ${pcee_iac_scan_file}"
         rm $pcee_iac_scan_file;
  fi
fi

exit


