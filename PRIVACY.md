# Privacy policy for Finally

Last updated: August 27, 2026

Finally is an open-source iOS task manager. The app stores a local task cache and connects only to providers you choose.

## Data on your device

Finally stores task and project data in SwiftData. Provider tokens and server credentials use the iOS Keychain. Widget summaries use the app group shared by the Finally app and its widget extension.

The project does not include advertising or product analytics. Apple may collect diagnostics under your device and App Store settings.

## Notion

When you connect Notion, Finally sends task and project requests to Notion's API. The OAuth relay exchanges the authorization code for a token and returns the result to the app. The relay is designed without application storage for tokens or task data. Vercel may retain infrastructure logs according to the deployment owner's settings.

## Finally Server

When you connect a Finally Server, the app sends credentials during sign-in and sends task data to the server address you enter. The server returns a session token that the app stores in Keychain. Data retention, backups, access logs, and account deletion depend on the operator of that server.

The Finally project does not operate or control independent Finally Server installations.

## Calendar context

A Finally Server deployment can connect to Google Calendar. The server stores Google OAuth tokens encrypted in its configured Redis service. Calendar event content is fetched for a planning request and is designed to remain out of task storage, Redis, and routine application logs. The server operator controls deployment configuration and infrastructure logs.

## Sharing and sale

The Finally project does not sell personal data. Data is sent to Apple, Notion, Vercel, Google, or a Finally Server only when those services are part of the feature you use. Each service has its own terms and privacy policy.

## Delete your data

Disconnecting Notion removes its stored token and signed-in session. Cached task and project rows may remain on the device until the app is deleted. Deleting remote data requires the controls provided by Notion, Google, or your Finally Server operator. Removing the app deletes its local container according to iOS behavior.

## Contact

Open a general issue at [github.com/kaungzinye/finally](https://github.com/kaungzinye/finally). Report vulnerabilities through [SECURITY.md](SECURITY.md).
