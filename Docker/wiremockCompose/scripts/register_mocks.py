#!/usr/bin/env python3
import json
import urllib.request

WIREMOCK = "http://localhost:8080"

stubs = [
  {
    "request": {"method": "GET", "urlPath": "/api/users"},
    "response": {
      "status": 200,
      "headers": {"Content-Type": "application/json"},
      "bodyFileName": "users.json"
    }
  },
  {
    "request": {"method": "GET", "urlPathTemplate": "/api/users/{userId}"},
    "response": {
      "status": 200,
      "headers": {"Content-Type": "application/json"},
      "transformers": ["response-template"],
      "body": "{\n  \"id\": \"{{request.path.userId}}\",\n  \"name\": \"User {{request.path.userId}}\",\n  \"email\": \"user{{request.path.userId}}@example.test\"\n}\n"
    }
  },
  {
    "request": {
      "method": "POST",
      "urlPath": "/api/orders",
      "headers": {"Content-Type": {'contains': "application/json"}}
    },
    "response": {
      "status": 201,
      "headers": {"Content-Type": "application/json"},
      "transformers": ["response-template"],
      "body": "{\n  \"orderId\": \"{{request.id}}\",\n  \"customerId\": \"{{jsonPath request.body '$.customerId'}}\",\n  \"receivedItems\": {{{jsonPath request.body '$.items'}}},\n  \"status\": \"CREATED\"\n}\n"
    }
  }
]

payload = {"mappings": stubs, "importOptions": {"duplicatePolicy": "OVERWRITE"}}
data = json.dumps(payload).encode("utf-8")

req = urllib.request.Request(
    url=f"{WIREMOCK}/__admin/mappings/import",
    data=data,
    method="POST",
    headers={"Content-Type": "application/json"}
)

print(f"Importing {len(stubs)} stubs into {WIREMOCK} ...")
with urllib.request.urlopen(req) as resp:
    print("Status:", resp.status)
    print(resp.read().decode("utf-8"))
