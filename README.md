# Event Announcement System (AWS, Terraform)

A fully serverless event announcement system using:
- S3 (web hosting + data JSON)
- CloudFront in front of the web bucket (OAC, HTTPS)
- API Gateway (REST) + 3 Lambda functions (Python 3.12)
- SNS email notifications

Region: us-east-1
Resource naming: event-announce-<env> (e.g., event-announce-dev)
Email subject: "Your Daily Newsletter"
Email body on new event: includes actual event details (title, date, location, description)

## Architecture Overview
- Web UI (S3 + CloudFront): Static site that lists events, allows event submission and email subscription.
- API Gateway (REST):
  - GET /events -> Lambda get_events (reads S3 JSON)
  - POST /events -> Lambda post_event (validates, writes to S3, publishes SNS)
  - POST /subscribe -> Lambda subscribe_email (SNS email subscription)
- S3 (Data): events/events.json stores an array of events
- SNS: sends email notifications to subscribers when a new event is created
- IAM: least-privilege for Lambdas (S3 get/put for events key, SNS publish/subscribe)

## Repository Structure
- infra/terraform/        # Terraform IaC (buckets, CloudFront, API, Lambdas, IAM, SNS)
- lambdas/
  - get_events/app.py
  - post_event/app.py     # Publishes SNS with detailed event content
  - subscribe_email/app.py
- web/
  - index.html            # Includes <script src="config.js"></script> and app.js
  - config.js             # Generated post-deploy to set window.API_BASE
  - app.js, styles.css
- commands.md             # Manual command sequence (also reflected below)

## Prerequisites
- Terraform >= 1.6
- AWS CLI configured with credentials that can create the resources
- zip utility (for packaging Lambdas)
- Python 3.12 runtime compatibility for Lambdas

Set your region for this shell (optional if your CLI is already configured):

```bash
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
# Optional: use a specific profile
# export AWS_PROFILE=your-profile
```

## One-time: Commit your current changes

```bash
git status
git add .
git commit -m "chore: add Terraform infra, Lambda handlers, and web app scaffold"
# Push to your current branch
BRANCH=$(git branch --show-current)
git push -u origin "$BRANCH"
```

## Step 1: Package Lambda functions (zip)

```bash
(cd lambdas/get_events && zip -q -r function.zip app.py)
(cd lambdas/post_event && zip -q -r function.zip app.py)
(cd lambdas/subscribe_email && zip -q -r function.zip app.py)
```

## Step 2: Initialize, format, and validate Terraform

```bash
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -recursive
terraform -chdir=infra/terraform validate
```

## Step 3: Plan and Apply (dev)

```bash
terraform -chdir=infra/terraform plan
terraform -chdir=infra/terraform apply
```
Review the plan carefully; apply will create billable AWS resources.

## Step 4: Capture outputs

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

## Step 5: Generate web/config.js with API base URL

```bash
echo "window.API_BASE = '$API_BASE';" > web/config.js
```

## Step 6: Ensure index.html loads config.js
Add this before app.js in web/index.html (already added in repo, but verify):

```html
<script src="config.js"></script>
```

If you need to insert automatically (macOS):

```bash
if ! grep -q 'config.js' web/index.html; then \
  sed -i '' '/<script src="app.js"/i\
  \ \ <script src="config.js"></script>' web/index.html; \
fi
```

## Step 7: Upload web assets to S3 (served via CloudFront)

```bash
aws s3 sync web/ s3://$WEB_BUCKET/ --delete
```

## Step 8 (Optional): Invalidate CloudFront cache

```bash
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?DomainName=='$CLOUDFRONT_DOMAIN'].Id | [0]" \
  --output text)

echo "CloudFront Distribution ID: $DIST_ID"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths '/*'
```

Note: If you skip invalidation, changes may take a few minutes to appear due to caching.

## Step 9: Smoke tests

- List events
```bash
curl -s "$API_BASE/events" | jq
```

- Create an event (triggers SNS email with details)
```bash
curl -s -X POST "$API_BASE/events" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Launch Day","date":"2025-09-01","location":"NYC","description":"System launch"}' | jq
```

- Subscribe an email (recipient must confirm via SNS email)
```bash
curl -s -X POST "$API_BASE/subscribe" \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com"}' | jq
```

- Open the web app
```bash
open "https://$CLOUDFRONT_DOMAIN"
```

## Updating code after first deploy
- Lambda code-only update (quick):
```bash
# Example for post_event
(cd lambdas/post_event && zip -q -r function.zip app.py)
aws lambda update-function-code \
  --function-name event-announce-dev-post-event \
  --zip-file fileb://lambdas/post_event/function.zip
```
- Or via Terraform (recommended to keep IaC as source of truth):
```bash
terraform -chdir=infra/terraform plan
terraform -chdir=infra/terraform apply
```

## Teardown
```bash
terraform -chdir=infra/terraform destroy
```

## Troubleshooting
- CloudFront shows old content: run an invalidation (Step 8) or wait for cache TTL.
- CORS errors: ensure API responses include Access-Control-Allow-Origin for the CloudFront domain; OPTIONS methods are configured in Terraform.
- SNS emails not arriving: confirm the subscription in your inbox; check SNS topic subscriptions and CloudWatch logs for the Lambda.
- S3 events file missing: infra creates an empty events/events.json; the API also tolerates a missing object and returns an empty list.

## Security & Costs
- Data bucket is private (public access blocked); web bucket is private and read via CloudFront OAC.
- IAM policies grant least-privilege for Lambdas (only required S3 paths and SNS actions).
- This stack incurs costs (CloudFront, API Gateway, Lambda, S3, SNS). Clean up with destroy when done.

