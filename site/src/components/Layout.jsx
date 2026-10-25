import { useLayoutEffect, useRef, useState } from 'react';
import Footer from './Footer';
import Navbar from './Navbar';
import useTheme from './useTheme';

// The footer stays at the bottom of the window on a short page
// (freecodecamp.org/news/how-to-keep-your-footer-where-it-belongs-59c6aa05c59c):
// the container fills the window, the footer sits at its bottom, and the
// content leaves room for it. Our footer's height changes with the width
// (its columns stack on a phone), so the room is measured, not fixed.
const Layout = ({ current, children }) => {
  const [isDark, toggleTheme] = useTheme();
  const footer = useRef(null);
  const [footerHeight, setFooterHeight] = useState(0);

  // Measured before the first paint, so the footer never covers the end of
  // the page while the observer's first report is on its way.
  useLayoutEffect(() => {
    const element = footer.current;
    setFooterHeight(element.offsetHeight);
    const observer = new ResizeObserver(() => setFooterHeight(element.offsetHeight));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  return (
    <div id="page-container">
      <div id="content-wrap" style={{ paddingBottom: `calc(${footerHeight}px + 2.5rem)` }}>
        <Navbar current={current} isDark={isDark} onToggleTheme={toggleTheme} />
        {children}
      </div>
      <Footer ref={footer} />
    </div>
  );
};

export default Layout;
