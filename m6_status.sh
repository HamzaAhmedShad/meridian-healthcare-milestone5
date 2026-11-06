#!/usr/bin/env bash
# m6_status.sh - collects the state of your project for Milestone 6.
# Run from the ROOT of your repo, with gcloud and kubectl already authenticated.
# Output goes to m6_status.txt. Review it for secrets before pasting.

OUT="m6_status.txt"
: > "$OUT"

section() { printf '\n\n===== %s =====\n' "$1" >> "$OUT"; }
run() {
  printf '\n$ %s\n' "$*" >> "$OUT"
  "$@" >> "$OUT" 2>&1 || echo "(command failed or not available)" >> "$OUT"
}
runsh() {
  printf '\n$ %s\n' "$1" >> "$OUT"
  bash -c "$1" >> "$OUT" 2>&1 || echo "(command failed or not available)" >> "$OUT"
}

section "0. GCP CONTEXT"
run gcloud config list
runsh "gcloud auth list --format='value(account)'"

section "1. REPO STRUCTURE"
runsh "git remote -v"
runsh "git branch -a"
runsh "git log --oneline -n 10"
runsh "find . -maxdepth 3 -not -path '*/node_modules*' -not -path '*/.git/*' -not -path '*/venv/*' -not -path '*/.venv/*' -not -path '*/__pycache__/*' -not -path '*/.terraform/*' | sort | head -150"

section "2. APP STACK (dependency files)"
runsh "cat package.json 2>/dev/null | head -50"
runsh "cat requirements.txt 2>/dev/null"
runsh "cat go.mod 2>/dev/null | head -30"
runsh "cat pom.xml 2>/dev/null | head -50"

section "3. DOCKERFILE"
runsh "cat Dockerfile 2>/dev/null || find . -name Dockerfile -not -path '*/node_modules/*' -exec sh -c 'echo \"--- {}\"; cat {}' \\;"

section "4. KUBERNETES MANIFESTS"
runsh "find . \\( -name '*.yaml' -o -name '*.yml' \\) -not -path '*/node_modules/*' -not -path '*/.github/*' -not -path '*/.terraform/*' | head -50"
runsh "for f in \$(grep -rlE 'kind: *(Deployment|Service|Ingress|HorizontalPodAutoscaler|PodDisruptionBudget|ManagedCertificate)' . --include='*.yaml' --include='*.yml' 2>/dev/null | grep -v node_modules); do echo \"--- \$f\"; sed -E 's/(password|secret|key|token)(.*:).*/\\1\\2 <REDACTED>/I' \"\$f\"; done"

section "5. LIVE CLUSTER STATE"
run kubectl config current-context
run kubectl get nodes
run kubectl get pods -A -o wide
run kubectl get deploy,svc,ingress,hpa,pdb -A
run kubectl get managedcertificate -A
runsh "kubectl rollout history deployment --all-namespaces 2>&1 | head -40"

section "6. APPLICATION LOGGING (is it JSON?)"
runsh "kubectl logs deploy/\$(kubectl get deploy -o jsonpath='{.items[0].metadata.name}') --tail=10"
runsh "grep -rniE 'winston|pino|structlog|python-json-logger|logging\\.|console\\.log|zap|logrus|slog' . --include='*.js' --include='*.ts' --include='*.py' --include='*.go' --include='*.java' --exclude-dir=node_modules --exclude-dir=venv --exclude-dir=.venv 2>/dev/null | head -30"

section "7. CLOUD LOGGING: LOG-BASED METRICS"
run gcloud logging metrics list --format=yaml
section "7b. RECENT 5xx LOGS (last 1h)"
runsh "gcloud logging read '(jsonPayload.status>=500 OR httpRequest.status>=500)' --freshness=1h --limit=3 --format=json"

section "8. MONITORING: DASHBOARDS"
runsh "gcloud monitoring dashboards list --format='table(name,displayName)'"

section "9. MONITORING: ALERT POLICIES"
runsh "gcloud alpha monitoring policies list --format='yaml(name,displayName,enabled,conditions,notificationChannels)'"
section "9b. NOTIFICATION CHANNELS"
runsh "gcloud alpha monitoring channels list --format='table(name,displayName,type,enabled)'"

section "10. TERRAFORM"
runsh "find . -name '*.tf' -not -path '*/.terraform/*'"
runsh "find . -name '*.tfvars' -not -path '*/.terraform/*'"
runsh "for f in \$(find . -name '*.tf' -not -path '*/.terraform/*'); do echo \"--- \$f\"; cat \"\$f\"; done | head -400"
runsh "terraform version"
runsh "terraform state list"
printf '\n(Running terraform plan, refresh on by default; this can take a minute)\n' >> "$OUT"
runsh "terraform plan -input=false -no-color 2>&1 | tail -60"

section "11. EXISTING GCP RESOURCES (to compare against Terraform)"
run gcloud container clusters list
run gcloud sql instances list
run gcloud storage buckets list --format='value(name)'
run gcloud artifacts repositories list
run gcloud secrets list --format='value(name)'
run gcloud iam service-accounts list --format='table(email,displayName)'
run gcloud compute networks list
run gcloud compute addresses list
run gcloud dns managed-zones list

section "12. CI/CD"
runsh "ls -la .github/workflows 2>/dev/null"
runsh "for f in .github/workflows/*; do [ -f \"\$f\" ] && { echo \"--- \$f\"; cat \"\$f\"; }; done"
runsh "cat cloudbuild.yaml 2>/dev/null"
run gcloud builds triggers list --format='table(name,filename,github.push.branch)'
run gcloud builds list --limit=5

section "13. HEALTH ENDPOINTS IN CODE"
runsh "grep -rniE '/health|/healthz|/ready|readinessProbe|livenessProbe' . --include='*.js' --include='*.ts' --include='*.py' --include='*.go' --include='*.java' --include='*.yaml' --include='*.yml' --exclude-dir=node_modules --exclude-dir=.terraform 2>/dev/null | head -20"

# Light redaction pass over the output file
sed -i.bak -E \
  -e 's/(password|passwd|secret|token|api[_-]?key|private_key)([\"'\'' ]*[:=][\"'\'' ]*)[^\"'\'' ,]+/\1\2<REDACTED>/Ig' \
  -e 's/AIza[0-9A-Za-z_-]{35}/<REDACTED_GOOGLE_KEY>/g' \
  -e 's/ghp_[0-9A-Za-z]{36}/<REDACTED_GH_TOKEN>/g' \
  "$OUT" && rm -f "$OUT.bak"

echo "Done. Review $OUT, then paste it (or upload it) into the chat."
