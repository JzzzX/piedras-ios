interface ResolveUserWorkspaceIdInput {
  defaultWorkspaceId: string;
  requestedWorkspaceId?: string | null;
  accessibleWorkspaceIds?: string[];
}

export function resolveUserWorkspaceId(input: ResolveUserWorkspaceIdInput) {
  const requestedWorkspaceId = input.requestedWorkspaceId?.trim();
  if (
    requestedWorkspaceId &&
    input.accessibleWorkspaceIds?.includes(requestedWorkspaceId)
  ) {
    return requestedWorkspaceId;
  }

  return input.defaultWorkspaceId;
}
