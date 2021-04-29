#!/bin/bash

# The following can be customized as you see fit (or can be left as is).
S1_GITHUB_USER='s1customer'
S1_GITHUB_PULL_SECRET_NAME=docker-registry-s1
REPO_HELPER=docker.pkg.github.com/s1-agents/cwpp_agent/s1helper
REPO_AGENT=docker.pkg.github.com/s1-agents/cwpp_agent/s1agent
HELM_RELEASE_NAME=s1
#S1_NAMESPACE=sentinelone

# Color control constants
Color_Off='\033[0m'       # Text Resets
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Check for prerequisite binaries
if ! command -v kubectl &> /dev/null ; then
    printf "\n${Red}Missing the 'kubectl' utility.  Please install this utility and try again.\n"
	printf "Reference:  https://kubernetes.io/docs/tasks/tools/install-kubectl/\n${Color_Off}"
	exit 0
fi

if ! command -v kubectl get nodes  &> /dev/null ; then
    printf "\n${Red}Unable to issue 'kubectl get nodes' command.  Please ensure that a valid context has been established.\n"
	printf "ie: kubectl config get-context\n"
	printf "kubectl config set-context CONTEXT\n${Color_Off}"
	exit 0
fi

if ! command -v helm &> /dev/null ; then
    printf "\n${Red}Missing the 'helm' utility!  Please install this utility and try again.\n"
	printf "Reference:  https://helm.sh/docs/intro/install/\n${Color_Off}"
fi



# prompt for S1_SITE_TOKEN, GITHUB_PASSWORD, S1_AGENT_TAG & provide error if no input. 

while [ -z "$S1_SITE_TOKEN" ]
do	printf 'S1 Site Token: '
	read -r S1_SITE_TOKEN
	[ -z "$S1_SITE_TOKEN" ] && echo 'S1 site token cannot be empty; try again.'
done

while [ -z "$S1_AGENT_TAG" ]
do      printf 'S1 Agent Version Tag: '
        read -r S1_AGENT_TAG
        [ -z "$S1_AGENT_TAG" ] && echo 'S1 agent version tag cannot be empty; try again.'
done

while [ -z "$S1_NAMESPACE" ]
do      printf 'S1 Agent Namespace: '
        read -r S1_NAMESPACE
        [ -z "$S1_NAMESPACE" ] && echo 'S1 agent namespace cannot be empty; try again.'
done

while [ -z "$S1_GITHUB_PASSWORD" ]
do      printf 'Github Password: '
        read -r S1_GITHUB_PASSWORD
        [ -z "$S1_GITHUB_PASSWORD" ] && echo 'Github password cannot be empty; try again.'
done


CLUSTER_NAME=$(kubectl config current-context)

# Create namespace for S1 resources
printf "\n${Green}Creating namespace...\n${Color_Off}"
kubectl create namespace ${S1_NAMESPACE}

# Create Kubernetes secret to house the GitHub Personal Access Token (that's used to access the S1 Helm Chart and Images) 
if ! kubectl get secret ${S1_GITHUB_PULL_SECRET_NAME} -n ${S1_NAMESPACE} &> /dev/null ; then
	printf "\n${Green}Creating GitHub secret for docker image download in K8s...\n${Color_Off}"
	kubectl create secret docker-registry -n ${S1_NAMESPACE} ${S1_GITHUB_PULL_SECRET_NAME} \
		--docker-username="${S1_GITHUB_USER}" \
		--docker-server=docker.pkg.github.com \
		--docker-password="${S1_GITHUB_PASSWORD}"
fi

# Add the SentinelOne helm repo
# helm repo add sentinelone https://sentinel-one.github.io/helm-charts

# Remove any existing helm charts (that might be old/stale)
if [ -d cwpp_agent ] ; then
        printf "\nRemoving old Helm Chart directory...\n"
        rm -rf cwpp_agent
fi

# Clone S1 agent repository, and authenticate to repo
printf "\nCloning Helm Charts from GitHub...\n"
T=`mktemp`
chmod 0700 $T
export GIT_ASKPASS=$T
cat > $T <<EOM
printf $S1_GITHUB_TOKEN
EOM
git clone https://${S1_GITHUB_USER}@github.com/S1-Agents/cwpp_agent.git
rm -f $T

# Match the version of the chart with the S1_AGENT_TAG
printf "\nChecking out branch for $S1_AGENT_TAG...\n"
cd cwpp_agent
git checkout $(git branch -r | grep $S1_AGENT_TAG) &> /dev/null
cd ..

# Deploy S1 agent!  Upgrade it if it already exists
printf "\n${Green}Deploying Helm Chart...\n${Color_Off}"
helm upgrade --install ${HELM_RELEASE_NAME} --namespace=${S1_NAMESPACE} \
	--set image.imagePullSecrets[0].name=${S1_GITHUB_PULL_SECRET_NAME} \
	--set helper.image.repository=${REPO_HELPER} \
	--set helper.image.tag=${S1_AGENT_TAG} \
	--set helper.env.cluster=${CLUSTER_NAME} \
	--set agent.image.repository=${REPO_AGENT} \
	--set agent.image.tag=${S1_AGENT_TAG} \
	--set agent.env.site_key=${S1_SITE_TOKEN} \
	./cwpp_agent/helm_charts/sentinelone &> /dev/null

printf "Sleeping 10 seconds...\n"
sleep 10

printf "Running: kubectl get pods -n $S1_NAMESPACE...\n"
kubectl get pods -n $S1_NAMESPACE


# Delete/Reboot S1 pods:  kubectl delete pod -n sentinelone $(kubectl get pods -n sentinelone | grep s1-agent | cut -d ' ' -f1)

# Clean up afterwards if you like...
# helm uninstall s1 -n sentinelone
# kubectl delete ns sentinelone
