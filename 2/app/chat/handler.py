"""AcmeAssist chat handler.

API Gateway (private REST API, Lambda proxy, AWS_IAM auth) -> this function
-> Bedrock Knowledge Base RetrieveAndGenerate (with guardrail) -> DynamoDB history.

The function runs in a VPC with no internet access. boto3 reaches Bedrock and
DynamoDB through VPC endpoints with private DNS, so no endpoint URLs are set here.
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

KB_ID = os.environ["KB_ID"]
MODEL_ARN = os.environ["MODEL_ARN"]
GUARDRAIL_ID = os.environ["GUARDRAIL_ID"]
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "1")
TABLE_NAME = os.environ["TABLE_NAME"]
MAX_QUESTION_CHARS = 1000

logger = logging.getLogger()
logger.setLevel(logging.INFO)

agent_runtime = boto3.client("bedrock-agent-runtime")
history = boto3.resource("dynamodb").Table(TABLE_NAME)


def handler(event, context):
    caller = event.get("requestContext", {}).get("identity", {}).get("userArn") or "unknown"

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Body must be JSON."})

    question = (body.get("question") or "").strip()
    if not question or len(question) > MAX_QUESTION_CHARS:
        return _response(400, {"error": f"'question' is required (max {MAX_QUESTION_CHARS} characters)."})

    request = {
        "input": {"text": question},
        "retrieveAndGenerateConfiguration": {
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": KB_ID,
                "modelArn": MODEL_ARN,
                "generationConfiguration": {
                    "guardrailConfiguration": {
                        "guardrailId": GUARDRAIL_ID,
                        "guardrailVersion": GUARDRAIL_VERSION,
                    }
                },
            },
        },
    }
    if body.get("sessionId"):
        request["sessionId"] = body["sessionId"]

    try:
        result = agent_runtime.retrieve_and_generate(**request)
    except ClientError as err:
        code = err.response["Error"]["Code"]
        logger.error(json.dumps({"caller": caller, "error": code}))
        if code == "ValidationException":
            return _response(400, {"error": "Invalid request or expired session. Start a new session."})
        if code == "ThrottlingException":
            return _response(429, {"error": "Too many requests. Try again shortly."})
        return _response(502, {"error": "The assistant is unavailable right now."})

    answer = result["output"]["text"]
    session_id = result["sessionId"]
    guardrail_action = result.get("guardrailAction", "NONE")
    sources = sorted({
        ref["location"]["s3Location"]["uri"]
        for citation in result.get("citations", [])
        for ref in citation.get("retrievedReferences", [])
        if "s3Location" in ref.get("location", {})
    })

    history.put_item(Item={
        "sessionId": session_id,
        "ts": f"{time.time():.6f}",
        "caller": caller,
        "question": question,
        "answer": answer,
        "sources": sources,
        "guardrailAction": guardrail_action,
        "modelArn": MODEL_ARN,
        "guardrailVersion": GUARDRAIL_VERSION,
    })

    # Metadata only: the full text lives in DynamoDB and the Bedrock invocation logs.
    logger.info(json.dumps({
        "caller": caller,
        "sessionId": session_id,
        "guardrailAction": guardrail_action,
        "sources": len(sources),
    }))

    return _response(200, {
        "answer": answer,
        "sources": sources,
        "sessionId": session_id,
        "guardrailAction": guardrail_action,
    })


def _response(status, payload):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }
