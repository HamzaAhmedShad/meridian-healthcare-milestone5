# Milestone 6 infrastructure

Run Terraform from this directory. Existing resources were imported into
local Terraform state. State and actual variable files are excluded from Git.
Use terraform.tfvars.example as a configuration reference.

## Resources managed
- GKE cluster and default node pool
- Cloud SQL instance, application database, and application user
- Uploads bucket
- Database password Secret Manager resource (not its secret value)
- CI deployer Google service account
- Kubernetes workload identity's secret-access and upload-create permissions
- HTTP 5xx log-based counter, monitoring dashboard, email notification
  channel, and alert policy

## Coverage limitations and exceptions
Existing lifecycle exclusions retain externally managed settings:
- Cluster: node_config, initial_node_count, master_auth, addons_config
- Node pool: node_count and node_config
- Cloud SQL instance: settings and root_password
- SQL user: password
- Secret Manager resource: replication
- Uploads bucket: cors and website

These excluded settings are not reconciled by Terraform. A no-changes plan
does not establish that these settings match the configuration.

Kubernetes resources are maintained through manifests and deployment
commands; application releases are managed by GitHub Actions. The demo
token's Kubernetes Secret is provisioned separately, and its value is not
committed.

The existing VPC, private service networking, reserved addresses, Artifact
Registry repository, other buckets, and CI project IAM grants are outside
this Terraform configuration. GKE controllers manage load-balancer
resources from Kubernetes configuration. Database secret values and CI
credentials are maintained separately.

## Verification
terraform init
terraform validate
terraform plan -input=false -refresh=true -parallelism=1

The refreshed normal plan must show no changes for the managed configuration.
