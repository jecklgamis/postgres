## postgres

[![Build](https://github.com/jecklgamis/postgres/actions/workflows/build.yaml/badge.svg)](https://github.com/jecklgamis/postgres/actions/workflows/build.yaml)

A single-instance PostgreSQL Docker image, built on the official `postgres` base image with TLS and password
authentication enabled.

## Features

* Based on the official `postgres:16-bookworm` image (no compiling Postgres from source)
* TLS-only for network connections (self-signed CA + cert generated at build time); `pg_hba.conf` requires
  `hostssl` + `scram-sha-256` for every host entry
* Password authentication required via `POSTGRES_PASSWORD` (enforced by the base image's entrypoint - it refuses
  to start without one)
* Data persisted under `/var/lib/postgresql/data`
* Docker image on Docker Hub, plus a Helm chart for deploying to Kubernetes

## Quick Start

```bash
docker run -d --name postgres -p 5432:5432 -e POSTGRES_PASSWORD=some-strong-password jecklgamis/postgres:main
```

Connect with `psql`:

```bash
docker exec -it postgres env PGSSLMODE=require psql -U postgres
```

The self-signed cert is only meant for local/dev use - anything beyond that should mount real certs and/or
terminate TLS at a proxy in front of it.

## Getting Started

```bash
git clone https://github.com/jecklgamis/postgres.git
cd postgres
make up POSTGRES_PASSWORD=some-strong-password
```

See the [`Makefile`](Makefile) for other targets (`image`, `run`, `run-bash`).

## Deploying to Kubernetes

A Helm chart is available under [`deployment/k8s/helm/chart`](deployment/k8s/helm/chart) for a single-instance
deployment with persistence, a Secret for `POSTGRES_PASSWORD`, and a ClusterIP service.

Generate a random password and store it as a Secret directly (keeps it out of `values.yaml`, shell history via
`--set`, and Helm's own release values):

```bash
kubectl create namespace postgres
POSTGRES_PASSWORD=$(openssl rand -base64 24)
kubectl create secret generic postgres-credentials -n postgres --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
```

Install the chart, pointing it at that Secret:

```bash
cd deployment/k8s/helm/chart
helm install postgres . -n postgres --set existingSecretName=postgres-credentials --wait
```

See [`deployment/k8s/helm/chart/values.yaml`](deployment/k8s/helm/chart/values.yaml) for other configurable
options (`postgresUser`, `postgresDb`, persistence size, etc).

### Retrieving the password later

```bash
kubectl get secret postgres-credentials -n postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

### Getting the TLS certs

The self-signed CA cert is baked into the image at `/certs/ca.crt` (same cert across pod restarts - it's part of
the image, not regenerated per-pod; a new one is only generated when the image itself is rebuilt). The chart
doesn't create a Secret for it automatically, so after installing, pull the certs out of the running pod once and
store them as a Secret for easy retrieval later (re-run this if you roll out a new image with a regenerated cert):

```bash
POD_NAME=$(kubectl get pods -n postgres -l "app.kubernetes.io/name=postgres,app.kubernetes.io/instance=postgres" -o jsonpath="{.items[0].metadata.name}")
TMPDIR=$(mktemp -d)
kubectl exec -n postgres $POD_NAME -- cat /certs/ca.crt > "$TMPDIR/ca.crt"
kubectl exec -n postgres $POD_NAME -- cat /certs/server.crt > "$TMPDIR/server.crt"
kubectl exec -n postgres $POD_NAME -- cat /certs/server.key > "$TMPDIR/server.key"

kubectl create secret generic postgres-tls-certs -n postgres \
  --from-file=ca.crt="$TMPDIR/ca.crt" \
  --from-file=server.crt="$TMPDIR/server.crt" \
  --from-file=server.key="$TMPDIR/server.key"
rm -rf "$TMPDIR"
```

Retrieve the CA cert later without touching the pod:

```bash
kubectl get secret postgres-tls-certs -n postgres -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

Then connect from any client:

```bash
PGSSLMODE=verify-full PGSSLROOTCERT=ca.crt psql -h <host> -p 5432 -U postgres -d postgres
```

### Accessing it locally

The Service is `ClusterIP` (internal-only), so from your machine you need to port-forward. In one terminal:

```bash
kubectl port-forward -n postgres svc/postgres 5432:5432
```

In another, connect using the CA cert and password from above:

```bash
PGSSLMODE=verify-full PGSSLROOTCERT=ca.crt PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```
