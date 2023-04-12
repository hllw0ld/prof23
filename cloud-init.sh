#!/bin/bash

source cloud.conf

terraform apply -auto-approve

terraform output | head -n -1 | tail -n -1 > privkey.pem
