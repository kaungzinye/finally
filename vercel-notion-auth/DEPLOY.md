# Vercel Deployment Guide

## How It Works

Vercel deployments are independent from git branches. We deploy from the local `vercel-notion-auth/` directory using the CLI. Git branches don't auto-trigger deploys (no GitHub integration connected).

## Stable URL

Production alias: `https://finally-auth.vercel.app`

This alias always points to the latest production deployment. It won't change.

## Deploying

```bash
cd vercel-notion-auth
vercel --prod --yes
vercel alias set <new-deployment-url> finally-auth.vercel.app
```

The alias step re-points the stable URL to your new deployment.

## Environment Variables

Managed via Vercel CLI or dashboard. Current vars:

| Variable | Purpose |
|----------|---------|
| `NOTION_CLIENT_ID` | Notion OAuth client ID |
| `NOTION_CLIENT_SECRET` | Notion OAuth client secret |
| `NOTION_REDIRECT_URI` | `https://finally-auth.vercel.app/api/notion/callback` |

```bash
# List
vercel env ls

# Add/update
echo "value" | vercel env add VAR_NAME production

# Remove
vercel env rm VAR_NAME production --yes
```

## Keeping Git and Vercel in Sync

There's no auto-deploy from git. To stay aligned:

1. Make changes to `vercel-notion-auth/` locally
2. Commit to your branch, merge to `main` when ready
3. Deploy from `main` to production:
   ```bash
   git checkout main
   cd vercel-notion-auth
   vercel --prod --yes
   vercel alias set <deployment-url> finally-auth.vercel.app
   ```

Rule of thumb: only `vercel --prod` from `main`. Use `vercel` (no `--prod`) from feature branches for preview deployments.

## Endpoints

| Path | Method | Purpose |
|------|--------|---------|
| `/api/notion/callback` | GET | Receives OAuth redirect from Notion, bounces to `finally://oauth-callback?code=XXX` |
| `/api/notion/token` | POST | Exchanges authorization code for access token using client secret |
