# harness-cicd-sto-demo

CI/CD + Security Testing Orchestration (STO) demo pipeline built on Harness (Free Tier), deploying a small Flask app to a local Kubernetes cluster.

## Status

Work in progress. Current contents:

- `app/` — Flask app (`/` and `/health` endpoints), Dockerfile, dependencies
- `k8s/` — Kubernetes manifests (Namespace, Deployment with rolling update strategy, NodePort Service)
- `scripts/verify-health.sh` — post-deploy health check with retry/backoff

Still to come: `harness/pipeline.yaml` (CI → STO → CD stages) and full setup/architecture documentation.

## Quick local test (without Docker/K8s)

```bash
cd app
pip install -r requirements.txt
python app.py
curl http://localhost:8080/health
```
