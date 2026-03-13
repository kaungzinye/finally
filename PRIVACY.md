# Privacy Policy — Finally

**Last updated**: March 13, 2026

Finally is a task management app that connects to your Notion workspace. Your privacy matters.

## What We Collect

- **Notion OAuth Token**: Stored locally in your device's Keychain. Used solely to read and write tasks in your Notion workspace.
- **Task Data**: Synced from your Notion workspace and cached locally on your device using SwiftData. Never sent to third-party servers.

## What We Don't Do

- We don't sell your data.
- We don't track your usage with analytics.
- We don't store your data on our servers. The only server component is a stateless token exchange function that forwards your OAuth code to Notion — it retains nothing.
- We don't share your information with third parties.

## Data Storage

- All task data stays on your device.
- Your Notion access token is stored in the iOS Keychain (hardware-encrypted).
- You can disconnect your Notion account at any time from Settings, which deletes all local data.

## Third-Party Services

- **Notion API**: Used to sync your tasks. Subject to [Notion's Privacy Policy](https://www.notion.so/privacy).
- **Vercel**: Hosts a stateless serverless function for OAuth token exchange only. No data is stored.

## Contact

Questions? Open an issue at [github.com/kaungzinye/finally](https://github.com/kaungzinye/finally) or email kaungzinye11@gmail.com.
