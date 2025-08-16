# Event Announcement System (AWS)

Terraform-managed serverless app:
- S3 (web hosting + data JSON)
- CloudFront in front of web bucket
- API Gateway + 3 Lambda functions (Python 3.12)
- SNS email notifications

## Prereqs
- Terraform >= 1.6
- AWS account/credentials (region us-east-1)
- Python 3.12

## Structure
- infra/terraform: IaC
- lambdas/: Lambda source
- web/: static site

## Quickstart
1. Create a "dev.auto.tfvars" in infra/terraform (optional; variables have defaults)
2. terraform init && terraform apply
3. Deploy Lambda code zips with Terraform (packaging steps in Makefile TBD)
4. Upload web/ contents to the provisioned web bucket (see outputs)

## Notes
- SNS email subscriptions require recipient confirmation.
- CORS is configured for the CloudFront domain.

