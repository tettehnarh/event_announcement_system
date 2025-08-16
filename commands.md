# Manual Commands: Event Announcement System (Terraform + AWS)

These commands deploy and operate the system step-by-step without using the Makefile.

Prereqs:
- AWS CLI configured (credentials with admin or suitable permissions)
- Terraform >= 1.6
- zip utility (macOS has it by default)
- Region: us-east-1

Set your region for AWS CLI in this shell:

```bash
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
# Optional: select profile
# export AWS_PROFILE=your-profile
```

## 0) Commit and push current changes

```bash
git status
git add .
git commit -m "chore: add Terraform infra, Lambda handlers, and web app scaffold"
# Push to your current branch
BRANCH=$(git branch --show-current)
git push -u origin "$BRANCH"
```

## 1) Package Lambda functions (zip)

```bash
(cd lambdas/get_events && zip -q -r function.zip app.py)
(cd lambdas/post_event && zip -q -r function.zip app.py)
(cd lambdas/subscribe_email && zip -q -r function.zip app.py)
```

## 2) Terraform init, fmt, validate

```bash
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -recursive
terraform -chdir=infra/terraform validate
```

## 3) Terraform plan and apply (dev)

```bash
terraform -chdir=infra/terraform plan
terraform -chdir=infra/terraform apply
```

Review the plan carefully; apply will create billable AWS resources.

## 4) Capture key outputs

```bash
WEB_BUCKET=$(terraform -chdir=infra/terraform output -raw web_bucket_name)
CLOUDFRONT_DOMAIN=$(terraform -chdir=infra/terraform output -raw cloudfront_domain_name)
API_BASE=$(terraform -chdir=infra/terraform output -raw api_base_url)
SNS_TOPIC_ARN=$(terraform -chdir=infra/terraform output -raw sns_topic_arn)

echo "WEB_BUCKET=$WEB_BUCKET"
echo "CLOUDFRONT_DOMAIN=$CLOUDFRONT_DOMAIN"
echo "API_BASE=$API_BASE"
echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN"
```

## 5) Generate web/config.js (inject API base URL)

```bash
echo "window.API_BASE = '$API_BASE';" > web/config.js
```

## 6) Ensure index.html includes config.js (one-time)

Add this script tag before app.js in web/index.html:

```html
<script src="config.js"></script>
```

If you prefer a one-liner (macOS sed) to insert before app.js, run:

```bash
if ! grep -q 'config.js' web/index.html; then \
  sed -i '' '/<script src="app.js"/i\
  \ \ <script src="config.js"></script>' web/index.html; \
fi
```

## 7) Upload web assets to S3 (behind CloudFront)

```bash
aws s3 sync web/ s3://$WEB_BUCKET/ --delete
```

## 8) (Optional) Invalidate CloudFront cache

```bash
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?DomainName=='$CLOUDFRONT_DOMAIN'].Id | [0]" \
  --output text)

echo "CloudFront Distribution ID: $DIST_ID"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths '/*'
```

Note: If you skip invalidation, allow a few minutes for the cache to refresh.

## 9) Smoke tests

- API list events:
```bash
curl -s "$API_BASE/events" | jq
```

- Create an event:
```bash
curl -s -X POST "$API_BASE/events" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Launch Day","date":"2025-09-01","location":"NYC","description":"System launch"}' | jq
```

- Subscribe an email (will receive a confirmation email from SNS):
```bash
curl -s -X POST "$API_BASE/subscribe" \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com"}' | jq
```

- Open the web app in your browser:
```bash
open "https://$CLOUDFRONT_DOMAIN"
```

## 10) Tear down (when finished)

```bash
terraform -chdir=infra/terraform destroy
```

