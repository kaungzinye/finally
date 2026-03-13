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

  const appURL = `finally://oauth-callback?code=${code}`;

  // Use JavaScript redirect — Safari blocks meta refresh and 302 to custom schemes
  return res.status(200).send(`
    <html>
      <head>
        <title>Redirecting to Finally...</title>
      </head>
      <body style="font-family:system-ui;text-align:center;padding:60px">
        <h2>Redirecting to Finally...</h2>
        <p>If the app doesn't open automatically, <a id="link" href="${appURL}">tap here to open Finally</a>.</p>
        <script>
          window.location.href = "${appURL}";
        </script>
      </body>
    </html>
  `);
}
