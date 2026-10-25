import Footer from './Footer';
import Navbar from './Navbar';
import useTheme from './useTheme';

const Layout = ({ current, children }) => {
  const [isDark, toggleTheme] = useTheme();
  return (
    <div className="min-h-screen">
      <Navbar current={current} isDark={isDark} onToggleTheme={toggleTheme} />
      {children}
      <Footer />
    </div>
  );
};

export default Layout;
