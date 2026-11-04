#!/bin/zsh
# Publish site/ to https://jot.qiaomu.ai (Nginx static root on the Qiaomu VPS, ssh alias `myvps`).
# Vhost: /www/server/panel/vhost/nginx/jot.qiaomu.ai.conf · TLS: Let's Encrypt via certbot webroot.
set -euo pipefail
cd "$(dirname "$0")/.."
rsync -az --delete --exclude .DS_Store site/ myvps:/www/wwwroot/jot.qiaomu.ai/
ssh myvps 'chown -R www:www /www/wwwroot/jot.qiaomu.ai'
curl -fsS -o /dev/null -w "jot.qiaomu.ai %{http_code}\n" https://jot.qiaomu.ai/
