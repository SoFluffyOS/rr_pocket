import { useEffect, useState } from 'react';

const key = 'rr-theme';

// The HTML sets the starting theme before the first paint; this keeps a
// choice made with the toggle for the next visit.
export default function useTheme() {
  const [isDark, setIsDark] = useState(() => document.documentElement.classList.contains('dark'));

  useEffect(() => {
    document.documentElement.classList.toggle('dark', isDark);
  }, [isDark]);

  const toggle = () => {
    const next = !isDark;
    setIsDark(next);
    try {
      localStorage.setItem(key, next ? 'dark' : 'light');
    } catch {
      // Private windows may refuse storage; the toggle still works.
    }
  };

  return [isDark, toggle];
}
