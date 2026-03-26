interface ResolveUserWorkspaceIdInput {
  defaultWorkspaceId: string;
  requestedWorkspaceId?: string | null;
}

export function resolveUserWorkspaceId(input: ResolveUserWorkspaceIdInput) {
  return input.defaultWorkspaceId;
}
