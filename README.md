# Prisma Cloud Enterprise Edition IaC Scanning Tool

[![CodeFactor](https://www.codefactor.io/repository/github/kyle9021/pcee_iac_demo_scanning_tool_rev2/badge/main)](https://www.codefactor.io/repository/github/kyle9021/pcee_iac_demo_scanning_tool_rev2/overview/main)

## Quick Overview: 

I wrote this tool with a few goals in mind:

* Tool should be easy to use with robust debugging. 
* It needs to be able to handle directories and files. I found out with my first script that it would fail on individual tf files but if I zipped them up into an archive then it would be successful. Knowing this, I wrote part of the code to zip the directory if a directory was specified. 
* I needed to be able to have a presales engineer have enough flags to showcase the tags and the CI Integrations without having to set up specific CI workflows. 
* I also needed it to be more secure so it could be used with multiple customers. (You don't need to assign the variables in the script)
* I wanted to ensure it was as entertaining as could be for a presentation at the terminal. Hence the cowsay. 

NOTE: Last confirmed working July 6th, 2021 at 5:50 PM EDT. Please ensure the copy you downloaded is after this date. 

## Assumptions

* You're using PRISMA CLOUD ENTERPRISE EDTION
* You're using a LINUX DISTRO to run this from, (giving instructions for debian distros with apt)
* You understand how to harden this script for production environments:

The biggest suggestion here is to not save the script with your secret key and access key in it. A better way to do this might be to have a seperate script which exports those credentials as environmental variables. My goal with this script is to simplify the process for those who are learning to work with the Prisma Cloud Enterprise Edition API. 

* If you do decide to keep the keys in this script, then it's critical you:

Add it to your `.gitignore` (if using git) file and `chmod 700 pcee_iac_scan_tool.sh` between steps 3 and 4 so that others can't read, write, or excute it. 

## Quick Start

* Step 1: Install jq `sudo apt-get install jq`
* Step 2: Install cowsay `sudo apt install cowsay`
* Step 3: `git clone https://github.com/Kyle9021/pcee_iac_demo_scanning_tool_rev2`
* Step 3: `cd pcee_iac_demo_scanning_tool_rev2`
* Step 4: (Optional) `nano pcee_iac_scan_tool.sh` and fill in the variables with the correct data from your console.
* Step 5: `git clone  https://github.com/bridgecrewio/terragoat`
* Step 6: `bash pcee_iac_scan_tool.sh -a terragoat/terraform/aws  -t tf`
* Step 7: Review the documentation by running `bash pcee_iac_scan_tool.sh -h`


## Documentation


```
Usage: bash pcee_iac_scan_tool.sh -a <path_to_directory_or_file> -t <template_type> [options]...
        
Options:
        
        -h, --help
            Displays this help text.
        
        -a, --asset (REQUIRED) <path_to_directory_or_file>
            Directory or file to be scanned. Recommending directory, to start off with. If \-\, stdin will be used instead. HINT: Tab complete works
        
        -t, --type (REQUIRED) tf=terraform, cft=cloud_formation_template, k8=kubernetes_manifest
            Template type
        
        -c, --criteria (OPTIONAL) The number of high medium and low severity policies it'll take to fail. Seperated by commas; default is 1,1,1
            Example: -c 1,2,3 = 1 high vulnerability policy will fail the scan, 2 medium vulnerbility policies, 3 low vulnerability policies
        
        -o, --operator (OPTIONAL) "AND" or "OR"
            Relates to the criteria flag; either fail if there's 1 high severity policy alert AND 1 medium AND 1 low.....or OR (I think you get it)
        
        -i, --additional-info (OPTIONAL) Populate the key:value tags in the Prisma Cloud Console to add additonal context. Seperate values by commas
            Example: -i developer,kyle,environment,production,department,IT will show up as: developer:kyle environment:production department:IT
            LIMIT IS THREE TAGS - not because of the platform, but due to my lack of effort
        
        -d, --demo-ci (OPTIONAL) Specifiy the CI tool integration you'd like to show off. Acceptable inputs are:
            AzureDevOps AWSCodePipeline BitbucketCloud BitbucketServer CircleCI GitHub GitLab-CICD GitLab-SCM IaC-API IntelliJ Jenkins twistcli or VSCode
            Defaults to IaC-API if the flag is omitted
```


## Links to reference

* [Official JQ Documentation](https://stedolan.github.io/jq/manual/)
* [Exporting variables for API Calls and why I choose bash](https://apiacademy.co/2019/10/devops-rest-api-execution-through-bash-shell-scripting/)
* [PAN development site](https://prisma.pan.dev/)
* [Compute Documentation](https://docs.twistlock.com)
