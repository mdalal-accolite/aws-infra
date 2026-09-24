# Backend settings shared by every component in STAGE (AWS account 419717495525).
#
# The bucket name contains a random token, so you CANNOT guess it - run
# bootstrap/ first, then paste its `state_bucket` output over the line below.
#
# The state KEY is supplied per component, by CI or by you:
#   terraform init \
#     -backend-config=../../envs/stage.backend.hcl \
#     -backend-config="key=stage/10-network.tfstate"

bucket = "scribl-stage-tfstate-fxiju7"   # e.g. scribl-stage-tfstate-k3m9x2
region = "us-east-1"
#dynamodb_table = "scribl-stage-tfstate-locks"
use_lockfile = true
encrypt = true