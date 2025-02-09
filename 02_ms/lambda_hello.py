import json

def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Greetings from API 2!"})
    }
