export async function loadAdminDashboardState<TDashboard>(
  session: {
    authenticated: boolean;
  },
  loader: () => Promise<TDashboard>
) {
  if (!session.authenticated) {
    return {
      dashboard: null as TDashboard | null,
      dashboardError: '',
    };
  }

  try {
    return {
      dashboard: await loader(),
      dashboardError: '',
    };
  } catch (error) {
    console.error('Failed to load admin dashboard data', error);
    return {
      dashboard: null as TDashboard | null,
      dashboardError: '后台数据加载失败，请稍后重试',
    };
  }
}
