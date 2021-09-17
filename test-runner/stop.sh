#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $0 -n parameterA -l parameterB"
   echo "-n Name Space of your Kubernetes deployment of apitestrunner"
   echo "-l Location of your JSON files"
   exit 1 # Exit script after printing help
}

unset NAMESPACE
unset LOCATION

while getopts n:l:h: opt; do
        case $opt in
                n) NAMESPACE=$OPTARG ;;
                l) LOCATION=$OPTARG ;;
                ?) helpFunction ;;
                *) echo 'Error in command line parsing' >&2
                   exit 1
                        
        esac
done

shift "$(( OPTIND - 1 ))"

if [ -z "${NAMESPACE}" ] || [ -z "${LOCATION}" ]; then
        echo 'Missing -n, or -l' >&2
        helpFunction
        exit 1
fi

cd ${LOCATION}/helm
pwd
helm uninstall apitestrunner -n ${NAMESPACE}

cd ..
pwd
