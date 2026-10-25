// A line drawing of a raccoon's face, for the footer, as Lumide's has its fox.
const RaccoonMark = ({ className = '' }) => (
  <svg viewBox="0 0 100 100" className={className} xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <g fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round" strokeLinecap="round">
      {/* Ears, rounded as a raccoon's are */}
      <path d="M 22,36 C 17,22 24,12 33,15 C 38,17 41,22 42,27" />
      <path d="M 27,30 C 25,23 28,19 32,20 C 35,21 37,24 37,26" />
      <path d="M 78,36 C 83,22 76,12 67,15 C 62,17 59,22 58,27" />
      <path d="M 73,30 C 75,23 72,19 68,20 C 65,21 63,24 63,26" />
      {/* Head */}
      <path d="M 16,48 C 16,30 34,24 50,24 C 66,24 84,30 84,48 C 84,66 66,84 50,86 C 34,84 16,66 16,48 Z" />
      {/* Mask */}
      <path d="M 18,46 C 26,38 38,40 46,48 L 50,52 L 54,48 C 62,40 74,38 82,46 L 80,58 C 72,64 62,62 55,58 L 50,62 L 45,58 C 38,62 28,64 20,58 Z" fill="currentColor" fillOpacity="0.18" />
      {/* Eyes */}
      <circle cx="34" cy="51" r="3.5" fill="currentColor" fillOpacity="0.5" />
      <circle cx="66" cy="51" r="3.5" fill="currentColor" fillOpacity="0.5" />
      {/* Nose and mouth */}
      <path d="M 45,70 L 55,70 L 50,75 Z" fill="currentColor" fillOpacity="0.5" />
      <path d="M 50,75 L 50,78 M 44,79 C 47,82 50,80 50,78 C 50,80 53,82 56,79" />
    </g>
  </svg>
);

export default RaccoonMark;
