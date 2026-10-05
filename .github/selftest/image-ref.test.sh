#!/usr/bin/env bash
# The digest-or-tag rule lives inline in three deploy workflows, because a
# reusable workflow cannot source a script from this repository: the checkout
# is the caller's. This test pins the snippet's behaviour and asserts that all
# three copies are identical.
set -euo pipefail
cd "$(dirname "$0")/../.."

# `if`, not `[ … ] && …`: the short form returns 1 on an empty digest and kills
# any caller running under `set -e`.
SNIPPET='IMAGE_REF="${IMAGE_REPO}:${IMAGE_TAG}"
if [ -n "${IMAGE_DIGEST}" ]; then IMAGE_REF="${IMAGE_REPO}@${IMAGE_DIGEST}"; fi'

fails=0
for f in shared-deploy-eks shared-deploy-ec2 shared-deploy-ec2-vpn; do
  python3 - "$f" "$SNIPPET" <<'PY' || fails=$((fails+1))
import sys,textwrap
f,snip=sys.argv[1],sys.argv[2]
body=open(f'.github/workflows/{f}.yml').read()
lines=[l.strip() for l in snip.splitlines()]
flat=[l.strip() for l in body.splitlines()]
ok=any(flat[i:i+len(lines)]==lines for i in range(len(flat)))
print(('ok   ' if ok else 'FAIL ')+f+' carries the image-ref snippet')
sys.exit(0 if ok else 1)
PY
done

ref() { IMAGE_REPO=r.example/app IMAGE_TAG=$1 IMAGE_DIGEST=$2 bash -c "set -e; $SNIPPET; echo \"\$IMAGE_REF\""; }
D=sha256:$(printf 'a%.0s' {1..64})
[ "$(ref abc1234 '')" = 'r.example/app:abc1234' ] && echo 'ok   no digest -> tag' || { echo 'FAIL no digest -> tag'; fails=$((fails+1)); }
[ "$(ref abc1234 "$D")" = "r.example/app@$D" ]   && echo 'ok   digest wins'     || { echo 'FAIL digest wins'; fails=$((fails+1)); }

# Helm must keep deploying by tag: ${IMAGE_URI%:*} on a digest ref is garbage.
# grep -F, not rg: ripgrep is not on every runner image, and fixed strings
# spare the escaping.
grep -qF -- '--set image.repository=${IMAGE_URI%:*}' .github/workflows/shared-deploy-eks.yml \
  && ! grep -qF 'IMAGE_URI: ${{ steps.setup.outputs.image_ref' .github/workflows/shared-deploy-eks.yml \
  && echo 'ok   helm keeps tag' || { echo 'FAIL helm keeps tag'; fails=$((fails+1)); }

echo "$fails failing case(s)"; exit $((fails > 0))
