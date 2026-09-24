# Backend settings shared by every component in PROD (AWS account 882781045478).
#
# The bucket name contains a random token, so you CANNOT guess it - run
# bootstrap/ first, then paste its `state_bucket` output over the line below.
#
# The state KEY is supplied per component, by CI or by you:
#   terraform init \
#     -backend-config=../../envs/prod.backend.hcl \
#     -backend-config="key=prod/10-network.tfstate"

bucket = "REPLACE_ME_WITH_BOOTSTRAP_OUTPUT"   # e.g. scribl-prod-tfstate-k3m9x2
region = "us-east-1"
