import json
import os
import uuid
from datetime import datetime, timezone

import boto3

s3 = boto3.client('s3')
sns = boto3.client('sns')

DATA_BUCKET = os.environ.get('DATA_BUCKET')
EVENTS_KEY = os.environ.get('EVENTS_KEY', 'events/events.json')
TOPIC_ARN = os.environ.get('TOPIC_ARN')
CORS_ORIGIN = os.environ.get('CORS_ORIGIN', '*')
EMAIL_SUBJECT = os.environ.get('EMAIL_SUBJECT', 'Your Daily Newsletter')
EMAIL_CONTENT = os.environ.get('EMAIL_CONTENT', 'This is your newsletter delivered')


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


def _validate(payload):
    required = ["title", "date", "location", "description"]
    missing = [k for k in required if not payload.get(k)]
    if missing:
        raise ValueError(f"Missing fields: {', '.join(missing)}")


def handler(event, context):
    try:
        body = event.get('body')
        payload = json.loads(body or '{}')
        _validate(payload)

        try:
            obj = s3.get_object(Bucket=DATA_BUCKET, Key=EVENTS_KEY)
            data = json.loads(obj['Body'].read().decode('utf-8'))
        except Exception:
            data = {"events": []}

        new_event = {
            "id": str(uuid.uuid4()),
            "title": payload["title"],
            "date": payload["date"],
            "location": payload["location"],
            "description": payload["description"],
            "createdAt": datetime.now(timezone.utc).isoformat()
        }
        data["events"].append(new_event)

        s3.put_object(Bucket=DATA_BUCKET, Key=EVENTS_KEY, Body=json.dumps(data), ContentType='application/json')

        # Publish SNS notification (subject + event details)
        message_lines = [
            "New Event Created:",
            f"Title: {new_event['title']}",
            f"Date: {new_event['date']}",
            f"Location: {new_event['location']}",
            f"Description: {new_event['description']}"
        ]
        message = "\n".join(message_lines)
        sns.publish(TopicArn=TOPIC_ARN, Subject=EMAIL_SUBJECT, Message=message)

        return _response(201, {"message": "Event created", "event": new_event})
    except ValueError as ve:
        return _response(400, {"error": str(ve)})
    except Exception as e:
        return _response(500, {"error": str(e)})

