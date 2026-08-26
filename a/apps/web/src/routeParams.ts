// Lightweight query-param routing helpers. No router library is installed in this app, so
// class/student selection is reflected in the URL (?class=<id>&student=<id>) via the History
// API directly. This keeps deep links and back/forward navigation working without pulling in
// a routing dependency.

export function readQueryParams(): { classId: string | null; studentId: string | null } {
  const params = new URLSearchParams(window.location.search)
  return { classId: params.get('class'), studentId: params.get('student') }
}

export function writeQueryParams(next: { classId?: string | null; studentId?: string | null }, push: boolean): void {
  const params = new URLSearchParams(window.location.search)
  if (next.classId !== undefined) {
    if (next.classId) params.set('class', next.classId)
    else params.delete('class')
  }
  if (next.studentId !== undefined) {
    if (next.studentId) params.set('student', next.studentId)
    else params.delete('student')
  }
  const query = params.toString()
  const url = `${window.location.pathname}${query ? `?${query}` : ''}`
  if (push) window.history.pushState({}, '', url)
  else window.history.replaceState({}, '', url)
}
