import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// One HTML file per page, so each has its own address: Play links straight
// to privacy.html. Relative paths, so the site works at a domain's root or
// under a path such as GitHub Pages' /rr_pocket/.
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        home: resolve(import.meta.dirname, 'index.html'),
        docs: resolve(import.meta.dirname, 'docs.html'),
        privacy: resolve(import.meta.dirname, 'privacy.html'),
      },
    },
  },
});
