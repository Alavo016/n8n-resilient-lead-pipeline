# Demo tests for "Lead Pipeline — Dispatcher (hardened demo)" — Windows PowerShell.
# Publish the three workflows first: the error workflow only fires for production executions.
# Usage:  .\demo-tests.ps1 -Test dataset | success | run-failed | api-error | invalid | no-secret

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dataset", "success", "run-failed", "api-error", "invalid", "no-secret")]
  [string]$Test,
  [string]$DatasetId = $env:DEMO_DATASET_ID
)

$ErrorActionPreference = "Stop"

$N8nUrl        = "https://YOUR-N8N-DOMAIN"   # no trailing slash
$WebhookSecret = $env:DEMO_WEBHOOK_SECRET    # same value as the WEBHOOK_SECRET credential
$ApifyToken    = $env:APIFY_TOKEN            # never hard-code it, never show it on screen

$Dispatcher = "$N8nUrl/webhook/lead-pipeline-dispatcher"
$Headers    = @{ "X-Webhook-Secret" = $WebhookSecret }
$Stamp      = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()   # fresh IDs: the duplicate guard skips seen runs

function Send-Callback([string]$Uri, [hashtable]$Payload) {
  $json = $Payload | ConvertTo-Json -Depth 5 -Compress
  Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json
}

switch ($Test) {
  "dataset" {
    # Creates a dataset with three fictional profiles. Run once, then reuse its ID.
    $ds = Invoke-RestMethod -Method Post -Uri "https://api.apify.com/v2/datasets?name=demo-profiles-$Stamp&token=$ApifyToken"
    $profiles = @(
      @{ firstName = "Camille"; lastName = "Martin";  headline = "Head of Sales"; linkedinUrl = "https://www.linkedin.com/in/demo-profile-1"; location = @{ linkedinText = "Lyon, France" };   experience = @(@{ position = "Head of Sales"; companyName = "Demo Agency";     endDate = @{ text = "Present" } }) },
      @{ firstName = "Julien";  lastName = "Bernard"; headline = "CEO";           linkedinUrl = "https://www.linkedin.com/in/demo-profile-2"; location = @{ linkedinText = "Paris, France" };  experience = @(@{ position = "CEO";           companyName = "Demo Consulting"; endDate = @{ text = "Present" } }) },
      @{ firstName = "Sarah";   lastName = "Petit";   headline = "Growth Lead";   linkedinUrl = "https://www.linkedin.com/in/demo-profile-3"; location = @{ linkedinText = "Nantes, France" }; experience = @(@{ position = "Growth Lead";   companyName = "Demo SaaS";       endDate = @{ text = "Present" } }) }
    )
    Invoke-RestMethod -Method Post -Uri "https://api.apify.com/v2/datasets/$($ds.data.id)/items?token=$ApifyToken" `
      -ContentType "application/json" -Body (ConvertTo-Json -InputObject $profiles -Depth 6 -Compress) | Out-Null
    "Dataset created: $($ds.data.id)   →   `$env:DEMO_DATASET_ID = '$($ds.data.id)'"
  }
  "success" {
    if (-not $DatasetId) { throw "Pass -DatasetId or set `$env:DEMO_DATASET_ID (run -Test dataset first)." }
    Send-Callback "${Dispatcher}?runId=ok-$Stamp" @{ eventType = "ACTOR.RUN.SUCCEEDED"; resource = @{ id = "ok-$Stamp"; defaultDatasetId = $DatasetId } }
  }
  "run-failed" {
    Send-Callback "${Dispatcher}?runId=fail-$Stamp" @{ eventType = "ACTOR.RUN.FAILED"; resource = @{ id = "fail-$Stamp"; statusMessage = "Actor timed out after 3600 s" } }
  }
  "api-error" {
    Send-Callback "${Dispatcher}?runId=api-$Stamp" @{ eventType = "ACTOR.RUN.SUCCEEDED"; resource = @{ id = "api-$Stamp"; defaultDatasetId = "doesNotExist$Stamp" } }
  }
  "invalid" {
    Send-Callback $Dispatcher @{ eventType = "ACTOR.RUN.SUCCEEDED"; resource = @{ id = "bad-$Stamp" } }
  }
  "no-secret" {
    try {
      Invoke-RestMethod -Method Post -Uri $Dispatcher -ContentType "application/json" -Body "{}"
      "Unexpected: the call was accepted without the secret."
    } catch {
      "Rejected as expected: HTTP $($_.Exception.Response.StatusCode.value__)"
    }
  }
}
