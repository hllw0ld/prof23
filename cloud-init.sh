#!/bin/bash

source cloud.conf

export TF_VAR_PROJECT_ID=$PROJECT_ID
export TF_VAR_USER_NAME=$USER_NAME
export TF_VAR_PASSWORD=$PASSWORD

terraform apply -auto-approve

terraform output | head -n -1 | tail -n +2 > privkey.pem
