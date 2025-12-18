# WireMock mock API (Docker Compose)

## Run
```bash
docker compose up --build
```

WireMock listens on:
- http://localhost:8080

Admin API:
- http://localhost:8080/__admin
- Health endpoint: http://localhost:8080/__admin/health

## Try it
```bash
curl http://localhost:8080/api/users
curl http://localhost:8080/api/users/42
curl -X POST http://localhost:8080/api/orders -H 'Content-Type: application/json' \
  -d '{"customerId":"c-123","items":[{"sku":"sku-1","qty":2}]}'
```

## "Mocks as code"
You can register the same mocks via code using the Admin API:

```bash
python3 scripts/register_mocks.py
```

This calls `POST /__admin/mappings/import` to bulk-load stubs.
