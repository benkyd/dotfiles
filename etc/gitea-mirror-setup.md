# Gitea: Pull Mirror Setup for GitHub Repos

Mirror GitHub repos to a self-hosted Gitea instance automatically.
Gitea's built-in pull mirror feature handles the scheduling internally.

## Via the UI (per-repo)

1. Go to the repo on Gitea
2. **Settings > Repository > Mirror Settings**
3. Enable pull mirror
4. Set clone URL: `https://github.com/youruser/repo.git`
5. For private repos, add a GitHub Personal Access Token as authorization
6. Set the **Mirror Interval** (e.g., `24h`, `8h`, `1h0m0s`)
7. Save

## Via the API (bulk setup)

Your Gitea instance serves API docs at `https://YOUR-GITEA/api/swagger`.

### Option 1: Patch existing repo to mirror

```
PATCH /api/v1/repos/{owner}/{repo}
```

```bash
curl -X PATCH "https://your-gitea/api/v1/repos/youruser/repo-name" \
  -H "Authorization: token YOUR_GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "mirror": true,
    "mirror_interval": "24h"
  }'
```

Note: Converting non-mirror repos via PATCH can be finicky in some Gitea versions.
If it doesn't work, use the migrate endpoint instead (Option 2).

### Option 2: Delete and re-create as mirror (more reliable)

```
POST /api/v1/repos/migrate
```

```bash
curl -X POST "https://your-gitea/api/v1/repos/migrate" \
  -H "Authorization: token YOUR_GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clone_addr": "https://github.com/youruser/repo-name.git",
    "auth_token": "YOUR_GITHUB_TOKEN",
    "repo_name": "repo-name",
    "repo_owner": "youruser",
    "mirror": true,
    "mirror_interval": "24h",
    "service": "github"
  }'
```

## Server-side config (`app.ini`)

Set global mirror interval defaults:

```ini
[mirror]
MIN_INTERVAL = 1h
DEFAULT_INTERVAL = 24h
```

## Reference

- Gitea mirror docs: https://docs.gitea.com/usage/repo-mirror
- Your instance's API docs: https://YOUR-GITEA/api/swagger
