import type { SVGProps } from 'react';

export function PencilIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 16 16" width="16" height="16" {...props}>
      <path d="M11.5 1.5l3 3-9 9h-3v-3z" />
    </svg>
  );
}

export function TrashIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 16 16" width="16" height="16" {...props}>
      <path d="M3 4h10l-1 10H4zM6 2h4v2H6z" />
    </svg>
  );
}
