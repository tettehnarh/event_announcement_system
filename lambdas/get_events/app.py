import json
import os
import boto3

s3 = boto3.client('s3')

DATA_BUCKET = os.environ.get('DATA_BUCKET')
EVENTS_KEY = os.environ.get('EVENTS_KEY', 'events/events.json')
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
        try:
            obj = s3.get_object(Bucket=DATA_BUCKET, Key=EVENTS_KEY)
            data = json.loads(obj['Body'].read().decode('utf-8'))
        except s3.exceptions.NoSuchKey:
            data = {"events": []}
        except Exception:
            # If object does not exist
            data = {"events": []}
        return _response(200, data)
    except Exception as e:
        return _response(500, {"error": str(e)})

