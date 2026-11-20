const apiRoutes = new Map([
  ['/api/inspections/auto-issue-preference', '/auto-issue-preference'],
  ['/api/inspections/inspection-driver', '/inspection-driver'],
  ['/api/inspections/inspection-result', '/inspection-result'],
  ['/auth/reset-password', '/reset-password'],
  ['/auth/delete-driver', '/delete-driver'],
]);

export default {
  fetch(request, env) {
    const url = new URL(request.url);
    const target = apiRoutes.get(url.pathname);
    if (target) {
      url.pathname = target;
      return env.ASEM_AUTH.fetch(new Request(url, request));
    }
    if (url.pathname.startsWith('/api/inspections/') || url.pathname.startsWith('/auth/') ||
        ['/recover', '/recover/', '/recover.html'].includes(url.pathname)) {
      return new Response(null, { status: 404 });
    }
    return env.ASSETS.fetch(request);
  },
};
