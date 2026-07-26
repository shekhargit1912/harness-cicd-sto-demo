# harness-cicd-sto-demo

CI/CD + Security Testing Orchestration (STO) demo pipeline built on Harness (Free Tier), deploying a small Flask app to a local Kubernetes cluster.

## GitOps Flow (bonus)

Deployment manifests live in a separate repo, [harness-k8s-manifest-files](https://github.com/shekhargit1912/harness-k8s-manifest-files), as a Helm chart. Harness's CD stage deploys from that repo, overriding `image.tag` with the tag the CI stage just built. Manifest changes land there via PR, independent of this app repo's history.

## Status

Work in progress. Current contents:

- `app/` — Flask app (`/` and `/health` endpoints), Dockerfile, dependencies
- `k8s/` — original plain Kubernetes manifests from early scaffolding, kept for reference; superseded by the Helm chart in the manifests repo above for actual deployment
- `harness/pipeline.yaml` — exported CI stage (build, tag with commit SHA, push)
- `scripts/verify-health.sh` — post-deploy health check with retry/backoff

Still to come: STO stage, CD stage wiring, full setup/architecture documentation.

## Quick local test (without Docker/K8s)

```bash
cd app
pip install -r requirements.txt
python app.py
curl http://localhost:8080/health
```
