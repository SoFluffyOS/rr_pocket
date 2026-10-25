# RR Pocket's website

https://rr.sofluffy.io, once hosted. The landing page, the docs and the privacy policy, in React with Vite and
Tailwind, as lumide-landing is. The colours are a raccoon's (`src/index.css`):
ash-grey fur, a near-black mask, a cream face, the tail's bands, and
RR Pocket's amber as the one accent.

```sh
npm install
npm run dev      # http://localhost:5173
npm run lint
npm run build    # static files in dist/: index.html, docs.html, privacy.html
```

`dist/` uses relative paths, so it works at a domain's root or under a path
such as GitHub Pages' `/rr_pocket/`. Each page is its own HTML file; Play
links to `privacy.html`. Nunito is served from the site itself, not Google
Fonts, so visiting it sends nothing to anyone else.

The privacy policy's text is also in `../store/privacy-policy.md`; change
both together. The plugin list (`src/data/plugins.js`) follows
`../app/pubspec.yaml`.

## Hosting

Cloudflare Workers Builds deploys it, as lumide-landing: `wrangler.json`
serves `dist/` as static files. Set up once, in the Cloudflare dashboard:

1. Workers & Pages → Create → Import a repository → this repo.
2. Root directory `site`, build command `npm ci && npm run build`, deploy
   command `npx wrangler deploy`.
3. Build watch paths `site/*`, so a change to the app doesn't redeploy the
   site.
4. The worker's Settings → Domains & Routes → add `rr.sofluffy.io`.

After that, each push to `main` that touches `site/` goes live; other
branches get a preview address. `npx wrangler deploy --dry-run` after a
build checks the config without uploading anything.
