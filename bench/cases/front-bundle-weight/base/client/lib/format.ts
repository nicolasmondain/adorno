import capitalize from 'lodash/capitalize';

export function formatContactName(firstName: string, lastName: string): string {
  return [firstName, lastName].filter(Boolean).map(capitalize).join(' ');
}
