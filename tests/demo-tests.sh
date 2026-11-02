#!/usr/bin/env bash
# Demo tests for "Lead Pipeline — Dispatcher (hardened demo)".
# Run with the Dispatcher ACTIVE: the error workflow only fires for production executions.
# Postman: Import → Raw text, then paste any single curl command below.
set -euo pipefail

N8N_URL="https://YOUR-N8N-DOMAIN"          # your n8n base URL, no trailing slash
WEBHOOK_SECRET="YOUR_WEBHOOK_SECRET"        # same value as the WEBHOOK_SECRET credential
APIFY_TOKEN="YOUR_APIFY_TOKEN"              # never paste it in the Loom
DISPATCHER="$N8N_URL/webhook/lead-pipeline-dispatcher"
STAMP=$(date +%s)                           # new run IDs on each test: the duplicate guard skips seen runs

case "${1:-help}" in

  dataset)
    # 0. Create a test dataset with three fictional profiles (free, once).
    DATASET_ID=$(curl -s -X POST "https://api.apify.com/v2/datasets?name=demo-profiles-$STAMP&token=$APIFY_TOKEN" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')
    curl -s -X POST "https://api.apify.com/v2/datasets/$DATASET_ID/items?token=$APIFY_TOKEN" \
      -H "Content-Type: application/json" -d '[
      {"firstName":"Camille","lastName":"Martin","headline":"Head of Sales","linkedinUrl":"https://www.linkedin.com/in/demo-profile-1",
       "location":{"linkedinText":"Lyon, France"},"about":"Fictional demo profile.",
       "experience":[{"position":"Head of Sales","companyName":"Demo Agency","companyLinkedinUrl":"https://www.linkedin.com/company/demo-agency","endDate":{"text":"Present"}}]},
      {"firstName":"Julien","lastName":"Bernard","headline":"CEO","linkedinUrl":"https://www.linkedin.com/in/demo-profile-2",
       "location":{"linkedinText":"Paris, France"},"about":"Fictional demo profile.",
       "experience":[{"position":"CEO","companyName":"Demo Consulting","companyLinkedinUrl":"https://www.linkedin.com/company/demo-consulting","endDate":{"text":"Present"}}]},
      {"firstName":"Sarah","lastName":"Petit","headline":"Growth Lead","linkedinUrl":"https://www.linkedin.com/in/demo-profile-3",
       "location":{"linkedinText":"Nantes, France"},"about":"Fictional demo profile.",
       "experience":[{"position":"Growth Lead","companyName":"Demo SaaS","companyLinkedinUrl":"https://www.linkedin.com/company/demo-saas","endDate":{"text":"Present"}}]}
    ]' > /dev/null
    echo "DATASET_ID=$DATASET_ID  → use it for the 'success' test"
    ;;

  success)
    # 1. Happy path: dataset fetched, one batch sent to the worker, progress reported once.
    curl -s -X POST "$DISPATCHER?runId=demo-$STAMP" \
      -H "X-Webhook-Secret: $WEBHOOK_SECRET" -H "Content-Type: application/json" \
      -d "{\"eventType\":\"ACTOR.RUN.SUCCEEDED\",\"resource\":{\"id\":\"apify-ok-$STAMP\",\"defaultDatasetId\":\"${2:?usage: $0 success DATASET_ID}\"}}"
    ;;

  run-failed)
    # 2. Apify run failed: IF false branch → failure lane → backend /failed + Telegram alert.
    curl -s -X POST "$DISPATCHER?runId=demo-$STAMP" \
      -H "X-Webhook-Secret: $WEBHOOK_SECRET" -H "Content-Type: application/json" \
      -d "{\"eventType\":\"ACTOR.RUN.FAILED\",\"resource\":{\"id\":\"apify-failed-$STAMP\",\"statusMessage\":\"Actor timed out after 3600 s\"}}"
    ;;

  api-error)
    # 3. Best one for the Loom: unknown dataset → Apify 404 → 3 tries (5 s apart) → error output → alert.
    curl -s -X POST "$DISPATCHER?runId=demo-$STAMP" \
      -H "X-Webhook-Secret: $WEBHOOK_SECRET" -H "Content-Type: application/json" \
      -d "{\"eventType\":\"ACTOR.RUN.SUCCEEDED\",\"resource\":{\"id\":\"apify-404-$STAMP\",\"defaultDatasetId\":\"doesNotExist$STAMP\"}}"
    ;;

  invalid)
    # 4. Malformed callback (no runId): validation throws → global error workflow alert.
    curl -s -X POST "$DISPATCHER" \
      -H "X-Webhook-Secret: $WEBHOOK_SECRET" -H "Content-Type: application/json" \
      -d "{\"eventType\":\"ACTOR.RUN.SUCCEEDED\",\"resource\":{\"id\":\"apify-bad-$STAMP\"}}"
    ;;

  no-secret)
    # 5. Bonus: no secret header → n8n answers 403, nothing runs.
    curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST "$DISPATCHER?runId=demo-$STAMP" \
      -H "Content-Type: application/json" -d '{"eventType":"ACTOR.RUN.SUCCEEDED"}'
    ;;

  *)
    echo "Usage: $0 dataset | success DATASET_ID | run-failed | api-error | invalid | no-secret"
    ;;
esac
echo
