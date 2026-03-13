import type { VercelRequest, VercelResponse } from "@vercel/node";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const { code, error } = req.query;

  if (error) {
    return res.status(400).send(`
      <html><body style="font-family:system-ui;text-align:center;padding:60px">
        <h2>Authorization failed</h2>
        <p>${error}</p>
      </body></html>
    `);
  }

  if (!code) {
    return res.status(400).send(`
      <html><body style="font-family:system-ui;text-align:center;padding:60px">
        <h2>Missing authorization code</h2>
      </body></html>
    `);
  }

  // Redirect to the iOS app with the code
  const appURL = `finally://oauth-callback?code=${code}`;

  return res.status(200).send(`
    <html>
      <head>
        <meta http-equiv="refresh" content="0;url=${appURL}">
      </head>
      <body style="font-family:system-ui;text-align:center;padding:60px">
        <h2>Redirecting to Finally...</h2>
        <p>If the app doesn't open, <a href="${appURL}">tap here</a>.</p>
      </body>
    </html>
  `);
}
