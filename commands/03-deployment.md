# 03 · Deployment (Docker + Google OAuth + Cloud Run)

Only what deployment adds on top of `01-basic-rag.md` and `02-security.md`.
Deploys `app_final.py` (Streamlit with a Google login gate and employee allow-list).

## Values

```bash
PROJECT_ID=your-project-id
PROJECT_NUMBER=123456789012
REGION=us-central1
GCS_BUCKET_NAME=your-project-id-hr-policies
COMPUTE_SA=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com
CLOUD_RUN_SERVICE=hr-rag-assistant
SECRET_NAME=streamlit-auth
# Assigned on first deploy: https://<service>-<PROJECT_NUMBER>.<REGION>.run.app
SERVICE_URL=https://hr-rag-assistant-123456789012.us-central1.run.app
```

Find your project number with `gcloud projects describe $PROJECT_ID --format="value(projectNumber)"`.

## 1. Enable the APIs

```bash
gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com \
  --project=$PROJECT_ID
```

Together with the earlier stages, the project needs seven: `aiplatform`, `storage`,
`modelarmor`, `run`, `cloudbuild`, `artifactregistry`, `secretmanager`.

## 2. Service-account permissions

Cloud Run runs as the default compute service account. Least privilege:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$COMPUTE_SA" --role="roles/aiplatform.user"        # Gemini
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$COMPUTE_SA" --role="roles/storage.objectViewer"   # read bucket
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$COMPUTE_SA" --role="roles/modelarmor.user"        # guardrail

# Confirm
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" \
  --filter="bindings.members:$COMPUTE_SA" --format="table(bindings.role)"
```

The Secret Manager role is granted per-secret in step 5.

## 3. Local config files (both gitignored)

### `deploy.env.yaml` — config + API keys, passed via `--env-vars-file`

```yaml
PROJECT_ID: "your-project-id"
LOCATION: "us-central1"
GCS_BUCKET_NAME: "your-project-id-hr-policies"
QDRANT_COLLECTION_NAME: "hr_policies"
QDRANT_NOISY_COLLECTION_NAME: "hr_policies_noisy_demo"
GUARDRAIL_PROVIDER: "model_armor"
MODEL_ARMOR_LOCATION: "us"
MODEL_ARMOR_TEMPLATE_ID: "hr-assistant-guardrail"
LANGSMITH_TRACING: "true"
LANGSMITH_ENDPOINT: "https://api.smith.langchain.com"
LANGSMITH_PROJECT: "hr-policy-assistant"
JINA_API_KEY: "<from your .env>"
QDRANT_URL: "<from your .env>"
QDRANT_API_KEY: "<from your .env>"
GROQ_API_KEY: "<from your .env>"
LANGSMITH_API_KEY: "<from your .env>"
ALLOWED_EMPLOYEE_EMAILS: "alice@example.com,bob@example.com"
```

- Format is `KEY: "value"`, one per line — this handles commas in `ALLOWED_EMPLOYEE_EMAILS`.
- `REGION` isn't read by the app; pass `--region` on the deploy command.
- `LANGSMITH_TRACING` must be the quoted string `"true"`.

### `.streamlit/secrets.toml` — OAuth only (goes to Secret Manager)

```toml
[auth]
redirect_uri = "https://<your-service-url>/oauth2callback"
cookie_secret = "<output of: openssl rand -hex 32>"

[auth.google]
client_id = "<from the Console, step 4>"
client_secret = "<from the Console, step 4>"
server_metadata_url = "https://accounts.google.com/.well-known/openid-configuration"
```

`redirect_uri` **must end in `/oauth2callback`** and match a URI registered on the
OAuth client character-for-character — the most common deploy failure.

## 4. Create the Google OAuth client (Console)

1. Console → your project → **Google Auth Platform** (older UI: *OAuth consent screen*).
2. **Get started** → app name, support email, **Audience: External** → Create.
3. **Audience → Test users** → add every email that should log in. While the app is in
   *Testing*, only these emails can sign in (separate from `ALLOWED_EMPLOYEE_EMAILS`).
4. **Clients → Create client** → *Web application*.
5. **Authorized redirect URIs** — add both:
   ```
   http://localhost:8501/oauth2callback
   https://<your-service-url>/oauth2callback
   ```
6. Copy the **Client ID** and **Client secret** into `.streamlit/secrets.toml`
   (the secret is shown once; reset it on the client page if lost).

## 5. Upload the OAuth secret to Secret Manager

```bash
gcloud secrets create $SECRET_NAME --data-file=.streamlit/secrets.toml --project=$PROJECT_ID
# or, if it already exists:
gcloud secrets versions add $SECRET_NAME --data-file=.streamlit/secrets.toml --project=$PROJECT_ID

# let the runtime service account read this one secret only
gcloud secrets add-iam-policy-binding $SECRET_NAME \
  --member="serviceAccount:$COMPUTE_SA" \
  --role="roles/secretmanager.secretAccessor" --project=$PROJECT_ID
```

## 6. Ingest the corpus up front

```bash
python ingest.py            # or: docker compose run --rm ingest
```

Otherwise the first Cloud Run request bootstraps ingestion and takes minutes.

## 7. Deploy

`--source .` sends the repo to Cloud Build, which builds the `Dockerfile`, pushes to
Artifact Registry and deploys. No manual `docker build`. The Dockerfile copies `data/`,
so it must exist locally.

```bash
gcloud run deploy $CLOUD_RUN_SERVICE \
  --source . \
  --project=$PROJECT_ID \
  --region=$REGION \
  --allow-unauthenticated \
  --set-secrets=/app/.streamlit/secrets.toml=$SECRET_NAME:latest \
  --env-vars-file=deploy.env.yaml
```

`--allow-unauthenticated` is intentional: the real gate is the OAuth + allow-list
check inside the app. First deploy takes 3–5 min.

## 8. Close the OAuth loop

If the service URL wasn't known in step 4, add `https://<service-url>/oauth2callback`
to the client's redirect URIs, wait a few minutes, retry login. If you changed
`redirect_uri` in `secrets.toml`, add a new secret version (step 5) and redeploy (step 7).

## 9. Verify

```bash
gcloud run services describe $CLOUD_RUN_SERVICE --region=$REGION --format="value(status.url)"
gcloud run services logs read $CLOUD_RUN_SERVICE --region=$REGION --limit=50
```

Healthy logs show `LangSmith tracing ENABLED` and `INPUT GUARDRAIL: pass`, with no
tracebacks. Open the URL in an incognito window → log in → chat. A non-listed email
sees "not on the approved list".

## 10. Change the allow-list

Two places, both required: add/remove the email under *Audience → Test users*, then edit
`ALLOWED_EMPLOYEE_EMAILS` in `deploy.env.yaml` and rerun the step 7 deploy command.

## 11. Run locally with Docker (optional)

```bash
gcloud auth application-default login
export GCLOUD_CONFIG="$APPDATA/gcloud"   # Windows Git Bash only
docker compose up                        # http://localhost:8501
docker compose run --rm ingest
docker compose run --rm eval
```

Without `.streamlit/secrets.toml` mounted the app runs in open local mode (no login).

## 12. Teardown

```bash
gcloud run services delete $CLOUD_RUN_SERVICE --region=$REGION --project=$PROJECT_ID
gcloud secrets delete $SECRET_NAME --project=$PROJECT_ID
```

Then delete the OAuth client in the Console.

## Troubleshooting

- **All messages blocked by the input guardrail** → the Model Armor call is failing
  (see `02-security.md` troubleshooting). Read the logs:
  `gcloud run services logs read $CLOUD_RUN_SERVICE --region=$REGION --limit=100`
  and look for `Guardrail provider error`. Most often the service account lacks
  `roles/modelarmor.user` (step 2).
- **Login error `redirect_uri_mismatch`** → URI in `secrets.toml` and on the OAuth client differ.
- **Env var changes not applied** → redeploy; Cloud Run reads them at deploy time.

## Cost

Cloud Run scales to zero. Cloud Build, a single Artifact Registry image and Secret
Manager's free tier are negligible. Model Armor adds two screening calls per request.
