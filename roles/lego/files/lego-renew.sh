#!/bin/bash

set -e

export LEGO_PATH=/etc/lego

# LEGO_SERVER and the DNS provider credentials, written by the lego role.
set -a
. /etc/lego/env
set +a

# With no argument, checks every registered domain; a site setup passes one to
# issue a single new certificate.
domain=${1:-*}

for env_file in /etc/lego/renew.d/$domain.env; do
  [[ -e $env_file ]] || continue

  # LEGO_DOMAINS and LEGO_DNS vary per site: one file per domain, written as
  # the site is set up. The certificate cannot stand in for these -- it records
  # the domains it was issued for, but never which DNS provider proved them.
  set -a
  . "$env_file"
  set +a

  echo "Checking $LEGO_DOMAINS via $LEGO_DNS"
  # lego 5.x has no `renew` command: `run` issues or renews as needed, and
  # decides due-ness itself from the certificate lifetime.
  lego run --accept-tos --deploy-hook 'systemctl reload nginx'
done
