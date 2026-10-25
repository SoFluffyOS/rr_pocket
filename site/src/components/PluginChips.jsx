import { plugins } from '../data/plugins';

const PluginChips = () => (
  <ul className="flex flex-wrap gap-1.5">
    {plugins.map((plugin) => (
      <li
        key={plugin}
        className="squircle-item border border-[var(--divider)] bg-[var(--panel-bg)] px-2.5 py-1 font-mono text-[12.5px] text-[var(--text-soft)]"
      >
        {plugin}
      </li>
    ))}
  </ul>
);

export default PluginChips;
