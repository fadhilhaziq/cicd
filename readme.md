# CICD with Jenkins, CCE, and GitLab
CI/CD is actually a process to automate process of code change, and deploy them. Jenkins is one of the tool to perform CI/CD process. While GitLab is code repository system with CI/CD build-in functionality
## Hand on deploy Jenkins in CCE

### 1. Setup Infrasture using Terraform

```bash
cd terraform
export HW_ACCESS_KEY="< Your Huawei Access Key>"
export HW_SECRET_KEY="< Your Huawei Secret Key>"
export PROJECT_ID="< Your Enterprise Project ID here >"
export PASSWORD="< Your Node Password here >"
# Create all neccessary infrastructure
terraform init
TF_VAR_secret_key=$HW_SECRET_KEY TF_VAR_access_key=$HW_ACCESS_KEY TF_VAR_password=$PASSWORD TF_VAR_project_ID=$PROJECT_ID terraform apply

# Copy kubernetes config file from terraform output to config file

# To remove all infrastructure
TF_VAR_secret_key=$HW_SECRET_KEY TF_VAR_access_key=$HW_ACCESS_KEY TF_VAR_password=$PASSWORD TF_VAR_project_ID=$PROJECT_ID terraform destroy
```
Below figure shown when you successful create needed infrastructure. You will get output of `jenkins-cluster-kubeconfig`. You need to copy the JSON value to your `~/.kube/config` file so that you can access to CCE cluster.
![alt text](./assets/image-17.png)

### 2. Deploy Jenkins Kubernetes
Before apply kubernetes file, you need to change the `kubernetes.io/elb.enterpriseID` value in `jenkins.service.yaml.example` file to your enterprise ID. This will tell Huawei Cloud to auto create new ELP when create new Load Balancer service. After you fill in your enterpriseID, rename the file to `jenkins.service.yaml`. You can apply those kubernetes file
```bash
# Rename the image tag in `jenkins.deployment.yaml`
kubectl apply -f . -n jenkins
```
Then copy the load balancer service IP to web broswer access to Jenkins UI. You may follow the below figure.

![alt text](./assets/image-18.png)

**How to get enterprise ID:**

Huawei Console | Search "Enterprise Project Management Service" | Find your project name | Copy the ID to the file


**What is the image used for this deployment**

For Image use for this deployment, we just used the official jenkins image, you may download the image from [DockerHub](https://hub.docker.com/r/jenkins/jenkins/tags?page=1&name=alpine) and push it to SWR. Then you can specify the image to `jenkins.deployment.yaml` file.

```bash
cd kubernetes
# Change kubernetes.io/elb.enterpriseID value and rename file

# (Optional) Deploy jenkins deployment to SWR
# Docker login reference: https://support.huaweicloud.com/intl/en-us/usermanual-swr/swr_01_1000.html
docker pull jenkins/jenkins:alpine3.19-jdk21

docker tag jenkins/jenkins:alpine3.19-jdk21 swr.ap-southeast-3.myhuaweicloud.com/test-fq/jenkins:alpine

docker push swr.ap-southeast-3.myhuaweicloud.com/test-fq/jenkins:alpine
```

### 3. Get Jenkins first time login pwd
```bash
kubectl get pods -n jenkins
kubectl logs -n jenkins <- pod-id ->
# Copy first time login password
```

### 4. Go to Jenkins UI
```bash
kubectl get svc -n jenkins
# copy the load balancer public IP, open with browser
# eg. http://10.10.10.10:8000
```

### 5. Use first time login password to login in Jenkins UI, then left every as default when proceed.

After you go to your load balancer service IP in your browser, you will see below page when you first time access the Jenkins Web Application
![alt text](./assets/image-16.png)

To get first time pwd, go to pod logs like figure below.
![alt text](./assets/image-15.png)
Paste the first time pwd to Jenkins UI | Install suggested plugins | Create first admin user | Leave default jenkins URL | Start using Jenkins
![alt text](./assets/image-19.png)
## Jenkins Agent Setup (Dynamic)

Before create agent, remember to change the number of executor for **built-in executor** to 0. **DON'T** mark the built-in executor to temporary offline else the pipeline won't be able to execute. 

![alt text](./assets/image-11.png)

### 1. Install Kubernetes plugin
Manage Jenkins > plugin
![alt text](./assets/image.png)

### 2. Create dynamic agent 
Manage Jenkins > Cloud > Kubernetes

![alt text](./assets/image-1.png)

### 3. Fill in all details with guide below

![alt text](./assets/image-3.png)

* Fill out plugin values
    * Name: kubernetes
    * Kubernetes URL: https://kubernetes.default:443
    * Kubernetes server certificate key: (Copy from Huawei Cloud Console)
    ![alt text](./assets/image-2.png)
    * Kubernetes Namespace: jenkins
    * Credentials | Add | Jenkins (Choose Kubernetes service account option & Global + Save)
    * Test Connection | Should be successful! If not, check RBAC permissions and fix it!
    * Jenkins URL: <private cluster IP url Jenkins SVC eg. http://xx.xx.xx.xx:8080>
    * Add Kubernetes Pod Template
        * Name: jenkins-slave
        * Namespace: jenkins
        * Usage: Use this node as much as possible
        * Containers | Add Template
            * Name: jnlp
            * Docker Image: swr.ap-southeast-3.myhuaweicloud.com/test-fq/jenkins-agent:latest (Can use your own inbound agent image)
            * Command to run : /bin/bash /app/connect.sh
            * Arguments to pass to the command: <Make this blank>
            * Allocate pseudo-TTY: yes
            * Add Volume
                * HostPath type
                * HostPath: /var/run/docker.sock
                * Mount Path: /var/run/docker.sock
                * HostPath type
                * HostPath: /usr/bin/docker
                * Mount Path: /usr/bin/docker
                * HostPath type
                * HostPath: /usr/lib64/libltdl.so.7
                * Mount Path: /usr/lib64/libltdl.so.7
                * HostPath type
                * HostPath: /usr/bin/kubectl
                * Mount Path: /usr/bin/kubectl
        * Service Account: jenkins
        * Run As User ID: 0

## Jenkins Agent Setup (Fixed)
Fixed Agent is Jenkins Agent that will ready all the time and consume compute resources even there is no job. 

### 1. Create Node for fixed-agent in Jenkins
Manage Jenkins > Node > New Node > Permanent Agent > Node Name > Create

* Fill in agent value as below:
  * number of executor: 1
  * remote root directory: /home/jenkins/agent
  * Launch method: launch agent by connecting it to controller
  * After done filling the value, create the node. You will find below page after you create the node.
    ![alt text](./assets/image-20.png)
    ![alt text](./assets/image-9.png)

**Important**
Take Note value for options below 
- `-url` (Need to find out Jenkins' cluster IP which expose port 8080 and 50000, in my case is http://10.247.63.78:8080/)
![alt text](./assets/image-10.png)
- `-name`
- `-secret`

### 2. Deploy fixed-agent
You had to finished create node in Jenkins first before deploy the kubernetes file. Because the information for kubernetes file will need the information display from create node process (Step 1)
```bash
# image: swr.ap-southeast-3.myhuaweicloud.com/test-fq/fixed-agent:latest
cd ../kubernetes-fixed-agent
# Base64 encode value get from previous session and put it to `agent.secret.yaml.example`
echo -n "http://10.247.63.123:8080/" | base64 -w 0
echo -n "your secret" | base64 -w 0
echo -n "Temp" | base64 -w 0

# Before apply，remember to change the environment variable in `agent.secret.yaml.example` accordingly and rename the file to `agent.secret.yaml` 
kubectl apply -f .
```

### Create pipeline
![alt text](./assets/image-12.png)

Before add the pipeline, remember to add the credentials involved in the groovy script like SWR_ACCESS_KEY, SWR_Secret_Key. 

**Add Secret to Jenkins**

Manage Jenkins > Credentials 

![alt text](./assets/image-14.png)

### Example Pipeline Used

```groovy
def git_url = 'https://github.com/oversampling/jenkins-demo.git'
def swr_login = 'docker login -u ${SWR_REGION}@$SWR_ACCESS_KEY -p $SWR_SECRET_KEY swr.${SWR_REGION}.myhuaweicloud.com'
def build_name = 'jenkins-demo'

pipeline {
    agent any
    environment {
        SWR_ACCESS_KEY = credentials("SWR_ACCESS_KEY")
        SWR_SECRET_KEY = credentials("SWR_SECRET_KEY")
        ORGANIZATION = credentials("ORGANIZATION")
        SWR_REGION = credentials("SWR_REGION")
    }
    stages {
        stage('Clone') { 
            steps{
                echo "1.Clone Stage" 
                git url: git_url
                script { 
                    build_tag = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim() 
                } 
            }
        } 
        stage('Test') { 
            steps{
                echo "2.Test Stage" 
            }
        } 
        stage('Build') { 
            steps{
                echo "3.Build Docker Image Stage" 
                sh "docker build -t swr.${SWR_REGION}.myhuaweicloud.com/${ORGANIZATION}/${build_name}:${BUILD_NUMBER} ." 
            }
        } 
        stage('Push') { 
            steps{
                echo "4.Push Docker Image Stage" 
                sh swr_login
                sh "docker push swr.${SWR_REGION}.myhuaweicloud.com/${ORGANIZATION}/${build_name}:${BUILD_NUMBER}" 
            }
        }
        stage('Update Deployment Image') {
            steps {
                script {
                    sh "sed -i 's|image: .*|image: swr.${SWR_REGION}.myhuaweicloud.com/${ORGANIZATION}/${build_name}:${BUILD_NUMBER}|' k8s.yaml"
                }
            }
        }
        stage('Deploy') {
            steps{
                echo "5. Deploy Stage"
                echo "This is a deploy step to test"                
                sh "cat k8s.yaml"
                sh "kubectl apply -f k8s.yaml -n jenkins"
            }
        }
    }
}
```

### GitHub Configuration
Remember, for simplicity, this project is run with a public repository

![alt text](./assets/image-13.png)

### Run the pipeline
Jenkins will prior to run job in fixed-agent first, remember to temporary mark fixed-agent to offline before test dynamic agent.

![alt text](./assets/image-4.png)

## Integrate Jenkins with GitHub

When there is event happened in GitHub which required to trigger Jenkins pipeline, GitHub need to signal Jenkins to execute relevent pipeline. 

### GitHub webhook
Create GitHub webhook
- Payload URL: http://<- jenkins public url->/github-webhook/
- Content-Type: application-json

You can make commit to your repo to see if there is any trigger on Jenkins Pipeline

## Gitlab CI/CD in CCE

### Configure Runner in GitLab
![alt text](./assets/image-5.png)
![alt text](./assets/image-6.png)

### Install GitLab Runner to cluster using Helm

![alt text](./assets/image-7.png)
Get authentication token after configure the GitLab runner, then use that token in helm's config_values_files

Create Gitlab's Helm Congifuration 
```yaml
gitlabUrl: https://gitlab.com/
# Registration token
runnerToken: ""
rbac:
    create: true
    clusterWideAccess: false
    rules:
      - apiGroups: [""]
        resources: ["*"]
        verbs: ["*"]
runners:
    config: |
      [[runners]]
        [runners.kubernetes]
          privileged = true
```
Create GitLab Runner using Helm with above configuration

```bash
kubectl create ns gitlab
helm repo add gitlab https://charts.gitlab.io
helm install --namespace gitlab gitlab-runner -f values.yaml gitlab/gitlab-runner

helm upgrade --namespace gitlab -f values.yaml <- RELEASE-NAME -> gitlab/gitlab-runner
helm upgrade --namespace gitlab -f values.yaml gitlab-runner gitlab/gitlab-runner

# Uninstall GitLab Runner 
helm uninstall gitlab-runner -n gitlab
```

### GitLab Environment Variable
You need specify the env variable in "variable" session which used in the GitLab Pipeline, in this case we will provide kubeconfig and SWR config details(organization, project-region,swr-ak, swr-sk)
![alt text](./assets/image-8.png)

### Configure GitLab CI/CD pipeline
```yaml
stages:
  - package  
  - build
  - deploy
# If no image is specified in each stage, the default image docker:latest is used.
image: docker:latest
# In the package stage, only printing is performed.
package:
  stage: package
  tags:
    - test
  script:
    - echo "hello"
    - echo "package"
# In the build stage, the Docker-in-Docker mode is used.
build:
  stage: build
  tags:
    - test
  # Define environment variables for the build stage.
  variables:
    DOCKER_HOST: tcp://docker:2375
  # Define the image for running Docker-in-Docker.
  services:
    - docker:18.09-dind
  script:
    - echo "build"
    # Log in to SWR.
    - docker login -u $project@$swr_ak -p $swr_sk swr.ap-southeast-3.myhuaweicloud.com
    # Build an image. k8s-dev is the organization name in SWR. Replace it to the actual name.
    - docker build -t swr.$project.myhuaweicloud.com/$organization/nginx:$CI_PIPELINE_ID .
    # Push the image to SWR.
    - docker push swr.$project.myhuaweicloud.com/$organization/nginx:$CI_PIPELINE_ID
deploy:
  image: 
    # Use the kubectl image.
    name: bitnami/kubectl:latest
    entrypoint: [""]
  tags:
    - test
  stage: deploy
  script:
    # Configure the kubeconfig file.
    - mkdir -p $HOME/.kube
    - export KUBECONFIG=$HOME/.kube/config
    - echo $kube_config |base64 -d > $KUBECONFIG
    # Replace the image in the k8s.yaml file.
    - sed -i "s/<IMAGE_NAME>/swr.$project.myhuaweicloud.com\/$organization\/nginx:$CI_PIPELINE_ID/g" k8s.yaml
    - cat k8s.yaml
    # Deploy an application.
    - kubectl apply -f k8s.yaml
```

# TL;DR
This section will talk about configuration on how to connect **GitLab with Jenkins Pipeline** and **GitHub action with CCE**.
## GitLab with Jenkins Pipeline
> Reference: https://docs.gitlab.com/ee/integration/jenkins.html#with-a-webhook

1. Configure Access token to allow Jenkins interact with GitLab. 
![alt text](./assets/image-21.png)
2. Configure Jenkins to connect to GitLab with access token created in step 1. 
- Manage Jenkins | System | Mark ✔ for "Enable authenticaiton for '/project' end-point" | Connection Name: GitLab | GitLab host URL: https://gitlab.com | Credentials: Add **GitLab API token** kind Credential with token you create access token created in step 1 | Test Connection | If connection OK, proeceed next step
  ![alt text](./assets/image-22.png)

3. Create new Pipeline which interconnect with GitLab
![alt text](./assets/image-23.png)

4. Configure GitLab to listen to GitLab webhook. First go to Jenkins Pipeline to generate secret token. Copy that secret token.
![alt text](./assets/image-24.png)

5. Create GitLab webhook to trigger GitLab Pipeline. You may test the connection to ensure everything is right.
![alt text](./assets/image-25.png)

### GitHub built in CICD runner On Kubernetes
GitHub Runner consist of two main components include `runner-scale-set` and `runner-controller`. 

`runner-controller` - Actions Runner Controller (ARC) is a Kubernetes operator that orchestrates and scales self-hosted runners for GitHub Actions.

`runner-scale-set` - Use to execute CI/CD pipeline.

### Configure GitHub Action to use Self-Host Runner on K8s.
> Reference: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller

GitHub Action runner involve two componenets. 
- ***Controller component*** which used to launch environment to execute GitHub's pipeline. 

- ***Scale-Set component*** which handle pipeline execution and pipeline execution dependency services.

1. First thing is to create Controller where controller need to use to launch new runner for pipeline execution.
```bash
NAMESPACE="arc-systems"
helm install arc \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

2. Second is to create Scale-Set. 

You need to create a GitHub's personal access token (PAT) with permission in `admin:org` and `repo`. Place PAT under `GITHUB_PAT=<PAT>` and your repository URL to `GITHUB_CONFIG_URL="<Your Repo URL>"`
```bash
INSTALLATION_NAME="arc-runner-set"
NAMESPACE="arc-runners"
GITHUB_CONFIG_URL="<Your Repo URL>"
GITHUB_PAT="<PAT>"
helm install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    --set githubConfigSecret.github_token="${GITHUB_PAT}" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```
3. Create GitHub Pipeline at root location of project `.github/workflow`. Filename can be anyname but with `yaml` or `yml` extension.

***`cicd.yaml`***
```yaml
name: CI Workflow

on: [push]

jobs:
  package:
    runs-on: arc-runner-set
    steps:
    - uses: actions/checkout@v4
    - name: Package step
      run: |
        echo "hello"
        echo "package"
  build:
    needs: package
    runs-on: arc-runner-set
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    - name: Set up QEMU
      uses: docker/setup-qemu-action@v3
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3.2.0
    - name: Login to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: swr.${{ secrets.PROJECT }}.myhuaweicloud.com
        username: ${{ secrets.PROJECT }}@${{ secrets.SWR_AK }}
        password: ${{ secrets.SWR_SK }}
    - name: List All File
      run: "ls -la"
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        file: ./Dockerfile
        load: true
        tags: "swr.${{ secrets.PROJECT }}.myhuaweicloud.com/${{ secrets.ORGANIZATION }}/jenkins-demo:${{ github.run_id }}"
    - name: Inspect
      run: |
        docker image inspect swr.${{ secrets.PROJECT }}.myhuaweicloud.com/${{ secrets.ORGANIZATION }}/jenkins-demo:${{ github.run_id }}
    - name: Push
      run: "docker push swr.${{ secrets.PROJECT }}.myhuaweicloud.com/${{ secrets.ORGANIZATION }}/jenkins-demo:${{ github.run_id }}"
```