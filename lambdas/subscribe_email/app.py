import json
import os
import boto3

sns = boto3.client('sns')

TOPIC_ARN = os.environ.get('TOPIC_ARN')
CORS_ORIGIN = os.environ.get('CORS_ORIGIN', '*')


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": f"https://{CORS_ORIGIN}" if CORS_ORIGIN != '*' else '*',
            "Access-Control-Allow-Credentials": "true"
        },
        "body": json.dumps(body)
    }


def handler(event, context):
    try:
        body = event.get('body')
        payload = json.loads(body or '{}')
        email = payload.get('email')
        if not email:
            return _response(400, {"error": "Email is required"})

        resp = sns.subscribe(TopicArn=TOPIC_ARN, Protocol='email', Endpoint=email)
        return _response(202, {"message": "Subscription pending confirmation", "subscriptionArn": resp.get('SubscriptionArn')})
    except Exception as e:
        return _response(500, {"error": str(e)})

