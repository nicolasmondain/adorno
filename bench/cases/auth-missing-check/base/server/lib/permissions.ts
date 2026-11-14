export type Permission = 'invoices:read' | 'invoices:write';

export interface Member {
  id: string;
  accountId: string;
  permissions: Permission[];
}

export class ForbiddenError extends Error {
  readonly status = 403;
}

export function requirePermission(member: Member, permission: Permission): void {
  if (!member.permissions.includes(permission)) {
    throw new ForbiddenError(`missing permission: ${permission}`);
  }
}
