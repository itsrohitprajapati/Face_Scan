import { useEffect, useState } from 'react'
import type React from 'react'
import { LogOut, ScanFace } from 'lucide-react'
import { api, authStore } from './api'
import type { AuthSession, User } from './types'
import { AuthPage } from './components/auth/AuthPage'
import { AdminDashboard } from './components/admin/AdminDashboard'
import { TeacherDashboard } from './components/teacher/TeacherDashboard'
import { StudentDashboard } from './components/student/StudentDashboard'
import './styles.css'

type Page = 'login' | 'register' | 'admin' | 'teacher' | 'student'

function App() {
  const [user, setUser] = useState<User | null>(null)
  const [page, setPage] = useState<Page>('login')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!authStore.getToken()) { setLoading(false); return }
    api.me().then(setUser).catch(() => authStore.clear()).finally(() => setLoading(false))
  }, [])

  const signIn = (session: AuthSession) => { authStore.setToken(session.access_token); setUser(session.user); setPage(session.user.role) }
  const signOut = () => { authStore.clear(); setUser(null); setPage('login') }
  if (loading) return <div className="grid min-h-screen place-items-center text-sm text-[var(--muted)]">Loading workspace…</div>
  if (!user) return <AuthPage page={page === 'admin' || page === 'teacher' || page === 'student' ? 'login' : page} onAuth={signIn} onPage={setPage} />
  return <Shell user={user} onSignOut={signOut}>{user.role === 'admin' ? <AdminDashboard /> : user.role === 'teacher' ? <TeacherDashboard /> : <StudentDashboard user={user} />}</Shell>
}

function Shell({ user, onSignOut, children }: { user: User; onSignOut: () => void; children: React.ReactNode }) {
  return <div className="min-h-screen"><header className="border-b border-[var(--line)] bg-white"><div className="mx-auto flex max-w-[1440px] items-center justify-between px-5 py-4 lg:px-10"><div className="flex items-center gap-3 text-sm font-bold tracking-[.12em] text-[var(--green)]"><span className="grid size-8 place-items-center rounded-md bg-[var(--green-soft)]"><ScanFace size={17} /></span> ATTEN</div><div className="flex items-center gap-4"><div className="hidden text-right sm:block"><p className="text-sm font-bold">{user.full_name}</p><p className="text-xs capitalize text-[var(--muted)]">{user.role} workspace</p></div><button title="Sign out" onClick={onSignOut} className="grid size-9 place-items-center rounded-md border border-[var(--line)] text-[var(--muted)] hover:bg-[#f4f6f3]"><LogOut size={16} /></button></div></div></header><main className="mx-auto max-w-[1440px] px-5 py-8 lg:px-10 lg:py-12">{children}</main></div>
}

export default App
