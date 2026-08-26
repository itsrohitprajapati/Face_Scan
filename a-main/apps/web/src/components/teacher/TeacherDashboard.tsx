import { useEffect, useState } from 'react'
import type React from 'react'
import { Plus } from 'lucide-react'
import { api } from '../../api'
import type { Classroom } from '../../types'
import { TeacherClassroom } from './TeacherClassroom'
import { AttendanceAssistant } from './AttendanceAssistant'
import { CreateClass } from './CreateClass'
import { Notice, PageHeading } from '../ui/primitives'

export function TeacherDashboard() {
  const [classes, setClasses] = useState<Classroom[]>([]); const [selected, setSelected] = useState<Classroom | null>(null); const [error, setError] = useState(''); const [showCreate, setShowCreate] = useState(false)
  const refresh = () => api.listClasses().then((items) => { setClasses(items); if (items.length && !selected) setSelected(items[0]) }).catch((e) => setError(e.message))
  useEffect(() => { void refresh() }, [])
  return <div className="fade-in"><PageHeading eyebrow="Teacher operations" title="Classroom control center" description="Set up your classes, connect camera sources, and run attendance sessions." action={<button onClick={() => setShowCreate(true)} className="flex items-center gap-2 rounded-md bg-[var(--green)] px-4 py-2.5 text-sm font-bold text-white hover:bg-[#0d583c]"><Plus size={16} /> New class</button>} />{error && <Notice tone="error">{error}</Notice>}<div className="mt-8"><AttendanceAssistant classes={classes} /></div><div className="mt-8 grid gap-6 lg:grid-cols-[280px_1fr]"><aside className="space-y-3"><div className="flex items-center justify-between"><h2 className="text-xs font-bold uppercase tracking-[.14em] text-[var(--muted)]">Your classes</h2><span className="tabular text-xs text-[var(--muted)]">{classes.length}</span></div>{classes.length === 0 ? <div className="rounded-xl border border-dashed border-[var(--line)] p-6 text-sm text-[var(--muted)]">Create your first class to begin.</div> : classes.map((item) => <button key={item.id} onClick={() => setSelected(item)} className={`w-full rounded-xl border p-4 text-left transition ${selected?.id === item.id ? 'border-[var(--green)] bg-[var(--green-soft)]' : 'border-[var(--line)] bg-white hover:border-[#b9c9bd]'}`}><p className="font-bold">{item.name}</p><p className="mt-1 text-xs text-[var(--muted)]">{item.section || 'No section'} · <span className="tabular">{item.join_code}</span></p></button>)}</aside>{selected ? <TeacherClassroom classroom={selected} /> : <div className="grid min-h-72 place-items-center rounded-xl border border-[var(--line)] bg-white text-sm text-[var(--muted)]">Select a class to manage it.</div>}</div>{showCreate && <CreateClass onClose={() => setShowCreate(false)} onCreated={(item) => { setClasses([item, ...classes]); setSelected(item); setShowCreate(false) }} />}</div>
}
