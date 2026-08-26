import { useState } from 'react'
import type React from 'react'
import { ArrowRight, ScanFace, ShieldCheck } from 'lucide-react'
import { api, ApiError } from '../../api'
import type { AuthSession } from '../../types'
import { CameraCapture } from './CameraCapture'
import { Field, Notice } from '../ui/primitives'

export function AuthPage({ page, onAuth, onPage }: { page: 'login' | 'register'; onAuth: (session: AuthSession) => void; onPage: (page: 'login' | 'register' | 'admin' | 'teacher' | 'student') => void }) {
  const [role, setRole] = useState<'admin' | 'teacher' | 'student'>('student')
  const [form, setForm] = useState({ full_name: '', roll_number: '', email: '', password: '', invite_code: '' })
  const [photos, setPhotos] = useState<Blob[]>([])
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const update = (key: keyof typeof form) => (event: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [key]: event.target.value })
  const submit = async (event: React.FormEvent) => {
    event.preventDefault(); setError(''); setBusy(true)
    try {
      const session = page === 'login' ? await api.login(form.email, form.password) : role === 'teacher'
        ? await api.registerTeacher(form) : role === 'admin' ? await api.registerAdmin(form) : await api.registerStudent({ ...form, photos })
      onAuth(session)
    } catch (error) { setError(error instanceof ApiError ? error.message : 'Unable to connect to the API.') }
    finally { setBusy(false) }
  }
  return <main className="grid min-h-screen lg:grid-cols-[minmax(340px,0.8fr)_1.2fr]">
    <section className="hidden bg-[#173e2f] p-12 text-white lg:flex lg:flex-col lg:justify-between">
      <div><div className="mb-20 flex items-center gap-3 text-sm font-semibold tracking-[.12em]"><span className="grid size-9 place-items-center rounded-md bg-[#d7eddf] text-[#173e2f]"><ScanFace size={19} /></span> ATTEN</div><p className="max-w-sm text-5xl font-semibold leading-[1.05] tracking-[-.04em]">Attendance that sees the whole classroom.</p><p className="mt-6 max-w-sm text-base leading-7 text-[#b8d2c1]">A privacy-first classroom workspace for recognition, review, and clear attendance records.</p></div>
      <div className="flex items-center gap-3 text-sm text-[#b8d2c1]"><ShieldCheck size={17} /> Local recognition · Teacher controlled</div>
    </section>
    <section className={`flex items-center justify-center p-6 sm:p-12 ${page === 'register' && role === 'student' ? 'lg:p-10' : ''}`}><div className={`w-full fade-in ${page === 'register' && role === 'student' ? 'max-w-3xl' : 'max-w-md'}`}>
      <div className="mb-10 lg:hidden"><div className="flex items-center gap-3 text-sm font-bold tracking-[.12em] text-[var(--green)]"><ScanFace size={22} /> ATTEN</div></div>
      <div className="mb-8"><p className="mb-3 text-xs font-bold uppercase tracking-[.16em] text-[var(--green)]">{page === 'login' ? 'Welcome back' : 'Create workspace access'}</p><h1 className="text-3xl font-semibold tracking-[-.03em]">{page === 'login' ? 'Sign in to Atten' : 'Set up your account'}</h1><p className="mt-2 text-sm leading-6 text-[var(--muted)]">{page === 'login' ? 'Continue to your classroom workspace.' : 'Choose your role to get started.'}</p></div>
        {page === 'register' && <div className="mb-6 grid grid-cols-3 gap-2 rounded-lg bg-[#e9ede9] p-1"><button onClick={() => setRole('student')} className={`rounded-md py-2.5 text-sm font-semibold ${role === 'student' ? 'bg-white text-[var(--green)] shadow-sm' : 'text-[var(--muted)]'}`}>Student</button><button onClick={() => setRole('teacher')} className={`rounded-md py-2.5 text-sm font-semibold ${role === 'teacher' ? 'bg-white text-[var(--green)] shadow-sm' : 'text-[var(--muted)]'}`}>Teacher</button><button onClick={() => setRole('admin')} className={`rounded-md py-2.5 text-sm font-semibold ${role === 'admin' ? 'bg-white text-[var(--green)] shadow-sm' : 'text-[var(--muted)]'}`}>Admin</button></div>}
      <form onSubmit={submit} className="space-y-4">
        {page === 'register' && <Field label="Full name" value={form.full_name} onChange={update('full_name')} placeholder="e.g. Aanya Sharma" required />}
        {page === 'register' && role === 'student' && <Field label="Roll number" value={form.roll_number} onChange={update('roll_number')} placeholder="e.g. CSE-042" required />}
        {page === 'register' && role === 'student' && <div className="mt-2"><label className="mb-1.5 block text-xs font-bold uppercase tracking-wide text-[var(--muted)]">Reference photos</label><CameraCapture photos={photos} setPhotos={setPhotos} /></div>}
        <Field label={page === 'login' ? 'Email or roll number' : 'Email address'} type={page === 'login' ? 'text' : 'email'} value={form.email} onChange={update('email')} placeholder={page === 'login' ? 'you@college.edu or CSE-042' : 'you@college.edu'} required />
        <Field label="Password" type="password" value={form.password} onChange={update('password')} placeholder="At least 8 characters" required minLength={8} />
        {page === 'register' && (role === 'admin' || role === 'teacher') && <Field label={`${role === 'admin' ? 'Admin' : 'Teacher'} invite code`} value={form.invite_code} onChange={update('invite_code')} placeholder={role === 'admin' ? 'SMART-ADMIN-DEMO' : 'SMART-TEACHER-DEMO'} required />}
        {error && <Notice tone="error">{error}</Notice>}
        <button disabled={busy || (page === 'register' && ((role === 'student' && photos.length !== 5) || ((role === 'teacher' || role === 'admin') && !form.invite_code.trim())))} className="flex w-full items-center justify-center gap-2 rounded-md bg-[var(--green)] px-4 py-3 text-sm font-bold text-white transition hover:bg-[#0d583c] disabled:cursor-not-allowed disabled:opacity-50">{busy ? 'Working…' : page === 'login' ? 'Sign in' : 'Create account'} <ArrowRight size={16} /></button>
      </form>
      <button onClick={() => onPage(page === 'login' ? 'register' : 'login')} className="mt-6 w-full text-center text-sm font-semibold text-[var(--green)] hover:underline">{page === 'login' ? 'Create a new account' : 'Already have an account? Sign in'}</button>
    </div></section>
  </main>
}
