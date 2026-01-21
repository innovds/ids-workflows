# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable GitHub Actions workflows for IDS microservices CI/CD. See `README.md` for usage examples and architecture diagrams.

## Key Design Decisions

1. **Docker-only builds**: No Java/Maven on runners. All builds inside Dockerfile.
2. **Build once, deploy everywhere**: Same image promoted via tag manipulation (no rebuild).
3. **OIDC authentication**: No static AWS credentials.
4. **Maven secrets via Docker**: Passed as `--secret id=maven_settings`.

## Structure

- `.github/workflows/` - Reusable workflows (`workflow_call`)
- `actions/` - Composite actions (lower-level building blocks)

## Testing Changes

No runtime code to test. To validate:
1. Reference `@<branch-name>` from a consumer repo
2. Use `yamllint` for syntax validation

## Hardcoded Values

- AWS Region: `eu-west-1`
- ECR Registry: `857736876208.dkr.ecr.eu-west-1.amazonaws.com`
