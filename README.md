![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Ready-blue)
![Vault](https://img.shields.io/badge/Secrets-HashiCorp%20Vault-000000?logo=vault&logoColor=white)

# HashiCorp Vault: Initialization, Auto-Unseal, Raft Join & Kubernetes Auth

This document explains how to:

- Initialize HashiCorp Vault with Raft storage
- Enable Vault auto-unseal using Google Cloud KMS
- Join additional Vault pods to a Raft cluster
- Configure Kubernetes authentication for applications
- Integrate the setup with GitHub Actions and Terraform

This setup reflects a **production-grade Vault deployment**  and is suitable for **platform engineering and GitOps-based environments**.

---

## 📌 Prerequisites

### Infrastructure
- Kubernetes cluster
- Vault deployed with Raft storage
- Google Cloud project
- Google Cloud KMS enabled
- GitHub repository with Actions enabled

### for minikube

```bash
minikube start --driver=docker --cni=cilium --nodes 3

```

---

## 🔐 GitHub Actions Secrets

The following secrets must be created in **GitHub → Repository → Settings → Secrets and variables → Actions**.

### Required Secrets

| Secret Name | Description | Example |
|------------|------------|---------|
| `BUCKET_TF_STATE` | GCS bucket name for Terraform state | `tf-state-prod` |
| `GCP_PROJECT` | Google Cloud project ID | `my-prod-123456` |
| `TF_KEY_RING_NAME` | GCP KMS key ring name | `vault-keyring` |
| `TF_CRYPTO_KEY_NAME` | GCP KMS crypto key name | `vault-unseal-key` |
| `TF_SERVICE_ACCOUNT_NAME` | GCP service account **account_id** | `vault-kms-unseal` |

> ⚠️ Use the **service account name**, not the full email, unless your Terraform module explicitly requires it.

---

### GitHub Actions Environment Mapping

```yaml
env:
  BUCKET_TF_STATE: ${{ secrets.BUCKET_TF_STATE }}
  TF_VAR_project_id: ${{ secrets.GCP_PROJECT }}
  TF_VAR_key_ring_name: ${{ secrets.TF_KEY_RING_NAME }}
  TF_VAR_crypto_key_name: ${{ secrets.TF_CRYPTO_KEY_NAME }}
  TF_VAR_service_account_name: ${{ secrets.TF_SERVICE_ACCOUNT_NAME }}
```
## 🧱 Initialize Vault (One-Time)

Vault must be initialized once before it can be used.  
Initialization generates unseal keys and a root token.

```bash
kubectl -n vault exec -i vault-0 -- \
  vault operator init \
    -recovery-shares=1 \
    -recovery-threshold=1 \
    -format=json
```
**Initialization Details** 

`recovery-shares=1` : Number of recovery keys generated
`recovery-threshold=1` : Minimum number of recovery keys required for recovery operations
`format=json` : Structured output for easier handling

**⚠️ Important**

* Recovery keys are **NOT used for unsealing**
* Vault auto-unseals using **Google Cloud KMS**
* Store the recovery key and initial root token securely

## 🔓 Auto-Unseal Behavior

After initialization:
* Vault unseals automatically
* Pod restarts and rescheduling require no manual action
* New Vault pods auto-unseal after joining the Raft cluster

Verify status:

```bash 
kubectl -n vault exec -i vault-0 -- \
  vault status
``` 
Expected output: `Sealed: false`

## 🔗 Join Vault Pods to the Raft Cluster
After the first Vault pod is initialized, additional Vault pods can join the Raft cluster.

**Join vault-1**

```bash
kubectl -n vault exec -i vault-1 -- \
  sh -c "vault operator raft join http://vault-0.vault-internal.vault.svc:8200"
```

**Join vault-2**

```bash
kubectl -n vault exec -i vault-2 -- \
  sh -c "vault operator raft join http://vault-0.vault-internal.vault.svc:8200"
```

## 🛡️ Create an Application Policy
This policy allows an application to read a specific secret path.

```bash
vault policy write app - <<EOF
path "secret/data/hello-world/my-secret" {
  capabilities = ["read"]
}
EOF

```
**Policy Scope**

* Read-only access
* Restricted to a single secret path
* Follows the principle of least privilege

## 🔑 Configure Kubernetes Authentication

Bind a Kubernetes ServiceAccount to the Vault policy

```bash
vault write auth/kubernetes/role/app \
  bound_service_account_names=app \
  bound_service_account_namespaces=default \
  policies=app \
  ttl=24h
```
**What This Enables**

* Pods using the `app` ServiceAccount in the default namespace can authenticate to Vault
* Vault issues tokens with the `app` policy attached
* Tokens are valid for 24 hours

## Configure the database secrets engine

* Enable the database secrets engine

```bash
vault secrets enable database

```
* Configure the database secrets engine with the connection credentials for the PostgreSQL database.

```bash
vault write database/config/postgres \
     plugin_name=postgresql-database-plugin \
     connection_url="postgresql://{{username}}:{{password}}@$POSTGRES_URL/postgres" \
     allowed_roles=readonly \
     username="$POSTGRES_USER" \
     password="$POSTGRES_PASSWORD"
```
## Create a role : a logical name within Vault that maps to database credentials.

* Define the SQL used to create credentials.

```bash
tee readonly.sql <<EOF
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT;
GRANT ro TO "{{name}}";
EOF
```

* Create the role named readonly that creates credentials with the readonly.sql.

```bash
vault write database/roles/readonly \
      db_name=postgres \
      creation_statements=@readonly.sql \
      default_ttl=1h \
      max_ttl=24h

```
 ## Request dynamic credentials

* Read credentials from the readonly database role.

```bash
vault read database/creds/readonly

```
## Verify the configuration

```bash
export VAULT_ADDR=https://vault.example.com
export VAULT_TOKEN=$(k -n vault get secrets vault-root-token -o jsonpath='{.data.token}' | base64 -d)
CREDS=$(vault read -format=json database/creds/readonly) && echo "$CREDS"
```


## Test the dynamic credentials

```bash
k -n postgresql exec -it postgresql-0 -c postgresql -- bash -lc "psql -h postgresql.postgresql.svc.cluster.local -p 5432 -U $(echo $CREDS | jq -r .data.username) postgres"

```
## Revoke the lease

```bash
vault lease revoke -prefix database/creds/readonly
```