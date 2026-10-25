import Features from '../components/Features';
import Hero from '../components/Hero';
import Layout from '../components/Layout';
import PluginsSection from '../components/PluginsSection';
import Steps from '../components/Steps';
import WhyRR from '../components/WhyRR';

const HomePage = () => (
  <Layout current="home">
    <main>
      <Hero />
      <Steps />
      <Features />
      <PluginsSection />
      <WhyRR />
    </main>
  </Layout>
);

export default HomePage;
