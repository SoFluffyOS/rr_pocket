// One entry in the docs' troubleshooting list.
const Problem = ({ title, children }) => (
  <div className="my-3 squircle-panel border border-[var(--divider)] px-5 py-4 [&>p:last-child]:mb-0">
    <h3 className="!mt-0">{title}</h3>
    {children}
  </div>
);

export default Problem;
