# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable GitHub Actions workflows for IDS microservices CI/CD. Multi-org support via templates.

## Key Design Decisions

1. **Docker-only builds**: No Java/Maven on runners, all builds inside Dockerfile
2. **Build once, deploy everywhere**: Same image promoted via tag manipulation
3. **Registry-agnostic**: `docker-build-push` works with any registry (ECR, Docker Hub, GHCR, GCR)
4. **OIDC authentication**: No static AWS credentials
5. **Template-based config**: Placeholders `{{VAR}}` in `templates/`, rendered via `scripts/render.sh`

## Structure

```
templates/              # Sources with {{placeholders}}
├── .github/workflows/
├── actions/
└── scripts/

.github/workflows/      # Generated files
actions/                # Generated files
scripts/
├── render.sh           # Generates from templates
├── init-repo.sh        # Generated
└── setup-secrets.sh    # Generated

config.example.sh       # Config template
config.local.sh         # Local config (gitignored)
```

## Development Workflow

```bash
# 1. Edit templates in templates/
# 2. Render for target org
./scripts/render.sh                    # Uses config.local.sh or config.example.sh
./scripts/render.sh config.client.sh   # Uses specific config
```

## Placeholders

| Placeholder | Example |
|-------------|---------|
| `{{ORG_NAME}}` | `ids-aws` |
| `{{AWS_ACCOUNT_ID}}` | `857736876208` |
| `{{AWS_REGION}}` | `eu-west-1` |
| `{{ECR_REGISTRY}}` | `857736876208.dkr.ecr.eu-west-1.amazonaws.com` |

## Actions

| Action | Purpose | Registry-agnostic |
|--------|---------|-------------------|
| `docker-build-push` | Build & push | ✅ Yes |
| `ecr-login` | AWS ECR login | ECR only |
| `ecs-deploy` | ECS Fargate deploy | AWS only |
| `docker-test` | Run tests | - |
| `maven-settings` | Prepare settings.xml | - |
