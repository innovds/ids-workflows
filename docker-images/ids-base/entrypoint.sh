#!/bin/sh

# APM: auto-configure from SPRING_PROFILES_ACTIVE
if echo "$SPRING_PROFILES_ACTIVE" | grep -q "prod"; then
  export ELASTIC_APM_ENABLED=false
else
  export ELASTIC_APM_ENABLED=true
  if echo "$SPRING_PROFILES_ACTIVE" | grep -q "stg"; then
    export ELASTIC_APM_ENVIRONMENT=stg
  elif echo "$SPRING_PROFILES_ACTIVE" | grep -q "int"; then
    export ELASTIC_APM_ENVIRONMENT=int
  else
    export ELASTIC_APM_ENVIRONMENT=local
  fi
fi

exec "$@"
