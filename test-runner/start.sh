#!/bin/bash

#Replace -d -l  with -l -d
helpFunction()
{
   echo ""
   echo "Usage: $0 -r parameterA -i parameterB -t parameterC -d parameterD"
   echo "-r Name of your dockerhub public registry"
   echo "-i Name of docker image you want to create"
   echo "-t Tag for your Docker image"
   echo "-l Location of your JSON files"
   echo "-d [options yes/no] yes means the application wil be deployed on kubernetes cluster, no means application will run on docker hub"
   exit 1 # Exit script after printing help
}

unset REGISTRY
unset IMAGE_NAME
unset TAG
unset DEPLOY
unset LOCATION

while getopts r:i:t:d:l:h: opt; do
        case $opt in
                r) REGISTRY=$OPTARG ;;
                i) IMAGE_NAME=$OPTARG ;;
                t) TAG=$OPTARG ;;
                l) LOCATION=$OPTARG ;;
                d) DEPLOY=$OPTARG ;;
                ?) helpFunction ;;
                *) echo 'Error in command line parsing' >&2
                   exit 1
                        
        esac
done

shift "$(( OPTIND - 1 ))"

if [ -z "${REGISTRY}" ] || [ -z "${IMAGE_NAME}" ] || [ -z "${TAG}" ] || [ -z "${LOCATION}" ]; then
        echo 'Missing -r, -i, -t or -l' >&2
        helpFunction
        exit 1
fi

repos="${REGISTRY}/${IMAGE_NAME}:${TAG}"
key="repository"
yaml_file="./values.yaml"
echo ${repos}


az acr login --name ${REGISTRY}
docker create --name apitestrunnertemp -p 80:80 bosdevregistry.azurecr.io/apitestrunnerbase:2.0

SchemaFile=${LOCATION}/apiSchemaSwagger.json
if [ -f "${SchemaFile}" ]; then
    docker cp ${SchemaFile} apitestrunnertemp:/api-test-runner/commonlib/src/main/resources/data/
else
    echo "Please keep your Schema, Datadog and OAuthDetails files in the given directory"
    exit
fi

DatadogDetails=${LOCATION}/dataDogDetails.json
if [ -f "${DatadogDetails}" ]; then
    docker cp ${DatadogDetails} apitestrunnertemp:/api-test-runner/commonlib/src/main/resources/data/
fi

oAuthDetails=${LOCATION}/oAuthDetails.json
if [ -f "${oAuthDetails}" ]; then
    docker cp ${oAuthDetails} apitestrunnertemp:/api-test-runner/commonlib/src/main/resources/data/
fi

sequence=${LOCATION}/testSequenceSwagger.json
if [ -f "${sequence}" ]; then
    echo "Have you modified the Schema file?[yes/no]"
    read modSchema
#Ask for modification for Sequence file?
    if [ ${modSchema} == "no" ]; then
        echo "Have you modified your testSequenceSwagger.json file?[yes/no]"
        read modSequence
        if [ ${modSequence} == "yes" ]; then
            docker cp ${LOCATION}/testSequenceSwagger.json apitestrunnertemp:api-test-runner/templates/restfulapicall/src/main/resources/data/
            docker cp ${LOCATION}/testSequenceSwaggerTemplate.json apitestrunnertemp:api-test-runner/templates/restfulapicall/src/main/resources/data/
        else
            echo "Do you want to continue with the existing testSequence file?[yes/no]"
            read conExisting
            if [ ${conExisting} == "yes" ]; then
                docker cp ${LOCATION}/testSequenceSwagger.json apitestrunnertemp:api-test-runner/templates/restfulapicall/src/main/resources/data/
                docker cp ${LOCATION}/testSequenceSwaggerTemplate.json apitestrunnertemp:api-test-runner/templates/restfulapicall/src/main/resources/data/
            else
                exit
            fi
        fi
    else
        echo "Backing up your existing testSequence files"
        mv ${LOCATION}/testSequenceSwagger.json ${LOCATION}/testSequenceSwaggerBackup_$(date +%d-%m-%Y-%H-%M-%S).json
        mv ${LOCATION}/testSequenceSwaggerTemplate.json ${LOCATION}/testSequenceSwaggerTemplateBackup_$(date +%d-%m-%Y-%H-%M-%S).json
    fi
fi

docker commit apitestrunnertemp ${REGISTRY}.azurecr.io/${IMAGE_NAME}:${TAG}
docker rm apitestrunnertemp
docker rmi -f bosdevregistry.azurecr.io/apitestrunnerbase:2.0
docker image push ${REGISTRY}.azurecr.io/${IMAGE_NAME}:${TAG}


if [ ${DEPLOY} == "yes" ]; then
	az acr login --name ${REGISTRY}
    echo "Enter the namespace of your kubernetes cluster?"
    read namespace
	cd ${LOCATION}/helm/apitestrunner
	cat ./values.yaml | sed -e "s/repository.*/repository: ${REGISTRY}.azurecr.io\/${IMAGE_NAME}:${TAG}/" > ./values_temp.yaml
	mv ./values_temp.yaml ./values.yaml
	cd ..
	helm install apitestrunner apitestrunner --namespace ${namespace}
else
	containerId=$(docker run -it -d -p 8080:8080 ${REGISTRY}.azurecr.io/${IMAGE_NAME}:${TAG})
	containerName=$(docker ps -a  --filter "id=${containerId}" --format "{{.Names}}")
	FILE=${LOCATION}/testSequenceSwaggerTemplate.json
	if [ ! -f "${FILE}" ]; then
		while [ $(docker inspect --format="{{.State.Status}}" ${containerName}) != "exited" ];
		do
			#docker inspect --format="{{.State.Status}}" ${containername}
			continue
		done
		File1=${LOCATION}/testSequenceSwagger.json
		if [ ! -f "${File1}" ]; then
			docker cp ${containerName}:/api-test-runner/templates/restfulapicall/src/main/resources/data/testSequenceSwagger.json ${LOCATION}/
		fi
		docker cp ${containerName}:/api-test-runner/templates/restfulapicall/src/main/resources/data/testSequenceSwaggerTemplate.json ${LOCATION}/
		docker cp ${containerName}:/api-test-runner/helm ${LOCATION}/
	fi
fi
