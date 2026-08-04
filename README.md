# harness-cicd-sto-demo

An end-to-end CI/CD pipeline with integrated security testing (STO), built on Harness (Free Tier), deploying a small Flask app to a Kubernetes cluster.

## Example executions

Harness supports running individual stages selectively (`allowStageExecutions: true` in the pipeline config), so these two executions demonstrate each half of the pipeline independently:

- **CI + STO — security gate blocking a real CRITICAL finding**: https://app.harness.io/ng/account/xleA1dQuRSC1SGqvBC4c9Q/all/orgs/default/projects/Harnedd_Demo/pipelines/harnesscidemo/deployments/7yAC22ueRKq3wwE4ckKP0A/pipeline?storeType=INLINE
  This execution shows **Failed** — intentionally included, not an error. AquaTrivy found an actual CRITICAL vulnerability in the container image and correctly stopped the pipeline before it could reach deployment, which is exactly what the mandatory security gate is designed to do. A clean pass only proves the gate is configured; a real block proves it works.
- **CD — rolling deploy + health check, Success**: https://app.harness.io/ng/account/xleA1dQuRSC1SGqvBC4c9Q/module/cd/orgs/default/projects/Harnedd_Demo/pipelines/harnesscidemo/deployments/hFHp1LCPTaSjeLOuIOT-gg/pipeline?storeType=INLINE

## Repositories

This project spans **two repositories**, intentionally — this is the GitOps Flow bonus (see below), not an accident:

- **[harness-cicd-sto-demo](https://github.com/shekhargit1912/harness-cicd-sto-demo)** (this repo) — application code, the exported Harness pipeline definition, and helper scripts.
- **[harness-k8s-manifest-files](https://github.com/shekhargit1912/harness-k8s-manifest-files)** — the Helm chart actually used to deploy the app. Kept separate so deployment config can change independently of application code, via its own PR history.

## Contents of this repo

```
app/                        Flask app (/ and /health endpoints), Dockerfile, dependencies
k8s/                         Original plain Kubernetes manifests from early scaffolding.
                              Superseded by the Helm chart in the manifests repo for actual
                              deployment; kept here for reference only.
harness/pipeline.yaml         Exported Harness pipeline definition (CI + CD stages)
scripts/verify-health.sh      Standalone health-check script with retry/backoff, usable
                              outside Harness for manual testing
```

## Architecture / Pipeline explanation

One Harness pipeline, `harnessci-demo`, with two stages:

```
Build-stage (CI)                              CD-With-Helm
┌─────────────────────────────────────────┐   ┌──────────────────────────┐
│ Clone codebase                           │   │ Fetch Helm chart from    │
│   → Semgrep (SAST)                       │   │   harness-k8s-manifest-  │
│   → Build & push Docker image            │──▶│   files repo             │
│     (tag: <+pipeline.sequenceId>)        │   │ → Rolling Deployment     │
│   → AquaTrivy (container scan)           │   │ → HTTP health check      │
└─────────────────────────────────────────┘   └──────────────────────────┘
```

**Why Semgrep runs before the Docker build:** SAST only needs the source code, not a built image. Running it first means a bad commit fails fast, before spending time building and pushing an image that would get rejected anyway.

**Why the image is tagged with a build number, not a commit SHA:** the assignment allows either ("tag with commit SHA **or** build number"). `<+pipeline.sequenceId>` is Harness's built-in incrementing execution ID — simpler to reference at deploy time than propagating a full commit SHA between the two independent CI and CD pipeline stages.

**CD-With-Helm** deploys via Harness's native `K8sRollingDeploy` step, pulling the chart from the separate manifests repo, then runs an HTTP check against `/health` to confirm the rollout is actually serving traffic before the pipeline reports success.

## How security gating works

Two scanners run in Build-stage, both configured to **fail the pipeline on any CRITICAL finding**:

- **Semgrep** (SAST, source code) — `config: auto-only`, `fail_on_severity: critical`
- **AquaTrivy** (container image scan) — `fail_on_severity: critical`

If either scanner finds a CRITICAL issue, Build-stage fails and the pipeline stops — CD-With-Helm never runs, so nothing gets deployed. This is the mandatory security gate.

**Shift-Left Security (bonus):** a webhook trigger fires Build-stage (Semgrep + AquaTrivy) automatically on every pull request opened or updated against `main`. Harness posts a status check directly on the PR, so a CRITICAL finding blocks the merge button before a human ever has to notice — the whole point of "shift left."

**CD-With-Helm is conditionally skipped on PR-triggered runs**, via:
```yaml
when:
  condition: <+codebase.build.type> != "PR"
```
This prevents unreviewed PR code from being auto-deployed — only manual runs or (if configured) a push-to-`main` trigger would actually deploy.

## Failure handling

- **Rollback**: `CD-With-Helm` defines an explicit `K8sRollingRollback` step under `rollbackSteps`, plus a stage-level `failureStrategies` rule (`StageRollback` on `AllErrors`) as a second line of defense. If the rollout or health check fails, Harness automatically rolls back to the last good release.
- **Retry/backoff**: the `Http_1` health-check step has a step-level `failureStrategies` rule — retries up to **5 times** with **increasing intervals (10s → 20s → 30s)** before giving up and marking the step failed (which then triggers the rollback above). `scripts/verify-health.sh` implements the same pattern (10 attempts, 3s apart) for manual/local testing outside the pipeline.

## Bonus features implemented

1. **Shift-Left Security** — PR-triggered pipeline runs both scans before merge (see above).
2. **GitOps Flow** — deployment manifests live in a separate repo ([harness-k8s-manifest-files](https://github.com/shekhargit1912/harness-k8s-manifest-files)), updated via PR (e.g. [PR #1](https://github.com/shekhargit1912/harness-k8s-manifest-files/pull/1), a replica-count change), independent of this repo's history.

## Setup instructions

1. **Kubernetes cluster**: minikube running on an EC2 instance (see Assumptions below for why).
2. **Harness connectors**: GitHub (`githubconnector`), Docker Hub (`dockerhubregistry`), Kubernetes cluster (`Kubernetesclsuter`) — all credential-backed via Harness's Secret Manager, nothing hardcoded.
3. **Harness Delegate**: deployed as a pod inside the same minikube cluster, so Harness (SaaS) can reach an otherwise-unreachable local/EC2-hosted cluster, and so in-cluster steps (like the HTTP health check) can resolve internal service DNS (`harness-demo-app.harness-demo.svc.cluster.local`).
4. **Trigger**: a GitHub webhook trigger on `harnessci-demo`, firing on Pull Request `Open`/`Reopen`/`Synchronize` against `main`.
5. **Local testing without Docker/Kubernetes**:
   ```bash
   cd app
   pip install -r requirements.txt
   python app.py
   curl http://localhost:8080/health
   ```
6. **Accessing the deployed app** (minikube on EC2, no public NodePort exposure by default):
   ```bash
   # on the EC2 instance:
   kubectl port-forward -n harness-demo svc/harness-demo-app 8080:8080
   # on your local machine, tunnel to it:
   ssh -i <key.pem> -L 8080:localhost:8080 <ec2-user>@<ec2-public-ip>
   # then open http://localhost:8080/health locally
   ```

## Assumptions and trade-offs

- **minikube on an EC2 instance**, not a local machine — explicitly allowed by the assignment ("or use any of the cloud free environments for infrastructure"). This also means the Harness Delegate runs in-cluster to bridge Harness Cloud to an otherwise-unreachable cluster.
- **Build number over commit SHA** for image tags (`<+pipeline.sequenceId>`) — both are explicitly permitted by the assignment; build number was simpler to wire between independently-runnable stages.
- **Full rebuild-and-rescan on every merge to `main`**, rather than promoting the exact artifact already validated during the PR. This is a deliberate simplicity trade-off, not the "Artifact Promotion" bonus pattern — every deploy is guaranteed freshly built and scanned against the merge commit, at the cost of redundant work already done during the PR.
- **`k8s/` plain manifests are kept but unused** for actual deployment — retained only as a record of the project's early scaffolding, before the Helm chart / GitOps split.
