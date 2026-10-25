import { useState } from 'react';
import { Check, Copy } from 'lucide-react';

// Lines starting with # are comments: shown dimmed, left out of the copy.
const CodeBlock = ({ code, compact = false }) => {
  const [copied, setCopied] = useState(false);
  const lines = code.trim().split('\n');
  const commands = lines.filter((line) => !line.startsWith('#')).join('\n');

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(commands);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // No clipboard outside a secure page; selecting the text still works.
    }
  };

  return (
    <div className={`group relative my-3 squircle-item bg-[var(--code-bg)] ${compact ? 'text-[12.5px]' : 'text-[14px]'}`}>
      <pre className={`overflow-x-auto scrollbar-hide font-mono leading-relaxed text-[var(--code-text)] ${compact ? 'py-3 pl-3.5 pr-11' : 'py-4 pl-4 pr-12'}`}>
        {lines.map((line, index) => (
          <div key={index} className={line.startsWith('#') ? 'text-[var(--code-muted)]' : undefined}>
            {line || ' '}
          </div>
        ))}
      </pre>
      <button
        onClick={copy}
        className="absolute right-2 top-2 grid size-7 place-items-center squircle-item text-[var(--code-muted)] transition-colors duration-75 hover:bg-white/10 hover:text-[var(--code-text)]"
        aria-label="Copy"
        title="Copy"
      >
        {copied ? <Check size={14} className="text-[var(--amber)]" /> : <Copy size={14} />}
      </button>
    </div>
  );
};

export default CodeBlock;
