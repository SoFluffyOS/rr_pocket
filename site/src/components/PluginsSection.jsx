import { plugins } from '../data/plugins';
import Code from './Code';
import PluginChips from './PluginChips';

const PluginsSection = () => (
  <section id="plugins" className="app-section">
    <div className="section-panel md:px-10">
      <h2 className="section-title">{plugins.length} plugins built in.</h2>
      <p className="section-copy mt-3 max-w-2xl text-[16px]">
        Your app can use these as they are. <Code>pocket pin</Code> matches your project&apos;s versions to the ones RR Pocket
        carries. Plain Dart packages, Hive CE among them, need nothing.
      </p>
      <div className="mt-7">
        <PluginChips />
      </div>
    </div>
  </section>
);

export default PluginsSection;
