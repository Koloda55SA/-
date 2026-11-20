const inspectionPaths = new Set(['/auto-issue-preference', '/inspection-driver', '/inspection-result']);
const apiPrefix = '/api/inspections';

export default {
  fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith(apiPrefix + '/')) return env.ASSETS.fetch(request);

    const path = url.pathname.slice(apiPrefix.length);
    if (!inspectionPaths.has(path)) return new Response(null, { status: 404 });

    url.pathname = path;
    return env.ASEM_AUTH.fetch(new Request(url, request));
  },
};
