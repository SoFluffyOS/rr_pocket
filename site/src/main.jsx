import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import HomePage from './pages/HomePage';
import DocsPage from './pages/DocsPage';
import PrivacyPage from './pages/PrivacyPage';

// Each HTML file names its page on #root.
const root = document.getElementById('root');
const Page = { docs: DocsPage, privacy: PrivacyPage }[root.dataset.page] ?? HomePage;

createRoot(root).render(
  <StrictMode>
    <Page />
  </StrictMode>,
);
