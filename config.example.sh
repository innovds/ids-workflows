#!/bin/bash
# Configuration template - Copy to config.local.sh and customize

# GitHub Organization
ORG_NAME="ids-aws"

# AWS Configuration
AWS_ACCOUNT_ID="857736876208"
AWS_REGION="eu-west-1"

# ECR Registry (derived)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
